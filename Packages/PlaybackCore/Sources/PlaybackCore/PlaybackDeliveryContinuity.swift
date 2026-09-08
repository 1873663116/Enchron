@preconcurrency import CoreMedia
import Foundation

public enum PlaybackDeliveryContinuityPhase: String, Codable, Sendable, Equatable {
    case inactive
    case starved
    case recovered
}

public enum PlaybackDeliveryContinuityDetectionSource: String, Codable, Sendable, Equatable {
    case blockedLanes
    case hostWatchdog
    case deliveryLag
}

public struct PlaybackDeliveryContinuityEvidence: Codable, Sendable, Equatable {
    public var incidentID: UInt64
    public var detectionSource: PlaybackDeliveryContinuityDetectionSource
    public var watchdogCause: PlaybackTimelineHostWatchdogCause?
    public var requiredLanes: [String]
    public var rateApplicationGeneration: UInt64
    public var videoStreamEpoch: UInt64
    public var audioStreamEpoch: UInt64
    public var requestedRate: Float
    public var frozenMediaTimeSeconds: Double
    public var exhaustedPresentationEndSeconds: [String: Double]
    public var recoveredMediaTimeSeconds: Double?
    public var recoveredPresentationEndSeconds: [String: Double]?

    public init(
        incidentID: UInt64,
        detectionSource: PlaybackDeliveryContinuityDetectionSource,
        watchdogCause: PlaybackTimelineHostWatchdogCause?,
        requiredLanes: [String],
        rateApplicationGeneration: UInt64,
        videoStreamEpoch: UInt64,
        audioStreamEpoch: UInt64,
        requestedRate: Float,
        frozenMediaTimeSeconds: Double,
        exhaustedPresentationEndSeconds: [String: Double],
        recoveredMediaTimeSeconds: Double? = nil,
        recoveredPresentationEndSeconds: [String: Double]? = nil
    ) {
        self.incidentID = incidentID
        self.detectionSource = detectionSource
        self.watchdogCause = watchdogCause
        self.requiredLanes = requiredLanes
        self.rateApplicationGeneration = rateApplicationGeneration
        self.videoStreamEpoch = videoStreamEpoch
        self.audioStreamEpoch = audioStreamEpoch
        self.requestedRate = requestedRate
        self.frozenMediaTimeSeconds = frozenMediaTimeSeconds
        self.exhaustedPresentationEndSeconds = exhaustedPresentationEndSeconds
        self.recoveredMediaTimeSeconds = recoveredMediaTimeSeconds
        self.recoveredPresentationEndSeconds = recoveredPresentationEndSeconds
    }
}

public struct PlaybackDeliveryContinuityObservation: Codable, Sendable, Equatable {
    public var phase: PlaybackDeliveryContinuityPhase
    public var evidence: PlaybackDeliveryContinuityEvidence?

    public init(
        phase: PlaybackDeliveryContinuityPhase,
        evidence: PlaybackDeliveryContinuityEvidence? = nil
    ) {
        self.phase = phase
        self.evidence = evidence
    }
}

struct PlaybackDeliveryContinuityMediaState: Equatable, Sendable {
    var requiredLanes: Set<PlaybackDeliveryLane>
    var providerEndedLanes: Set<PlaybackDeliveryLane>
    var presentationEndByLane: [PlaybackDeliveryLane: CMTime]
}

struct PlaybackDeliveryContinuity: Sendable {
    private struct Starvation: Sendable {
        var run: PlaybackTimelineProgressRun
        var frozenMediaTime: CMTime
        var baselinePresentationEndByLane: [PlaybackDeliveryLane: CMTime]
        var evidence: PlaybackDeliveryContinuityEvidence
    }

    private enum Phase: Sendable {
        case inactive
        case monitoring(PlaybackTimelineProgressRun)
        case starved(Starvation)
    }

    private var phase = Phase.inactive
    private var lagStarvation: PlaybackDeliveryContinuityEvidence?
    private var nextLagIncidentID: UInt64 = 0

    var isStarved: Bool {
        if lagStarvation != nil { return true }
        if case .starved = phase { return true }
        return false
    }

    var currentRun: PlaybackTimelineProgressRun? {
        switch phase {
        case .inactive:
            nil
        case .monitoring(let run):
            run
        case .starved(let starvation):
            starvation.run
        }
    }

    mutating func activate(_ run: PlaybackTimelineProgressRun) {
        phase = .monitoring(run)
    }

    mutating func invalidate() -> PlaybackDeliveryContinuityObservation? {
        let wasStarved = isStarved
        phase = .inactive
        lagStarvation = nil
        return wasStarved
            ? PlaybackDeliveryContinuityObservation(phase: .inactive)
            : nil
    }

