import CoreMedia
import Foundation

@MainActor
public final class PlaybackCoreController {
    public private(set) var activeSession: SampleBufferPlaybackSession?
    public private(set) var status = PlaybackStatus.idle
    public private(set) var diagnostics = PlaybackDiagnostics()
    public private(set) var selectedRoute = PlaybackRoute.ffmpegCompressed
    public private(set) var selectedURL: URL?
    public private(set) var selectedAsset: PlaybackAsset?
    public private(set) var selectedStereoLayout: VideoStereoLayout?
    public private(set) var selectedProjectionOverride: VideoProjectionOverride?

    public var onStatusChange: ((PlaybackStatus) -> Void)?
    public var onDiagnosticsChange: ((PlaybackDiagnostics) -> Void)?
    public var onSessionChange: ((SampleBufferPlaybackSession?) -> Void)?
    public var onSubtitleCuesChange: (([PlaybackSubtitleCue]) -> Void)?
    public var onSubtitleFrameChange: ((PlaybackSubtitleFrame?) -> Void)?

    public var debugDirectoryURL: URL? {
        debugRecorder?.directoryURL
    }

    public var staleUpdateCount: Int {
        mediaSlot.staleUpdateCount
    }

    private var mediaSlot = MediaSessionState()
    private var debugRecorder: PlaybackDebugRecorder?
    private let sessionFactory: (PlaybackRoute, String) -> SampleBufferPlaybackSession
    private var activeSeekTask: Task<Void, Error>?
    private var activeSubtitleSelectionTask: Task<Void, Error>?
    private var activeStereoTask: Task<UInt64, Error>?
    private var failedCleanupTask: Task<Void, Never>?
    private var pendingCleanupMediaSessionID: String?
    private var pendingCleanupWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestRequestedSeekTime: CMTime?
    private var seekGeneration: UInt64 = 0
    private var subtitleSelectionGeneration: UInt64 = 0
    private var stereoGeneration: UInt64 = 0

    public init() {
        sessionFactory = { route, sessionID in
            SampleBufferPlaybackSession(route: route, traceID: sessionID)
        }
    }

    init(
        sessionFactory: @escaping (PlaybackRoute, String) -> SampleBufferPlaybackSession
    ) {
        self.sessionFactory = sessionFactory
    }

    @discardableResult
    public func open(
        _ url: URL,
        asset: PlaybackAsset? = nil,
        startTime: CMTime = .zero,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        initialStereoLayout: VideoStereoLayout? = nil,
        initialProjectionOverride: VideoProjectionOverride? = nil,
        provenance: String = "appOpen",
        accessRequirement: String = "appAdapterManaged"
    ) async throws -> SampleBufferPlaybackSession {
        try await open(
            url,
            asset: asset,
            route: Self.providerRoute(for: url, asset: asset),
            startTime: startTime,
            startsPaused: startsPaused,
            initialRate: initialRate,
            initialStereoLayout: initialStereoLayout,
            initialProjectionOverride: initialProjectionOverride,
            provenance: provenance,
            accessRequirement: accessRequirement
        )
    }

