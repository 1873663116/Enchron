import Foundation
import Observation

private let streamingProbe = StreamSessionProbes.self

@MainActor
@Observable
public final class StreamingModel {
    public private(set) var hosts: [HostSnapshot] = []
    public private(set) var selectedHostID: HostID?
    public private(set) var pairing: PairingChallenge?
    public private(set) var pairingError: StreamFailure?
    public private(set) var discoveredHosts: [DiscoveredHost] = []
    public private(set) var isDiscovering = false
    public private(set) var session: SessionSnapshot?
    public private(set) var renderBinding: StreamRenderBinding?
    public private(set) var failure: StreamFailure?

    public var settings: StreamOptions {
        didSet {
            settingsStore.save(settings)
        }
    }

    public var selectedHost: HostSnapshot? {
        guard let selectedHostID else { return nil }
        return hosts.first { $0.id == selectedHostID }
    }

    public var applications: [HostApplication] {
        selectedHost?.applications.applications ?? []
    }

    public var emptyStateVisible: Bool {
        hosts.isEmpty
    }

    private let backend: any StreamingBackend
    private let hostStore: HostStore
    private let settingsStore: StreamSettingsStore

    private var storedHosts: [StoredHost] = []
    private var discoveryTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var activePairingSession: (any BackendPairingSession)?
    private var coordinator: StreamSessionCoordinator?
    private var teardownRequested = false
    private var teardownFallbackTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?

    public init(
        backend: any StreamingBackend,
        hostStore: HostStore = HostStore(),
        settingsStore: StreamSettingsStore = StreamSettingsStore()
    ) {
        self.backend = backend
        self.hostStore = hostStore
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        reloadHosts()
    }

    public func reloadHosts() {
        storedHosts = hostStore.load()
        hosts = storedHosts.map(snapshot(from:))
        if let selectedHostID, !hosts.contains(where: { $0.id == selectedHostID }) {
            self.selectedHostID = hosts.first?.id
        }
    }

    private func snapshot(from stored: StoredHost) -> HostSnapshot {
        HostSnapshot(
            id: stored.hostID,
            name: stored.name,
            address: stored.address,
            reachability: .unknown,
            pairing: stored.hasPairingRecord ? .paired : .unpaired
        )
    }

    public func selectHost(_ hostID: HostID?) {
        selectedHostID = hostID
        if hostID != nil, selectedHost?.applications.applications == nil {
            loadApplications(hostID: hostID!)
        }
    }

