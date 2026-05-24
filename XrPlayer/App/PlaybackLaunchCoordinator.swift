import Foundation
import Observation

/// Coordinates playback launch across all entry points.
///
/// Owns the launch gate (generation tracking, active task cancellation)
/// and delegates to `AppModel` for state and `WindowVideoViewModel` for
/// actual player operations.
@MainActor
@Observable
public final class PlaybackLaunchCoordinator: PlaybackLaunching {
    private let appModel: AppModel
    private let windowVideoViewModel: WindowVideoViewModel
    private let progressStore: ProgressStoring
    private let preferencesStore: PreferencesStoring
    private let metadataService: PlaybackMediaMetadataService
    private let prefetchService: MediaProfilePrefetchService?
    private let networkMonitor: NetworkMonitor

    private static let maxRetries = 3
    private static let retryBaseDelay: Duration = .seconds(2)

    /// Closure that returns the next file's playback request for auto-next-episode.
    /// Set by the app layer after constructing the file browsing view model.
    public var nextFileProvider: (@MainActor @Sendable () async -> PlaybackLaunchRequest?)?

    private var activeTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var generation: Int = 0

    // MARK: - Prepare/Confirm state
    public private(set) var currentPreparation: PreparationState?
    private var preparationTask: Task<Void, Never>?
    private var preparationTTLTask: Task<Void, Never>?
    private static let preparationTTLSeconds: UInt64 = 60

    /// Cache of recently prepared playback snapshots keyed by file URL.
    /// When the user navigates back to a previously opened video, the cached
    /// metadata and tracks are reused immediately without re-running loadPaused.
    private var preparationCache: [URL: PreparedPlayback] = [:]
    private static let maxCachedPreparations = 10