    mutating func observeDeliveryLag(
        frozenMediaTime: CMTime,
        mediaState: PlaybackDeliveryContinuityMediaState,
        rateApplicationGeneration: UInt64,
        videoStreamEpoch: UInt64,
        audioStreamEpoch: UInt64,
        requestedRate: Float
    ) -> PlaybackDeliveryContinuityObservation? {
        guard lagStarvation == nil, frozenMediaTime.isNumeric else { return nil }
        let activeRequiredLanes = mediaState.requiredLanes.subtracting(
            mediaState.providerEndedLanes
        )
        var exhaustedEnds: [PlaybackDeliveryLane: CMTime] = [:]
        for lane in activeRequiredLanes {
            guard let presentationEnd = mediaState.presentationEndByLane[lane],
                  presentationEnd.isNumeric else { continue }
            exhaustedEnds[lane] = presentationEnd
        }
        nextLagIncidentID &+= 1
        let evidence = PlaybackDeliveryContinuityEvidence(
            incidentID: nextLagIncidentID,
            detectionSource: .deliveryLag,
            watchdogCause: nil,
            requiredLanes: activeRequiredLanes.map(\.rawValue).sorted(),
            rateApplicationGeneration: rateApplicationGeneration,
            videoStreamEpoch: videoStreamEpoch,
            audioStreamEpoch: audioStreamEpoch,
            requestedRate: requestedRate,
            frozenMediaTimeSeconds: frozenMediaTime.seconds,
            exhaustedPresentationEndSeconds: Self.secondsByLane(exhaustedEnds)
        )
        lagStarvation = evidence
        return PlaybackDeliveryContinuityObservation(phase: .starved, evidence: evidence)
    }

    mutating func observeIncident(
        _ incident: PlaybackTimelineProgressIncident,
        mediaState: PlaybackDeliveryContinuityMediaState
    ) -> PlaybackDeliveryContinuityObservation? {
        let activeRequiredLanes = mediaState.requiredLanes.subtracting(
            mediaState.providerEndedLanes
        )
        guard case .monitoring(let run) = phase,
              run == incident.run,
              activeRequiredLanes.isEmpty == false else { return nil }

        var exhaustedEnds: [PlaybackDeliveryLane: CMTime] = [:]
        for lane in activeRequiredLanes {
            guard let presentationEnd = mediaState.presentationEndByLane[lane],
                  presentationEnd.isNumeric,
                  CMTimeCompare(presentationEnd, incident.frozenMediaTime) <= 0 else {
                return nil
            }
            exhaustedEnds[lane] = presentationEnd
        }

        let detectionSource: PlaybackDeliveryContinuityDetectionSource
        let watchdogCause: PlaybackTimelineHostWatchdogCause?
        switch incident.evidence {
        case .blockedLanes:
            detectionSource = .blockedLanes
            watchdogCause = nil
        case .hostWatchdog(let watchdog):
            detectionSource = .hostWatchdog
            watchdogCause = watchdog.cause
        }
        let evidence = PlaybackDeliveryContinuityEvidence(
            incidentID: incident.incidentID,
            detectionSource: detectionSource,
            watchdogCause: watchdogCause,
            requiredLanes: activeRequiredLanes
                .map(\.rawValue)
                .sorted(),
            rateApplicationGeneration: run.generation,
            videoStreamEpoch: run.videoStreamEpoch,
            audioStreamEpoch: run.audioStreamEpoch,
            requestedRate: run.requestedRate,
            frozenMediaTimeSeconds: incident.frozenMediaTime.seconds,
            exhaustedPresentationEndSeconds: Self.secondsByLane(exhaustedEnds)
        )
        phase = .starved(Starvation(
            run: run,
            frozenMediaTime: incident.frozenMediaTime,
            baselinePresentationEndByLane: exhaustedEnds,
            evidence: evidence
        ))
        return PlaybackDeliveryContinuityObservation(
            phase: .starved,
            evidence: evidence
        )
    }

    mutating func observeProgress(
        run: PlaybackTimelineProgressRun,
        reading: PlaybackTimelineClockReading,
        mediaState: PlaybackDeliveryContinuityMediaState
    ) -> PlaybackDeliveryContinuityObservation? {
        let activeRequiredLanes = mediaState.requiredLanes.subtracting(
            mediaState.providerEndedLanes
        )
        guard case .starved(let starvation) = phase,
              starvation.run == run,
              reading.mediaTime.isNumeric,
              CMTimeCompare(reading.mediaTime, starvation.frozenMediaTime) > 0,
              activeRequiredLanes
                == Set(starvation.baselinePresentationEndByLane.keys) else { return nil }

        var recoveredEnds: [PlaybackDeliveryLane: CMTime] = [:]
        for lane in activeRequiredLanes {
            guard let baseline = starvation.baselinePresentationEndByLane[lane],
                  let current = mediaState.presentationEndByLane[lane],
                  current.isNumeric,
                  CMTimeCompare(current, baseline) > 0,
                  CMTimeCompare(current, reading.mediaTime) > 0 else {
                return nil
            }
            recoveredEnds[lane] = current
        }

        var evidence = starvation.evidence
        evidence.recoveredMediaTimeSeconds = reading.mediaTime.seconds
        evidence.recoveredPresentationEndSeconds = Self.secondsByLane(recoveredEnds)
        phase = .monitoring(run)
        return PlaybackDeliveryContinuityObservation(
            phase: .recovered,
            evidence: evidence
        )
    }

    private static func secondsByLane(
        _ values: [PlaybackDeliveryLane: CMTime]
    ) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: values.map { lane, time in
            (lane.rawValue, time.seconds)
        })
    }
}
