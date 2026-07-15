import Foundation

public nonisolated enum PlaybackModel {}

nonisolated extension PlaybackModel {
    public enum PlaybackState: String, Sendable {
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