    /// Adds a host and returns the identity key it is stored under. The same
    /// physical host reached through a different port route (for example a
    /// loopback proxy) is a distinct entry with its own pairing.
    public func addHost(addressString: String, name: String?) async throws -> HostID {
        guard let address = HostAddress(parsing: addressString) else {
            throw StreamFailure(
                stage: .connect,
                kind: .unreachable,
                message: "地址无效",
                recovery: .none
            )
        }

        if storedHosts.contains(where: { $0.address == address }) {
            throw StreamFailure(
                stage: .connect,
                kind: .duplicateHost,
                message: "该主机已存在",
                recovery: .none
            )
        }

        let info: BackendServerInfo
        do {
            info = try await backend.fetchServerInfo(BackendCredentials(address: address))
        } catch {
            throw StreamFailure(
                stage: .connect,
                kind: .unreachable,
                message: "无法连接到主机",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }

        let userProvidedName = name?.isEmpty == false
        let hostID = address.portBase == HostAddress.defaultPortBase
            ? info.uniqueID
            : "\(info.uniqueID)@\(address.portBase)"
        let stored = StoredHost(
            id: hostID,
            name: userProvidedName ? name! : info.name,
            address: address,
            serverCert: nil,
            preferredAppID: nil,
            hasPairingRecord: info.pairStatus == 1,
            nameIsUserProvided: userProvidedName
        )
        _ = hostStore.upsert(stored)
        reloadHosts()
        refreshReachability(hostID: stored.hostID)
        return stored.hostID
    }

    public func forgetHost(_ hostID: HostID) throws {
        if let session, session.hostID == hostID {
            throw StreamFailure(
                stage: .teardown,
                kind: .hostBusy,
                message: "该主机有进行中的会话",
                recovery: .none
            )
        }
        _ = hostStore.remove(id: hostID.rawValue)
        if selectedHostID == hostID {
            selectedHostID = nil
        }
        reloadHosts()
    }

    public func refreshReachability(hostID: HostID? = nil) {
        reachabilityTask?.cancel()
        let targets = storedHosts.filter { hostID == nil || $0.hostID == hostID! }
        reachabilityTask = Task { [backend] in
            for target in targets {
                let credentials = BackendCredentials(address: target.address, serverCert: target.serverCert)
                do {
                    let info = try await backend.fetchServerInfo(credentials)
                    guard !Task.isCancelled else { return }
                    self.applyServerInfo(
                        info,
                        hostID: target.hostID,
                        authoritativePairing: target.serverCert != nil
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self.applyReachability(.offline, hostID: target.hostID)
                }
            }
        }
    }

    /// Applies a server info reply. `authoritativePairing` says the query proved
    /// this client's certificate: PairStatus can only name this client then, and
    /// an unpinned reply says nothing about the stored pairing.
    private func applyServerInfo(
        _ info: BackendServerInfo,
        hostID: HostID,
        authoritativePairing: Bool
    ) {
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }
        hosts[index].reachability = .online
        if authoritativePairing {
            hosts[index].pairing = info.pairStatus == 1 ? .paired : .unpaired
        } else if case .unknown = hosts[index].pairing {
            hosts[index].pairing = .unpaired
        }
        if !info.name.isEmpty,
           !(storedHosts.first(where: { $0.hostID == hostID })?.hasUserProvidedName ?? false) {
            hosts[index].name = info.name
        }
        hosts[index].remoteSession = RemoteSessionInfo(
            currentGame: info.currentGame,
            rawState: info.state
        )
        if authoritativePairing, let storedIndex = storedHosts.firstIndex(where: { $0.hostID == hostID }) {
            storedHosts[storedIndex].hasPairingRecord = info.pairStatus == 1
            if !storedHosts[storedIndex].hasUserProvidedName,
               storedHosts[storedIndex].name != info.name, !info.name.isEmpty {
                storedHosts[storedIndex].name = info.name
                _ = hostStore.upsert(storedHosts[storedIndex])
            }
        }
    }

    private func applyReachability(_ reachability: HostReachability, hostID: HostID) {
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }
        hosts[index].reachability = reachability
    }

    public func startDiscovery() {
        guard discoveryTask == nil else { return }
        isDiscovering = true
        discoveryTask = Task { [backend] in
            for await batch in backend.discoverHosts() {
                guard !Task.isCancelled else { return }
                self.discoveredHosts = batch
            }
            self.isDiscovering = false
        }
    }