    @discardableResult
    public func open(
        _ url: URL,
        asset: PlaybackAsset? = nil,
        route: PlaybackRoute,
        startTime: CMTime = .zero,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        initialStereoLayout: VideoStereoLayout? = nil,
        initialProjectionOverride: VideoProjectionOverride? = nil,
        provenance: String = "appOpen",
        accessRequirement: String = "appAdapterManaged"
    ) async throws -> SampleBufferPlaybackSession {
        await waitForPendingCleanup()
        let source = MediaSourceRecord(
            locator: url,
            provenance: provenance,
            privacySafeSummary: url.lastPathComponent,
            accessRequirement: accessRequirement
        )
        let sessionID = UUID().uuidString
        switch mediaSlot.admitOpen(
            source: source,
            route: route,
            initialTimeSeconds: startTime.seconds,
            startsPaused: startsPaused,
            initialRate: initialRate,
            mediaSessionID: sessionID
        ) {
        case .rejected(let rejection):
            activeSession?.debugStore.recordOpenRejection(rejection)
            activeSession?.debugStore.emit(
                mediaSessionID: activeSession?.traceID,
                route: activeSession?.route,
                node: .mediaSessionAndRouteBinding,
                kind: "open.rejected",
                outcome: .failed,
                details: ["reason": rejection.reason]
            )
            throw PlaybackControlError.openRejected(rejection)
        case .accepted:
            break
        }

        selectedURL = url
        selectedAsset = asset
        selectedRoute = route
        setStatus(.loading)
        let session = sessionFactory(route, sessionID)
        if let initialStereoLayout {
            _ = try await session.setStereoLayout(initialStereoLayout)
        }
        if let initialProjectionOverride {
            _ = try await session.setProjectionOverride(initialProjectionOverride)
        }
        activeSession = session
        debugRecorder = PlaybackDebugRecorder(session: session, platform: platformName)
        session.debugStore.recordPlatform(
            platformName,
            hardwareDisplayFacts: hardwareDisplayFactAvailability
        )
        bindCallbacks(to: session)
        onSessionChange?(session)

        session.debugStore.emit(
            mediaSessionID: sessionID,
            route: route,
            node: .sourceAcquisition,
            kind: "source.acquired",
            outcome: .succeeded,
            details: [
                "source": source.privacySafeSummary,
                "provenance": provenance,
            ]
        )
        session.debugStore.emit(
            mediaSessionID: sessionID,
            route: route,
            node: .mediaSessionAndRouteBinding,
            kind: "open.admitted",
            outcome: .succeeded
        )
        do {
            try await session.prepare(
                url: url,
                asset: asset,
                startTime: startTime,
                startsPaused: startsPaused,
                initialRate: initialRate,
                provenance: provenance,
                accessRequirement: accessRequirement
            )
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedStereoLayout = initialStereoLayout
            selectedProjectionOverride = initialProjectionOverride
            return session
        } catch {
            guard activeSession === session else { throw error }
            await session.closeAndWait()
            debugRecorder?.stop()
            debugRecorder = nil
            activeSession = nil
            _ = mediaSlot.release(mediaSessionID: sessionID)
            onSessionChange?(nil)
            setStatus(.failed(error.localizedDescription))
            throw error
        }
    }

