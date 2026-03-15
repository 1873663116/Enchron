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
    private let metadataService: PlaybackMediaMetadataService

    private var activeTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var generation: Int = 0

    public init(
        appModel: AppModel,
        windowVideoViewModel: WindowVideoViewModel,
        progressStore: ProgressStoring = SwiftDataStore(),
        metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService()
    ) {
        self.appModel = appModel
        self.windowVideoViewModel = windowVideoViewModel
        self.progressStore = progressStore
        self.metadataService = metadataService

        self.windowVideoViewModel.onMediaProfileResolved = { [weak self] request, profile in
            guard let self else { return }
            Task {
                let metadata = await self.metadataService.recordDetectedProfile(
                    profile, for: request)
                await MainActor.run {
                    guard self.windowVideoViewModel.currentLaunchRequest == request else { return }
                    self.windowVideoViewModel.applyPrefetchedMetadata(metadata)
                    self.appModel.updateMediaProfile(profile)
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
            } catch {
                guard self.generation == currentGeneration else { return }
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
}

private struct PlaybackPersistenceSnapshot {
    let request: PlaybackLaunchRequest
    let position: PlaybackCoreDomain.PlaybackPosition
    let metadata: PlaybackMediaMetadata?
}
