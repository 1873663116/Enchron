import AVFoundation
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

    public enum DiagnosticRenderer: String, CaseIterable, Sendable {
        case mpv = "MPV"
        case apple = "Apple"
    }

    public struct AVReferenceMetadata: Equatable, Sendable {
        public var eligibleForHDRPlayback: Bool?
        public var containsHDRVideo: Bool?
        public var transferFunction: String?
        public var colorPrimaries: String?
        public var yCbCrMatrix: String?
        public var status: String

        public static let idle = AVReferenceMetadata(
            eligibleForHDRPlayback: nil,
            containsHDRVideo: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            yCbCrMatrix: nil,
            status: "not loaded"
        )
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
    public var diagnosticRenderer: DiagnosticRenderer = .mpv
    public private(set) var appleReferencePlayer: AVPlayer?
    public private(set) var avReferenceMetadata: AVReferenceMetadata = .idle
    public private(set) var syntheticHDRProbeSample: PlaybackCoreDomain.HDRProbeSample?
    public private(set) var latestHDRProbeSample: PlaybackCoreDomain.HDRProbeSample?
    public private(set) var latestHDRProbeOnSample: PlaybackCoreDomain.HDRProbeSample?
    public private(set) var latestHDRProbeOffSample: PlaybackCoreDomain.HDRProbeSample?
    public private(set) var lastHDRProbeError: String?
    public var currentPlaybackSpeed: PlaybackCoreDomain.PlaybackSpeed = .default

    // Metal renderer
    public let renderer: MetalVideoRenderer?

    // Dependencies
    private let player: PlaybackControlling
    private let hdrProbeController = HDRProbeController()
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
        if diagnosticRenderer == .apple, let appleReferencePlayer {
            let seconds = appleReferencePlayer.currentTime().seconds
            let duration = appleReferencePlayer.currentItem?.duration.seconds
            playbackPosition = .init(
                seconds: seconds.isFinite ? seconds : playbackPosition.seconds,
                duration: duration?.isFinite == true ? duration ?? playbackPosition.duration : playbackPosition.duration
            )
            playbackState = appleReferencePlayer.rate == 0 ? .paused : .playing
            return
        }

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

    public var hdrProbeDelta: PlaybackCoreDomain.HDRProbeDelta? {
        guard let latestHDRProbeOnSample, let latestHDRProbeOffSample else { return nil }
        return PlaybackCoreDomain.HDRProbeDelta(
            onSample: latestHDRProbeOnSample,
            offSample: latestHDRProbeOffSample
        )
    }

    /// The current video's display aspect ratio, derived from MediaProfile resolution.
    /// Returns nil when no video is loaded or resolution is unknown.
    public var videoAspectRatio: CGFloat? {
        guard let resolution = currentMediaProfile?.resolution,
              resolution.width > 0,
              resolution.height > 0 else { return nil }
        return CGFloat(resolution.width) / CGFloat(resolution.height)
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
            diagnosticRenderer = .mpv
            teardownAppleReferencePlayer()
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
        if diagnosticRenderer == .apple {
            appleReferencePlayer?.pause()
            playbackState = .paused
            return
        }
        player.pause()
    }

    public func resume() {
        if diagnosticRenderer == .apple {
            appleReferencePlayer?.playImmediately(atRate: Float(currentPlaybackSpeed.value))
            playbackState = .playing
            return
        }
        player.resume()
    }

    public func stop() {
        stopPlaybackEngine()
        teardownAppleReferencePlayer()
        lastErrorMessage = nil
        clearPresentation()
    }

    public func cancelPendingLoad() {
        cancelPendingLoadEngine()
        teardownAppleReferencePlayer()
        lastErrorMessage = nil
        clearPresentation()
    }

    public func seek(to seconds: Double) {
        if diagnosticRenderer == .apple {
            appleReferencePlayer?.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            playbackPosition = .init(seconds: seconds, duration: playbackPosition.duration)
            return
        }
        player.seek(to: seconds)
        // Immediate UI update — don't wait for 200ms polling
        playbackPosition = .init(seconds: seconds, duration: playbackPosition.duration)
    }

    public func skip(by delta: Double) {
        if diagnosticRenderer == .apple {
            seek(to: max(0, playbackPosition.seconds + delta))
            return
        }
        player.skip(by: delta)
    }

    public func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        currentPlaybackSpeed = speed
        player.setSpeed(speed)
        if diagnosticRenderer == .apple {
            appleReferencePlayer?.rate = Float(speed.value)
        }
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
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.sampleCurrentHDRDrawable(trigger: "hdr_toggle")
        }
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

    public func setDiagnosticRenderer(_ renderer: DiagnosticRenderer) {
        guard renderer != diagnosticRenderer else { return }
        switch renderer {
        case .mpv:
            switchBackToMPVRenderer()
        case .apple:
            switchToAppleReferenceRenderer()
        }
    }

    public func sampleSyntheticHDRProbe() {
        let sample = hdrProbeController.sampleSyntheticEDR(
            hdrOutputEnabled: isHDROutputEnabled
        )
        syntheticHDRProbeSample = sample
        latestHDRProbeSample = sample
        lastHDRProbeError = nil
    }

    public func sampleCurrentHDRDrawable(trigger: String = "manual") async {
        (player as? MPVPlayerAdapter)?.prepareForHDRDiagnosticProbe()
        do {
            let sample = try hdrProbeController.sampleMPVDrawable(
                from: nativeVideoLayer,
                hdrOutputEnabled: isHDROutputEnabled,
                videoTime: playbackPosition.seconds
            )
            latestHDRProbeSample = sample
            if sample.hdrOutputEnabled == true {
                latestHDRProbeOnSample = sample
            } else if sample.hdrOutputEnabled == false {
                latestHDRProbeOffSample = sample
            }
            lastHDRProbeError = nil
            print("[HDRProbe] sample trigger=\(trigger) max=\(sample.statistics.maxRGB.maxChannel) p99=\(sample.statistics.p99Luminance) above1=\(sample.statistics.countAbove1)")
        } catch {
            lastHDRProbeError = error.localizedDescription
            print("[HDRProbe] sample_failed trigger=\(trigger) error=\(error.localizedDescription)")
        }
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
        syntheticHDRProbeSample = nil
        latestHDRProbeSample = nil
        latestHDRProbeOnSample = nil
        latestHDRProbeOffSample = nil
        lastHDRProbeError = nil
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

    private func switchToAppleReferenceRenderer() {
        guard let url = currentPlaybackURL else { return }
        let time = playbackPosition.seconds
        let shouldResume = playbackState == .playing
        player.pause()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        appleReferencePlayer = player
        diagnosticRenderer = .apple
        Task { await loadAVReferenceMetadata(for: url) }

        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        let rate = Float(currentPlaybackSpeed.value)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
            guard shouldResume else { return }
            player?.playImmediately(atRate: rate)
        }
    }

    private func switchBackToMPVRenderer() {
        let playerTime = appleReferencePlayer?.currentTime().seconds
        let shouldResume = (appleReferencePlayer?.rate ?? 0) != 0
        appleReferencePlayer?.pause()
        diagnosticRenderer = .mpv
        if let playerTime, playerTime.isFinite {
            seek(to: playerTime)
        }
        if shouldResume {
            resume()
        }
    }

    private func teardownAppleReferencePlayer() {
        appleReferencePlayer?.pause()
        appleReferencePlayer = nil
        avReferenceMetadata = .idle
        diagnosticRenderer = .mpv
    }

    private func loadAVReferenceMetadata(for url: URL) async {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        defer { asset.cancelLoading() }

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                avReferenceMetadata = AVReferenceMetadata(
                    eligibleForHDRPlayback: AVPlayer.eligibleForHDRPlayback,
                    containsHDRVideo: nil,
                    transferFunction: nil,
                    colorPrimaries: nil,
                    yCbCrMatrix: nil,
                    status: "unsupported by AVFoundation reference path"
                )
                return
            }
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            let description = formatDescriptions.first
            avReferenceMetadata = AVReferenceMetadata(
                eligibleForHDRPlayback: AVPlayer.eligibleForHDRPlayback,
                containsHDRVideo: videoTrack.hasMediaCharacteristic(.containsHDRVideo),
                transferFunction: Self.formatExtension(
                    description,
                    key: kCMFormatDescriptionExtension_TransferFunction
                ),
                colorPrimaries: Self.formatExtension(
                    description,
                    key: kCMFormatDescriptionExtension_ColorPrimaries
                ),
                yCbCrMatrix: Self.formatExtension(
                    description,
                    key: kCMFormatDescriptionExtension_YCbCrMatrix
                ),
                status: "system reference only"
            )
        } catch {
            avReferenceMetadata = AVReferenceMetadata(
                eligibleForHDRPlayback: AVPlayer.eligibleForHDRPlayback,
                containsHDRVideo: nil,
                transferFunction: nil,
                colorPrimaries: nil,
                yCbCrMatrix: nil,
                status: "unsupported by AVFoundation reference path"
            )
        }
    }

    private static func formatExtension(
        _ description: CMFormatDescription?,
        key: CFString
    ) -> String? {
        guard let description else { return nil }
        return CMFormatDescriptionGetExtension(description, extensionKey: key) as? String
    }
}
