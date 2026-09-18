import Foundation
import MediaSource
import Observation
import OSLog

@MainActor
public protocol PlaybackLaunching: AnyObject {
    func beginPlayback(_ request: PlaybackLaunchRequest)
    func stopPlayback(reason: PlaybackLeaveReason)
}

@MainActor
@Observable
public final class PlaybackLaunchCoordinator: PlaybackLaunching {
    public let preparation = MediaSourcePreparation()
    private var pendingLaunchRequest: PlaybackLaunchRequest?

    public struct ResumeDecision {
        enum Outcome {
            case launch(
                request: PlaybackLaunchRequest,
                format: MediaFormat?,
                playbackMode: PersistedPlaybackMode,
                trackSelectionPreference: TrackSelectionPreference?
            )
            case choice(@MainActor (Bool) -> Void)
        }

        public let seconds: Double
        let outcome: Outcome
    }

    private struct ResolvedLaunch {
        let launchGeneration: Int
        let request: PlaybackLaunchRequest
        let resumeSeconds: Double?
        var savedFormat: MediaFormat?
        var playbackMode: PersistedPlaybackMode
        var trackSelectionPreference: TrackSelectionPreference?
    }

    private struct ActiveFailureRecovery {
        let failure: PlaybackActiveFailure
        let resolvedLaunch: ResolvedLaunch
    }

    private struct ActiveFailureRetry {
        let recovery: ActiveFailureRecovery
        let launchGeneration: Int
        let runtimeGeneration: UInt64
        let request: PlaybackLaunchRequest
        var launchConfigurationCompleted: Bool
    }

    private enum PlaybackRequestOrigin {
        case userInitiated
        case automaticContinuation
    }

    private struct MediaFormatRequestTarget: Equatable {
        let requestID: UInt64
        let launchGeneration: Int
        let mediaSessionID: String?
        let versionedIdentity: VersionedMediaIdentity?
    }

    private struct MediaServerReportingSession {
        enum Phase {
            case armed
            case active
            case finished
        }

        let generation: Int
        let runtimeGeneration: UInt64
        let reporter: any PlaybackSessionReporting
        var phase: Phase
        var lastReport: PlaybackSessionReport
        var lastLifecycle: ProductPlaybackLifecycle
        var nextPeriodicThresholdSeconds: Double
        var launchConfigurationCompleted: Bool
    }

    private let playbackRuntime: any PlaybackRuntimeControlling
    private let mediaStateStore: MediaStateStore
    private let preferencesProvider: PlaybackPreferencesProviding
    private let metadataService: PlaybackMediaMetadataService
    private let networkMonitor: any NetworkConnectivityWaiting
    private let requestResolutionTimeout: Duration
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackLaunch")

    public var nextFileProvider: (@MainActor @Sendable () async -> PlaybackLaunchRequest?)?
    public var hasNextPlaybackItemProvider: (@MainActor @Sendable () -> Bool)?
    public var playbackQueueProvider: (@MainActor () -> PlaybackQueueSnapshot)?
    public var queueSelectionProvider: (@MainActor @Sendable (UUID) async -> PlaybackLaunchRequest?)?
    public var onEffectiveMediaFormatApplied: (
        @MainActor (EffectiveMediaFormatInterpretation) -> Void
    )?
    public var onPlaybackModeEntryStarted: (
        @MainActor (PersistedPlaybackMode, Bool) -> PersistedPlaybackMode
    )?
    public var onViewingStatesCleared: (@MainActor () -> Void)?
    public var onPlaybackIntentStarted: (@MainActor () -> Void)?
    public var onPlaybackStopRequested: (@MainActor () -> Void)?
    public private(set) var pendingResumeDecision: ResumeDecision?
    public private(set) var isResolvingPlaybackRequest = false
    public private(set) var resumePromptPresentationCount = 0
    public private(set) var automaticResumeBypassCount = 0

    private var launchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var mediaStateMutationTask: Task<Void, Never>?
    private var mediaFormatCoreOperationTask: Task<Void, Error>?
    private var mediaFormatRequestID: UInt64 = 0
    private var generation = 0
    private var lastResolvedLaunch: ResolvedLaunch?
    private var pendingRequestResolution: (@MainActor () async throws -> PlaybackLaunchRequest)?
    private var activeFailureRecovery: ActiveFailureRecovery?
    private var activeFailureRetry: ActiveFailureRetry?
    private var mediaServerReportingSession: MediaServerReportingSession?

