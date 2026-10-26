import AVFoundation
import Foundation
import Observation
import UIKit

private let streamingProbe = StreamSessionProbes.self

@MainActor
@Observable
public final class StreamingModel {
    public private(set) var hosts: [HostSnapshot] = []
    public private(set) var selectedHostID: HostID?
    public private(set) var pairings: [HostID: PairingChallenge] = [:]
    public private(set) var failures: [HostID: StreamFailure] = [:]
    public private(set) var discoveredHosts: [DiscoveredHost] = []
    public private(set) var isDiscovering = false
    public private(set) var session: SessionSnapshot?
    public var onSessionChanged: ((SessionSnapshot?) -> Void)?
    public private(set) var renderBinding: StreamRenderBinding?
    public private(set) var artworkCache: [String: URL] = [:]

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

    public var videoAspectRatio: CGFloat {
        if let negotiated = session?.negotiated, negotiated.width > 0, negotiated.height > 0 {
            return CGFloat(negotiated.width) / CGFloat(negotiated.height)
        }
        let resolution = session?.requested.resolution ?? settings.resolution
        guard resolution.height > 0 else { return 16.0 / 9.0 }
        return CGFloat(resolution.width) / CGFloat(resolution.height)
    }

    public func pairing(for hostID: HostID) -> PairingChallenge? {
        pairings[hostID]
    }

    public func failure(for hostID: HostID) -> StreamFailure? {
        failures[hostID]
    }

    public func recordFailure(_ failure: StreamFailure, hostID: HostID) {
        failures[hostID] = failure
    }

    public func clearFailure(hostID: HostID) {
        failures[hostID] = nil
    }

    private let backend: any StreamingBackend
    private let hostStore: HostStore
    private let settingsStore: StreamSettingsStore

    private var storedHosts: [StoredHost] = []
    private var discoveryTask: Task<Void, Never>?
    private var pairingTasks: [HostID: Task<Void, Never>] = [:]
    private var activePairingSessions: [HostID: any BackendPairingSession] = [:]
    private var coordinator: StreamSessionCoordinator?
    private var hostFrameRateRecoveryInFlight = false
    private var hostFrameRateRecoveryAttempts: [HostID: Date] = [:]
    private var teardownRequested = false
    private var teardownFallbackTask: Task<Void, Never>?
    private var hostQuitRetryTasks: [HostID: Task<Void, Never>] = [:]
    private var suspendedStream: (hostID: HostID, appID: AppID, appName: String)?
    public var hostQuitFailureMessage: String?
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
        if let hostID, selectedHost?.applications.applications == nil {
            loadApplications(hostID: hostID)
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
            name: userProvidedName ? (name ?? info.name) : info.name,
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
        hostQuitRetryTasks[hostID]?.cancel()
        hostQuitRetryTasks[hostID] = nil
        cancelPairing(hostID: hostID)
        if selectedHostID == hostID {
            selectedHostID = nil
        }
        reloadHosts()
    }

