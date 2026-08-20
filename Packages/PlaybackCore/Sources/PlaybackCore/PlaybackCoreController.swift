import AVFoundation
import CoreMedia
import Foundation

enum PlaybackDebugRecorderMode: Equatable, Sendable {
    static let verificationDisableEnvironmentKey =
        "ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER"

    case enabled
    case disabledForVerification

    init(environment: [String: String]) {
        self = environment[Self.verificationDisableEnvironmentKey] == "1"
            ? .disabledForVerification
            : .enabled
    }
}

/// Owns PlaybackCore's single current media slot and the only product playback control path.
@MainActor
public final class PlaybackCoreController {
    public private(set) var activeSession: SampleBufferPlaybackSession?
    public private(set) var status = PlaybackStatus.idle
    public private(set) var diagnostics = PlaybackDiagnostics()
    public private(set) var selectedURL: URL?
    public private(set) var selectedAsset: PlaybackAsset?
    public private(set) var selectedStereoLayout: VideoStereoLayout?
    public private(set) var selectedProjectionOverride: VideoProjectionOverride?
    public private(set) var selectedDynamicRangeOverride: VideoDynamicRangeOverride?

    public var onStatusChange: ((PlaybackStatus) -> Void)?
    public var onDiagnosticsChange: ((PlaybackDiagnostics) -> Void)?
    public var onAcceptedVideoFormatRevisionChange: ((UInt64) -> Void)?
    public var onSessionChange: ((SampleBufferPlaybackSession?) -> Void)?
    public var onSubtitleCuesChange: (([PlaybackSubtitleCue]) -> Void)?
    public var onSubtitleFrameChange: ((PlaybackSubtitleFrame?) -> Void)?

    public var debugDirectoryURL: URL? {
        debugRecorder?.directoryURL
    }

    public var staleUpdateCount: Int {
        mediaSlot.staleUpdateCount
    }

    public var endedContinuity: PlaybackEndedContinuity? {
        guard case .ended(let reason) = status,
              let activeSession,
              let finalVideoPresentationTime =
                activeSession.finalDisplayableVideoPresentationTime,
              diagnostics.durationSeconds.isFinite,
              diagnostics.durationSeconds >= 0 else {
            return nil
        }
        return PlaybackEndedContinuity(
            reason: reason,
            logicalPosition: CMTime(
                seconds: diagnostics.durationSeconds,
                preferredTimescale: 60_000
            ),
            finalVideoPresentationTime: finalVideoPresentationTime
        )
    }

    private var mediaSlot = MediaSessionState()
    private var debugRecorder: PlaybackDebugRecorder?
    private let debugRecorderMode: PlaybackDebugRecorderMode
    private let sessionFactory: (String) -> SampleBufferPlaybackSession
    private var activeSeekTask: Task<Void, Error>?
    private var activeSubtitleSelectionTask: Task<Void, Error>?
    private var activeFormatOverrideTask: Task<UInt64, Error>?
    private var failedCleanupTask: Task<Void, Never>?
    private var pendingCleanupMediaSessionID: String?
    private var pendingCleanupWaiters: [CheckedContinuation<Void, Never>] = []
    private var replacementRetirementTasks: [UUID: Task<Void, Never>] = [:]
    private var latestRequestedSeekTime: CMTime?
    private var seekGeneration: UInt64 = 0
    private var subtitleSelectionGeneration: UInt64 = 0
    private var formatOverrideGeneration: UInt64 = 0
    private var selectedSourceIsRemote = false

    public init() {
        sessionFactory = { sessionID in
            SampleBufferPlaybackSession(traceID: sessionID)
        }
        #if DEBUG
        debugRecorderMode = PlaybackDebugRecorderMode(
            environment: ProcessInfo.processInfo.environment
        )
        #else
        debugRecorderMode = .enabled
        #endif
    }

    init(
        sessionFactory: @escaping (String) -> SampleBufferPlaybackSession,
        debugRecorderMode: PlaybackDebugRecorderMode = .enabled
    ) {
        self.sessionFactory = sessionFactory
        self.debugRecorderMode = debugRecorderMode
    }

