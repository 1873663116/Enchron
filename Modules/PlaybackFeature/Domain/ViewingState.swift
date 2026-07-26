import Foundation
import MediaSource

public enum ViewingStatus: Codable, Equatable, Sendable {
    case resumable(positionSeconds: Double, durationSeconds: Double)
    case completed(durationSeconds: Double)
}

public struct ViewingState: Codable, Equatable, Sendable {
    public let versionedIdentity: VersionedMediaIdentity
    public let status: ViewingStatus
    public let updatedAt: Date

    public init(
        versionedIdentity: VersionedMediaIdentity,
        status: ViewingStatus,
        updatedAt: Date = Date()
    ) {
        self.versionedIdentity = versionedIdentity
        self.status = status
        self.updatedAt = updatedAt
    }
}

public struct PlaybackSessionEvidence: Equatable, Sendable {
    public var durationSeconds: Double
    public var positionSeconds: Double
    public var actualPlaybackSeconds: Double
    public var endedNaturally: Bool

    public init(
        durationSeconds: Double,
        positionSeconds: Double,
        actualPlaybackSeconds: Double,
        endedNaturally: Bool
    ) {
        self.durationSeconds = max(0, durationSeconds)
        self.positionSeconds = max(0, positionSeconds)
        self.actualPlaybackSeconds = max(0, actualPlaybackSeconds)
        self.endedNaturally = endedNaturally
    }
}

public enum ViewingStateMutation: Equatable, Sendable {
    case unchanged
    case remove
    case save(ViewingStatus)
}

public enum ViewingStatePolicy {
    public static let minimumContentDurationSeconds: Double = 15 * 60
    public static let minimumActualPlaybackSeconds: Double = 15
    public static let maximumNearEndSeconds: Double = 5 * 60
    public static let nearEndDurationFraction: Double = 0.1

    public static func mutation(for evidence: PlaybackSessionEvidence) -> ViewingStateMutation {
        guard evidence.durationSeconds >= minimumContentDurationSeconds else { return .remove }

        if evidence.endedNaturally {
            return .save(.completed(durationSeconds: evidence.durationSeconds))
        }

        guard evidence.actualPlaybackSeconds >= minimumActualPlaybackSeconds else {
            return .unchanged
        }

        let position = min(evidence.positionSeconds, evidence.durationSeconds)
        let remaining = evidence.durationSeconds - position
        let nearEndThreshold = min(
            evidence.durationSeconds * nearEndDurationFraction,
            maximumNearEndSeconds
        )
        guard remaining > nearEndThreshold else { return .remove }

        return .save(.resumable(
            positionSeconds: position,
            durationSeconds: evidence.durationSeconds
        ))
    }
}

public struct ActualPlaybackAccumulator: Equatable, Sendable {
    public private(set) var seconds: Double = 0
    private var previousDate: Date?
    private var previousPositionSeconds: Double?

    public init() {}

    @discardableResult
    public mutating func record(
        positionSeconds: Double,
        at date: Date,
        isPlaying: Bool,
        playbackRate: Double
    ) -> Double {
        defer {
            previousDate = date
            previousPositionSeconds = positionSeconds
        }
        guard isPlaying,
              let previousDate,
              let previousPositionSeconds else { return seconds }
        let wallInterval = date.timeIntervalSince(previousDate)
        let mediaInterval = positionSeconds - previousPositionSeconds
        guard wallInterval > 0, mediaInterval > 0 else { return seconds }
        seconds += min(wallInterval, mediaInterval / max(playbackRate, 0.25))
        return seconds
    }

    public mutating func markDiscontinuity() {
        previousDate = nil
        previousPositionSeconds = nil
    }

    public mutating func reset() {
        self = .init()
    }
}
