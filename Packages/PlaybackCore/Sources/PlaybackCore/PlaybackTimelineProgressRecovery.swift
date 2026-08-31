@preconcurrency import CoreMedia
import Foundation

enum PlaybackDeliveryLane: String, Codable, Hashable, Sendable {
    case video
    case audio
}

struct PlaybackTimelineProgressRun: Equatable, Sendable {
    var generation: UInt64
    var videoStreamEpoch: UInt64
    var audioStreamEpoch: UInt64
    var requestedRate: Float
    var applicationHostTime: CMTime
}

struct PlaybackTimelineClockReading: Equatable, Sendable {
    var mediaTime: CMTime
    var sourceTime: CMTime
    var ultimateSourceTime: CMTime
    var directRate: Float64
    var effectiveRate: Float64
}

struct PlaybackTimelineFrozenLane: Equatable, Sendable {
    var lane: PlaybackDeliveryLane
    var blockedPresentationTime: CMTime
    var previous: PlaybackTimelineClockReading
    var detected: PlaybackTimelineClockReading
}

public enum PlaybackTimelineHostWatchdogCause: String, Codable, Equatable, Sendable {
    case stoppedTimebase
    case frozenMediaClock
}

struct PlaybackTimelineHostWatchdogEvidence: Equatable, Sendable {
    var cause: PlaybackTimelineHostWatchdogCause
    var first: PlaybackTimelineClockReading
    var detected: PlaybackTimelineClockReading
    var consecutiveObservationCount: Int
}

enum PlaybackTimelineProgressIncidentEvidence: Equatable, Sendable {
    case blockedLanes([PlaybackDeliveryLane: PlaybackTimelineFrozenLane])
    case hostWatchdog(PlaybackTimelineHostWatchdogEvidence)
}

struct PlaybackTimelineProgressIncident: Equatable, Sendable {
    var incidentID: UInt64
    var run: PlaybackTimelineProgressRun
    var frozenMediaTime: CMTime
    var evidence: PlaybackTimelineProgressIncidentEvidence
    var reanchorHostTime: CMTime?

    var frozenLanes: [PlaybackDeliveryLane: PlaybackTimelineFrozenLane] {
        guard case .blockedLanes(let lanes) = evidence else { return [:] }
        return lanes
    }
}

enum PlaybackTimelineProgressDecision: Equatable, Sendable {
    case none
    case reanchor(PlaybackTimelineProgressIncident)
    case resumed(PlaybackTimelineProgressIncident, PlaybackTimelineClockReading)
    case notResumed(PlaybackTimelineProgressIncident, PlaybackTimelineClockReading)
}

struct PlaybackTimelineProgressRecovery: Sendable {
    private struct HostWatchdogState: Sendable {
        var previous: PlaybackTimelineClockReading?
        var firstQualifying: PlaybackTimelineClockReading?
        var cause: PlaybackTimelineHostWatchdogCause?
        var consecutiveObservationCount = 0
    }

    private enum Phase: Sendable {
        case inactive
        case observing(
            run: PlaybackTimelineProgressRun,
            previousByLane: [PlaybackDeliveryLane: PlaybackTimelineClockReading],
            frozenByLane: [PlaybackDeliveryLane: PlaybackTimelineFrozenLane],
            hostWatchdog: HostWatchdogState
        )
        case claimed(PlaybackTimelineProgressIncident)
        case reanchorApplied(PlaybackTimelineProgressIncident)
        case notResumed(PlaybackTimelineProgressIncident)
    }

    private var phase = Phase.inactive
    private var nextGeneration: UInt64 = 0
    private var nextIncidentID: UInt64 = 0

    var currentRun: PlaybackTimelineProgressRun? {
        switch phase {
        case .inactive:
            nil
        case .observing(let run, _, _, _):
            run
        case .claimed(let incident),
             .reanchorApplied(let incident),
             .notResumed(let incident):
            incident.run
        }
    }

    mutating func activate(
        requestedRate: Float,
        applicationHostTime: CMTime,
        videoStreamEpoch: UInt64,
        audioStreamEpoch: UInt64
    ) -> PlaybackTimelineProgressRun {
        nextGeneration &+= 1
        let run = PlaybackTimelineProgressRun(
            generation: nextGeneration,
            videoStreamEpoch: videoStreamEpoch,
            audioStreamEpoch: audioStreamEpoch,
            requestedRate: requestedRate,
            applicationHostTime: applicationHostTime
        )
        phase = .observing(
            run: run,
            previousByLane: [:],
            frozenByLane: [:],
            hostWatchdog: HostWatchdogState()
        )
        return run
    }

    mutating func invalidate() {
        phase = .inactive
    }

