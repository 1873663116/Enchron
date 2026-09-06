public enum PlaybackAfterSeekBehavior: Sendable, Equatable {
    case preserveCurrentPauseState
    case play
    case pause
    case end

    var endsPlayback: Bool { self == .end }

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
        case .pause, .end:
            true
        }
    }
}
