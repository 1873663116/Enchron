public enum PlaybackSeekEvent: Sendable, Equatable, CaseIterable {
    case progressBar
    case skip
    case precisionTimeline
    case frameStep
}

public enum PlaybackSeekTargetBoundary: Sendable, Equatable {
    case beforeEnd
    case end
}

public enum PlaybackAfterSeekIntent: Sendable, Equatable {
    case preserveCurrentPlaybackIntent
    case pause
    case ended
}

/// Resolves product-level seek semantics without teaching PlaybackCore about UI controls.
public enum PlaybackSeekPolicy {
    public static func intent(
        for event: PlaybackSeekEvent,
        lifecycle: ProductPlaybackLifecycle,
        targetBoundary: PlaybackSeekTargetBoundary
    ) -> PlaybackAfterSeekIntent {
        guard targetBoundary == .beforeEnd else { return .ended }

        switch event {
        case .precisionTimeline, .frameStep:
            return .pause
        case .progressBar, .skip:
            switch lifecycle {
            case .playing, .paused:
                return .preserveCurrentPlaybackIntent
            case .ended, .ready, .idle, .loading, .failed:
                return .pause
            }
        }
    }
}