    public init(
        playbackRuntime: any PlaybackRuntimeControlling,
        mediaStateSuiteName: String? = nil,
        preferencesProvider: PlaybackPreferencesProviding = DefaultPlaybackPreferencesProvider(),
        requestResolutionTimeout: Duration = .seconds(15)
    ) {
        self.playbackRuntime = playbackRuntime
        self.mediaStateStore = MediaStateStore(suiteName: mediaStateSuiteName)
        self.preferencesProvider = preferencesProvider
        self.metadataService = PlaybackMediaMetadataService()
        self.networkMonitor = MediaSourceServices.makeNetworkConnectivityWaiter()
        self.requestResolutionTimeout = requestResolutionTimeout

        playbackRuntime.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                let metadata = await self.metadataService.recordDetectedProfile(profile, for: request)
                guard self.playbackRuntime.currentLaunchRequest == request else { return }
                self.playbackRuntime.applyPrefetchedMetadata(metadata)
            }
        }
        playbackRuntime.onPlaybackObservation = { [weak self] observation in
            self?.receivePlaybackObservation(observation)
        }
    }

    public func viewingState(for identity: MediaIdentity) async -> ViewingStatus? {
        await mediaStateMutationTask?.value
        return await mediaStateStore.viewingProjection(for: identity)
    }

    public func knownDuration(for identity: MediaIdentity) async -> Double? {
        await mediaStateMutationTask?.value
        return await mediaStateStore.knownDurationProjection(for: identity)
    }

    public func recordKnownDuration(
        _ durationSeconds: Double,
        for identity: VersionedMediaIdentity
    ) async {
        await enqueueMediaStateMutation { store in
            await store.recordKnownDuration(durationSeconds, for: identity)
        }.value
    }

    #if DEBUG
    public func debugViewingStateSnapshot() async -> ViewingStateDiagnosticSnapshot {
        await mediaStateMutationTask?.value
        return await mediaStateStore.debugSnapshot()
    }
    #endif

    public func requestPlayback(_ request: PlaybackLaunchRequest) {
        pendingRequestResolution = nil
        requestPlayback(request, origin: .userInitiated)
    }

    public func requestPlayback(
        resolving resolve: @escaping @MainActor () async throws -> PlaybackLaunchRequest
    ) {
        pendingRequestResolution = resolve
        isResolvingPlaybackRequest = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isResolvingPlaybackRequest = false }
            do {
                let request = try await preparation.resolve {
                    try await self.resolveRequestWithTimeout(resolve)
                }
                self.requestPlayback(request)
            } catch is CancellationError {
                return
            } catch {
                logger.error(
                    "playback request resolution failed error=\(error.localizedDescription, privacy: .public)"
                )
                self.playbackRuntime.setUserVisibleIssue(
                    Self.requestResolutionIssue(for: error)
                )
            }
        }
    }

    static func requestResolutionIssue(for error: Error) -> PlaybackUserVisibleIssue {
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return .connectionFailed
        }
        return .mediaRequestFailed
    }

    private func resolveRequestWithTimeout(
        _ resolve: @escaping @MainActor () async throws -> PlaybackLaunchRequest
    ) async throws -> PlaybackLaunchRequest {
        try await withThrowingTaskGroup(of: PlaybackLaunchRequest.self) { group in
            group.addTask { try await resolve() }
            group.addTask {
                try await Task.sleep(for: self.requestResolutionTimeout)
                throw URLError(.timedOut)
            }
            guard let request = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return request
        }
    }

    private func requestPlayback(
        _ request: PlaybackLaunchRequest,
        origin: PlaybackRequestOrigin
    ) {
        preparation.cancel()
        releasePendingLaunch(excluding: request)
        pendingLaunchRequest = request
        activeFailureRecovery = nil
        activeFailureRetry = nil
        playbackRuntime.setUserVisibleIssue(nil)
        generation += 1
        let requestGeneration = generation
        pendingResumeDecision = nil
        Task { [weak self] in
            guard let self else { return }
            await mediaStateMutationTask?.value
            guard generation == requestGeneration else { return }
            switch request.viewingStateAuthority {
            case .enchronPersistence:
                let persistedState: PersistedMediaState? = if let identity = request.versionedIdentity {
                    await mediaStateStore.loadValidated(for: identity)
                } else { nil }
                guard generation == requestGeneration else { return }
                let playbackMode = persistedState?.playbackModePreference ?? .window
                let seconds: Double
                if let status = persistedState?.viewingStatus,
                   case .resumable(let position, _) = status {
                    seconds = position
                } else {
                    seconds = 0
                }
                switch (preferencesProvider.loadPlaybackPreferences().resumePolicy, origin) {
                case (.askEveryTime, .userInitiated) where seconds > 0:
                    resumePromptPresentationCount += 1
                    pendingResumeDecision = ResumeDecision(
                        seconds: seconds,
                        outcome: .launch(
                            request: request,
                            format: persistedState?.formatPreference,
                            playbackMode: playbackMode,
                            trackSelectionPreference: persistedState?.trackSelectionPreference
                        )
                    )
                case (.alwaysResume, _) where seconds > 0:
                    launchResolvedPlayback(
                        request,
                        resumeAt: seconds,
                        savedFormat: persistedState?.formatPreference,
                        playbackMode: playbackMode,
                        trackSelectionPreference: persistedState?.trackSelectionPreference
                    )
                case (.askEveryTime, .automaticContinuation) where seconds > 0:
                    automaticResumeBypassCount += 1
                    launchResolvedPlayback(
                        request,
                        resumeAt: seconds,
                        savedFormat: persistedState?.formatPreference,
                        playbackMode: playbackMode,
                        trackSelectionPreference: persistedState?.trackSelectionPreference
                    )
                default:
                    launchResolvedPlayback(
                        request,
                        resumeAt: nil,
                        savedFormat: persistedState?.formatPreference,
                        playbackMode: playbackMode,
                        trackSelectionPreference: persistedState?.trackSelectionPreference
                    )
                }
            case .mediaServer:
                let presentationPreferences: PersistedPlaybackPresentationPreferences? =
                    if let identity = request.versionedIdentity {
                        await mediaStateStore.loadPlaybackPresentationPreferencesValidated(
                            for: identity
                        )
                    } else { nil }
                guard generation == requestGeneration else { return }
                launchResolvedPlayback(
                    request,
                    resumeAt: request.startPositionSeconds,
                    savedFormat: presentationPreferences?.format,
                    playbackMode: presentationPreferences?.playbackMode ?? .window,
                    trackSelectionPreference: nil
                )
            }
        }
    }

    public func resumePendingPlayback() {
        settlePendingResumeDecision(resuming: true)
    }

    public func startPendingPlaybackFromBeginning() {
        settlePendingResumeDecision(resuming: false)
    }

    public func cancelPendingResumeDecision() {
        guard pendingResumeDecision != nil else { return }
        pendingResumeDecision = nil
        releasePendingLaunch()
        generation += 1
    }

    public func decideResume(
        fromSeconds seconds: Double,
        onChoice: @escaping @MainActor (Bool) -> Void
    ) {
        pendingResumeDecision = nil
        guard seconds > 0 else {
            onChoice(false)
            return
        }
        switch preferencesProvider.loadPlaybackPreferences().resumePolicy {
        case .askEveryTime:
            resumePromptPresentationCount += 1
            pendingResumeDecision = ResumeDecision(seconds: seconds, outcome: .choice(onChoice))
        case .alwaysResume:
            onChoice(true)
        case .alwaysStartFromBeginning:
            onChoice(false)
        }
    }

    private func settlePendingResumeDecision(resuming: Bool) {
        guard let decision = pendingResumeDecision else { return }
        pendingResumeDecision = nil
        switch decision.outcome {
        case let .launch(request, format, playbackMode, trackSelectionPreference):
            launchResolvedPlayback(
                request,
                resumeAt: resuming ? decision.seconds : nil,
                savedFormat: format,
                playbackMode: playbackMode,
                trackSelectionPreference: trackSelectionPreference
            )
        case let .choice(deliver):
            deliver(resuming)
        }
    }

    public func beginPlayback(_ request: PlaybackLaunchRequest) {
        requestPlayback(request)
    }

    public var canRetryActiveFailure: Bool {
        guard let failure = playbackRuntime.userVisibleIssue?
            .activePlaybackFailure,
              let recovery = activeFailureRecovery else { return false }
        return recovery.failure == failure
    }

    public func retryPlayback() {
        if playbackRuntime.userVisibleIssue == .connectionFailed,
           let resolve = pendingRequestResolution {
            playbackRuntime.setUserVisibleIssue(nil)
            requestPlayback(resolving: resolve)
            return
        }
        if playbackRuntime.userVisibleIssue?.activePlaybackFailure != nil {
            retryActiveFailure()
            return
        }
        guard let lastResolvedLaunch else { return }
        launchResolvedPlayback(
            lastResolvedLaunch.request,
            resumeAt: lastResolvedLaunch.resumeSeconds,
            savedFormat: lastResolvedLaunch.savedFormat,
            playbackMode: lastResolvedLaunch.playbackMode,
            trackSelectionPreference: lastResolvedLaunch.trackSelectionPreference
        )
    }

    @discardableResult
    public func relaunchLastResolvedPlayback(
        resumeAt seconds: Double?,
        playbackMode: PersistedPlaybackMode
    ) -> Bool {
        guard let lastResolvedLaunch else { return false }
        launchResolvedPlayback(
            lastResolvedLaunch.request,
            resumeAt: seconds,
            savedFormat: lastResolvedLaunch.savedFormat,
            playbackMode: playbackMode,
            trackSelectionPreference: lastResolvedLaunch.trackSelectionPreference
        )
        return true
    }

    @discardableResult
    public func retryActiveFailure(
        playbackMode overrideMode: PersistedPlaybackMode? = nil
    ) -> Bool {
        guard let failure = playbackRuntime.userVisibleIssue?
            .activePlaybackFailure,
              let recovery = activeFailureRecovery,
              recovery.failure == failure else { return false }
        launchResolvedPlayback(
            recovery.resolvedLaunch.request,
            resumeAt: failure.causalPosition.seconds,
            savedFormat: recovery.resolvedLaunch.savedFormat,
            playbackMode: overrideMode ?? recovery.resolvedLaunch.playbackMode,
            trackSelectionPreference: recovery.resolvedLaunch.trackSelectionPreference,
            retrying: recovery
        )
        return true
    }

    public var playbackQueue: PlaybackQueueSnapshot {
        playbackQueueProvider?() ?? .empty
    }

    public func selectPlaybackQueueItem(_ id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            guard let request = try? await preparation.resolve({
                await self.queueSelectionProvider?(id)
            }) else { return }
            requestPlayback(request)
        }
    }

    public func clearViewingStates() {
        let clearing = enqueueMediaStateMutation { store in
            await store.clearViewingStates()
        }
        Task { [weak self] in
            await clearing.value
            self?.onViewingStatesCleared?()
        }
    }

    private func launchResolvedPlayback(
        _ request: PlaybackLaunchRequest,
        resumeAt seconds: Double?,
        savedFormat: MediaFormat?,
        playbackMode: PersistedPlaybackMode,
        trackSelectionPreference: TrackSelectionPreference?,
        retrying recovery: ActiveFailureRecovery? = nil
    ) {
        pendingLaunchRequest = nil
        onPlaybackIntentStarted?()
        if recovery == nil {
            activeFailureRecovery = nil
            activeFailureRetry = nil
        }
        let isColdLaunch = playbackRuntime.currentLaunchRequest == nil
        let entryPlaybackMode = onPlaybackModeEntryStarted?(
            playbackMode,
            isColdLaunch
        ) ?? playbackMode
        generation += 1
        let launchGeneration = generation
        lastResolvedLaunch = ResolvedLaunch(
            launchGeneration: launchGeneration,
            request: request,
            resumeSeconds: seconds,
            savedFormat: savedFormat,
            playbackMode: entryPlaybackMode,
            trackSelectionPreference: trackSelectionPreference
        )
        saveCurrentArtwork()
        persistCurrentSession()
        launchTask?.cancel()
        metadataTask?.cancel()
        let reusesSourceAccess = (request.sourceAccess != nil
            && playbackRuntime.currentLaunchRequest?.sourceAccess === request.sourceAccess)
            || (request.source.byteStreamHandle != nil
                && playbackRuntime.currentLaunchRequest?.source.byteStreamHandle
                    === request.source.byteStreamHandle)
        playbackRuntime.stopForNextRequest(
            releasingSourceAccess: reusesSourceAccess == false
        )

        let preparedRequest = request.updating(metadata: request.initialMetadata)
        playbackRuntime.prepareForPlayback(preparedRequest)
        if let recovery {
            activeFailureRetry = ActiveFailureRetry(
                recovery: recovery,
                launchGeneration: launchGeneration,
                runtimeGeneration: playbackRuntime.observationGeneration,
                request: preparedRequest,
                launchConfigurationCompleted: false
            )
        }
        armMediaServerReportingSession(
            for: preparedRequest,
            generation: launchGeneration
        )
        logger.info("launch requested source=\(preparedRequest.displayName, privacy: .public)")

        metadataTask = Task { [weak self] in
            guard let self else { return }
            let metadata = await metadataService.prepareMetadata(for: preparedRequest)
            guard !Task.isCancelled, generation == launchGeneration else { return }
            if let metadata {
                playbackRuntime.applyPrefetchedMetadata(metadata)
            }
        }

        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let initialSpeed = PlaybackModel.PlaybackSpeed(
                    preferencesProvider.loadPlaybackPreferences().defaultSpeed
                )
                try await playbackRuntime.open(
                    preparedRequest,
                    startTimeSeconds: seconds ?? 0,
                    initialSpeed: initialSpeed,
                    initialFormat: savedFormat
                )
                guard generation == launchGeneration else { return }
                guard try await applyLaunchConfiguration(
                    for: preparedRequest,
                    savedFormat: savedFormat,
                    formatWasAppliedDuringOpen: savedFormat != nil,
                    trackSelectionPreference: trackSelectionPreference,
                    expectedGeneration: launchGeneration
                ) else { return }
                savePlaybackMode(entryPlaybackMode)
                markMediaServerLaunchConfigurationCompleted()
                completeActiveFailureRetry(
                    recovery,
                    expectedGeneration: launchGeneration,
                    request: preparedRequest,
                    launchConfigurationCompleted: true
                )
            } catch {
                guard generation == launchGeneration else { return }
                if preparedRequest.source.isRemote,
                   await retry(
                    preparedRequest,
                    resumeAt: seconds,
                    savedFormat: savedFormat,
                    playbackMode: entryPlaybackMode,
                    trackSelectionPreference: trackSelectionPreference,
                    generation: launchGeneration
                   ) {
                    completeActiveFailureRetry(
                        recovery,
                        expectedGeneration: launchGeneration,
                        request: preparedRequest,
                        launchConfigurationCompleted: true
                    )
                    return
                }
                guard generation == launchGeneration, !Task.isCancelled else { return }
                finishMediaServerReportingSession()
                if activeFailureRetry?.launchGeneration == launchGeneration {
                    activeFailureRetry = nil
                }
                logger.error(
                    "playback launch failed error=\(error.localizedDescription, privacy: .public)"
                )
                if let recovery {
                    if playbackRuntime.userVisibleIssue == nil {
                        playbackRuntime.setUserVisibleIssue(
                            .activePlaybackFailure(recovery.failure)
                        )
                    }
                } else if playbackRuntime.userVisibleIssue == nil {
                    playbackRuntime.setUserVisibleIssue(.mediaOpeningFailed)
                }
            }
        }
    }

    public func applyFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int? = nil,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool = false
    ) async throws {
        let target = beginMediaFormatRequest()
        try await performMediaFormatCoreOperation { [playbackRuntime] in
            try await playbackRuntime.setFormat(
                projection: projection,
                horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                stereo: stereo,
                usesDolbyVisionFallback: usesDolbyVisionFallback
            )
        }
        guard mediaFormatRequestIsCurrent(target) else { return }
        let format = MediaFormat(
            projection: Self.projection(from: projection),
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: Self.stereo(from: stereo),
            usesDolbyVisionFallback: usesDolbyVisionFallback
        )
        guard await persistMediaFormatMutationIfCurrent(target, mutation: { store, identity in
            await store.saveFormat(format, for: identity)
        }) else { return }
        if lastResolvedLaunch?.launchGeneration == generation {
            lastResolvedLaunch?.savedFormat = format
        }
        notifyEffectiveMediaFormatApplied()
    }

    public func resetFormat() async throws {
        let target = beginMediaFormatRequest()
        try await performMediaFormatCoreOperation { [playbackRuntime] in
            try await playbackRuntime.useSourceFormat()
        }
        guard mediaFormatRequestIsCurrent(target) else { return }
        guard await persistMediaFormatMutationIfCurrent(target, mutation: { store, identity in
            await store.resetFormat(for: identity)
        }) else { return }
        if lastResolvedLaunch?.launchGeneration == generation {
            lastResolvedLaunch?.savedFormat = nil
        }
        notifyEffectiveMediaFormatApplied()
    }

    public func savePlaybackMode(_ mode: PersistedPlaybackMode) {
        if lastResolvedLaunch?.launchGeneration == generation,
           lastResolvedLaunch?.request == playbackRuntime.currentLaunchRequest {
            lastResolvedLaunch?.playbackMode = mode
        }
        guard let identity = playbackRuntime.currentLaunchRequest?.versionedIdentity else {
            return
        }
        enqueueMediaStateMutation { store in
            await store.savePlaybackMode(mode, for: identity)
        }
    }

    public func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws {
        let request = playbackRuntime.currentLaunchRequest
        let sessionID = playbackRuntime.activeSessionID
        try await playbackRuntime.selectAudioTrack(track)
        guard let request,
              playbackRuntime.activeSessionID == sessionID,
              playbackRuntime.currentLaunchRequest == request,
              playbackRuntime.currentAudioTrackID == track.id else { return }
        if lastResolvedLaunch?.launchGeneration == generation,
           lastResolvedLaunch?.request == request {
            var preference = lastResolvedLaunch?.trackSelectionPreference
                ?? TrackSelectionPreference()
            preference.audioTrackID = track.id
            lastResolvedLaunch?.trackSelectionPreference = preference
        }
        switch request.viewingStateAuthority {
        case .enchronPersistence:
            guard let identity = request.versionedIdentity else { return }
            await enqueueMediaStateMutation { store in
                await store.saveAudioTrackSelection(id: track.id, for: identity)
            }.value
        case .mediaServer:
            reportImmediateMediaServerProgress()
        }
    }

    public func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws {
        let request = playbackRuntime.currentLaunchRequest
        let sessionID = playbackRuntime.activeSessionID
        try await playbackRuntime.selectSubtitleTrack(track)
        guard let request,
              playbackRuntime.activeSessionID == sessionID,
              playbackRuntime.currentLaunchRequest == request,
              playbackRuntime.currentSubtitleTrackID == track?.id else { return }
        if lastResolvedLaunch?.launchGeneration == generation,
           lastResolvedLaunch?.request == request {
            var preference = lastResolvedLaunch?.trackSelectionPreference
                ?? TrackSelectionPreference()
            preference.subtitleTrack = track.map {
                .track(id: $0.id)
            } ?? .off
            lastResolvedLaunch?.trackSelectionPreference = preference
        }
        switch request.viewingStateAuthority {
        case .enchronPersistence:
            guard let identity = request.versionedIdentity else { return }
            let selection: SubtitleTrackSelectionPreference = if let track {
                .track(id: track.id)
            } else {
                .off
            }
            await enqueueMediaStateMutation { store in
                await store.saveSubtitleTrackSelection(selection, for: identity)
            }.value
        case .mediaServer:
            reportImmediateMediaServerProgress()
        }
    }

    public func stopPlayback(reason: PlaybackLeaveReason) {
        prepareToLeavePlayback()
        playbackRuntime.leavePlayback(reason: reason)
    }

    public func stopPlaybackAndWait(reason: PlaybackLeaveReason) async {
        prepareToLeavePlayback()
        await playbackRuntime.leavePlaybackAndWait(reason: reason)
    }

    private func prepareToLeavePlayback() {
        cancelPlaybackLaunchAndPersistProgress()
        onPlaybackStopRequested?()
        activeFailureRecovery = nil
        activeFailureRetry = nil
        lastResolvedLaunch = nil
        pendingRequestResolution = nil
        playbackRuntime.setUserVisibleIssue(nil)
    }

    private func cancelPlaybackLaunchAndPersistProgress() {
        preparation.cancel()
        releasePendingLaunch()
        generation += 1
        launchTask?.cancel()
        metadataTask?.cancel()
        launchTask = nil
        metadataTask = nil
        pendingResumeDecision = nil
        saveCurrentArtwork()
        persistCurrentSession()
    }

    private func releasePendingLaunch(excluding next: PlaybackLaunchRequest? = nil) {
        guard let pending = pendingLaunchRequest else { return }
        pendingLaunchRequest = nil
        let current = playbackRuntime.currentLaunchRequest
        if let access = pending.sourceAccess,
           access !== current?.sourceAccess, access !== next?.sourceAccess {
            access.release()
        }
        let retained = [current, next].compactMap { $0 }
        let retainedHandles = retained.flatMap {
            [$0.source.byteStreamHandle].compactMap { $0 }
                + $0.externalSubtitleSources.compactMap(\.byteStreamHandle)
        }
        let pendingHandles = [pending.source.byteStreamHandle].compactMap { $0 }
            + pending.externalSubtitleSources.compactMap(\.byteStreamHandle)
        for handle in pendingHandles where !retainedHandles.contains(where: { $0 === handle }) {
            handle.release()
        }
        let retainedSubtitleAccess = retained.flatMap {
            $0.externalSubtitleSources.compactMap(\.accessLease)
        }
        for access in pending.externalSubtitleSources.compactMap(\.accessLease)
            where !retainedSubtitleAccess.contains(where: { $0 === access }) {
            access.release()
        }
    }

    private func saveCurrentArtwork() {
        guard let identity = playbackRuntime.currentLaunchRequest?.versionedIdentity?.mediaIdentity,
              let image = playbackRuntime.displayedArtworkImage() else { return }
        do {
            try ArtworkStore.shared.store(image, for: ArtworkKey(mediaIdentity: identity))
        } catch {
            logger.error("artwork write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public var endedAffordance: PlaybackEndedAffordance {
        PlaybackEndPolicy.affordance(
            for: preferencesProvider.loadPlaybackPreferences().endBehavior,
            nextAvailable: hasNextPlaybackItemProvider?() ?? false
        )
    }

    public func handlePlaybackEnded() {
        persistCurrentSession(endedNaturally: true)
    }

    public func playEndedContinuation() {
        guard playbackRuntime.productLifecycle == .ended else { return }
        Task { [weak self] in
            guard let self,
                  let request = try? await self.preparation.resolve({
                      await self.nextFileProvider?()
                  }),
                  self.playbackRuntime.productLifecycle == .ended else { return }
            self.requestPlayback(request, origin: .automaticContinuation)
        }
    }

    private func persistCurrentSession(endedNaturally: Bool = false) {
        guard let request = playbackRuntime.currentLaunchRequest else { return }
        switch request.viewingStateAuthority {
        case .enchronPersistence:
            switch playbackRuntime.productLifecycle {
            case .ready, .playing, .paused, .ended:
                break
            case .idle, .loading, .failed:
                return
            }
            if let identity = request.versionedIdentity {
                let position = playbackRuntime.playbackPosition
                let evidence = PlaybackSessionEvidence(
                    durationSeconds: position.duration,
                    positionSeconds: position.seconds,
                    actualPlaybackSeconds: playbackRuntime.actualPlaybackSeconds,
                    endedNaturally: endedNaturally || playbackRuntime.didEndNaturally
                )
                let mutation = ViewingStatePolicy.mutation(for: evidence)
                enqueueMediaStateMutation { store in
                    await store.recordKnownDuration(evidence.durationSeconds, for: identity)
                    await store.applyViewingMutation(mutation, for: identity)
                }
            }
        case .mediaServer:
            finishMediaServerReportingSession()
            switch playbackRuntime.productLifecycle {
            case .ready, .playing, .paused, .ended:
                break
            case .idle, .loading, .failed:
                return
            }
        }
        let metadata = playbackRuntime.prefetchedMetadata?.merging(
            with: playbackRuntime.displayMediaProfile.map {
                PlaybackMediaMetadata(
                    mediaProfile: $0,
                    fileSizeInBytes: playbackRuntime.displayFileSizeInBytes
                )
            }
        )
        Task.detached(priority: .utility) { [metadataService] in
            if let metadata {
                await metadataService.persist(metadata, for: request)
            }
        }
    }

    private func armMediaServerReportingSession(
        for request: PlaybackLaunchRequest,
        generation: Int
    ) {
        switch request.viewingStateAuthority {
        case .enchronPersistence:
            mediaServerReportingSession = nil
        case .mediaServer:
            guard let reporter = request.sessionReporter else {
                mediaServerReportingSession = nil
                return
            }
            mediaServerReportingSession = MediaServerReportingSession(
                generation: generation,
                runtimeGeneration: playbackRuntime.observationGeneration,
                reporter: reporter,
                phase: .armed,
                lastReport: currentPlaybackSessionReport(),
                lastLifecycle: playbackRuntime.productLifecycle,
                nextPeriodicThresholdSeconds: 10,
                launchConfigurationCompleted: false
            )
        }
    }

    private func receivePlaybackObservation(_ observation: PlaybackRuntimeObservation) {
        if case .activeFailure(let failure) = observation.event {
            receiveActiveFailure(failure, observationGeneration: observation.generation)
            return
        }
        completeActiveFailureRetryIfUsable(observation)
        guard var session = mediaServerReportingSession,
              session.generation == generation,
              session.runtimeGeneration == observation.generation else { return }
        if case .finished = session.phase { return }

        switch observation.event {
        case .diagnostics(let position, let actualPlaybackSeconds):
            let report = currentPlaybackSessionReport(positionSeconds: position.seconds)
            session.lastReport = report
            guard case .active = session.phase,
                  actualPlaybackSeconds >= session.nextPeriodicThresholdSeconds else {
                mediaServerReportingSession = session
                return
            }
            repeat {
                session.nextPeriodicThresholdSeconds += 10
            } while actualPlaybackSeconds >= session.nextPeriodicThresholdSeconds
            mediaServerReportingSession = session
            session.reporter.playbackProgressed(report)
        case .lifecycle(let lifecycle):
            let previousLifecycle = session.lastLifecycle
            let report = currentPlaybackSessionReport(
                isPaused: lifecycle == .paused
            )
            session.lastLifecycle = lifecycle
            session.lastReport = report
            switch lifecycle {
            case .playing:
                switch session.phase {
                case .armed:
                    session.phase = .active
                    mediaServerReportingSession = session
                    session.reporter.playbackStarted(report)
                case .active where previousLifecycle == .paused:
                    mediaServerReportingSession = session
                    session.reporter.playbackProgressed(report)
                case .active, .finished:
                    mediaServerReportingSession = session
                }
            case .paused:
                mediaServerReportingSession = session
                guard case .active = session.phase,
                      previousLifecycle != .paused else { return }
                session.reporter.playbackProgressed(report)
            case .ended:
                mediaServerReportingSession = session
                finishMediaServerReportingSession(
                    expectedRuntimeGeneration: observation.generation,
                    report: report
                )
            case .failed:
                mediaServerReportingSession = session
                guard session.launchConfigurationCompleted else { return }
                finishMediaServerReportingSession(
                    expectedRuntimeGeneration: observation.generation,
                    report: report
                )
            case .idle, .loading, .ready:
                mediaServerReportingSession = session
            }
        case .seekCompleted(let positionSeconds):
            session.lastReport = currentPlaybackSessionReport(
                positionSeconds: positionSeconds
            )
            mediaServerReportingSession = session
            reportImmediateMediaServerProgress(positionSeconds: positionSeconds)
        case .stopped:
            finishMediaServerReportingSession(
                expectedRuntimeGeneration: observation.generation
            )
        case .activeFailure:
            return
        }
    }

    private func receiveActiveFailure(
        _ failure: PlaybackActiveFailure,
        observationGeneration: UInt64
    ) {
        guard observationGeneration == failure.runtimeGeneration,
              observationGeneration == playbackRuntime.observationGeneration,
              failure.requestID == playbackRuntime.currentLaunchRequest?.id,
              failure.mediaSessionID == playbackRuntime.activeSessionID,
              let resolvedLaunch = lastResolvedLaunch,
              resolvedLaunch.launchGeneration == generation,
              resolvedLaunch.request.id == failure.requestID else { return }
        activeFailureRecovery = ActiveFailureRecovery(
            failure: failure,
            resolvedLaunch: resolvedLaunch
        )
    }

    private func completeActiveFailureRetry(
        _ recovery: ActiveFailureRecovery?,
        expectedGeneration: Int,
        request: PlaybackLaunchRequest,
        launchConfigurationCompleted: Bool
    ) {
        guard let recovery,
              var retry = activeFailureRetry,
              retry.recovery.failure == recovery.failure,
              retry.launchGeneration == expectedGeneration,
              retry.runtimeGeneration == playbackRuntime.observationGeneration,
              retry.request == request,
              generation == expectedGeneration,
              activeFailureRecovery?.failure == recovery.failure,
              playbackRuntime.currentLaunchRequest == request else { return }
        if launchConfigurationCompleted {
            retry.launchConfigurationCompleted = true
            activeFailureRetry = retry
        }
        guard retry.launchConfigurationCompleted else { return }
        switch playbackRuntime.productLifecycle {
        case .ready, .playing, .paused:
            activeFailureRetry = nil
            activeFailureRecovery = nil
            playbackRuntime.setUserVisibleIssue(
                request.externalSubtitleResolutionFailed ? .externalSubtitleFailed : nil
            )
        case .idle, .loading, .ended, .failed:
            break
        }
    }

    private func completeActiveFailureRetryIfUsable(
        _ observation: PlaybackRuntimeObservation
    ) {
        guard case .lifecycle(let lifecycle) = observation.event,
              lifecycle == .ready || lifecycle == .playing || lifecycle == .paused,
              let retry = activeFailureRetry,
              observation.generation == retry.runtimeGeneration else { return }
        completeActiveFailureRetry(
            retry.recovery,
            expectedGeneration: retry.launchGeneration,
            request: retry.request,
            launchConfigurationCompleted: false
        )
    }

    private func reportImmediateMediaServerProgress(positionSeconds: Double? = nil) {
        guard var session = mediaServerReportingSession,
              session.generation == generation,
              session.runtimeGeneration == playbackRuntime.observationGeneration,
              case .active = session.phase else { return }
        let report = currentPlaybackSessionReport(positionSeconds: positionSeconds)
        session.lastReport = report
        mediaServerReportingSession = session
        session.reporter.playbackProgressed(report)
    }

    private func markMediaServerLaunchConfigurationCompleted() {
        guard var session = mediaServerReportingSession,
              session.generation == generation,
              session.runtimeGeneration == playbackRuntime.observationGeneration else { return }
        session.launchConfigurationCompleted = true
        mediaServerReportingSession = session
        guard session.lastLifecycle == .failed else { return }
        finishMediaServerReportingSession()
    }

    private func finishMediaServerReportingSession(
        expectedRuntimeGeneration: UInt64? = nil,
        report: PlaybackSessionReport? = nil
    ) {
        guard var session = mediaServerReportingSession else { return }
        if case .finished = session.phase { return }
        if let expectedRuntimeGeneration,
           session.runtimeGeneration != expectedRuntimeGeneration {
            return
        }
        let finalReport: PlaybackSessionReport
        if let report {
            finalReport = report
        } else if playbackRuntime.currentLaunchRequest != nil {
            finalReport = currentPlaybackSessionReport()
        } else {
            finalReport = session.lastReport
        }
        session.lastReport = finalReport
        session.phase = .finished
        mediaServerReportingSession = session
        session.reporter.playbackStopped(finalReport)
    }

    private func currentPlaybackSessionReport(
        positionSeconds: Double? = nil,
        isPaused: Bool? = nil
    ) -> PlaybackSessionReport {
        PlaybackSessionReport(
            positionSeconds: positionSeconds ?? playbackRuntime.playbackPosition.seconds,
            isPaused: isPaused ?? (playbackRuntime.productLifecycle == .paused),
            selectedAudioTrackID: playbackRuntime.currentAudioTrackID,
            selectedSubtitleTrackID: playbackRuntime.currentSubtitleTrackID
        )
    }

    private func beginMediaFormatRequest() -> MediaFormatRequestTarget {
        mediaFormatRequestID &+= 1
        return MediaFormatRequestTarget(
            requestID: mediaFormatRequestID,
            launchGeneration: generation,
            mediaSessionID: playbackRuntime.activeSessionID,
            versionedIdentity: playbackRuntime.currentLaunchRequest?.versionedIdentity
        )
    }

    private func mediaFormatRequestIsCurrent(
        _ target: MediaFormatRequestTarget
    ) -> Bool {
        guard let mediaSessionID = target.mediaSessionID else { return false }
        return target.requestID == mediaFormatRequestID
            && target.launchGeneration == generation
            && playbackRuntime.activeSessionID == mediaSessionID
            && playbackRuntime.currentLaunchRequest?.versionedIdentity
                == target.versionedIdentity
    }

    private func performMediaFormatCoreOperation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let previous = mediaFormatCoreOperationTask
        let task = Task { @MainActor in
            if let previous {
                _ = await previous.result
            }
            try Task.checkCancellation()
            try await operation()
        }
        mediaFormatCoreOperationTask = task
        try await task.value
    }

    private func persistMediaFormatMutationIfCurrent(
        _ target: MediaFormatRequestTarget,
        mutation: @escaping @Sendable (
            MediaStateStore,
            VersionedMediaIdentity
        ) async -> Void
    ) async -> Bool {
        guard mediaFormatRequestIsCurrent(target) else { return false }
        guard let identity = target.versionedIdentity else { return true }

        await mediaStateMutationTask?.value
        guard mediaFormatRequestIsCurrent(target) else { return false }
        await enqueueMediaStateMutation { store in
            await mutation(store, identity)
        }.value
        return mediaFormatRequestIsCurrent(target)
    }

    private func notifyEffectiveMediaFormatApplied() {
        onEffectiveMediaFormatApplied?(
            playbackRuntime.effectiveMediaFormatInterpretation
        )
    }

    @discardableResult
    private func enqueueMediaStateMutation(
        _ operation: @escaping @Sendable (MediaStateStore) async -> Void
    ) -> Task<Void, Never> {
        let previous = mediaStateMutationTask
        let store = mediaStateStore
        let task = Task {
            await previous?.value
            await operation(store)
        }
        mediaStateMutationTask = task
        return task
    }

    private func retry(
        _ request: PlaybackLaunchRequest,
        resumeAt seconds: Double?,
        savedFormat: MediaFormat?,
        playbackMode: PersistedPlaybackMode,
        trackSelectionPreference: TrackSelectionPreference?,
        generation: Int
    ) async -> Bool {
        for attempt in 1...3 {
            guard Self.retryAttemptIsCurrent(
                expectedGeneration: generation,
                currentGeneration: self.generation,
                isCancelled: Task.isCancelled
            ) else { return false }
            try? await Task.sleep(for: .seconds(1 << attempt))
            guard Self.retryAttemptIsCurrent(
                expectedGeneration: generation,
                currentGeneration: self.generation,
                isCancelled: Task.isCancelled
            ) else { return false }
            let isConnected = await networkMonitor.waitForConnection(timeout: .seconds(10))
            guard Self.retryAttemptIsCurrent(
                expectedGeneration: generation,
                currentGeneration: self.generation,
                isCancelled: Task.isCancelled
            ) else { return false }
            guard isConnected else { continue }
            do {
                let initialSpeed = PlaybackModel.PlaybackSpeed(
                    preferencesProvider.loadPlaybackPreferences().defaultSpeed
                )
                try await playbackRuntime.open(
                    request,
                    startTimeSeconds: seconds ?? 0,
                    initialSpeed: initialSpeed,
                    initialFormat: savedFormat
                )
                guard try await applyLaunchConfiguration(
                    for: request,
                    savedFormat: savedFormat,
                    formatWasAppliedDuringOpen: savedFormat != nil,
                    trackSelectionPreference: trackSelectionPreference,
                    expectedGeneration: generation
                ) else { return false }
                savePlaybackMode(playbackMode)
                markMediaServerLaunchConfigurationCompleted()
                logger.info("network retry succeeded attempt=\(attempt)")
                return true
            } catch {
                logger.error("network retry failed attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    static func retryAttemptIsCurrent(
        expectedGeneration: Int,
        currentGeneration: Int,
        isCancelled: Bool
    ) -> Bool {
        expectedGeneration == currentGeneration && !isCancelled
    }

    private func applyLaunchConfiguration(
        for request: PlaybackLaunchRequest,
        savedFormat: MediaFormat?,
        formatWasAppliedDuringOpen: Bool = false,
        trackSelectionPreference: TrackSelectionPreference?,
        expectedGeneration: Int
    ) async throws -> Bool {
        guard generation == expectedGeneration else { return false }
        switch request.viewingStateAuthority {
        case .enchronPersistence:
            if let audioTrackID = trackSelectionPreference?.audioTrackID,
               let track = playbackRuntime.availableAudioTracks.first(where: { $0.id == audioTrackID }) {
                do {
                    try await playbackRuntime.selectAudioTrack(track)
                } catch {
                    logger.error(
                        "saved audio track could not be restored error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            guard generation == expectedGeneration else { return false }
            switch trackSelectionPreference?.subtitleTrack {
            case .off:
                do {
                    try await playbackRuntime.selectSubtitleTrack(nil)
                } catch {
                    logger.error(
                        "saved subtitle-off selection could not be restored error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            case .track(let id):
                if let track = playbackRuntime.availableSubtitleTracks.first(where: { $0.id == id }) {
                    do {
                        try await playbackRuntime.selectSubtitleTrack(track)
                    } catch {
                        logger.error(
                            "saved subtitle track could not be restored error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            case nil:
                break
            }
        case .mediaServer:
            break
        }
        guard generation == expectedGeneration else { return false }
        guard playbackRuntime.mediaKind == .video else {
            notifyEffectiveMediaFormatApplied()
            return true
        }
        if savedFormat != nil, formatWasAppliedDuringOpen {
            notifyEffectiveMediaFormatApplied()
            return true
        }
        guard let format = savedFormat else {
            try await performMediaFormatCoreOperation { [playbackRuntime] in
                try await playbackRuntime.useSourceFormat()
            }
            guard generation == expectedGeneration else { return false }
            notifyEffectiveMediaFormatApplied()
            return true
        }
        try await performMediaFormatCoreOperation { [playbackRuntime] in
            try await playbackRuntime.setFormat(
                projection: Self.projection(from: format.projection),
                horizontalFieldOfViewDegrees: format.horizontalFieldOfViewDegrees,
                stereo: Self.stereo(from: format.stereoLayout),
                usesDolbyVisionFallback: false
            )
        }
        guard generation == expectedGeneration else { return false }
        notifyEffectiveMediaFormatApplied()
        return generation == expectedGeneration
    }

    private static func projection(from value: MediaProjection) -> PlaybackModel.ProjectionType {
        switch value {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func projection(from value: PlaybackModel.ProjectionType) -> MediaProjection {
        switch value {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func stereo(from value: MediaStereoLayout) -> PlaybackModel.StereoLayout {
        switch value {
        case .mono: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    private static func stereo(from value: PlaybackModel.StereoLayout) -> MediaStereoLayout {
        switch value {
        case .mono, .multiview: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }
}
