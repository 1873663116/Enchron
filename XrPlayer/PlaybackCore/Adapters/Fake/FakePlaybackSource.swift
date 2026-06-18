import Foundation

/// In-memory fake satisfying the `PlaybackControlling` timing semantics for the FakeApp.
/// It simulates position advance, end-of-media, track selection, and HDR flags entirely
/// in memory — no decoding, no rendering, no I/O. Swap to `MPVPlayerAdapter` to ship.
///
/// The advance loop is driven by `tick(realSeconds:)`, so unit tests can step time
/// deterministically without sleeping. The internal timer calls the same `tick`.
public nonisolated final class FakePlaybackSource: PlaybackControlling, @unchecked Sendable {
    public var onMediaProfileDetected: ((PlaybackCoreDomain.MediaProfile) -> Void)? {
        get { stateLock.withLock { internalOnMediaProfileDetected } }
        set { stateLock.withLock { internalOnMediaProfileDetected = newValue } }
    }
    public var onPlaybackEnded: (() -> Void)? {
        get { stateLock.withLock { internalOnPlaybackEnded } }
        set { stateLock.withLock { internalOnPlaybackEnded = newValue } }
    }

    private let stateLock = NSLock()
    private let duration: Double
    private let framesPerSecond: Double
    private let tickInterval: Double

    // Protected by stateLock.
    private var internalState: PlaybackCoreDomain.PlaybackState = .idle
    private var internalSeconds: Double = 0
    private var internalSpeed: Double = 1.0
    private var internalCurrentAudioTrackID: String?
    private var internalCurrentSubtitleTrackID: String?
    private var isHDREnabled = false
    private var didNotifyProfile = false
    private var internalOnMediaProfileDetected: ((PlaybackCoreDomain.MediaProfile) -> Void)?
    private var internalOnPlaybackEnded: (() -> Void)?

    private var timer: DispatchSourceTimer?

    private static let audioTracks: [PlaybackCoreDomain.AudioTrack] = [
        .init(id: "1", languageCode: "en", displayName: "English", isDefault: true),
        .init(id: "2", languageCode: "ja", displayName: "Japanese")
    ]
    private static let subtitleTracks: [PlaybackCoreDomain.SubtitleTrack] = [
        .init(id: "1", languageCode: "en", displayName: "English", isDefault: true),
        .init(id: "2", languageCode: "zh", displayName: "Chinese")
    ]

    public init(duration: Double = 7200, framesPerSecond: Double = 24, tickInterval: Double = 0.25) {
        self.duration = max(0, duration)
        self.framesPerSecond = max(1, framesPerSecond)
        self.tickInterval = max(0.01, tickInterval)
    }

    deinit {
        timer?.cancel()
    }

    public func play(url: URL) async throws {
        stateLock.withLock {
            internalState = .playing
            internalSeconds = 0
        }
        notifyProfileIfNeeded()
        startTimer()
    }

    public func loadPaused(url: URL) async throws {
        stopTimer()
        stateLock.withLock {
            internalState = .paused
            internalSeconds = 0
        }
        notifyProfileIfNeeded()
    }

    public func pause() {
        stopTimer()
        stateLock.withLock {
            if internalState == .playing { internalState = .paused }
        }
    }

    public func resume() {
        stateLock.withLock {
            if internalState != .ended { internalState = .playing }
        }
        startTimer()
    }

    public func stop() {
        stopTimer()
        stateLock.withLock {
            internalState = .stopped
            internalSeconds = 0
        }
    }

    public func cancelPendingLoad() {
        stopTimer()
        stateLock.withLock {
            internalState = .idle
            internalSeconds = 0
        }
    }

    public func seek(to seconds: Double) {
        stateLock.withLock {
            internalSeconds = clampedSeconds(seconds)
        }
    }

    public func skip(by seconds: Double) {
        stateLock.withLock {
            internalSeconds = clampedSeconds(internalSeconds + seconds)
        }
    }

    public func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        stateLock.withLock { internalSpeed = speed.value }
    }

    public func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack) {
        stateLock.withLock { internalCurrentAudioTrackID = track.id }
    }

    public func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?) {
        stateLock.withLock { internalCurrentSubtitleTrackID = track?.id }
    }

    public func replay() {
        stateLock.withLock {
            internalSeconds = 0
            internalState = .playing
        }
        startTimer()
    }

    public func setHDREnabled(_ enabled: Bool) {
        stateLock.withLock { isHDREnabled = enabled }
    }

    public func frameStepForward() {
        stopTimer()
        stateLock.withLock {
            internalState = .paused
            internalSeconds = clampedSeconds(internalSeconds + 1.0 / framesPerSecond)
        }
    }

    public func frameStepBackward() {
        stopTimer()
        stateLock.withLock {
            internalState = .paused
            internalSeconds = clampedSeconds(internalSeconds - 1.0 / framesPerSecond)
        }
    }

    public var currentState: PlaybackCoreDomain.PlaybackState {
        stateLock.withLock { internalState }
    }

    public var currentPosition: PlaybackCoreDomain.PlaybackPosition {
        stateLock.withLock {
            PlaybackCoreDomain.PlaybackPosition(seconds: internalSeconds, duration: duration)
        }
    }

    public var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] { Self.audioTracks }

    public var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] { Self.subtitleTracks }

    public var currentAudioTrackID: String? {
        stateLock.withLock { internalCurrentAudioTrackID }
    }

    public var currentSubtitleTrackID: String? {
        stateLock.withLock { internalCurrentSubtitleTrackID }
    }

    public var isHDRContent: Bool { false }

    public var isHDROutputEnabled: Bool {
        stateLock.withLock { isHDREnabled }
    }

    public var hdrOutputMode: PlaybackCoreDomain.HDROutputMode { .unsupported }

    /// Advances simulated playback by `realSeconds` of wall time, scaled by the current speed.
    /// Reaching `duration` transitions to `.ended` and fires `onPlaybackEnded`. Deterministic
    /// and side-effect-free apart from the end callback, so tests can drive time directly.
    public func tick(realSeconds: Double) {
        let endedCallback: (() -> Void)? = stateLock.withLock {
            guard internalState == .playing else { return nil }
            internalSeconds = min(duration, internalSeconds + realSeconds * internalSpeed)
            guard internalSeconds >= duration else { return nil }
            internalSeconds = duration
            internalState = .ended
            return internalOnPlaybackEnded
        }
        if endedCallback != nil { stopTimer() }
        endedCallback?()
    }

    private func startTimer() {
        stopTimer()
        let source = DispatchSource.makeTimerSource(queue: .global())
        source.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.tick(realSeconds: self.tickInterval)
        }
        timer = source
        source.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func clampedSeconds(_ seconds: Double) -> Double {
        min(max(0, seconds), duration)
    }

    private func notifyProfileIfNeeded() {
        let callback: ((PlaybackCoreDomain.MediaProfile) -> Void)? = stateLock.withLock {
            guard didNotifyProfile == false else { return nil }
            didNotifyProfile = true
            return internalOnMediaProfileDetected
        }
        guard let callback else { return }
        let profile = PlaybackCoreDomain.MediaProfile(
            projectionType: .flat,
            stereoLayout: .mono,
            hdrType: .sdr,
            resolution: .init(width: 1920, height: 1080),
            frameRate: framesPerSecond,
            videoCodec: "h264",
            durationSeconds: duration
        )
        callback(profile)
    }
}
