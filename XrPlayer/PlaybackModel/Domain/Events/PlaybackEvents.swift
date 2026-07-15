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
    case positionUpdated(PlaybackModel.PlaybackPosition)
    case speedChanged(PlaybackModel.PlaybackSpeed)
    case trackSwitched
    case mediaProfileDetected(PlaybackModel.MediaProfile)
    case failed(PlaybackError)
}