    /// Opens one media session after pending cleanup, applying initial rate and format before playback starts.
    @discardableResult
    public func open(
        _ url: URL,
        asset: PlaybackAsset? = nil,
        startTime: CMTime = .zero,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        sourceIsRemote: Bool = false,
        initialStereoLayout: VideoStereoLayout? = nil,
        initialProjectionOverride: VideoProjectionOverride? = nil,
        initialDynamicRangeOverride: VideoDynamicRangeOverride? = nil,
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
            initialTimeSeconds: startTime.seconds,
            startsPaused: startsPaused,
            initialRate: initialRate,
            mediaSessionID: sessionID
        ) {
        case .rejected(let rejection):
            activeSession?.debugStore.recordOpenRejection(rejection)
            activeSession?.debugStore.emit(
                mediaSessionID: activeSession?.traceID,
                node: .mediaSessionBinding,
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
        selectedSourceIsRemote = sourceIsRemote
        setStatus(.loading)
        let session = sessionFactory(sessionID)
        if initialStereoLayout != nil || initialProjectionOverride != nil
            || initialDynamicRangeOverride != nil {
            _ = try await session.setFormatOverrides(
                stereoLayout: initialStereoLayout,
                projection: initialProjectionOverride,
                dynamicRange: initialDynamicRangeOverride
            )
        }
        activeSession = session
        if debugRecorderMode == .enabled {
            debugRecorder = PlaybackDebugRecorder(session: session, platform: platformName)
        }
        session.debugStore.recordPlatform(
            platformName,
            hardwareDisplayFacts: hardwareDisplayFactAvailability
        )
        bindCallbacks(to: session)
        onSessionChange?(session)

        session.debugStore.emit(
            mediaSessionID: sessionID,
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
            node: .mediaSessionBinding,
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
                sourceIsRemote: sourceIsRemote,
                provenance: provenance,
                accessRequirement: accessRequirement
            )
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedStereoLayout = initialStereoLayout
            selectedProjectionOverride = initialProjectionOverride
            selectedDynamicRangeOverride = initialDynamicRangeOverride
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

    public func playWithExternallyManagedFirstVideoFrameDeadline() throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        try rejectIfSeekIsInProgress()
        try activeSession.play(armingFirstVideoFrameDeadline: false)
    }

    /// Waits until the first delivered sample has anchored the renderer
    /// synchronizer. A prepared and attached session can report `ready`
    /// before that asynchronous media-time boundary exists.
    public func waitUntilTimelineReadyForControl() async throws {
        guard let expectedSession = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        while expectedSession.debugSnapshot().rendererState?.timelineConfigured != true {
            guard activeSession === expectedSession else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            if case .failed = status {
                throw PlaybackControlError.timelineNotReady
            }
            try await Task.sleep(for: .milliseconds(25))
        }
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

    public func clearDisplayedVideoImage(forMediaSessionID mediaSessionID: String) async {
        guard let activeSession, activeSession.traceID == mediaSessionID else { return }
        await activeSession.clearDisplayedVideoImage()
    }

    public func suspendVideoSampleDelivery(flushingRenderer: Bool = false) async throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        await activeSession.suspendVideoSampleDelivery(flushingRenderer: flushingRenderer)
        guard self.activeSession === activeSession else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
    }

    public func resumeVideoSampleDelivery() throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        activeSession.resumeVideoSampleDelivery()
    }

    /// Hands the caller a renderer its next RealityView Entity has never bound,
    /// leaving the source open and the timeline running. Video sample delivery
    /// stays suspended until the caller has bound the renderer and calls
    /// `restartVideoSampleDelivery(at:)`.
    public func replaceVideoRendererGraph() async throws -> AVSampleBufferVideoRenderer {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        let replacement = try await activeSession.replaceVideoRendererGraph()
        guard self.activeSession === activeSession else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        return replacement
    }

