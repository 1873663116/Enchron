import Foundation

public nonisolated protocol PlaybackControlling: AnyObject {
    func play(url: URL) async throws
    /// Loads a file for track enumeration without starting playback.
    func loadPaused(url: URL) async throws
    func pause()
    func resume()
    func stop()
    func cancelPendingLoad()
    func seek(to seconds: Double)
    func skip(by seconds: Double)
    func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed)
    func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack)
    func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?)
    func replay()
    func setHDREnabled(_ enabled: Bool)
    func frameStepForward()
    func frameStepBackward()

    var onMediaProfileDetected: ((PlaybackCoreDomain.MediaProfile) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var currentState: PlaybackCoreDomain.PlaybackState { get }
    var currentPosition: PlaybackCoreDomain.PlaybackPosition { get }
    var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] { get }
    var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] { get }
    var currentAudioTrackID: String? { get }
    var currentSubtitleTrackID: String? { get }
    var isHDRContent: Bool { get }
    var isHDROutputEnabled: Bool { get }
    var hdrOutputMode: PlaybackCoreDomain.HDROutputMode { get }
}
