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

    public init(
        appModel: AppModel,
        windowVideoViewModel: WindowVideoViewModel,
        progressStore: ProgressStoring = SwiftDataStore(),
        preferencesStore: PreferencesStoring = UserDefaultsStore(),
        metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService(),
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.appModel = appModel
        self.windowVideoViewModel = windowVideoViewModel
        self.progressStore = progressStore
        self.preferencesStore = preferencesStore
        self.metadataService = metadataService
        self.networkMonitor = networkMonitor

        self.windowVideoViewModel.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                let metadata = await self.metadataService.recordDetectedProfile(
                    profile, for: request)
                await MainActor.run {
                    guard self.windowVideoViewModel.currentLaunchRequest == request else { return }
                    self.windowVideoViewModel.applyPrefetchedMetadata(metadata)
                    self.appModel.updateMediaProfile(profile)
                    self.appModel.updateDetectedProjection(profile.projectionType)
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
        windowVideoViewModel.clearPresentationForTeardown()
        print("[Playback] surface_cleared reason=switch")
        tearDownPlaybackEngine()

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
                        self.appModel.updateDetectedProjection(mediaProfile.projectionType)
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
        windowVideoViewModel.clearPresentation()
        appModel.stopPlayback()
        print("[Playback] surface_cleared reason=close")
        tearDownPlaybackEngine()

        if let previousSession {
            queuePersistence(for: previousSession)
        }
    }

    // MARK: - Prepare/Confirm Flow

    /// Starts metadata prefetch and track enumeration without beginning playback.
    ///
    /// The coordinator publishes progress through `currentPreparation`.
    /// Call `confirmPlayback(_:)` with the resulting `PreparedPlayback` to
    /// actually start playback, or `cancelPreparedPlayback()` to discard it.
    public func preparePlayback(_ request: PlaybackLaunchRequest) {
        generation += 1
        let currentGeneration = generation

        // Cancel any in-flight preparation
        cancelPreparationTasks()
        currentPreparation = .preparing(request: request, metadata: request.initialMetadata)
        print("[Playback] prepare_started name=\(request.displayName)")

        preparationTask = Task { [weak self] in
            guard let self else { return }

            // Phase 1: Metadata prefetch
            let resolvedMetadata = await self.metadataService.prepareMetadata(for: request)
            guard !Task.isCancelled else { return }
            guard self.generation == currentGeneration else { return }

            let mergedMetadata = request.initialMetadata?.merging(with: resolvedMetadata) ?? resolvedMetadata

            // Update preparation state with resolved metadata
            self.currentPreparation = .preparing(request: request, metadata: mergedMetadata)

            // Phase 2: Load file paused for track enumeration — no frames rendered.
            // Uses mpv's pause=yes mode: container is parsed, tracks populated,
            // but no video frames are decoded or presented.
            let preparedRequest = request.updating(metadata: mergedMetadata)
            // Store the request for tracking but do NOT change presentation state.
            self.windowVideoViewModel.currentLaunchRequest = preparedRequest

            do {
                try await self.windowVideoViewModel.loadPaused(url: preparedRequest.url)
                guard !Task.isCancelled else { return }
                guard self.generation == currentGeneration else { return }

                // Wait for mpv to parse container, detect profile, and populate track lists.
                // Poll until tracks appear or timeout after ~2s.
                var waitedMs = 0
                let maxWaitMs = 2000
                while waitedMs < maxWaitMs {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    guard self.generation == currentGeneration else { return }
                    waitedMs += 100
                    // Break early once tracks and profile are available
                    if !self.windowVideoViewModel.availableAudioTracks.isEmpty,
                       self.windowVideoViewModel.displayMediaProfile != nil {
                        break
                    }
                }

                let audioTracks = self.windowVideoViewModel.availableAudioTracks
                let subtitleTracks = self.windowVideoViewModel.availableSubtitleTracks

                // Merge metadata from service prefetch AND mpv runtime detection
                var finalMetadata = mergedMetadata
                if let vmMetadata = self.windowVideoViewModel.prefetchedMetadata {
                    finalMetadata = finalMetadata?.merging(with: vmMetadata) ?? vmMetadata
                }
                if let runtimeProfile = self.windowVideoViewModel.displayMediaProfile,
                   finalMetadata?.mediaProfile == nil {
                    let runtimeMeta = PlaybackMediaMetadata(
                        mediaProfile: runtimeProfile,
                        fileSizeInBytes: finalMetadata?.fileSizeInBytes ?? 0
                    )
                    finalMetadata = finalMetadata?.merging(with: runtimeMeta) ?? runtimeMeta
                }

                let prepared = PreparedPlayback(
                    request: preparedRequest.updating(metadata: finalMetadata),
                    metadata: finalMetadata,
                    audioTracks: audioTracks,
                    subtitleTracks: subtitleTracks,
                    generation: currentGeneration
                )
                self.currentPreparation = .ready(prepared)
                print("[Playback] prepare_ready name=\(request.displayName) audio=\(audioTracks.count) sub=\(subtitleTracks.count)")

                // Start TTL timer
                self.startPreparationTTL(generation: currentGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                guard self.generation == currentGeneration else { return }
                self.currentPreparation = .failed(error)
                print("[Playback] prepare_failed name=\(request.displayName) error=\(error.localizedDescription)")
            }
        }
    }

    /// Resumes playback after the user confirms from the detail view.
    ///
    /// Validates that `prepared.generation` matches the coordinator's current
    /// generation to reject stale confirmations.
    public func confirmPlayback(_ prepared: PreparedPlayback, resumePosition: Double? = nil) {
        guard prepared.generation == generation else {
            print("[Playback] confirm_rejected reason=stale_generation expected=\(generation) got=\(prepared.generation)")
            return
        }

        cancelPreparationTasks()
        currentPreparation = nil

        // Set up ViewModel presentation state now that user has confirmed
        windowVideoViewModel.prepareForPlayback(prepared.request)

        // Resume the already-loaded file
        appModel.startPlayback(url: prepared.request.url)
        if let mediaProfile = prepared.metadata?.mediaProfile {
            appModel.updateMediaProfile(mediaProfile)
            appModel.updateDetectedProjection(mediaProfile.projectionType)
        }
        windowVideoViewModel.resume()

        // Apply default speed preference
        let defaultSpeed = preferencesStore.loadPreferences().defaultPlaybackSpeed
        if defaultSpeed != 1.0 {
            windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(defaultSpeed))
        }

        // Seek to resume position if provided
        if let pos = resumePosition, pos > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.windowVideoViewModel.seek(to: pos)
            }
        }

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
                        self.appModel.updateDetectedProjection(mediaProfile.projectionType)
                    }
                }
            }
        }
    }

    /// Cancels an in-flight or ready preparation and tears down any preloaded state.
    public func cancelPreparedPlayback() {
        guard currentPreparation != nil else { return }

        print("[Playback] prepare_cancelled")
        cancelPreparationTasks()
        currentPreparation = nil

        // Clean up the preloaded mpv state
        windowVideoViewModel.clearPresentation()
        tearDownPlaybackEngine()
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
            break
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
                snapshot.position.seconds > 0
            {
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

private struct PlaybackPersistenceSnapshot {
    let request: PlaybackLaunchRequest
    let position: PlaybackCoreDomain.PlaybackPosition
    let metadata: PlaybackMediaMetadata?
}