    /// Removes the renderer the previous Scene was presenting. Call it once that
    /// Scene has gone, not before, so the transition never shows an empty surface.
    public func retireDepartingVideoRendererGraph() async {
        await activeSession?.retireDepartingVideoRendererGraph()
    }

    public func restartVideoSampleDelivery(
        at time: CMTime,
        after behavior: PlaybackAfterSeekBehavior = .preserveCurrentPauseState
    ) async throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        activeSession.allowVideoSampleDeliveryRestart()
        do {
            try await seek(to: time, after: behavior)
        } catch {
            if self.activeSession === activeSession {
                activeSession.startVideoDelivery()
            }
            throw error
        }
    }

    public func restartVideoSampleDelivery(
        preserving continuity: PlaybackEndedContinuity
    ) async throws {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        activeSession.allowVideoSampleDeliveryRestart()
        do {
            try await seek(
                to: continuity.finalVideoPresentationTime,
                after: .pause,
                removingDisplayedImage: false,
                requiresAudioTarget: false
            )
            guard self.activeSession === activeSession else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeSession.restoreEndedPresentation(continuity)
            _ = mediaSlot.updateLifecycle(
                .ended,
                mediaSessionID: activeSession.traceID
            )
            diagnostics.currentSeconds = continuity.logicalPosition.seconds
            setStatus(.ended(continuity.reason))
        } catch {
            if self.activeSession === activeSession {
                activeSession.startVideoDelivery()
            }
            throw error
        }
    }

    /// Applies an explicit Play command, then proves that the current renderer
    /// graph accepts later input, runs its timebase, and displays later frames.
    public func playAndVerifyRendererGraphContinuity(
        timeout: Duration = .seconds(3)
    ) async throws -> RendererGraphPlaybackContinuity {
        guard let activeSession else { throw PlaybackControlError.noActiveMediaSession }
        let baseline = activeSession.rendererGraphPlaybackObservation()
        try play()
        guard self.activeSession === activeSession else {
            throw PlaybackControlError.openTerminatedByCleanup
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let result = RendererGraphPlaybackContinuity.evaluate(
                baseline: baseline,
                current: activeSession.rendererGraphPlaybackObservation(),
                requiredGraphRevision: baseline.graphRevision
            )
            if result == .ready { return .ready }
            try await Task.sleep(for: .milliseconds(25))
        }
        return RendererGraphPlaybackContinuity.evaluate(
            baseline: baseline,
            current: activeSession.rendererGraphPlaybackObservation(),
            requiredGraphRevision: baseline.graphRevision
        )
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

    /// Applies projection and stereo interpretation at one renderer-input revision.
    @discardableResult
    public func setFormatOverrides(
        stereoLayout: VideoStereoLayout?,
        projection: VideoProjectionOverride?,
        dynamicRange: VideoDynamicRangeOverride? = nil
    ) async throws -> UInt64 {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        if activeFormatOverrideTask != nil {
            throw PlaybackControlError.operationInProgress(.setFormatOverrides)
        }
        formatOverrideGeneration &+= 1
        let generation = formatOverrideGeneration
        let task = Task {
            try await session.setFormatOverrides(
                stereoLayout: stereoLayout,
                projection: projection,
                dynamicRange: dynamicRange
            )
        }
        activeFormatOverrideTask = task
        do {
            let revision = try await task.value
            guard formatOverrideGeneration == generation else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeFormatOverrideTask = nil
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedStereoLayout = stereoLayout
            selectedProjectionOverride = projection
            selectedDynamicRangeOverride = dynamicRange
            return revision
        } catch {
            if formatOverrideGeneration == generation {
                activeFormatOverrideTask = nil
            }
            throw error
        }
    }

    private func updateProjectionOverride(
        _ projection: VideoProjectionOverride?
    ) async throws -> UInt64 {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        if activeFormatOverrideTask != nil {
            throw PlaybackControlError.operationInProgress(.setProjection)
        }
        formatOverrideGeneration &+= 1
        let generation = formatOverrideGeneration
        let task = Task {
            if let projection {
                return try await session.setProjectionOverride(projection)
            }
            return try await session.clearProjectionOverride()
        }
        activeFormatOverrideTask = task
        do {
            let revision = try await task.value
            guard formatOverrideGeneration == generation else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeFormatOverrideTask = nil
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedProjectionOverride = projection
            return revision
        } catch {
            if formatOverrideGeneration == generation {
                activeFormatOverrideTask = nil
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
        if activeFormatOverrideTask != nil {
            throw PlaybackControlError.operationInProgress(.setStereoLayout)
        }
        formatOverrideGeneration &+= 1
        let generation = formatOverrideGeneration
        let task = Task {
            if let layout {
                return try await session.setStereoLayout(layout)
            }
            return try await session.clearStereoLayoutOverride()
        }
        activeFormatOverrideTask = task
        do {
            let revision = try await task.value
            guard formatOverrideGeneration == generation else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            activeFormatOverrideTask = nil
            guard activeSession === session else {
                throw PlaybackControlError.openTerminatedByCleanup
            }
            selectedStereoLayout = layout
            return revision
        } catch {
            if formatOverrideGeneration == generation {
                activeFormatOverrideTask = nil
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

    /// Includes the active decoder graph and every graph still completing its
    /// destructive retirement. This is the physical overlap count used when
    /// profiling high-resolution presentation changes.
    public var liveTechnicalSessionCount: Int {
        (activeSession == nil ? 0 : 1) + replacementRetirementTasks.count
    }

    public var retiringTechnicalSessionCount: Int {
        replacementRetirementTasks.count
    }

    public var activeSubtitleCues: [PlaybackSubtitleCue] {
        activeSession?.activeSubtitleCues ?? []
    }

    public var activeSubtitleFrame: PlaybackSubtitleFrame? {
        activeSession?.activeSubtitleFrame
    }

    public func addExternalSubtitleSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> [PlaybackSubtitleTrack] {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        let tracks = try await session.addExternalSubtitleSource(source)
        guard activeSession === session else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        return tracks
    }

    public func removeExternalSubtitleSource(id sourceID: String) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try rejectIfSeekIsInProgress()
        subtitleSelectionGeneration &+= 1
        let generation = subtitleSelectionGeneration
        if let activeSubtitleSelectionTask {
            activeSubtitleSelectionTask.cancel()
            _ = try? await activeSubtitleSelectionTask.value
            self.activeSubtitleSelectionTask = nil
        }
        guard subtitleSelectionGeneration == generation,
              activeSession === session else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        try session.removeExternalSubtitleSource(id: sourceID)
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

    /// Seeks the current media session and applies an explicit after-seek playback behavior.
    public func seek(
        to time: CMTime,
        after behavior: PlaybackAfterSeekBehavior = .preserveCurrentPauseState
    ) async throws {
        try await seek(
            to: time,
            after: behavior,
            removingDisplayedImage: true,
            requiresAudioTarget: true
        )
    }

    private func seek(
        to time: CMTime,
        after behavior: PlaybackAfterSeekBehavior,
        removingDisplayedImage: Bool,
        requiresAudioTarget: Bool
    ) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        if activeFormatOverrideTask != nil {
            throw PlaybackControlError.operationInProgress(.setFormatOverrides)
        }
        subtitleSelectionGeneration &+= 1
        if let activeSubtitleSelectionTask {
            activeSubtitleSelectionTask.cancel()
            _ = try? await activeSubtitleSelectionTask.value
            self.activeSubtitleSelectionTask = nil
        }
        let time = try session.clampedSeekTime(time)
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
        let paused = behavior.resolvesStartsPaused(for: status)
        let task = Task {
            try await session.seek(
                to: time,
                startsPaused: paused,
                removingDisplayedImage: removingDisplayedImage,
                requiresAudioTarget: requiresAudioTarget
            )
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

    /// Seeks relative to the latest requested position and applies an explicit after-seek behavior.
    public func seek(
        by offset: CMTime,
        after behavior: PlaybackAfterSeekBehavior = .preserveCurrentPauseState
    ) async throws {
        guard let session = activeSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let base = latestRequestedSeekTime ?? session.currentTime()
        let target = CMTime(
            seconds: base.seconds + offset.seconds,
            preferredTimescale: max(base.timescale, 600)
        )
        try await seek(to: target, after: behavior)
    }

    /// Preserves source compatibility while callers migrate from the nullable pause flag.
    @available(*, deprecated, message: "Use seek(to:after:) with PlaybackAfterSeekBehavior.")
    public func seek(to time: CMTime, startsPaused: Bool?) async throws {
        try await seek(to: time, after: Self.afterSeekBehavior(startsPaused: startsPaused))
    }

    /// Preserves source compatibility while callers migrate from the nullable pause flag.
    @available(*, deprecated, message: "Use seek(by:after:) with PlaybackAfterSeekBehavior.")
    public func seek(by offset: CMTime, startsPaused: Bool?) async throws {
        try await seek(by: offset, after: Self.afterSeekBehavior(startsPaused: startsPaused))
    }

    private static func afterSeekBehavior(
        startsPaused: Bool?
    ) -> PlaybackAfterSeekBehavior {
        switch startsPaused {
        case nil: .preserveCurrentPauseState
        case false: .play
        case true: .pause
        }
    }

    @discardableResult
    public func reopen() async throws -> SampleBufferPlaybackSession {
        guard let url = selectedURL else {
            throw PlaybackControlError.noActiveMediaSession
        }
        let stereoLayout = selectedStereoLayout
        let projectionOverride = selectedProjectionOverride
        let dynamicRangeOverride = selectedDynamicRangeOverride
        let accessRequirement = mediaSlot.current?.source.accessRequirement
            ?? "appAdapterManaged"
        await closeAndWait(clearSource: false)
        return try await open(
            url,
            asset: selectedAsset,
            sourceIsRemote: selectedSourceIsRemote,
            initialStereoLayout: stereoLayout,
            initialProjectionOverride: projectionOverride,
            initialDynamicRangeOverride: dynamicRangeOverride,
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
            selectedSourceIsRemote = false
        }
        formatOverrideGeneration &+= 1
        activeFormatOverrideTask?.cancel()
        activeFormatOverrideTask = nil
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
            selectedSourceIsRemote = false
        }
        formatOverrideGeneration &+= 1
        subtitleSelectionGeneration &+= 1
        let closingFormatOverrideGeneration = formatOverrideGeneration
        latestRequestedSeekTime = nil
        guard let session = activeSession else {
            activeSeekTask?.cancel()
            activeSeekTask = nil
            activeFormatOverrideTask?.cancel()
            activeFormatOverrideTask = nil
            activeSubtitleSelectionTask?.cancel()
            activeSubtitleSelectionTask = nil
            setStatus(.idle)
            await waitForPendingCleanup()
            await waitForReplacementRetirements()
            return
        }
        if let activeSeekTask {
            activeSeekTask.cancel()
            _ = try? await activeSeekTask.value
            self.activeSeekTask = nil
        }
        if let activeFormatOverrideTask {
            activeFormatOverrideTask.cancel()
            _ = try? await activeFormatOverrideTask.value
            if formatOverrideGeneration == closingFormatOverrideGeneration {
                self.activeFormatOverrideTask = nil
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
        await waitForReplacementRetirements()
    }

    /// Irreversibly removes the current technical session from the control
    /// slot, then releases its decoder graph in the background. A replacement
    /// may be opened immediately; callers must never try to reactivate the
    /// retiring instance.
    @discardableResult
    public func retireActiveSessionForReplacement() -> Task<Void, Never>? {
        failedCleanupTask?.cancel()
        failedCleanupTask = nil
        formatOverrideGeneration &+= 1
        activeFormatOverrideTask?.cancel()
        activeFormatOverrideTask = nil
        activeSeekTask?.cancel()
        activeSeekTask = nil
        subtitleSelectionGeneration &+= 1
        activeSubtitleSelectionTask?.cancel()
        activeSubtitleSelectionTask = nil
        latestRequestedSeekTime = nil

        guard let session = activeSession else { return nil }
        let mediaSessionID = session.traceID
        let recorder = debugRecorder
        debugRecorder = nil
        activeSession = nil
        onSessionChange?(nil)
        diagnostics = PlaybackDiagnostics()
        onDiagnosticsChange?(diagnostics)
        _ = mediaSlot.release(mediaSessionID: mediaSessionID)
        setStatus(.idle)

        let retirementID = UUID()
        let retirement = Task { @MainActor in
            await session.closeAndWait()
            recorder?.stop()
        }
        replacementRetirementTasks[retirementID] = retirement
        Task { @MainActor [weak self] in
            await retirement.value
            self?.replacementRetirementTasks[retirementID] = nil
        }
        return retirement
    }

    public func writeDebugSnapshot() {
        debugRecorder?.writeSnapshotIgnoringErrors()
    }

    #if DEBUG
    public func debugEvidenceJSON() -> String? {
        debugRecorder?.diagnosticEvidenceJSON()
    }
    #endif

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
        session.onAcceptedVideoFormatRevisionChange = { [weak self, weak session] revision in
            Task { @MainActor in
                guard let self, let session else { return }
                guard self.activeSession === session else {
                    self.recordStaleCallback(from: session, kind: "videoFormatRevision")
                    return
                }
                self.onAcceptedVideoFormatRevisionChange?(revision)
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
        if activeFormatOverrideTask != nil {
            throw PlaybackControlError.operationInProgress(.setFormatOverrides)
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

    private func waitForReplacementRetirements() async {
        let retirements = Array(replacementRetirementTasks.values)
        for retirement in retirements {
            await retirement.value
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
        formatOverrideGeneration &+= 1
        let closingFormatOverrideGeneration = formatOverrideGeneration
        if let activeFormatOverrideTask {
            activeFormatOverrideTask.cancel()
            _ = try? await activeFormatOverrideTask.value
            if formatOverrideGeneration == closingFormatOverrideGeneration {
                self.activeFormatOverrideTask = nil
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
#if targetEnvironment(simulator)
        "visionOSSimulator"
#else
        "visionOS"
#endif
    }

    private var hardwareDisplayFactAvailability: FactAvailability {
#if !targetEnvironment(simulator)
        .unknown
#else
        .notAvailable
#endif
    }
}

public enum PlaybackControlError: LocalizedError, Sendable {
    case noActiveMediaSession
    case openRejected(OpenRejectionRecord)
    case openTerminatedByCleanup
    case presentationNotAttached
    case seekSuperseded(Double)
    case invalidSeekTime(Double)
    case timelineNotReady
    case invalidRate(Float)
    case invalidVolume(Float)
    case invalidAudioTrack(Int)
    case invalidSubtitleTrack(String)
    case externalSubtitleHasNoSupportedTracks(String)
    case operationInProgress(PlaybackOperationKind)
    case mediaSessionClosed

    public var errorDescription: String? {
        switch self {
        case .noActiveMediaSession:
            "There is no active media session."
        case .openRejected(let rejection):
            "Open was rejected: \(rejection.reason)."
        case .openTerminatedByCleanup:
            "Open was terminated by cleanup."
        case .presentationNotAttached:
            "The renderer graph is not attached to the active presentation."
        case .seekSuperseded(let seconds):
            "Seek to \(seconds) seconds was superseded by a newer request."
        case .invalidSeekTime(let seconds):
            "The requested seek time \(seconds) is not finite."
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
        case .externalSubtitleHasNoSupportedTracks(let displayName):
            "\(displayName) does not contain a supported subtitle track."
        case .operationInProgress(let kind):
            "The \(kind.rawValue) operation is still in progress."
        case .mediaSessionClosed:
            "The media session is already closed."
        }
    }
}
