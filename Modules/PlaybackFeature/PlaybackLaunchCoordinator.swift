import Foundation
import MediaSource
import Observation
import OSLog

@MainActor
public protocol PlaybackLaunching: AnyObject {
    func beginPlayback(for url: URL)
    func beginPlayback(_ request: PlaybackLaunchRequest)
    func stopPlayback()
}

@MainActor
@Observable
public final class PlaybackLaunchCoordinator: PlaybackLaunching {
    public struct ResumeDecision: Equatable {
        public let request: PlaybackLaunchRequest
        public let seconds: Double
        public let format: MediaFormat?
    }

    private struct ResolvedLaunch {
        let request: PlaybackLaunchRequest
        let resumeSeconds: Double?
        let savedFormat: MediaFormat?
    }

    private let playbackRuntime: any PlaybackRuntimeControlling
    private let mediaStateStore: MediaStateStore
    private let preferencesProvider: PlaybackPreferencesProviding
    private let metadataService: PlaybackMediaMetadataService
    private let networkMonitor: any NetworkConnectivityWaiting
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackLaunch")

    public var nextFileProvider: (@MainActor @Sendable () async -> PlaybackLaunchRequest?)?
    public var playbackQueueProvider: (@MainActor () -> PlaybackQueueSnapshot)?
    public var queueSelectionProvider: (@MainActor @Sendable (UUID) async -> PlaybackLaunchRequest?)?
    public var onResolvedLaunchFormatApplied: (@MainActor (MediaFormat) -> Void)?
    public var onViewingStatesCleared: (@MainActor () -> Void)?
    public private(set) var pendingResumeDecision: ResumeDecision?

    private var launchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var mediaStateMutationTask: Task<Void, Never>?
    private var generation = 0
    private var lastResolvedLaunch: ResolvedLaunch?

