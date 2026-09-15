import Foundation

public enum PlaybackHost: String, Equatable, Sendable {
    case window
    case immersiveSpace
}

public enum PlaybackLeaveReason: String, Equatable, Sendable {
    case backButton
    case windowClosedByWearer
    case applicationBackgrounded
    case failure
}

public enum PlaybackResidency: Equatable, Sendable {
    case browsing
    case playing(host: PlaybackHost)
    case closing(since: ContinuousClock.Instant, reason: PlaybackLeaveReason)

    public var probeDescription: String {
        switch self {
        case .browsing:
            "browsing"
        case .playing(let host):
            "playing:\(host.rawValue)"
        case .closing(_, let reason):
            "closing:\(reason.rawValue)"
        }
    }
}

public enum PlaybackCloseBudget {
    public static let deadline: Duration = .seconds(1)

    public static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1_000)
            + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
