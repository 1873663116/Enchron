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

    private var activeTask: Task<Void, Never>?
    private var generation: Int = 0

    public init(appModel: AppModel, windowVideoViewModel: WindowVideoViewModel) {
        self.appModel = appModel
        self.windowVideoViewModel = windowVideoViewModel
    }

    public func beginPlayback(for url: URL) {
        generation += 1
        let currentGeneration = generation

        activeTask?.cancel()
        activeTask = nil

        // Tear down any in-flight or active playback.
        switch windowVideoViewModel.playbackState {
        case .loading, .buffering:
            windowVideoViewModel.cancelPendingLoad()
        case .playing, .paused, .ended, .failed, .stopped:
            windowVideoViewModel.stop()
        case .idle:
            break
        }

        appModel.startPlayback(url: url)

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
            guard self.appModel.currentPlaybackURL == url else { return }

            print("[PlaybackLaunch] request_started url=\(url.lastPathComponent)")

            do {
                try await self.windowVideoViewModel.play(url: url)
                print("[PlaybackLaunch] first_frame_visible url=\(url.lastPathComponent)")
            } catch {
                guard self.generation == currentGeneration else { return }
                print("[PlaybackLaunch] playback_failed url=\(url.lastPathComponent) error=\(error.localizedDescription)")
                self.appModel.stopPlayback()
            }
        }
    }
}
