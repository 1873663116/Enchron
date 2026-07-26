public enum PlaybackEndBehavior: Sendable, Hashable {
    case stop
    case repeatOne
    case playNext
}

public enum ResumePolicy: Sendable, Hashable {
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
        endBehavior: PlaybackEndBehavior = .stop,
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

public enum PlaybackEndAction: Equatable, Sendable {
    case stayEnded
    case repeatCurrent
    case playNext
}

public enum PlaybackEndPolicy {
    public static func action(for behavior: PlaybackEndBehavior) -> PlaybackEndAction {
        switch behavior {
        case .stop: .stayEnded
        case .repeatOne: .repeatCurrent
        case .playNext: .playNext
        }
    }
}

public struct DefaultPlaybackPreferencesProvider: PlaybackPreferencesProviding {
    public init() {}

    public func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences()
    }
}