    func matches(
        videoStreamEpoch: UInt64,
        audioStreamEpoch: UInt64,
        requestedRate: Float
    ) -> Bool {
        let run: PlaybackTimelineProgressRun
        switch phase {
        case .inactive:
            return false
        case .observing(let current, _, _, _):
            run = current
        case .claimed(let incident),
             .reanchorApplied(let incident),
             .notResumed(let incident):
            run = incident.run
        }
        return run.videoStreamEpoch == videoStreamEpoch
            && run.audioStreamEpoch == audioStreamEpoch
            && run.requestedRate == requestedRate
    }

    func matches(_ run: PlaybackTimelineProgressRun) -> Bool {
        switch phase {
        case .inactive:
            return false
        case .observing(let current, _, _, _):
            return current == run
        case .claimed(let incident),
             .reanchorApplied(let incident),
             .notResumed(let incident):
            return incident.run == run
        }
    }

    mutating func observeHostWatchdog(
        run: PlaybackTimelineProgressRun,
        reading: PlaybackTimelineClockReading
    ) -> PlaybackTimelineProgressDecision {
        switch phase {
        case .inactive, .claimed:
            return .none
        case .reanchorApplied(let incident), .notResumed(let incident):
            guard incident.run == run else { return .none }
            return observeAfterReanchor(incident: incident, reading: reading)
        case .observing(
            let currentRun,
            let previousByLane,
            let frozenByLane,
            var hostWatchdog
        ):
            guard currentRun == run else { return .none }
            guard run.requestedRate > 0,
                  clockReadingIsValid(reading),
                  CMTimeCompare(reading.ultimateSourceTime, run.applicationHostTime) >= 0 else {
                hostWatchdog = HostWatchdogState()
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }

            if let previous = hostWatchdog.previous,
               CMTimeCompare(reading.mediaTime, previous.mediaTime) != 0 {
                hostWatchdog = HostWatchdogState(previous: reading)
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }

            let timebaseIsStopped = reading.directRate == 0 || reading.effectiveRate == 0
            if timebaseIsStopped {
                if hostWatchdog.cause != .stoppedTimebase {
                    hostWatchdog.firstQualifying = nil
                    hostWatchdog.consecutiveObservationCount = 0
                }
                hostWatchdog.previous = reading
                hostWatchdog.cause = .stoppedTimebase
                hostWatchdog.firstQualifying = hostWatchdog.firstQualifying ?? reading
                hostWatchdog.consecutiveObservationCount += 1
            } else {
                guard reading.directRate > 0,
                      reading.effectiveRate > 0,
                      let previous = hostWatchdog.previous,
                      CMTimeCompare(reading.mediaTime, previous.mediaTime) == 0,
                      CMTimeCompare(
                        reading.ultimateSourceTime,
                        previous.ultimateSourceTime
                      ) > 0 else {
                    hostWatchdog = HostWatchdogState(previous: reading)
                    phase = .observing(
                        run: run,
                        previousByLane: previousByLane,
                        frozenByLane: frozenByLane,
                        hostWatchdog: hostWatchdog
                    )
                    return .none
                }
                if hostWatchdog.cause != .frozenMediaClock {
                    hostWatchdog.firstQualifying = previous
                    hostWatchdog.consecutiveObservationCount = 0
                }
                hostWatchdog.previous = reading
                hostWatchdog.cause = .frozenMediaClock
                hostWatchdog.firstQualifying = hostWatchdog.firstQualifying ?? previous
                hostWatchdog.consecutiveObservationCount += 1
            }

            guard hostWatchdog.consecutiveObservationCount == 3,
                  let cause = hostWatchdog.cause,
                  let first = hostWatchdog.firstQualifying else {
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }
            return claim(
                run: run,
                frozenMediaTime: reading.mediaTime,
                evidence: .hostWatchdog(PlaybackTimelineHostWatchdogEvidence(
                    cause: cause,
                    first: first,
                    detected: reading,
                    consecutiveObservationCount:
                        hostWatchdog.consecutiveObservationCount
                ))
            )
        }
    }