    public init(
        playbackRuntime: any PlaybackRuntimeControlling,
        mediaStateSuiteName: String? = nil,
        preferencesProvider: PlaybackPreferencesProviding = DefaultPlaybackPreferencesProvider()
    ) {
        self.playbackRuntime = playbackRuntime
        self.mediaStateStore = MediaStateStore(suiteName: mediaStateSuiteName)
        self.preferencesProvider = preferencesProvider
        self.metadataService = PlaybackMediaMetadataService()
        self.networkMonitor = MediaSourceServices.makeNetworkConnectivityWaiter()

        playbackRuntime.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                let metadata = await self.metadataService.recordDetectedProfile(profile, for: request)
                guard self.playbackRuntime.currentLaunchRequest == request else { return }
                self.playbackRuntime.applyPrefetchedMetadata(metadata)
            }
        }
    }

    public func viewingState(for identity: MediaIdentity) async -> ViewingStatus? {
        await mediaStateStore.viewingProjection(for: identity)
    }

    public func beginPlayback(for url: URL) {
        requestPlayback(.init(url: url, displayName: url.lastPathComponent))
    }

    public func requestPlayback(_ request: PlaybackLaunchRequest) {
        generation += 1
        let requestGeneration = generation
        pendingResumeDecision = nil
        Task { [weak self] in
            guard let self else { return }
            await mediaStateMutationTask?.value
            guard generation == requestGeneration else { return }
            let persistedState: PersistedMediaState? = if let identity = request.versionedIdentity {
                await mediaStateStore.loadValidated(for: identity)
            } else { nil }
            guard generation == requestGeneration else { return }
            let seconds: Double
            if let status = persistedState?.viewingStatus,
               case .resumable(let position, _) = status {
                seconds = position
            } else {
                seconds = 0
            }
            switch preferencesProvider.loadPlaybackPreferences().resumePolicy {
            case .askEveryTime where seconds > 0:
                pendingResumeDecision = ResumeDecision(
                    request: request,
                    seconds: seconds,
                    format: persistedState?.formatPreference
                )
            case .alwaysResume where seconds > 0:
                launchResolvedPlayback(
                    request,
                    resumeAt: seconds,
                    savedFormat: persistedState?.formatPreference
                )
            default:
                launchResolvedPlayback(
                    request,
                    resumeAt: nil,
                    savedFormat: persistedState?.formatPreference
                )
            }
        }
    }

    public func resumePendingPlayback() {
        guard let decision = pendingResumeDecision else { return }
        pendingResumeDecision = nil
        launchResolvedPlayback(
            decision.request,
            resumeAt: decision.seconds,
            savedFormat: decision.format
        )
    }

    public func startPendingPlaybackFromBeginning() {
        guard let decision = pendingResumeDecision else { return }
        pendingResumeDecision = nil
        guard let identity = decision.request.versionedIdentity else {
            launchResolvedPlayback(decision.request, resumeAt: nil, savedFormat: decision.format)
            return
        }

        let decisionGeneration = generation
        let removal = enqueueMediaStateMutation { store in
            await store.applyViewingMutation(.remove, for: identity)
        }
        Task { [weak self] in
            guard let self else { return }
            await removal.value
            guard generation == decisionGeneration else { return }
            launchResolvedPlayback(decision.request, resumeAt: nil, savedFormat: decision.format)
        }
    }

    public func beginPlayback(_ request: PlaybackLaunchRequest) {
        requestPlayback(request)
    }

    public func retryPlayback() {
        guard let lastResolvedLaunch else { return }
        launchResolvedPlayback(
            lastResolvedLaunch.request,
            resumeAt: lastResolvedLaunch.resumeSeconds,
            savedFormat: lastResolvedLaunch.savedFormat
        )
    }

    public var playbackQueue: PlaybackQueueSnapshot {
        playbackQueueProvider?() ?? .empty
    }

    public func selectPlaybackQueueItem(_ id: UUID) {
        Task { [weak self] in
            guard let self, let request = await queueSelectionProvider?(id) else { return }
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
        savedFormat: MediaFormat?
    ) {
        lastResolvedLaunch = ResolvedLaunch(
            request: request,
            resumeSeconds: seconds,
            savedFormat: savedFormat
        )
        generation += 1
        let launchGeneration = generation
        persistCurrentSession()
        launchTask?.cancel()
        metadataTask?.cancel()
        let reusesSourceAccess = request.sourceAccess != nil
            && playbackRuntime.currentLaunchRequest?.sourceAccess === request.sourceAccess
        playbackRuntime.stop(releasingSourceAccess: reusesSourceAccess == false)

        let preparedRequest = request.updating(metadata: request.initialMetadata)
        playbackRuntime.prepareForPlayback(preparedRequest)
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
                    initialSpeed: initialSpeed
                )
                guard generation == launchGeneration else { return }
                guard try await applyLaunchConfiguration(
                    savedFormat: savedFormat,
                    expectedGeneration: launchGeneration
                ) else { return }
            } catch {
                guard generation == launchGeneration else { return }
                if Self.isNetworkURL(preparedRequest.url),
                   await retry(
                    preparedRequest,
                    resumeAt: seconds,
                    savedFormat: savedFormat,
                    generation: launchGeneration
                   ) {
                    return
                }
                playbackRuntime.lastErrorMessage = error.localizedDescription
            }
        }
    }

    public func applyFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout
    ) async throws {
        let identity = playbackRuntime.currentLaunchRequest?.versionedIdentity
        let sessionID = playbackRuntime.activeSessionID
        try await playbackRuntime.setFormat(projection: projection, stereo: stereo)
        guard let identity,
              playbackRuntime.activeSessionID == sessionID,
              playbackRuntime.currentLaunchRequest?.versionedIdentity == identity else { return }
        let format = MediaFormat(
            projection: Self.projection(from: projection),
            stereoLayout: Self.stereo(from: stereo)
        )
        await enqueueMediaStateMutation { store in
            await store.saveFormat(format, for: identity)
        }.value
    }

    public func resetFormat() async throws {
        let identity = playbackRuntime.currentLaunchRequest?.versionedIdentity
        let sessionID = playbackRuntime.activeSessionID
        try await playbackRuntime.setFormat(projection: .flat, stereo: .mono)
        guard let identity,
              playbackRuntime.activeSessionID == sessionID,
              playbackRuntime.currentLaunchRequest?.versionedIdentity == identity else { return }
        await enqueueMediaStateMutation { store in
            await store.resetFormat(for: identity)
        }.value
    }

    public func stopPlayback() {
        cancelPlaybackLaunchAndPersistProgress()
        playbackRuntime.stop(releasingSourceAccess: true)
    }

    public func stopPlaybackAndWait() async {
        cancelPlaybackLaunchAndPersistProgress()
        await playbackRuntime.stopAndWait(releasingSourceAccess: true)
    }

    private func cancelPlaybackLaunchAndPersistProgress() {
        generation += 1
        launchTask?.cancel()
        metadataTask?.cancel()
        launchTask = nil
        metadataTask = nil
        pendingResumeDecision = nil
        persistCurrentSession()
    }

    public func handlePlaybackEnded(onFallbackShowControls: (@MainActor () -> Void)? = nil) -> Bool {
        persistCurrentSession(endedNaturally: true)
        switch PlaybackEndPolicy.action(
            for: preferencesProvider.loadPlaybackPreferences().endBehavior
        ) {
        case .stayEnded:
            return false
        case .repeatCurrent:
            playbackRuntime.replay()
            return false
        case .playNext:
            Task { [weak self] in
                guard let self else { return }
                if let next = await nextFileProvider?() {
                    requestPlayback(next)
                } else {
                    onFallbackShowControls?()
                }
            }
            return false
        }
    }

    private func persistCurrentSession(endedNaturally: Bool = false) {
        guard let request = playbackRuntime.currentLaunchRequest else { return }
        switch playbackRuntime.productLifecycle {
        case .ready, .playing, .paused, .ended:
            break
        case .idle, .loading, .failed:
            return
        }
        let position = playbackRuntime.playbackPosition
        let metadata = playbackRuntime.prefetchedMetadata?.merging(
            with: playbackRuntime.displayMediaProfile.map {
                PlaybackMediaMetadata(
                    mediaProfile: $0,
                    fileSizeInBytes: playbackRuntime.displayFileSizeInBytes
                )
            }
        )
        let actualPlaybackSeconds = playbackRuntime.actualPlaybackSeconds
        let didEndNaturally = endedNaturally || playbackRuntime.didEndNaturally
        if let identity = request.versionedIdentity {
            let evidence = PlaybackSessionEvidence(
                durationSeconds: position.duration,
                positionSeconds: position.seconds,
                actualPlaybackSeconds: actualPlaybackSeconds,
                endedNaturally: didEndNaturally
            )
            let mutation = ViewingStatePolicy.mutation(for: evidence)
            enqueueMediaStateMutation { store in
                await store.applyViewingMutation(mutation, for: identity)
            }
        }
        Task.detached(priority: .utility) { [metadataService] in
            if let metadata {
                await metadataService.persist(metadata, for: request)
            }
        }
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
        generation: Int
    ) async -> Bool {
        for attempt in 1...3 {
            guard self.generation == generation, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .seconds(1 << attempt))
            guard await networkMonitor.waitForConnection(timeout: .seconds(10)) else { continue }
            do {
                let initialSpeed = PlaybackModel.PlaybackSpeed(
                    preferencesProvider.loadPlaybackPreferences().defaultSpeed
                )
                try await playbackRuntime.open(
                    request,
                    startTimeSeconds: seconds ?? 0,
                    initialSpeed: initialSpeed
                )
                guard try await applyLaunchConfiguration(
                    savedFormat: savedFormat,
                    expectedGeneration: generation
                ) else { return false }
                logger.info("network retry succeeded attempt=\(attempt)")
                return true
            } catch {
                logger.error("network retry failed attempt=\(attempt) error=\(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    private func applyLaunchConfiguration(
        savedFormat: MediaFormat?,
        expectedGeneration: Int
    ) async throws -> Bool {
        guard generation == expectedGeneration else { return false }
        let format = savedFormat ?? .standard
        try await playbackRuntime.setFormat(
            projection: Self.projection(from: format.projection),
            stereo: Self.stereo(from: format.stereoLayout)
        )
        guard generation == expectedGeneration else { return false }
        onResolvedLaunchFormatApplied?(format)
        return generation == expectedGeneration
    }

    private static func isNetworkURL(_ url: URL) -> Bool {
        ["smb", "http", "https", "ftp"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func projection(from value: MediaProjection) -> PlaybackModel.ProjectionType {
        switch value {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .fisheye: .fisheye
        }
    }

    private static func projection(from value: PlaybackModel.ProjectionType) -> MediaProjection {
        switch value {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .fisheye: .fisheye
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
        case .mono: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }
}
