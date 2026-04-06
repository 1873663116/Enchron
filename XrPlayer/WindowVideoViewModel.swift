import Foundation
import MetalKit
import Observation
import QuartzCore

@MainActor
@Observable
public final class WindowVideoViewModel {
    public enum PresentationState: Sendable {
        case hidden
        case placeholder
        case videoVisible
    }

    public var playbackState: PlaybackCoreDomain.PlaybackState = .idle
    public var playbackPosition: PlaybackCoreDomain.PlaybackPosition = .init(
        seconds: 0, duration: 0)
    public var lastErrorMessage: String?
    public var currentMediaProfile: PlaybackCoreDomain.MediaProfile?
    public private(set) var currentPlaybackURL: URL?
    public var currentLaunchRequest: PlaybackLaunchRequest?
    public private(set) var prefetchedMetadata: PlaybackMediaMetadata?
    public private(set) var presentationState: PresentationState = .hidden
    public let usesNativeGPUOutput: Bool
    public let gestureUseCase = DisambiguateGestureUseCase()

    // Metal renderer
    public let renderer: MetalVideoRenderer?

    // Dependencies
    private let player: PlaybackControlling
    private nonisolated(unsafe) var _cancelStatus: (() -> Void)?
    private var isAwaitingFirstFramePresentation = false

    public var onPlaybackEnded: (() -> Void)?
    public var onMediaProfileResolved:
        ((PlaybackLaunchRequest, PlaybackCoreDomain.MediaProfile) -> Void)?

    public init(player: PlaybackControlling) {
        self.player = player
        if let adapter = player as? MPVPlayerAdapter {
            self.usesNativeGPUOutput = adapter.usesNativeGPUOutput
        } else {
            self.usesNativeGPUOutput = false
        }

        if self.usesNativeGPUOutput == false, let device = MTLCreateSystemDefaultDevice() {
            self.renderer = MetalVideoRenderer(device: device)
        } else {
            self.renderer = nil
        }

        // Wire up FrameOutput after all properties are initialized
        if let adapter = player as? MPVPlayerAdapter {
            adapter.frameOutput = renderer
            adapter.onRuntimeError = { [weak self] message in
                self?.playbackState = .failed
                self?.lastErrorMessage = message
            }
            adapter.onPlaybackEnded = { [weak self] in
                self?.onPlaybackEnded?()
            }
        }

        player.onMediaProfileDetected = { [weak self] profile in
            Task { @MainActor in
                self?.handleMediaProfileDetected(profile)
            }
        }

        startStatusTask()
    }

    deinit {
        _cancelStatus?()
    }

    private func startStatusTask() {
        _cancelStatus?()
        let task = Task { [weak self] in
            while Task.isCancelled == false {
                await MainActor.run { [weak self] in
                    self?.updateStatus()
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        _cancelStatus = { task.cancel() }
    }

    private func updateStatus() {
        let latestState = player.currentState
        // Guard against redundant state writes — avoids spurious @Observable notifications
        // that would re-evaluate every view reading playbackState (play button, menus).
        if self.playbackState != latestState {
            self.playbackState = latestState
        }
        self.playbackPosition = player.currentPosition

        if isAwaitingFirstFramePresentation {
            switch latestState {
            case .playing, .paused, .ended:
                isAwaitingFirstFramePresentation = false
                presentationState = .videoVisible
            case .idle, .loading, .buffering, .stopped, .failed:
                break
            }
        }
    }

    public var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] {
        player.availableAudioTracks
    }

    public var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] {
        player.availableSubtitleTracks
    }

    public var currentAudioTrackID: String? {
        player.currentAudioTrackID
    }

    public var currentSubtitleTrackID: String? {
        player.currentSubtitleTrackID
    }

    public var isHDRContent: Bool {
        player.isHDRContent
    }

    public var isHDROutputEnabled: Bool {
        player.isHDROutputEnabled
    }

    public var hdrOutputMode: PlaybackCoreDomain.HDROutputMode {
        player.hdrOutputMode
    }

    public var displayMediaProfile: PlaybackCoreDomain.MediaProfile? {
        currentMediaProfile ?? prefetchedMetadata?.mediaProfile
    }

    public var displayFileSizeInBytes: Int64? {
        prefetchedMetadata?.fileSizeInBytes
    }

    public var canPresentControls: Bool {
        presentationState == .videoVisible
            && (displayMediaProfile != nil || displayFileSizeInBytes != nil)
    }

    public func play(url: URL) async throws {
        do {
            currentPlaybackURL = url
            try await player.play(url: url)
            lastErrorMessage = nil
        } catch {
            self.playbackState = .failed
            self.lastErrorMessage = error.localizedDescription
            print("Failed to play: \(error.localizedDescription)")
            throw error
        }
    }

    /// Loads a file into mpv for track enumeration only — no frames are rendered.
    /// Used by the prepare/confirm flow in PlaybackLaunchCoordinator.
    public func loadPaused(url: URL) async throws {
        do {
            currentPlaybackURL = url
            try await player.loadPaused(url: url)
            lastErrorMessage = nil
        } catch {
            self.playbackState = .failed
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func pause() {
        player.pause()
    }

    public func resume() {
        player.resume()
    }

    public func stop() {
        stopPlaybackEngine()
        lastErrorMessage = nil
        clearPresentation()
    }

    public func cancelPendingLoad() {
        cancelPendingLoadEngine()
        lastErrorMessage = nil
        clearPresentation()
    }

    public func seek(to seconds: Double) {
        player.seek(to: seconds)
        // Immediate UI update — don't wait for 200ms polling
        playbackPosition = .init(seconds: seconds, duration: playbackPosition.duration)
    }

    public func skip(by delta: Double) {
        player.skip(by: delta)
    }

    public func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        player.setSpeed(speed)
    }

    public func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack) {
        player.selectAudioTrack(track)
    }

    public func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?) {
        player.selectSubtitleTrack(track)
    }

