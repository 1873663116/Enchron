import Foundation

public enum PlaybackCoreDomain {}

extension PlaybackCoreDomain {
    public enum PlaybackState: Sendable {
        case idle
        case loading
        case playing
        case paused
        case buffering
        case stopped
        case ended
        case failed
    }
}