    public func refreshReachability(hostID: HostID? = nil) {
        reachabilityTask?.cancel()
        let targets = storedHosts.filter { requested in
            hostID.map { $0 == requested.hostID } ?? true
        }
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
        failures[hostID] = nil
        let credentials = BackendCredentials(address: stored.address, serverCert: stored.serverCert)
        let backendPairing = try await backend.beginPairing(credentials)
        activePairingSessions[hostID] = backendPairing

        let challenge = PairingChallenge(id: backendPairing.pairingID, pin: backendPairing.pin)
        pairings[hostID] = challenge
        StreamSessionProbes.record(
            "pairing begin host=\(stored.name) pin=\(challenge.pin)",
            retention: .evidence
        )

        pairingTasks[hostID] = Task { [weak self] in
            do {
                let outcome = try await backendPairing.waitForOutcome()
                guard !Task.isCancelled else { return }
                self?.completePairing(hostID: hostID, outcome: outcome)
            } catch {
                guard !Task.isCancelled else { return }
                self?.pairingFailed(hostID: hostID, message: String(describing: error))
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
            pairings[hostID] = nil
            reloadHosts()
            refreshReachability(hostID: hostID)
            loadApplications(hostID: hostID)
        case .alreadyPaired(nil):
            _ = hostStore.update(id: hostID.rawValue) { stored in
                stored.hasPairingRecord = true
            }
            pairings[hostID] = nil
            reloadHosts()
            refreshReachability(hostID: hostID)
        }
        activePairingSessions[hostID] = nil
        pairingTasks[hostID] = nil
    }

    private func pairingFailed(hostID: HostID, message: String) {
        StreamSessionProbes.record(
            "pairing failed error=\(message)",
            retention: .evidence
        )
        pairings[hostID]?.state = .failed(message)
        failures[hostID] = StreamFailure(
            stage: .pairing,
            kind: .pairingRejected,
            message: "配对失败",
            recovery: .pairAgain,
            upstreamDetail: message
        )
        activePairingSessions[hostID] = nil
        pairingTasks[hostID] = nil
    }

    public func cancelPairing(hostID: HostID) {
        pairingTasks[hostID]?.cancel()
        pairingTasks[hostID] = nil
        activePairingSessions[hostID]?.cancel()
        activePairingSessions[hostID] = nil
        pairings[hostID] = nil
        failures[hostID] = nil
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

    private func relaunchForDisplayMode() async throws {
        guard let current = session else { return }
        let hostID = current.hostID
        let appID = current.appID
        let appName = current.appName
        stopSessionInternal(reason: "displayModeMismatch")
        try await startSession(hostID: hostID, appID: appID, appName: appName, preferResume: false)
    }

    public func reconnect() async throws {
        guard let current = session else { return }
        let hostID = current.hostID
        let appID = current.appID
        let appName = current.appName
        stopSessionInternal(reason: "reconnect")
        try await startSession(hostID: hostID, appID: appID, appName: appName, preferResume: true)
    }

    private func startSession(
        hostID: HostID,
        appID: AppID?,
        appName: String?,
        preferResume: Bool,
        continuesSuspendedSession: Bool = false
    ) async throws {
        hostQuitRetryTasks[hostID]?.cancel()
        hostQuitRetryTasks[hostID] = nil
        if !continuesSuspendedSession {
            suspendedStream = nil
        }
        if !continuesSuspendedSession, let current = session {
            let replacesTheRunningApp = appID.map { $0 != current.appID } ?? false
            switch current.state {
            case .connecting, .streaming:
                _ = replacesTheRunningApp
                stopSessionInternal(reason: "replace")
                finishSessionDismissal()
                if let stored = storedHosts.first(where: { $0.hostID == hostID }) {
                    try? await backend.quitApplication(
                        BackendCredentials(address: stored.address, serverCert: stored.serverCert)
                    )
                }
                try await waitForHostToReleaseTheSession()
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

        let sessionID = SessionID()
        setSession(
            SessionSnapshot(
                id: sessionID,
                hostID: hostID,
                appID: resolvedAppID,
                hostName: stored.name,
                appName: resolvedAppName,
                state: .connecting(stage: "starting"),
                requested: settings,
                negotiated: nil,
                input: StreamInputDiagnostics(),
                diagnostics: StreamDiagnostics(),
                failure: nil,
                adjustments: [],
                hdrModeReported: false
            )
        )

        do {
            let backendSession = preferResume
                ? try await backend.resumeSession(request)
                : try await backend.launchSession(request)
            if continuesSuspendedSession, session?.id != sessionID {
                return
            }
            let coordinator = StreamSessionCoordinator(
                sessionID: sessionID,
                hostID: hostID,
                appID: resolvedAppID,
                hostName: stored.name,
                appName: resolvedAppName,
                options: settings,
                backend: backendSession
            )
            self.coordinator = coordinator
            teardownRequested = false
            setSession(coordinator.snapshot)
            renderBinding = coordinator.binding
            failures[hostID] = nil
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
            coordinator.onHostFrameRateMismatch = { [weak self] in
                Task { @MainActor in
                    guard let self, !self.hostFrameRateRecoveryInFlight else { return }
                    guard let hostID = self.session?.hostID else { return }
                    if let last = self.hostFrameRateRecoveryAttempts[hostID],
                       Date().timeIntervalSince(last) < 300 {
                        return
                    }
                    self.hostFrameRateRecoveryAttempts[hostID] = Date()
                    self.hostFrameRateRecoveryInFlight = true
                    defer { self.hostFrameRateRecoveryInFlight = false }
                    try? await self.relaunchForDisplayMode()
                }
            }
            coordinator.start()
        } catch let failure as StreamFailure {
            failures[hostID] = failure
            setSession(nil)
            startHostQuit(hostID: hostID)
            StreamSessionProbes.record(
                "session start failed host=\(hostID.rawValue)"
                    + " app=\(resolvedAppName)"
                    + " stage=\(failure.stage.rawValue)"
                    + " kind=\(failure.kind.rawValue)"
                    + " message=\(failure.message)"
                    + " upstream=\(failure.upstreamDetail ?? "none")",
                retention: .evidence
            )
            throw failure
        } catch {
            setSession(nil)
            let failure = StreamFailure(
                stage: .launch,
                kind: .unknown,
                message: "启动串流失败",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
            failures[hostID] = failure
            StreamSessionProbes.record(
                "session start failed host=\(hostID.rawValue)"
                    + " app=\(resolvedAppName)"
                    + " stage=\(failure.stage.rawValue)"
                    + " kind=\(failure.kind.rawValue)"
                    + " message=\(failure.message)"
                    + " upstream=\(failure.upstreamDetail ?? "none")",
                retention: .evidence
            )
            throw failure
        }
    }

    private func setSession(_ snapshot: SessionSnapshot?) {
        session = snapshot
        onSessionChanged?(snapshot)
    }

    private func applySessionSnapshot(_ snapshot: SessionSnapshot) {
        guard coordinator?.sessionID == snapshot.id else { return }
        setSession(snapshot)
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
        guard !teardownRequested else { return }
        suspendedStream = nil
        teardownRequested = true
        let coordinator = self.coordinator
        self.coordinator = nil
        setSession(nil)
        renderBinding = nil
        teardownRequested = false
        Task {
            coordinator?.stop(reason: "user")
        }
    }

    public func endStream() {
        guard !teardownRequested else { return }
        let hostID = session?.hostID
        releaseInputs(cause: "disconnect")
        disconnect()
        guard let hostID else { return }
        startHostQuit(hostID: hostID)
    }

    public func suspendForBackground() {
        guard !teardownRequested, let current = session, let coordinator else { return }
        switch current.state {
        case .connecting, .streaming, .interrupted:
            break
        case .stopping, .ended:
            return
        }
        suspendedStream = (current.hostID, current.appID, current.appName)
        teardownFallbackTask?.cancel()
        teardownFallbackTask = nil
        self.coordinator = nil
        streamingProbe.record(
            "stream suspended for background session=\(current.id.rawValue)",
            retention: .evidence
        )
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "stream-suspend")
        Task {
            coordinator.stop(reason: "background")
            UIApplication.shared.endBackgroundTask(assertion)
        }
    }

    public func resumeFromBackground() {
        guard let suspended = suspendedStream else { return }
        suspendedStream = nil
        guard session != nil, coordinator == nil else { return }
        streamingProbe.record(
            "stream resuming after background host=\(suspended.hostID.rawValue) app=\(suspended.appName)",
            retention: .evidence
        )
        Task {
            try? await startSession(
                hostID: suspended.hostID,
                appID: suspended.appID,
                appName: suspended.appName,
                preferResume: true,
                continuesSuspendedSession: true
            )
        }
    }

    private func startHostQuit(hostID: HostID) {
        hostQuitRetryTasks[hostID]?.cancel()
        hostQuitRetryTasks[hostID] = Task { [weak self] in
            guard let self else { return }
            let assertion = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "host-quit")
            }
            defer {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(assertion)
                }
            }
            for attempt in 1...2 {
                if Task.isCancelled { break }
                if self.session != nil {
                    self.hostQuitRetryTasks[hostID] = nil
                    return
                }
                guard let stored = self.storedHosts.first(where: { $0.hostID == hostID }) else {
                    self.hostQuitRetryTasks[hostID] = nil
                    return
                }
                do {
                    try await self.backend.quitApplication(
                        BackendCredentials(
                            address: stored.address,
                            serverCert: stored.serverCert
                        )
                    )
                    self.hostQuitRetryTasks[hostID] = nil
                    streamingProbe.record(
                        "host quit confirmed host=\(hostID.rawValue)",
                        retention: .evidence
                    )
                    return
                } catch {
                    streamingProbe.record(
                        "host quit attempt \(attempt) failed host=\(hostID.rawValue)"
                            + " error=\(error.localizedDescription)",
                        retention: .evidence
                    )
                }
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            self.hostQuitRetryTasks[hostID] = nil
            streamingProbe.record(
                "host quit abandoned host=\(hostID.rawValue)",
                retention: .evidence
            )
            if let stored = self.storedHosts.first(where: { $0.hostID == hostID }),
               (try? await self.backend.fetchServerInfo(
                   BackendCredentials(
                       address: stored.address,
                       serverCert: stored.serverCert
                   )
               )) != nil {
                self.hostQuitFailureMessage = "服务端可能仍在运行该应用。"
            }
        }
    }

    private func waitForHostToReleaseTheSession() async throws {
        guard let stored = storedHosts.first else { return }
        let credentials = BackendCredentials(address: stored.address, serverCert: stored.serverCert)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(750))
            guard let info = try? await backend.fetchServerInfo(credentials) else { continue }
            guard let remote = info.currentGame, remote.isEmpty == false, remote != "0" else {
                return
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
        setSession(nil)
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

    public func sendGestureClick(normalizedX: Float, normalizedY: Float) {
        coordinator?.sendGestureClick(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    public func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {
        coordinator?.sendKey(hidUsage: hidUsage, down: down, modifierFlags: modifierFlags)
    }

    @discardableResult
    public func sendGamepad(_ state: StreamGamepadState) -> Int32? {
        coordinator?.sendGamepad(state)
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

    /// Rebuilds the renderer graph for a presentation root that cannot reuse the
    /// current graph, and returns the renderer the running session now feeds.
    public func rebuildRendererGraphForPresentation() -> AVSampleBufferVideoRenderer? {
        coordinator?.rebuildRendererGraph(reason: "presentationRebuild")
    }

    public func updateSettings(_ transform: (inout StreamOptions) -> Void) {
        var next = settings
        transform(&next)
        next.normalize()
        settings = next
    }

    public func savePreferredApplication(hostID: HostID, appID: AppID) {
        _ = hostStore.update(id: hostID.rawValue) { stored in
            stored.preferredAppID = appID
        }
        reloadHosts()
    }

    public func hideApplication(hostID: HostID, appID: AppID) {
        _ = hostStore.update(id: hostID.rawValue) { stored in
            var hidden = stored.hiddenApps
            hidden.insert(appID.rawValue)
            stored.hiddenAppIDs = Array(hidden).sorted()
        }
        reloadHosts()
    }

    public func hiddenApplicationIDs(hostID: HostID) -> Set<String> {
        storedHosts.first { $0.hostID == hostID }?.hiddenApps ?? []
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

    public func artworkFileURL(hostID: HostID, appID: AppID) async -> URL? {
        let key = "\(hostID.rawValue)-\(appID.rawValue)"
        if let cached = artworkCache[key] {
            return cached
        }
        guard let data = await artwork(hostID: hostID, appID: appID) else { return nil }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("enchron-app-artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("app-\(key).png")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        artworkCache[key] = file
        return file
    }

}
