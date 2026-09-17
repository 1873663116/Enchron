import CoreMedia
import Foundation

public enum PlaybackEndReason: String, Codable, Equatable, Sendable {
    case naturalCompletion
    case seekToEnd
}

public struct PlaybackEndReceipt: Equatable, Sendable {
    public enum Provenance: String, Equatable, Sendable {
        case naturalCompletion
        case seekToEnd
        case restored
    }

    public let reason: PlaybackEndReason
    public let deliveredEndSeconds: Double?
    let provenance: Provenance

    private init(
        reason: PlaybackEndReason,
        deliveredEndSeconds: Double?,
        provenance: Provenance
    ) {
        self.reason = reason
        self.deliveredEndSeconds = deliveredEndSeconds
        self.provenance = provenance
    }

    static func completion(
        reason: PlaybackEndReason,
        deliveredEndSeconds: Double?,
        declaredDurationSeconds: Double?
    ) -> PlaybackEndReceipt? {
        if let duration = declaredDurationSeconds, duration.isFinite, duration > 0 {
            guard let deliveredEndSeconds,
                  deliveredEndSeconds >= duration
                      - PlaybackBufferingPolicy.endOfMediaToleranceSeconds
            else { return nil }
        }
        return PlaybackEndReceipt(
            reason: reason,
            deliveredEndSeconds: deliveredEndSeconds,
            provenance: reason == .seekToEnd ? .seekToEnd : .naturalCompletion
        )
    }

    static func seekToEnd(endSeconds: Double) -> PlaybackEndReceipt {
        PlaybackEndReceipt(
            reason: .seekToEnd,
            deliveredEndSeconds: endSeconds,
            provenance: .seekToEnd
        )
    }

    public init(restoring continuity: PlaybackEndedContinuity) {
        self.init(
            reason: continuity.reason,
            deliveredEndSeconds: continuity.finalVideoPresentationTime.isNumeric
                ? continuity.finalVideoPresentationTime.seconds
                : nil,
            provenance: .restored
        )
    }
}

public struct PlaybackEndedContinuity: Equatable, Sendable {
    public let reason: PlaybackEndReason
    public let logicalPosition: CMTime
    public let finalVideoPresentationTime: CMTime
}

enum PlaybackEndClaim: Equatable, Sendable {
    case pending
    case completed(PlaybackEndReceipt)
    case truncated(deliveredEndSeconds: Double?, declaredDurationSeconds: Double)
}

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended(PlaybackEndReceipt)
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
