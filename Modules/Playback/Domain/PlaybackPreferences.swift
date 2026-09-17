nonisolated public enum PlaybackEndBehavior: Sendable, Hashable {
    case repeatOne
    case playNext
}

nonisolated public enum ResumePolicy: Sendable, Hashable {
    case askEveryTime
    case alwaysResume
    case alwaysStartFromBeginning
}

public struct PlaybackPreferences: Sendable, Equatable {
    public var resumePolicy: ResumePolicy
    public var endBehavior: PlaybackEndBehavior
    public var defaultSpeed: Double

    public init(
        resumePolicy: ResumePolicy = .askEveryTime,
        endBehavior: PlaybackEndBehavior = .repeatOne,
        defaultSpeed: Double = 1
    ) {
        self.resumePolicy = resumePolicy
        self.endBehavior = endBehavior
        self.defaultSpeed = defaultSpeed
    }
}

public protocol PlaybackPreferencesProviding: Sendable {
    func loadPlaybackPreferences() -> PlaybackPreferences
}

public enum PlaybackEndPolicy {
    public static func affordance(
        for behavior: PlaybackEndBehavior,
        nextAvailable: Bool
    ) -> PlaybackEndedAffordance {
        switch behavior {
        case .repeatOne: .replay
        case .playNext: .playNext(available: nextAvailable)
        }
    }
}

public struct DefaultPlaybackPreferencesProvider: PlaybackPreferencesProviding {
    public init() {}

    public func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences()
    }
}
