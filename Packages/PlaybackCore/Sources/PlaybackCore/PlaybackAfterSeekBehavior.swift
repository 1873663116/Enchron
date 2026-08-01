/// Determines whether playback runs after the current media session completes a seek.
public enum PlaybackAfterSeekBehavior: Sendable, Equatable {
    /// Keeps Playing or Paused. Ended has no playing intent and therefore leaves the seek paused.
    case preserveCurrentPauseState
    /// Completes the seek with playback running.
    case play
    /// Completes the seek with playback paused.
    case pause

    func resolvesStartsPaused(for status: PlaybackStatus) -> Bool {
        switch self {
        case .preserveCurrentPauseState:
            switch status {
            case .playing:
                false
            case .idle, .loading, .ready, .paused, .ended, .failed:
                true
            }
        case .play:
            false
        case .pause:
            true
        }
    }
}