    public func start() throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.start()
    }

    public func presentationDidAttach(session: SampleBufferPlaybackSession) throws {
        guard activeSession === session else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        let snapshot = session.debugSnapshot()
        guard snapshot.realityKitBinding?.active == true,
              snapshot.presentationBinding?.entityAttached == true else {
            throw PlaybackControlError.presentationNotAttached
        }
        if status == .loading {
            setStatus(.ready)
        }
    }

    public func play() throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.play()
    }

    public func pause() throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.pause()
    }

    public func setRate(_ rate: Float) throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.setRate(rate)
    }

    public func setVolume(_ volume: Float) throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.setVolume(volume)
    }

    public func setMuted(_ muted: Bool) throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        activeSession.setMuted(muted)
    }

    @discardableResult
    public func setStereoLayout(_ layout: VideoStereoLayout) async throws -> UInt64 {
        try await updateStereoLayout(layout)
    }

    @discardableResult
    public func clearStereoLayoutOverride() async throws -> UInt64 {
        try await updateStereoLayout(nil)
    }

    @discardableResult
    public func setProjectionOverride(_ projection: VideoProjectionOverride) async throws -> UInt64 {
        try await updateProjectionOverride(projection)
    }

    @discardableResult
    public func clearProjectionOverride() async throws -> UInt64 {
        try await updateProjectionOverride(nil)
    }

    private func updateProjectionOverride(
        _ projection: VideoProjectionOverride?
    ) async throws -> UInt64 {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        if activeStereoTask != nil {
            throw PlaybackControlError.operationInProgress(.setProjection)
        }
        stereoGeneration &+= 1
        let generation = stereoGeneration
        let task = Task {
            if let projection {
                return try await session.setProjectionOverride(projection)
            }
            return try await session.clearProjectionOverride()
        }
        activeStereoTask = task
        do {
            let revision = try await task.value
            guard stereoGeneration == generation else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeStereoTask = nil
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedProjectionOverride = projection
            return revision
        } catch {
            if stereoGeneration == generation {
                activeStereoTask = nil
            }
            throw error
        }
    }

    private func updateStereoLayout(
        _ layout: VideoStereoLayout?
    ) async throws -> UInt64 {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        if activeStereoTask != nil {
            throw PlaybackControlError.operationInProgress(.setStereoLayout)
        }
        stereoGeneration &+= 1
        let generation = stereoGeneration
        let task = Task {
            if let layout {
                return try await session.setStereoLayout(layout)
            }
            return try await session.clearStereoLayoutOverride()
        }
        activeStereoTask = task
        do {
            let revision = try await task.value
            guard stereoGeneration == generation else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeStereoTask = nil
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedStereoLayout = layout
            return revision
        } catch {
            if stereoGeneration == generation {
                activeStereoTask = nil
            }
            throw error
        }
    }

    public var availableAudioTracks: [PlaybackAudioTrack] {
        activeSession?.availableAudioTracks ?? []
    }

    public func selectAudioTrack(streamIndex: Int) async throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try await activeSession.selectAudioTrack(streamIndex: streamIndex)
    }

    public var availableSubtitleTracks: [PlaybackSubtitleTrack] {
        activeSession?.availableSubtitleTracks ?? []
    }

    public var selectedSubtitleTrackID: PlaybackSubtitleTrack.ID? {
        activeSession?.selectedSubtitleTrackID
    }

    public var activeSubtitleCues: [PlaybackSubtitleCue] {
        activeSession?.activeSubtitleCues ?? []
    }

    public var activeSubtitleFrame: PlaybackSubtitleFrame? {
        activeSession?.activeSubtitleFrame
    }

    public func selectSubtitleTrack(id: PlaybackSubtitleTrack.ID?) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        subtitleSelectionGeneration &+= 1
        let generation = subtitleSelectionGeneration
        if let activeSubtitleSelectionTask {
            activeSubtitleSelectionTask.cancel()
            _ = try? await activeSubtitleSelectionTask.value
        }
        guard subtitleSelectionGeneration == generation,
              activeSession === session else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        let task = Task {
            try await session.selectSubtitleTrack(id: id)
        }
        activeSubtitleSelectionTask = task
        do {
            try await task.value
            if subtitleSelectionGeneration == generation {
                activeSubtitleSelectionTask = nil
            }
        } catch {
            if subtitleSelectionGeneration == generation {
                activeSubtitleSelectionTask = nil
            }
            throw error
        }
    }

    public func seek(to time: CMTime, startsPaused: Bool? = nil) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        if activeStereoTask != nil {
            throw PlaybackControlError.operationInProgress(.setStereoLayout)
        }
        subtitleSelectionGeneration &+= 1
        if let activeSubtitleSelectionTask {
            activeSubtitleSelectionTask.cancel()
            _ = try? await activeSubtitleSelectionTask.value
            self.activeSubtitleSelectionTask = nil
        }
        let time = clampedSeekTime(time)
        latestRequestedSeekTime = time
        seekGeneration += 1
        let generation = seekGeneration
        if let activeSeekTask {
            activeSeekTask.cancel()
            _ = try? await activeSeekTask.value
        }
        guard seekGeneration == generation else {
            let target = time.seconds.isFinite ? time.seconds : 0
            throw PlaybackControlError.seekSuperseded(target)
        }
        guard activeSession === session else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let paused = startsPaused ?? (status == .paused)
        let task = Task {
            try await session.seek(to: time, startsPaused: paused)
        }
        activeSeekTask = task
        do {
            try await task.value
            if seekGeneration == generation {
                activeSeekTask = nil
                latestRequestedSeekTime = nil
            }
        } catch {
            if seekGeneration == generation {
                activeSeekTask = nil
                latestRequestedSeekTime = nil
            }
            if error is CancellationError {
                let target = time.seconds.isFinite ? time.seconds : 0
                session.recordSupersededSeekRequest(targetSeconds: target)
                throw PlaybackControlError.seekSuperseded(target)
            }
            if case CorePlaybackError.seekSuperseded(let target) = error {
                throw PlaybackControlError.seekSuperseded(target)
            }
            throw error
        }
    }

    public func seek(by offset: CMTime, startsPaused: Bool? = nil) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let base = latestRequestedSeekTime ?? session.currentTime()
        let target = CMTime(
            seconds: base.seconds + offset.seconds,
            preferredTimescale: max(base.timescale, 600)
        )
        try await seek(to: target, startsPaused: startsPaused)
    }

    private func clampedSeekTime(_ time: CMTime) -> CMTime {
        let seconds = time.seconds.isFinite ? time.seconds : 0
        return CMTime(
            seconds: max(0, seconds),
            preferredTimescale: max(time.timescale, 600)
        )
    }

    @discardableResult
    public func switchRoute(to route: PlaybackRoute) async throws -> SampleBufferPlaybackSession {
        guard route != selectedRoute else {
            throw PlaybackControlError.routeAlreadySelected(route)
        }
        guard let url = selectedURL else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let startTime = activeSession?.currentTime() ?? .zero
        let startsPaused = activeSession.map { $0.currentRate() == 0 } ?? (status == .paused)
        let initialRate = activeSession?.preferredPlaybackRate ?? 1
        let volume = activeSession?.currentVolume ?? 1
        let muted = activeSession?.isMuted ?? false
        let audioStreamIndex = activeSession?.selectedAudioStreamIndex
        let stereoLayout = selectedStereoLayout
        let projectionOverride = selectedProjectionOverride
        let accessRequirement = mediaSlot.current?.source.accessRequirement
            ?? "appAdapterManaged"
        let sourceRoute = selectedRoute
        let startedAt = Date()
        await closeAndWait(clearSource: false)
        let session = try await open(
            url,
            asset: selectedAsset,
            route: route,
            startTime: startTime,
            startsPaused: startsPaused,
            initialRate: initialRate,
            initialStereoLayout: stereoLayout,
            initialProjectionOverride: projectionOverride,
            provenance: "coldRouteSwitch",
            accessRequirement: accessRequirement
        )
        try session.setVolume(volume)
        session.setMuted(muted)
        if let audioStreamIndex,
           session.availableAudioTracks.contains(where: { $0.streamIndex == audioStreamIndex }) {
            try await session.selectAudioTrack(streamIndex: audioStreamIndex)
        }
        session.registerPendingRouteSwitch(from: sourceRoute, startedAt: startedAt)
        return session
    }

    private static func providerRoute(for _: URL, asset _: PlaybackAsset?) -> PlaybackRoute {
        .ffmpegCompressed
    }

    @discardableResult
    public func reopen() async throws -> SampleBufferPlaybackSession {
        guard let url = selectedURL else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let route = selectedRoute
        let stereoLayout = selectedStereoLayout
        let projectionOverride = selectedProjectionOverride
        let accessRequirement = mediaSlot.current?.source.accessRequirement
            ?? "appAdapterManaged"
        await closeAndWait(clearSource: false)
        return try await open(
            url,
            asset: selectedAsset,
            route: route,
            initialStereoLayout: stereoLayout,
            initialProjectionOverride: projectionOverride,
            provenance: "reopen",
            accessRequirement: accessRequirement
        )
    }

    public func close(clearSource: Bool = true) {
        failedCleanupTask?.cancel()
        failedCleanupTask = nil
        if clearSource {
            selectedURL = nil
            selectedAsset = nil
        }
        stereoGeneration &+= 1
        activeStereoTask?.cancel()
        activeStereoTask = nil
        activeSeekTask?.cancel()
        activeSeekTask = nil
        subtitleSelectionGeneration &+= 1
        activeSubtitleSelectionTask?.cancel()
        activeSubtitleSelectionTask = nil
        latestRequestedSeekTime = nil
        guard let session = activeSession else {
            setStatus(.idle)
            return
        }
        beginPendingCleanup(for: session)
    }

    public func closeAndWait(clearSource: Bool = true) async {
        failedCleanupTask?.cancel()
        failedCleanupTask = nil
        if clearSource {
            selectedURL = nil
            selectedAsset = nil
        }
        stereoGeneration &+= 1
        subtitleSelectionGeneration &+= 1
        let closingStereoGeneration = stereoGeneration
        latestRequestedSeekTime = nil
        guard let session = activeSession else {
            activeSeekTask?.cancel()
            activeSeekTask = nil
            activeStereoTask?.cancel()
            activeStereoTask = nil
            activeSubtitleSelectionTask?.cancel()
            activeSubtitleSelectionTask = nil
            setStatus(.idle)
            await waitForPendingCleanup()
            return
        }
        if let activeSeekTask {
            activeSeekTask.cancel()
            _ = try? await activeSeekTask.value
            self.activeSeekTask = nil
        }
        if let activeStereoTask {
            activeStereoTask.cancel()
            _ = try? await activeStereoTask.value
            if stereoGeneration == closingStereoGeneration {
                self.activeStereoTask = nil
            }
        }
        if let activeSubtitleSelectionTask {
            activeSubtitleSelectionTask.cancel()
            _ = try? await activeSubtitleSelectionTask.value
            self.activeSubtitleSelectionTask = nil
        }
        if activeSession === session {
            beginPendingCleanup(for: session)
        }
        await waitForPendingCleanup()
    }

    public func writeDebugSnapshot() {
        debugRecorder?.writeSnapshotIgnoringErrors()
    }

    private func bindCallbacks(to session: SampleBufferPlaybackSession) {
        session.onStatusChange = { [weak self, weak session] status in
            Task { @MainActor in
                guard let self, let session else { return }
                let lifecycle = Self.lifecycle(for: status)
                guard self.activeSession === session else {
                    if let lifecycle {
                        _ = self.mediaSlot.updateLifecycle(
                            lifecycle,
                            mediaSessionID: session.traceID
                        )
                    }
                    self.recordStaleCallback(from: session, kind: "status")
                    return
                }
                if let lifecycle {
                    _ = self.mediaSlot.updateLifecycle(
                        lifecycle,
                        mediaSessionID: session.traceID
                    )
                }
                self.setStatus(status)
                if case .failed(let message) = status {
                    self.failedCleanupTask?.cancel()
                    self.failedCleanupTask = Task { @MainActor [weak self, weak session] in
                        guard let self, let session, self.activeSession === session else { return }
                        await self.releaseFailedSession(session, message: message)
                    }
                }
            }
        }
        session.onDiagnosticsChange = { [weak self, weak session] diagnostics in
            Task { @MainActor in
                guard let self, let session else { return }
                guard self.activeSession === session else {
                    self.recordStaleCallback(from: session, kind: "diagnostics")
                    return
                }
                self.diagnostics = diagnostics
                self.onDiagnosticsChange?(diagnostics)
            }
        }
        session.onSubtitleCuesChange = { [weak self, weak session] cues in
            Task { @MainActor in
                guard let self, let session else { return }
                guard self.activeSession === session else {
                    self.recordStaleCallback(from: session, kind: "subtitleCues")
                    return
                }
                self.onSubtitleCuesChange?(cues)
            }
        }
        session.onSubtitleFrameChange = { [weak self, weak session] frame in
            Task { @MainActor in
                guard let self, let session else { return }
                guard self.activeSession === session else {
                    self.recordStaleCallback(from: session, kind: "subtitleFrame")
                    return
                }
                self.onSubtitleFrameChange?(frame)
            }
        }
    }

    private func setStatus(_ status: PlaybackStatus) {
        self.status = status
        onStatusChange?(status)
    }

    private func rejectIfSeekIsInProgress() throws {
        if activeSeekTask != nil {
            throw PlaybackControlError.operationInProgress(.seek)
        }
        if activeStereoTask != nil {
            throw PlaybackControlError.operationInProgress(.setStereoLayout)
        }
    }

    private func beginPendingCleanup(
        for session: SampleBufferPlaybackSession,
        statusWhileClosing: PlaybackStatus = .idle
    ) {
        let mediaSessionID = session.traceID
        let recorder = debugRecorder
        pendingCleanupMediaSessionID = mediaSessionID
        debugRecorder = nil
        activeSession = nil
        onSessionChange?(nil)
        diagnostics = PlaybackDiagnostics()
        onDiagnosticsChange?(diagnostics)
        setStatus(statusWhileClosing)
        session.close { [weak self] in
            Task { @MainActor in
                guard let self else {
                    recorder?.stop()
                    return
                }
                self.finishPendingCleanup(
                    mediaSessionID: mediaSessionID,
                    recorder: recorder
                )
            }
        }
    }

    private func finishPendingCleanup(
        mediaSessionID: String,
        recorder: PlaybackDebugRecorder?
    ) {
        guard pendingCleanupMediaSessionID == mediaSessionID else {
            recorder?.stop()
            return
        }
        _ = mediaSlot.release(mediaSessionID: mediaSessionID)
        pendingCleanupMediaSessionID = nil
        recorder?.stop()
        let waiters = pendingCleanupWaiters
        pendingCleanupWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForPendingCleanup() async {
        guard pendingCleanupMediaSessionID != nil else { return }
        await withCheckedContinuation { continuation in
            pendingCleanupWaiters.append(continuation)
        }
    }

    private func releaseFailedSession(
        _ session: SampleBufferPlaybackSession,
        message: String
    ) async {
        if let activeSeekTask {
            activeSeekTask.cancel()
            _ = try? await activeSeekTask.value
            self.activeSeekTask = nil
        }
        stereoGeneration &+= 1
        let closingStereoGeneration = stereoGeneration
        if let activeStereoTask {
            activeStereoTask.cancel()
            _ = try? await activeStereoTask.value
            if stereoGeneration == closingStereoGeneration {
                self.activeStereoTask = nil
            }
        }
        guard activeSession === session else { return }
        failedCleanupTask = nil
        beginPendingCleanup(
            for: session,
            statusWhileClosing: .failed(message)
        )
        await waitForPendingCleanup()
    }

    private func recordStaleCallback(
        from session: SampleBufferPlaybackSession,
        kind: String
    ) {
        guard let activeSession else { return }
        activeSession.debugStore.recordStaleRejection()
        activeSession.debugStore.emit(
            mediaSessionID: activeSession.traceID,
            route: activeSession.route,
            kind: "callback.rejectedAsStale",
            outcome: .terminatedByCleanup,
            details: [
                "callbackKind": kind,
                "staleMediaSessionID": session.traceID,
            ]
        )
    }

    private static func lifecycle(for status: PlaybackStatus) -> PlaybackLifecycle? {
        switch status {
        case .idle: .idle
        case .loading: .opening
        case .ready: .ready
        case .playing: .playing
        case .paused: .paused
        case .ended: .ended
        case .failed: .failed
        }
    }

    private var platformName: String {
#if os(visionOS)
    #if targetEnvironment(simulator)
        "visionOSSimulator"
    #else
        "visionOS"
    #endif
#else
        "macOS"
#endif
    }

    private var hardwareDisplayFactAvailability: FactAvailability {
#if os(visionOS) && !targetEnvironment(simulator)
        .unknown
#else
        .notAvailable
#endif
    }
}

