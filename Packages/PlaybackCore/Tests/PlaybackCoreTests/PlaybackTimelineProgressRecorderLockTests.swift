import CoreMedia
import Foundation
@testable import PlaybackCore
import Testing

@Test func deliveryContinuityInvalidationPublishesAfterReleasingRecoveryLock() throws {
    let session = SampleBufferPlaybackSession(
        traceID: "timeline-progress-recorder-lock-\(UUID().uuidString)"
    )
    let recorder = PlaybackDebugRecorder(
        session: session,
        platform: "macOS"
    )
    defer {
        recorder.stop()
        session.close()
        try? FileManager.default.removeItem(at: recorder.directoryURL)
    }

    let run = PlaybackTimelineProgressRun(
        generation: 1,
        videoStreamEpoch: 1,
        audioStreamEpoch: 1,
        requestedRate: 1,
        applicationHostTime: CMTime(seconds: 100, preferredTimescale: 600)
    )
    let reading = PlaybackTimelineClockReading(
        mediaTime: CMTime(seconds: 5, preferredTimescale: 600),
        sourceTime: CMTime(seconds: 3, preferredTimescale: 600),
        ultimateSourceTime: CMTime(seconds: 103, preferredTimescale: 600),
        directRate: 1,
        effectiveRate: 1
    )
    let incident = PlaybackTimelineProgressIncident(
        incidentID: 1,
        run: run,
        frozenMediaTime: reading.mediaTime,
        evidence: .hostWatchdog(PlaybackTimelineHostWatchdogEvidence(
            cause: .frozenMediaClock,
            first: reading,
            detected: reading,
            consecutiveObservationCount: 3
        )),
        reanchorHostTime: nil
    )
    session.timelineProgressRecoveryLock.withLock {
        session.deliveryContinuity.activate(run)
        let starvation = session.deliveryContinuity.observeIncident(
            incident,
            mediaState: PlaybackDeliveryContinuityMediaState(
                requiredLanes: [.video],
                providerEndedLanes: [],
                presentationEndByLane: [.video: reading.mediaTime]
            )
        )
        #expect(starvation?.phase == .starved)
    }

    let lockProbe = TimelineProgressRecorderLockProbe()
    let observerID = session.debugStore.addEventObserver { event in
        guard event.kind == "deliveryContinuity.inactive" else { return }
        let acquiredRecoveryLock = session.timelineProgressRecoveryLock.try()
        if acquiredRecoveryLock {
            session.timelineProgressRecoveryLock.unlock()
        }
        lockProbe.record(
            sequenceNumber: event.sequenceNumber,
            acquiredRecoveryLock: acquiredRecoveryLock
        )
    }
    defer { session.debugStore.removeEventObserver(observerID) }

    session.invalidateTimelineProgressRecovery()

    let observation = try #require(lockProbe.observation)
    #expect(observation.acquiredRecoveryLock)
    let snapshotDecoder = JSONDecoder()
    snapshotDecoder.dateDecodingStrategy = .iso8601
    let persistedSnapshot = try snapshotDecoder.decode(
        PlaybackDebugSnapshotV1.self,
        from: Data(contentsOf: recorder.snapshotURL)
    )
    #expect(persistedSnapshot.deliveryContinuity?.phase == .inactive)
    let persistedEvents = try String(contentsOf: recorder.eventsURL, encoding: .utf8)
    let eventDecoder = JSONDecoder()
    eventDecoder.dateDecodingStrategy = .iso8601
    let inactiveEvent = try #require(
        persistedEvents
            .split(separator: "\n")
            .compactMap {
                try? eventDecoder.decode(
                    PlaybackDebugEvent.self,
                    from: Data($0.utf8)
                )
            }
            .first { $0.kind == "deliveryContinuity.inactive" }
    )
    #expect(inactiveEvent.sequenceNumber == observation.sequenceNumber)
}

private final class TimelineProgressRecorderLockProbe: @unchecked Sendable {
    struct Observation: Sendable {
        var sequenceNumber: UInt64
        var acquiredRecoveryLock: Bool
    }

    private let lock = NSLock()
    private var storedObservation: Observation?

    var observation: Observation? {
        lock.withLock { storedObservation }
    }

    func record(sequenceNumber: UInt64, acquiredRecoveryLock: Bool) {
        lock.withLock {
            storedObservation = Observation(
                sequenceNumber: sequenceNumber,
                acquiredRecoveryLock: acquiredRecoveryLock
            )
        }
    }
}