    public func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isDiscovering = false
        discoveredHosts = []
    }

    public func beginPairing(hostID: HostID) async throws -> PairingChallenge {
        guard let stored = storedHosts.first(where: { $0.hostID == hostID }) else {
            throw StreamFailure(stage: .pairing, kind: .unreachable, message: "主机不存在", recovery: .none)
        }
        pairingError = nil
        let credentials = BackendCredentials(address: stored.address, serverCert: stored.serverCert)
        let backendPairing = try await backend.beginPairing(credentials)
        activePairingSession = backendPairing

        let challenge = PairingChallenge(id: backendPairing.pairingID, pin: backendPairing.pin)
        pairing = challenge
        StreamSessionProbes.record(
            "pairing begin host=\(stored.name) pin=\(challenge.pin)",
            retention: .evidence
        )

        pairingTask = Task { [weak self] in
            do {
                let outcome = try await backendPairing.waitForOutcome()
                guard !Task.isCancelled else { return }
                self?.completePairing(hostID: hostID, outcome: outcome)
            } catch {
                guard !Task.isCancelled else { return }
                self?.pairingFailed(String(describing: error))
            }
        }
        return challenge
    }

    private func completePairing(hostID: HostID, outcome: PairingOutcome) {
        StreamSessionProbes.record(
            "pairing complete host=\(hostID.rawValue)",
            retention: .evidence
        )
        switch outcome {
        case .paired(let serverCert), .alreadyPaired(.some(let serverCert)):
            _ = hostStore.update(id: hostID.rawValue) { stored in
                stored.serverCert = serverCert
                stored.hasPairingRecord = true
            }
            pairing?.state = .paired
            reloadHosts()
            refreshReachability(hostID: hostID)
            loadApplications(hostID: hostID)
        case .alreadyPaired(nil):
            _ = hostStore.update(id: hostID.rawValue) { stored in
                stored.hasPairingRecord = true
            }
            pairing?.state = .paired
            reloadHosts()
            refreshReachability(hostID: hostID)
        }
        activePairingSession = nil
    }

    private func pairingFailed(_ message: String) {
        StreamSessionProbes.record(
            "pairing failed error=\(message)",
            retention: .evidence
        )
        pairing?.state = .failed(message)
        pairingError = StreamFailure(
            stage: .pairing,
            kind: .pairingRejected,
            message: "配对失败",
            recovery: .pairAgain,
            upstreamDetail: message
        )
        activePairingSession = nil
    }

    public func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        activePairingSession?.cancel()
        activePairingSession = nil
        pairing = nil
        pairingError = nil
    }

    public func clearPairing() {
        pairing = nil
        pairingError = nil
    }

    public func loadApplications(hostID: HostID) {
        guard let stored = storedHosts.first(where: { $0.hostID == hostID }) else { return }
        if let index = hosts.firstIndex(where: { $0.id == hostID }) {
            hosts[index].applications = .unknown
        }
        Task { [backend] in
            do {
                let applications = try await backend.applications(
                    BackendCredentials(address: stored.address, serverCert: stored.serverCert)
                )
                guard let index = self.hosts.firstIndex(where: { $0.id == hostID }) else { return }
                self.hosts[index].applications = .loaded(applications)
            } catch {
                guard let index = self.hosts.firstIndex(where: { $0.id == hostID }) else { return }
                self.hosts[index].applications = .failed(String(describing: error))
            }
        }
    }

    public func launch(hostID: HostID, appID: AppID, appName: String) async throws {
        try await startSession(hostID: hostID, appID: appID, appName: appName, preferResume: false)
    }

    public func resume(hostID: HostID, appID: AppID?, appName: String?) async throws {
        try await startSession(hostID: hostID, appID: appID, appName: appName, preferResume: true)
    }

    public func reconnect() async throws {
        guard let current = session else { return }
        let hostID = current.hostID
        let appID = current.appID
        let appName = current.appName
        stopSessionInternal(reason: "reconnect")
        try await startSession(hostID: hostID, appID: appID, appName: appName, preferResume: true)
    }

    private func startSession(hostID: HostID, appID: AppID?, appName: String?, preferResume: Bool) async throws {
        if let current = session {
            switch current.state {
            case .connecting, .streaming:
                throw StreamFailure(stage: .launch, kind: .hostBusy, message: "已有进行中的会话", recovery: .none)
            case .interrupted, .ended, .stopping:
                stopSessionInternal(reason: "replace")
                finishSessionDismissal()
            }
        }
        guard let stored = storedHosts.first(where: { $0.hostID == hostID }) else {
            throw StreamFailure(stage: .launch, kind: .unreachable, message: "主机不存在", recovery: .none)
        }
        guard stored.hasPairingRecord else {
            throw StreamFailure(stage: .pairing, kind: .notPaired, message: "主机未配对", recovery: .pairAgain)
        }

        let resolvedAppID: AppID
        let resolvedAppName: String
        if let appID, let appName {
            resolvedAppID = appID
            resolvedAppName = appName
        } else {
            let applications = try await backend.applications(
                BackendCredentials(address: stored.address, serverCert: stored.serverCert)
            )
            guard let application = applications.first else {
                throw StreamFailure(
                    stage: .applicationList,
                    kind: .applicationMissing,
                    message: "主机没有可用应用",
                    recovery: .repickApplication
                )
            }
            resolvedAppID = application.id
            resolvedAppName = application.name
        }

        let request = BackendSessionRequest(
            credentials: BackendCredentials(address: stored.address, serverCert: stored.serverCert),
            appID: resolvedAppID,
            appName: resolvedAppName,
            options: settings
        )

        do {
            let backendSession = preferResume
                ? try await backend.resumeSession(request)
                : try await backend.launchSession(request)
            let coordinator = StreamSessionCoordinator(
                sessionID: SessionID(),
                hostID: hostID,
                appID: resolvedAppID,
                hostName: stored.name,
                appName: resolvedAppName,
                options: settings,
                backend: backendSession
            )
            self.coordinator = coordinator
            teardownRequested = false
            session = coordinator.snapshot
            renderBinding = coordinator.binding
            failure = nil
            coordinator.onSnapshot = { [weak self] snapshot in
                Task { @MainActor in
                    self?.applySessionSnapshot(snapshot)
                }
            }
            coordinator.onBindingChange = { [weak self] binding in
                Task { @MainActor in
                    self?.renderBinding = binding
                }
            }
            coordinator.start()
        } catch let failure as StreamFailure {
            self.failure = failure
            throw failure
        } catch {
            let failure = StreamFailure(
                stage: .launch,
                kind: .unknown,
                message: "启动串流失败",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
            self.failure = failure
            throw failure
        }
    }

    private func applySessionSnapshot(_ snapshot: SessionSnapshot) {
        guard coordinator?.sessionID == snapshot.id else { return }
        session = snapshot
        if case .ended = snapshot.state {
            if teardownRequested {
                finishSessionDismissal()
            } else {
                teardownFallbackTask?.cancel()
                teardownFallbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.finishSessionDismissal()
                }
            }
        }
    }

    public func disconnect() {
        stopSessionInternal(reason: "user")
        teardownRequested = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if self.session != nil, self.coordinator != nil {
                self.finishSessionDismissal()
            }
        }
    }

    private func stopSessionInternal(reason: String) {
        teardownFallbackTask?.cancel()
        teardownFallbackTask = nil
        coordinator?.stop(reason: reason)
    }

    private func finishSessionDismissal() {
        coordinator = nil
        session = nil
        renderBinding = nil
        teardownRequested = false
    }

    public func quitApplication(hostID: HostID) async throws {
        guard let stored = storedHosts.first(where: { $0.hostID == hostID }) else { return }
        try await backend.quitApplication(
            BackendCredentials(address: stored.address, serverCert: stored.serverCert)
        )
    }

    public func sendPointerMove(normalizedX: Float, normalizedY: Float) {
        coordinator?.sendMousePosition(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    public func sendPointerDelta(dx: Int32, dy: Int32) {
        coordinator?.sendMouseMove(dx: dx, dy: dy)
    }

    public func sendMouseButton(code: Int32, down: Bool) {
        coordinator?.sendMouseButton(code: code, down: down)
    }

    public func sendScroll(amount: Int32) {
        coordinator?.sendScroll(amount: amount)
    }

    public func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {
        coordinator?.sendKey(hidUsage: hidUsage, down: down, modifierFlags: modifierFlags)
    }

    public func releaseInputs(cause: String) {
        coordinator?.releaseAllInput(cause: cause)
    }

    public func recordVideoSurfaceBinding(revision: Int, bound: Bool) {
        if bound {
            coordinator?.videoSurfaceDidBind(revision: revision)
        } else {
            coordinator?.videoSurfaceDidUnbind(revision: revision)
        }
    }

    public func updateSettings(_ transform: (inout StreamOptions) -> Void) {
        var next = settings
        transform(&next)
        settings = next
    }

    public func savePreferredApplication(hostID: HostID, appID: AppID) {
        _ = hostStore.update(id: hostID.rawValue) { stored in
            stored.preferredAppID = appID
        }
        reloadHosts()
    }

    public func preferredApplicationID(hostID: HostID) -> AppID? {
        storedHosts.first { $0.hostID == hostID }?.preferredAppID
    }

    public func artwork(hostID: HostID, appID: AppID) async -> Data? {
        guard let stored = storedHosts.first(where: { $0.hostID == hostID }) else { return nil }
        return try? await backend.artwork(
            BackendCredentials(address: stored.address, serverCert: stored.serverCert),
            appID: appID
        )
    }
}
