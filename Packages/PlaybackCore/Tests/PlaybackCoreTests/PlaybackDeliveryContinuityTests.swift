import CoreMedia
import Foundation
@testable import PlaybackCore
import Testing

@Suite struct PlaybackDeliveryContinuityTests {
  @Test func exhaustedRequiredMediaAndStoppedTimelinePublishStarvation() throws {
    let run = playbackDeliveryRun(generation: 4)
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)

    let observation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    )

    let starved = try #require(observation)
    #expect(starved.phase == .starved)
    #expect(starved.evidence?.requiredLanes == ["audio", "video"])
    #expect(starved.evidence?.rateApplicationGeneration == 4)
    #expect(starved.evidence?.frozenMediaTimeSeconds == 5)
  }

  @Test func positiveBufferedMediaAbsorbsAReconnectWithoutSignal() {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)

    let observation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(videoEnd: 8, audioEnd: 8)
    )

    #expect(observation == nil)
    #expect(continuity.isStarved == false)
  }

  @Test func recoveryRequiresNewDeliveryAndTimelineAdvancement() throws {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)
    let starved = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    )
    _ = try #require(starved)

    #expect(continuity.observeProgress(
      run: run,
      reading: playbackDeliveryReading(media: 6),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    ) == nil)
    #expect(continuity.observeProgress(
      run: run,
      reading: playbackDeliveryReading(media: 5),
      mediaState: playbackDeliveryMediaState(videoEnd: 8, audioEnd: 8)
    ) == nil)

    let recovery = continuity.observeProgress(
      run: run,
      reading: playbackDeliveryReading(media: 6),
      mediaState: playbackDeliveryMediaState(videoEnd: 8, audioEnd: 8)
    )

    #expect(recovery?.phase == .recovered)
    #expect(recovery?.evidence?.recoveredMediaTimeSeconds == 6)
    #expect(recovery?.evidence?.recoveredPresentationEndSeconds == [
      "audio": 8,
      "video": 8,
    ])
  }

  @Test func pauseInvalidationClearsStarvationAndRejectsOldRecovery() throws {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)
    let starvation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    )
    _ = try #require(starvation)

    #expect(continuity.invalidate()?.phase == .inactive)
    #expect(continuity.observeProgress(
      run: run,
      reading: playbackDeliveryReading(media: 6),
      mediaState: playbackDeliveryMediaState(videoEnd: 8, audioEnd: 8)
    ) == nil)
  }

  @Test func replacementRunRejectsStaleIncidentAndRecovery() throws {
    let staleRun = playbackDeliveryRun(generation: 1)
    let replacementRun = playbackDeliveryRun(generation: 2)
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(staleRun)
    continuity.activate(replacementRun)

    #expect(continuity.observeIncident(
      playbackDeliveryIncident(run: staleRun),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    ) == nil)
    let replacementStarvation = continuity.observeIncident(
      playbackDeliveryIncident(run: replacementRun),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    )
    _ = try #require(replacementStarvation)
    #expect(continuity.observeProgress(
      run: staleRun,
      reading: playbackDeliveryReading(media: 6),
      mediaState: playbackDeliveryMediaState(videoEnd: 8, audioEnd: 8)
    ) == nil)
    #expect(continuity.isStarved)
  }

  @Test func naturalProviderEndIsNotStarvation() {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)

    let observation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(
        videoEnd: 5,
        audioEnd: 5,
        providerEndedLanes: [.video, .audio]
      )
    )

    #expect(observation == nil)
  }

  @Test func remainingAudioCanStarveAndRecoverAfterVideoProviderEnds() throws {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)

    let observation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(
        videoEnd: 5,
        audioEnd: 5,
        providerEndedLanes: [.video]
      )
    )

    let starved = try #require(observation)
    #expect(starved.phase == .starved)
    #expect(starved.evidence?.requiredLanes == ["audio"])
    #expect(starved.evidence?.exhaustedPresentationEndSeconds == ["audio": 5])

    let recovery = continuity.observeProgress(
      run: run,
      reading: playbackDeliveryReading(media: 6),
      mediaState: playbackDeliveryMediaState(
        videoEnd: 5,
        audioEnd: 8,
        providerEndedLanes: [.video]
      )
    )
    #expect(recovery?.phase == .recovered)
    #expect(recovery?.evidence?.recoveredPresentationEndSeconds == ["audio": 8])
  }

  @Test func deliveryContinuitySurvivesDebugSnapshotCoding() throws {
    let run = playbackDeliveryRun()
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(run)
    let emittedObservation = continuity.observeIncident(
      playbackDeliveryIncident(run: run),
      mediaState: playbackDeliveryMediaState(videoEnd: 5, audioEnd: 5)
    )
    let observation = try #require(emittedObservation)
    var snapshot = PlaybackDebugSnapshotV1()
    snapshot.deliveryContinuity = observation

    let decoded = try JSONDecoder().decode(
      PlaybackDebugSnapshotV1.self,
      from: JSONEncoder().encode(snapshot)
    )

    #expect(decoded.deliveryContinuity == observation)
  }
}

private func playbackDeliveryRun(
  generation: UInt64 = 1
) -> PlaybackTimelineProgressRun {
  PlaybackTimelineProgressRun(
    generation: generation,
    videoStreamEpoch: generation,
    audioStreamEpoch: generation,
    requestedRate: 1,
    applicationHostTime: CMTime(seconds: 100, preferredTimescale: 600)
  )
}

private func playbackDeliveryIncident(
  run: PlaybackTimelineProgressRun
) -> PlaybackTimelineProgressIncident {
  let first = playbackDeliveryReading(media: 5, host: 101)
  let detected = playbackDeliveryReading(media: 5, host: 103)
  return PlaybackTimelineProgressIncident(
    incidentID: run.generation,
    run: run,
    frozenMediaTime: CMTime(seconds: 5, preferredTimescale: 600),
    evidence: .hostWatchdog(PlaybackTimelineHostWatchdogEvidence(
      cause: .frozenMediaClock,
      first: first,
      detected: detected,
      consecutiveObservationCount: 3
    )),
    reanchorHostTime: CMTime(seconds: 104, preferredTimescale: 600)
  )
}

private func playbackDeliveryMediaState(
  videoEnd: Double,
  audioEnd: Double,
  providerEndedLanes: Set<PlaybackDeliveryLane> = []
) -> PlaybackDeliveryContinuityMediaState {
  PlaybackDeliveryContinuityMediaState(
    requiredLanes: [.video, .audio],
    providerEndedLanes: providerEndedLanes,
    presentationEndByLane: [
      .video: CMTime(seconds: videoEnd, preferredTimescale: 600),
      .audio: CMTime(seconds: audioEnd, preferredTimescale: 600),
    ]
  )
}

private func playbackDeliveryReading(
  media: Double,
  host: Double = 105
) -> PlaybackTimelineClockReading {
  PlaybackTimelineClockReading(
    mediaTime: CMTime(seconds: media, preferredTimescale: 600),
    sourceTime: CMTime(seconds: host - 100, preferredTimescale: 600),
    ultimateSourceTime: CMTime(seconds: host, preferredTimescale: 600),
    directRate: 1,
    effectiveRate: 1
  )
}
