import Foundation
import Observation
import MetalKit
import QuartzCore

@MainActor
@Observable
public final class WindowVideoViewModel {
    public var playbackState: PlaybackCoreDomain.PlaybackState = .idle
    public var playbackPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    public var lastErrorMessage: String?
    public var currentMediaProfile: PlaybackCoreDomain.MediaProfile?
    public let usesNativeGPUOutput: Bool
    public let gestureUseCase = DisambiguateGestureUseCase()

    // Metal renderer
    public let renderer: MetalVideoRenderer?

    // Dependencies
    private let player: PlaybackControlling
    private nonisolated(unsafe) var _cancelStatus: (() -> Void)?

    public var onPlaybackEnded: (() -> Void)?

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
                self?.currentMediaProfile = profile
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
        self.playbackState = player.currentState
        self.playbackPosition = player.currentPosition
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

    public func play(url: URL) async throws {
        do {
            try await player.play(url: url)
            lastErrorMessage = nil
        } catch {
            self.playbackState = .failed
            self.lastErrorMessage = error.localizedDescription
            print("Failed to play: \(error.localizedDescription)")
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
        player.stop()
        lastErrorMessage = nil
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

    public func attachVideoLayer(_ layer: CAMetalLayer?) {
        (player as? MPVPlayerAdapter)?.attachVideoLayer(layer)
    }
}
