import Foundation

public enum PlaybackEndReason: String, Codable, Equatable, Sendable {
    case naturalCompletion
    case seekToEnd
}

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended(PlaybackEndReason)
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "No video"
        case .loading: "Loading"
        case .ready: "Ready"
        case .playing: "Playing"
        case .paused: "Paused"
        case .ended: "Ended"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

public struct MediaSessionState: Sendable {
    public private(set) var current: MediaSessionRecord?
    public private(set) var lastRejection: OpenRejectionRecord?
    public private(set) var staleUpdateCount = 0

    public init() {}

    public mutating func admitOpen(
        source: MediaSourceRecord,
        initialTimeSeconds: Double = 0,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        mediaSessionID: String = UUID().uuidString
    ) -> OpenAdmission {
        if let current {
            let rejection = OpenRejectionRecord(
                sourceSummary: source.privacySafeSummary,
                reason: "currentMediaSlotOccupied",
                occupyingMediaSessionID: current.mediaSessionID
            )
            lastRejection = rejection
            return .rejected(rejection)
        }

        let session = MediaSessionRecord(
            mediaSessionID: mediaSessionID,
            source: source,
            initialTimeSeconds: initialTimeSeconds,
            startsPaused: startsPaused,
            initialRate: initialRate
        )
        current = session
        return .accepted(session)
    }

    public mutating func updateLifecycle(
        _ lifecycle: PlaybackLifecycle,
        mediaSessionID: String
    ) -> Bool {
        guard current?.mediaSessionID == mediaSessionID else {
            staleUpdateCount += 1
            return false
        }
        current?.lifecycle = lifecycle
        return true
    }

    public mutating func release(mediaSessionID: String) -> Bool {
        guard current?.mediaSessionID == mediaSessionID else {
            staleUpdateCount += 1
            return false
        }
        current = nil
        return true
    }
}