    public func replay() {
        player.replay()
    }

    public func setHDREnabled(_ enabled: Bool) {
        player.setHDREnabled(enabled)
    }

    public func frameStepForward() {
        player.frameStepForward()
    }

    public func frameStepBackward() {
        player.frameStepBackward()
    }

    public func debugSubtitleState() -> String? {
        (player as? MPVPlayerAdapter)?.debugSubtitleState()
    }

    public func captureScreenshot(to url: URL, flags: String = "subtitles") {
        (player as? MPVPlayerAdapter)?.captureScreenshot(to: url, flags: flags)
    }

    /// The CAMetalLayer that libmpv's gpu-next renders into.
    public var nativeVideoLayer: CAMetalLayer? {
        (player as? MPVPlayerAdapter)?.nativeVideoLayer
    }

    public func attachVideoLayer(_ layer: CAMetalLayer?) {
        (player as? MPVPlayerAdapter)?.attachVideoLayer(layer)
    }

    public func prepareForPlayback(_ request: PlaybackLaunchRequest) {
        currentLaunchRequest = request
        currentPlaybackURL = request.url
        currentMediaProfile = nil
        prefetchedMetadata = request.initialMetadata
        playbackPosition = .init(seconds: 0, duration: 0)
        playbackState = .loading
        presentationState = .placeholder
        isAwaitingFirstFramePresentation = true
        lastErrorMessage = nil
        print("[Playback] presentation_prepared name=\(request.displayName)")
    }

    public func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = prefetchedMetadata?.merging(with: metadata) ?? metadata
    }

    public func clearPresentationForTeardown() {
        currentMediaProfile = nil
        prefetchedMetadata = nil
        presentationState = .hidden
        isAwaitingFirstFramePresentation = false
        lastErrorMessage = nil
    }

    public func clearPresentation() {
        clearPresentationForTeardown()
        currentLaunchRequest = nil
        currentPlaybackURL = nil
        playbackPosition = .init(seconds: 0, duration: 0)
    }

    public func stopPlaybackEngine() {
        player.stop()
        playbackState = .stopped
    }

    public func cancelPendingLoadEngine() {
        player.cancelPendingLoad()
        playbackState = .idle
    }

    private func handleMediaProfileDetected(_ profile: PlaybackCoreDomain.MediaProfile) {
        currentMediaProfile = profile
        print(
            "[Playback] profile_ready name=\(currentLaunchRequest?.displayName ?? profile.projectionType.rawValue)"
        )
        if let currentLaunchRequest {
            onMediaProfileResolved?(currentLaunchRequest, profile)
        }
    }
}
