import Foundation

public protocol PlaybackControlling: AnyObject {
    func play(url: URL) async throws
    func pause()
    func resume()
    func stop()
    func cancelPendingLoad()
    func seek(to seconds: Double)
    func skip(by seconds: Double)
    func setSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed)
    func selectAudioTrack(_ track: PlaybackCoreDomain.AudioTrack)
    func selectSubtitleTrack(_ track: PlaybackCoreDomain.SubtitleTrack?)

    var currentState: PlaybackCoreDomain.PlaybackState { get }
    var currentPosition: PlaybackCoreDomain.PlaybackPosition { get }
    var availableAudioTracks: [PlaybackCoreDomain.AudioTrack] { get }
    var availableSubtitleTracks: [PlaybackCoreDomain.SubtitleTrack] { get }
}