    mutating func observeBlockedLane(
        _ lane: PlaybackDeliveryLane,
        blockedPresentationTime: CMTime,
        reading: PlaybackTimelineClockReading,
        requiredLanes: Set<PlaybackDeliveryLane>
    ) -> PlaybackTimelineProgressDecision {
        switch phase {
        case .inactive, .claimed:
            return .none
        case .reanchorApplied(let incident), .notResumed(let incident):
            return observeAfterReanchor(incident: incident, reading: reading)
        case .observing(
            let run,
            var previousByLane,
            var frozenByLane,
            let hostWatchdog
        ):
            guard run.requestedRate > 0,
                  CMTimeCompare(reading.ultimateSourceTime, run.applicationHostTime) >= 0 else {
                previousByLane[lane] = reading
                frozenByLane.removeAll()
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }
            guard let previous = previousByLane[lane] else {
                previousByLane[lane] = reading
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }
            previousByLane[lane] = reading
            guard clockProvesFrozen(previous: previous, current: reading) else {
                frozenByLane.removeAll()
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }

            if frozenByLane.values.contains(where: {
                CMTimeCompare($0.detected.mediaTime, reading.mediaTime) != 0
            }) {
                frozenByLane.removeAll()
            }
            frozenByLane[lane] = PlaybackTimelineFrozenLane(
                lane: lane,
                blockedPresentationTime: blockedPresentationTime,
                previous: previous,
                detected: reading
            )
            guard !requiredLanes.isEmpty,
                  requiredLanes.isSubset(of: Set(frozenByLane.keys)) else {
                phase = .observing(
                    run: run,
                    previousByLane: previousByLane,
                    frozenByLane: frozenByLane,
                    hostWatchdog: hostWatchdog
                )
                return .none
            }

            return claim(
                run: run,
                frozenMediaTime: reading.mediaTime,
                evidence: .blockedLanes(frozenByLane)
            )
        }
    }

    mutating func observeProgress(
        _ reading: PlaybackTimelineClockReading
    ) -> PlaybackTimelineProgressDecision {
        switch phase {
        case .reanchorApplied(let incident), .notResumed(let incident):
            return observeAfterReanchor(incident: incident, reading: reading)
        case .observing(let run, _, _, _):
            phase = .observing(
                run: run,
                previousByLane: [:],
                frozenByLane: [:],
                hostWatchdog: HostWatchdogState()
            )
            return .none
        case .inactive, .claimed:
            return .none
        }
    }

    mutating func cancelClaim(_ incident: PlaybackTimelineProgressIncident) {
        guard case .claimed(let current) = phase,
              current.incidentID == incident.incidentID else { return }
        phase = .observing(
            run: current.run,
            previousByLane: [:],
            frozenByLane: [:],
            hostWatchdog: HostWatchdogState()
        )
    }

    mutating func didApplyReanchor(
        _ incident: PlaybackTimelineProgressIncident,
        at hostTime: CMTime
    ) -> PlaybackTimelineProgressIncident? {
        guard case .claimed(let current) = phase,
              current.incidentID == incident.incidentID else { return nil }
        var applied = current
        applied.reanchorHostTime = hostTime
        phase = .reanchorApplied(applied)
        return applied
    }

    private mutating func observeAfterReanchor(
        incident: PlaybackTimelineProgressIncident,
        reading: PlaybackTimelineClockReading
    ) -> PlaybackTimelineProgressDecision {
        if CMTimeCompare(reading.mediaTime, incident.frozenMediaTime) > 0 {
            phase = .observing(
                run: incident.run,
                previousByLane: [:],
                frozenByLane: [:],
                hostWatchdog: HostWatchdogState()
            )
            return .resumed(incident, reading)
        }
        guard case .reanchorApplied = phase,
              let reanchorHostTime = incident.reanchorHostTime,
              CMTimeCompare(reading.ultimateSourceTime, reanchorHostTime) > 0 else {
            return .none
        }
        phase = .notResumed(incident)
        return .notResumed(incident, reading)
    }

    private mutating func claim(
        run: PlaybackTimelineProgressRun,
        frozenMediaTime: CMTime,
        evidence: PlaybackTimelineProgressIncidentEvidence
    ) -> PlaybackTimelineProgressDecision {
        nextIncidentID &+= 1
        let incident = PlaybackTimelineProgressIncident(
            incidentID: nextIncidentID,
            run: run,
            frozenMediaTime: frozenMediaTime,
            evidence: evidence,
            reanchorHostTime: nil
        )
        phase = .claimed(incident)
        return .reanchor(incident)
    }

    private func clockReadingIsValid(_ reading: PlaybackTimelineClockReading) -> Bool {
        reading.mediaTime.isNumeric
            && reading.sourceTime.isNumeric
            && reading.ultimateSourceTime.isNumeric
            && reading.directRate.isFinite
            && reading.effectiveRate.isFinite
    }

    private func clockProvesFrozen(
        previous: PlaybackTimelineClockReading,
        current: PlaybackTimelineClockReading
    ) -> Bool {
        guard previous.mediaTime.isNumeric,
              current.mediaTime.isNumeric,
              previous.ultimateSourceTime.isNumeric,
              current.ultimateSourceTime.isNumeric,
              CMTimeCompare(current.mediaTime, previous.mediaTime) == 0,
              CMTimeCompare(current.ultimateSourceTime, previous.ultimateSourceTime) > 0 else {
            return false
        }
        let mediaTick = CMTime(
            value: 1,
            timescale: max(current.mediaTime.timescale, 1)
        )
        return CMTimeCompare(
            CMTimeSubtract(current.ultimateSourceTime, previous.ultimateSourceTime),
            mediaTick
        ) >= 0
    }
}
