import Foundation

public enum PlaybackError: Error, Sendable {
    case failedToLoad(URL)
    case unsupportedMedia
    case runtime(String)
}

public enum PlaybackEvent: Sendable {
    case started
    case paused
    case resumed
    case ended
    case positionUpdated(PlaybackCoreDomain.PlaybackPosition)
    case speedChanged(PlaybackCoreDomain.PlaybackSpeed)
    case trackSwitched
    case mediaProfileDetected(PlaybackCoreDomain.MediaProfile)
    case failed(PlaybackError)
}