public enum PlaybackControlError: LocalizedError, Sendable {
    case noActiveMediaSession
    case routeAlreadySelected(PlaybackRoute)
    case openRejected(OpenRejectionRecord)
    case openTerminatedByCleanup
    case presentationNotAttached
    case seekSuperseded(Double)
    case timelineNotReady
    case invalidRate(Float)
    case invalidVolume(Float)
    case invalidAudioTrack(Int)
    case invalidSubtitleTrack(String)
    case operationInProgress(PlaybackOperationKind)
    case mediaSessionClosed

    public var errorDescription: String? {
        switch self {
        case .noActiveMediaSession:
            "There is no active media session."
        case .routeAlreadySelected(let route):
            "The \(route.label) route is already selected."
        case .openRejected(let rejection):
            "Open was rejected: \(rejection.reason)."
        case .openTerminatedByCleanup:
            "Open was terminated by cleanup."
        case .presentationNotAttached:
            "The renderer graph is not attached to the active presentation."
        case .seekSuperseded(let seconds):
            "Seek to \(seconds) seconds was superseded by a newer request."
        case .timelineNotReady:
            "The renderer timeline is not ready for this control request."
        case .invalidRate(let rate):
            "The requested playback rate \(rate) is invalid."
        case .invalidVolume(let volume):
            "The requested audio volume \(volume) is outside 0...1."
        case .invalidAudioTrack(let streamIndex):
            "Audio stream \(streamIndex) is not available in this source."
        case .invalidSubtitleTrack(let trackID):
            "Subtitle track \(trackID) is not available in this source."
        case .operationInProgress(let kind):
            "The \(kind.rawValue) operation is still in progress."
        case .mediaSessionClosed:
            "The media session is already closed."
        }
    }
}
