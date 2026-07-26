/// Determines whether playback runs after the current media session completes a seek.
public enum PlaybackAfterSeekBehavior: Sendable, Equatable {
    /// Keeps the current paused state; every non-paused status resumes after the seek.
    case preserveCurrentPauseState
    /// Completes the seek with playback running.
    case play
    /// Completes the seek with playback paused.
    case pause

    func resolvesStartsPaused(for status: PlaybackStatus) -> Bool {
        switch self {
        case .preserveCurrentPauseState:
            status == .paused
        case .play:
            false
        case .pause:
            true
        }
    }
}