    public init(
        appModel: AppModel,
        windowVideoViewModel: WindowVideoViewModel,
        progressStore: ProgressStoring = SwiftDataStore(),
        preferencesStore: PreferencesStoring = UserDefaultsStore(),
        metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService(),
        prefetchService: MediaProfilePrefetchService? = nil,
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.appModel = appModel
        self.windowVideoViewModel = windowVideoViewModel
        self.progressStore = progressStore
        self.preferencesStore = preferencesStore
        self.metadataService = metadataService
        self.prefetchService = prefetchService
        self.networkMonitor = networkMonitor

        self.windowVideoViewModel.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                guard !Task.isCancelled else { return }
                let metadata = await self.metadataService.recordDetectedProfile(
                    profile, for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.windowVideoViewModel.currentLaunchRequest == request else { return }
                    self.windowVideoViewModel.applyPrefetchedMetadata(metadata)
                    self.appModel.updateMediaProfile(profile)
                    self.appModel.updateDetectedProjection(profile.projectionType, stereoLayout: profile.stereoLayout)

                    // Update in-flight preparation if profile arrived after .ready was set
                    if case .ready(let prepared) = self.currentPreparation,
                       prepared.request == request.updating(metadata: prepared.metadata),
                       prepared.isMetadataPartial {
                        let updatedMetadata = prepared.metadata?.merging(with: metadata) ?? metadata
                        let updated = PreparedPlayback(
                            request: prepared.request.updating(metadata: updatedMetadata),
                            metadata: updatedMetadata,
                            audioTracks: self.windowVideoViewModel.availableAudioTracks.isEmpty
                                ? prepared.audioTracks
                                : self.windowVideoViewModel.availableAudioTracks,
                            subtitleTracks: self.windowVideoViewModel.availableSubtitleTracks.isEmpty
                                ? prepared.subtitleTracks
                                : self.windowVideoViewModel.availableSubtitleTracks,
                            generation: prepared.generation,
                            isMetadataPartial: false
                        )
                        self.currentPreparation = .ready(updated)
                        print("[Playback] prepare_profile_resolved name=\(request.displayName)")
                    }
                }
            }
        }
    }

    public func beginPlayback(for url: URL) {
        beginPlayback(
            PlaybackLaunchRequest(
                url: url,
                displayName: url.lastPathComponent
            )
        )
    }

    public func beginPlayback(_ request: PlaybackLaunchRequest) {
        generation += 1
        let currentGeneration = generation
        let previousSession = currentPersistenceSnapshot()

        activeTask?.cancel()
        metadataTask?.cancel()
        activeTask = nil
        metadataTask = nil
        cancelPreparationTasks()
        currentPreparation = nil

        if previousSession != nil {
            print("[Playback] teardown_started reason=switch")
        }
        tearDownPlaybackEngine()
        windowVideoViewModel.clearPresentationForTeardown()
        print("[Playback] surface_cleared reason=switch")

        if let previousSession {
            queuePersistence(for: previousSession)
        }

        let preparedRequest = request.updating(metadata: request.initialMetadata)
        appModel.startPlayback(url: preparedRequest.url)
        appModel.mediaProfile = preparedRequest.initialMetadata?.mediaProfile
        windowVideoViewModel.prepareForPlayback(preparedRequest)
        print("[Playback] request_started name=\(preparedRequest.displayName)")

        metadataTask = Task { [weak self] in
            guard let self else { return }
            print("[Playback] metadata_prefetch_started name=\(preparedRequest.displayName)")
            let resolvedMetadata = await self.metadataService.prepareMetadata(for: preparedRequest)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.generation == currentGeneration else { return }
                guard self.windowVideoViewModel.currentLaunchRequest == preparedRequest else {
                    return
                }
                if let resolvedMetadata {
                    print("[Playback] metadata_prefetch_ready name=\(preparedRequest.displayName)")
                    self.windowVideoViewModel.applyPrefetchedMetadata(resolvedMetadata)
                    if let mediaProfile = resolvedMetadata.mediaProfile {
                        self.appModel.updateMediaProfile(mediaProfile)
                        self.appModel.updateDetectedProjection(mediaProfile.projectionType, stereoLayout: mediaProfile.stereoLayout)
                    }
                } else {
                    print("[Playback] metadata_prefetch_empty name=\(preparedRequest.displayName)")
                }
            }
        }

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == currentGeneration {
                    self.activeTask = nil
                }
            }

            // Give SwiftUI multiple run-loop passes to render WindowVideoView
            // and call attachVideoLayer.
            for _ in 0..<8 {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            guard self.generation == currentGeneration else { return }
            guard self.appModel.currentPlaybackURL == preparedRequest.url else { return }
            print("[Playback] launch_gate_ready name=\(preparedRequest.displayName)")

            do {
                try await self.windowVideoViewModel.play(url: preparedRequest.url)

                // Apply default speed preference
                let defaultSpeed = self.preferencesStore.loadPreferences().defaultPlaybackSpeed
                if defaultSpeed != 1.0 {
                    self.windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(defaultSpeed))
                }
            } catch {
                guard self.generation == currentGeneration else { return }

                if Self.isNetworkURL(preparedRequest.url) {
                    let recovered = await self.retryPlayback(
                        request: preparedRequest,
                        generation: currentGeneration
                    )
                    if recovered { return }
                }

                self.windowVideoViewModel.clearPresentation()
                self.appModel.stopPlayback()
            }
        }
    }

    public func stopPlayback() {
        generation += 1
        activeTask?.cancel()
        metadataTask?.cancel()
        activeTask = nil
        metadataTask = nil
        cancelPreparationTasks()

        let previousSession = currentPersistenceSnapshot()
        if previousSession != nil {
            print("[Playback] teardown_started reason=close")
        }
        windowVideoViewModel.stop()
        appModel.stopPlayback()
        print("[Playback] surface_cleared reason=close")

        if let previousSession {
            queuePersistence(for: previousSession)
        }
    }

    // MARK: - Prepare/Confirm Flow

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Starts metadata prefetch without beginning playback.
    ///
    /// The coordinator publishes progress through `currentPreparation`.
    /// Call `confirmPlayback(_:)` with the resulting `PreparedPlayback` to
    /// actually start playback, or `cancelPreparedPlayback()` to discard it.
    public func preparePlayback(_ request: PlaybackLaunchRequest) {
        generation += 1
        let currentGeneration = generation

        // Cancel any in-flight launch/preparation and tear down the previous
        // mpv state before the detail page starts resolving metadata.
        activeTask?.cancel()
        metadataTask?.cancel()
        activeTask = nil
        metadataTask = nil
        cancelPreparationTasks()
        tearDownPlaybackEngine()
        windowVideoViewModel.clearPresentation()

        // Check preparation cache — if we've already prepared this file,
        // skip metadata work and reuse the cached snapshot.
        if let cached = preparationCache[request.url] {
            let refreshed = PreparedPlayback(
                request: request.updating(metadata: cached.metadata),
                metadata: cached.metadata,
                audioTracks: cached.audioTracks,
                subtitleTracks: cached.subtitleTracks,
                generation: currentGeneration,
                isMetadataPartial: cached.isMetadataPartial
            )
            currentPreparation = .ready(refreshed)
            startPreparationTTL(generation: currentGeneration)
            print("[Playback] prepare_cache_hit name=\(request.displayName)")
            return
        }

        currentPreparation = .preparing(request: request, metadata: request.initialMetadata)
        print("[Playback] prepare_started name=\(request.displayName)")

        preparationTask = Task { [weak self] in
            guard let self else { return }

            // Phase 1: Metadata prefetch — try cache first, then await in-flight prefetch
            var resolvedMetadata = await self.metadataService.prepareMetadata(for: request)
            guard !Task.isCancelled else { return }
            guard self.generation == currentGeneration else { return }

            // If cache missed, await the in-flight prefetch task (if any)
            if resolvedMetadata?.mediaProfile == nil,
               let fileID = request.fileIdentifier,
               let service = self.prefetchService {
                if let profile = await service.awaitProfile(for: fileID) {
                    let prefetchedMeta = PlaybackMediaMetadata(
                        mediaProfile: profile,
                        fileSizeInBytes: resolvedMetadata?.fileSizeInBytes ?? 0
                    )
                    resolvedMetadata = resolvedMetadata?.merging(with: prefetchedMeta) ?? prefetchedMeta
                    print("[Playback] prepare_awaited_prefetch name=\(request.displayName)")
                }
                guard !Task.isCancelled else { return }
                guard self.generation == currentGeneration else { return }
            }

            let mergedMetadata = request.initialMetadata?.merging(with: resolvedMetadata) ?? resolvedMetadata

            // Update preparation state with resolved metadata
            self.currentPreparation = .preparing(request: request, metadata: mergedMetadata)

            // Phase 2: publish a ready snapshot without touching the production
            // mpv session. The detail page must stay independent from the window
            // playback layer; otherwise first-launch details can wait forever for
            // a CAMetalLayer or leave paused mpv state behind the sheet.
            let preparedRequest = request.updating(metadata: mergedMetadata)

            // Merge metadata from service prefetch. Runtime mpv detection will
            // still correct the profile after the user starts playback.
            var finalMetadata = mergedMetadata

            // If profile is not yet available, use a placeholder so the UI can
            // render immediately. The real profile arrives asynchronously during
            // playback and updates the app state in-place.
            let isMetadataPartial: Bool
            if finalMetadata?.mediaProfile == nil {
                let fallbackProfile = PlaybackCoreDomain.MediaProfile(
                    projectionType: .flat,
                    stereoLayout: .mono,
                    hdrType: .sdr,
                    resolution: .init(width: 1920, height: 1080)
                )
                let fallbackMeta = PlaybackMediaMetadata(
                    mediaProfile: fallbackProfile,
                    fileSizeInBytes: finalMetadata?.fileSizeInBytes ?? 0
                )
                finalMetadata = finalMetadata?.merging(with: fallbackMeta) ?? fallbackMeta
                isMetadataPartial = true
                print("[Playback] prepare_profile_pending name=\(request.displayName)")
            } else {
                isMetadataPartial = false
            }

            let prepared = PreparedPlayback(
                request: preparedRequest.updating(metadata: finalMetadata),
                metadata: finalMetadata,
                audioTracks: [],
                subtitleTracks: [],
                generation: currentGeneration,
                isMetadataPartial: isMetadataPartial
            )
            self.currentPreparation = .ready(prepared)

            // Cache for instant re-open when user navigates back
            self.preparationCache[request.url] = prepared
            if self.preparationCache.count > Self.maxCachedPreparations {
                // Evict oldest (arbitrary key — LRU would be better but not worth the complexity)
                if let firstKey = self.preparationCache.keys.first {
                    self.preparationCache.removeValue(forKey: firstKey)
                }
            }
            print("[Playback] prepare_ready name=\(request.displayName) audio=0 sub=0 partial=\(isMetadataPartial)")

            // Start TTL timer
            self.startPreparationTTL(generation: currentGeneration)
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Resumes playback after the user confirms from the detail view.
    ///
    /// Validates that `prepared.generation` matches the coordinator's current
    /// generation to reject stale confirmations.
    public func confirmPlayback(
        _ prepared: PreparedPlayback,
        resumePosition: Double? = nil,
        selectedAudioTrackID: String? = nil,
        selectedSubtitleTrackID: String? = nil,
        subtitlesOff: Bool = false
    ) {
        guard prepared.generation == generation else {
            print("[Playback] confirm_rejected reason=stale_generation expected=\(generation) got=\(prepared.generation)")
            return
        }

        cancelPreparationTasks()
        currentPreparation = nil

        appModel.startPlayback(url: prepared.request.url)
        if let mediaProfile = prepared.metadata?.mediaProfile {
            appModel.updateMediaProfile(mediaProfile)
            appModel.updateDetectedProjection(mediaProfile.projectionType, stereoLayout: mediaProfile.stereoLayout)
        }
        windowVideoViewModel.prepareForPlayback(prepared.request)

        let requestedResumePosition = resumePosition

        print("[Playback] confirm_resumed name=\(prepared.request.displayName) resume=\(resumePosition ?? 0)")

        // Start metadata profile detection callback (same as beginPlayback)
        let currentGeneration = generation
        metadataTask = Task { [weak self] in
            guard let self else { return }
            if let metadata = prepared.metadata {
                await MainActor.run {
                    guard self.generation == currentGeneration else { return }
                    self.windowVideoViewModel.applyPrefetchedMetadata(metadata)
                    if let mediaProfile = metadata.mediaProfile {
                        self.appModel.updateMediaProfile(mediaProfile)
                        self.appModel.updateDetectedProjection(mediaProfile.projectionType, stereoLayout: mediaProfile.stereoLayout)
                    }
                }
            }
        }

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == currentGeneration {
                    self.activeTask = nil
                }
            }

            for _ in 0..<8 {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            guard self.generation == currentGeneration else { return }
            guard self.appModel.currentPlaybackURL == prepared.request.url else { return }
            print("[Playback] launch_gate_ready name=\(prepared.request.displayName)")

            do {
                try await self.windowVideoViewModel.play(url: prepared.request.url)

                if let audioID = selectedAudioTrackID,
                   let track = prepared.audioTracks.first(where: { $0.id == audioID }) {
                    self.windowVideoViewModel.selectAudioTrack(track)
                }
                if subtitlesOff {
                    self.windowVideoViewModel.selectSubtitleTrack(nil)
                } else if let subID = selectedSubtitleTrackID,
                          let track = prepared.subtitleTracks.first(where: { $0.id == subID }) {
                    self.windowVideoViewModel.selectSubtitleTrack(track)
                }
                self.windowVideoViewModel.setHDREnabled(true)

                let defaultSpeed = self.preferencesStore.loadPreferences().defaultPlaybackSpeed
                if defaultSpeed != 1.0 {
                    self.windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(defaultSpeed))
                }

                if let pos = requestedResumePosition, pos > 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    guard self.generation == currentGeneration else { return }
                    self.windowVideoViewModel.seek(to: pos)
                }
            } catch {
                guard self.generation == currentGeneration else { return }
                self.windowVideoViewModel.clearPresentation()
                self.appModel.stopPlayback()
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Cancels an in-flight or ready preparation and tears down any preloaded state.
    public func cancelPreparedPlayback() {
        guard currentPreparation != nil else { return }

        print("[Playback] prepare_cancelled")
        cancelPreparationTasks()
        currentPreparation = nil

        // Clean up any old mpv state that may have existed before preparation.
        tearDownPlaybackEngine()
        windowVideoViewModel.clearPresentation()
    }

    // MARK: - Playback End Handling

    /// Handles playback-ended event based on user preferences.
    ///
    /// The `onFallbackShowControls` closure is called when auto-next-episode
    /// fails to find a next file, so the UI can show controls as a fallback.
    public func handlePlaybackEnded(onFallbackShowControls: (@MainActor () -> Void)? = nil) -> Bool {
        let prefs = preferencesStore.loadPreferences()
        switch prefs.playbackEndBehavior {
        case .stop:
            return true
        case .repeatOne:
            windowVideoViewModel.replay()
            return false
        case .playNext:
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let next = await self.nextFileProvider?() {
                    self.beginPlayback(next)
                } else {
                    // No next file — show controls so user isn't stuck
                    onFallbackShowControls?()
                }
            }
            return false
        }
    }

    // MARK: - Progress Access

    /// Loads saved playback progress for a file. Used by VideoDetailView for resume prompts.
    public func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? {
        await progressStore.loadProgress(for: fileID)
    }

    /// Returns the current resume policy. Used by VideoDetailView to decide button layout.
    public func currentResumePolicy() -> PersistenceDomain.ResumePolicy {
        preferencesStore.loadPreferences().resumePolicy
    }

    // MARK: - Preparation Helpers

    private func cancelPreparationTasks() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationTTLTask?.cancel()
        preparationTTLTask = nil
    }

    private func startPreparationTTL(generation: Int) {
        preparationTTLTask?.cancel()
        preparationTTLTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.preparationTTLSeconds))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.generation == generation else { return }
            guard self.currentPreparation != nil else { return }
            print("[Playback] prepare_ttl_expired generation=\(generation)")
            self.cancelPreparedPlayback()
        }
    }

    private func tearDownPlaybackEngine() {
        switch windowVideoViewModel.playbackState {
        case .loading, .buffering:
            windowVideoViewModel.cancelPendingLoadEngine()
        case .playing, .paused, .ended, .failed, .stopped:
            windowVideoViewModel.stopPlaybackEngine()
        case .idle:
            if windowVideoViewModel.currentPlaybackURL != nil {
                windowVideoViewModel.stopPlaybackEngine()
            }
        }
    }

    private func currentPersistenceSnapshot() -> PlaybackPersistenceSnapshot? {
        guard let request = windowVideoViewModel.currentLaunchRequest else {
            return nil
        }

        let metadata =
            windowVideoViewModel.prefetchedMetadata?.merging(
                with: windowVideoViewModel.displayMediaProfile.map {
                    PlaybackMediaMetadata(
                        mediaProfile: $0,
                        fileSizeInBytes: windowVideoViewModel.displayFileSizeInBytes
                    )
                }
            )
            ?? windowVideoViewModel.displayMediaProfile.map {
                PlaybackMediaMetadata(
                    mediaProfile: $0,
                    fileSizeInBytes: windowVideoViewModel.displayFileSizeInBytes
                )
            }

        return PlaybackPersistenceSnapshot(
            request: request,
            position: windowVideoViewModel.playbackPosition,
            metadata: metadata
        )
    }

    private func queuePersistence(for snapshot: PlaybackPersistenceSnapshot) {
        print("[Playback] persist_queued name=\(snapshot.request.displayName)")
        Task.detached(priority: .utility) { [progressStore, metadataService] in
            if let fileIdentifier = snapshot.request.fileIdentifier,
                snapshot.position.seconds > 0 {
                await progressStore.saveProgress(
                    PersistenceDomain.PlaybackProgress(
                        fileID: fileIdentifier,
                        position: PersistenceDomain.ProgressPosition(
                            seconds: snapshot.position.seconds)
                    )
                )
            }

            if let metadata = snapshot.metadata {
                await metadataService.persist(metadata, for: snapshot.request)
            }
        }
    }

    // MARK: - Network Retry

    private static func isNetworkURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return ["smb", "http", "https", "ftp"].contains(scheme)
    }

    /// Retries playback with exponential backoff, waiting for network to recover.
    /// Returns `true` if playback eventually succeeds.
    private func retryPlayback(
        request: PlaybackLaunchRequest,
        generation: Int
    ) async -> Bool {
        for attempt in 1...Self.maxRetries {
            guard self.generation == generation else { return false }
            guard !Task.isCancelled else { return false }

            let delay = Self.retryBaseDelay * Int(pow(2.0, Double(attempt - 1)))
            print("[Playback] retry_waiting attempt=\(attempt)/\(Self.maxRetries) delay=\(delay)")

            // Show buffering state while waiting
            windowVideoViewModel.playbackState = .buffering

            // Wait for delay, then check network
            try? await Task.sleep(for: delay)
            guard self.generation == generation else { return false }

            let networkReady = await networkMonitor.waitForConnection(timeout: .seconds(10))
            guard self.generation == generation else { return false }
            guard networkReady else {
                print("[Playback] retry_no_network attempt=\(attempt)")
                continue
            }

            print("[Playback] retry_attempting attempt=\(attempt)")
            do {
                try await windowVideoViewModel.play(url: request.url)
                let defaultSpeed = preferencesStore.loadPreferences().defaultPlaybackSpeed
                if defaultSpeed != 1.0 {
                    windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(defaultSpeed))
                }
                print("[Playback] retry_succeeded attempt=\(attempt)")
                return true
            } catch {
                print("[Playback] retry_failed attempt=\(attempt) error=\(error.localizedDescription)")
            }
        }
        print("[Playback] retry_exhausted max=\(Self.maxRetries)")
        return false
    }
}

private nonisolated struct PlaybackPersistenceSnapshot: Sendable {
    let request: PlaybackLaunchRequest
    let position: PlaybackCoreDomain.PlaybackPosition
    let metadata: PlaybackMediaMetadata?
}
