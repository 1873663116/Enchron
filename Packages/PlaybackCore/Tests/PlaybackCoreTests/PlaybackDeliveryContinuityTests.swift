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

  @Test func deliveryLagRecoveryPublishesStarvationUntilTheTimelineChanges() throws {
    var continuity = PlaybackDeliveryContinuity()
    continuity.activate(playbackDeliveryRun(generation: 6))

    let observation = continuity.observeDeliveryLag(
      frozenMediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaState: playbackDeliveryMediaState(videoEnd: 14.6, audioEnd: 15.1),
      rateApplicationGeneration: 6,
      videoStreamEpoch: 2,
      audioStreamEpoch: 3,
      requestedRate: 1
    )

    let starved = try #require(observation)
    #expect(starved.phase == .starved)
    #expect(starved.evidence?.detectionSource == .deliveryLag)
    #expect(starved.evidence?.requiredLanes == ["audio", "video"])
    #expect(starved.evidence?.frozenMediaTimeSeconds == 15.2)
    #expect(starved.evidence?.exhaustedPresentationEndSeconds["video"] == 14.6)
    #expect(starved.evidence?.rateApplicationGeneration == 6)
    #expect(continuity.isStarved)

    let repeated = continuity.observeDeliveryLag(
      frozenMediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaState: playbackDeliveryMediaState(videoEnd: 14.6, audioEnd: 15.1),
      rateApplicationGeneration: 6,
      videoStreamEpoch: 2,
      audioStreamEpoch: 3,
      requestedRate: 1
    )
    #expect(repeated == nil)

    let clearedObservation = continuity.invalidate()
    let cleared = try #require(clearedObservation)
    #expect(cleared.phase == .inactive)
    #expect(continuity.isStarved == false)
    #expect(continuity.invalidate() == nil)
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

  @Test func starvationTriggerFiresOnVideoLaneWhenTheClockRunsPastDelivery() throws {
    let trigger = playbackDeliveryMediaState(
      videoEnd: 14.6,
      audioEnd: 20
    ).starvationTrigger(
      mediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaKindIsAudioOnly: false,
      triggerSeconds: 0.5
    )

    let observed = try #require(trigger)
    #expect(observed.lane == .video)
    #expect(observed.presentationEnd.seconds == 14.6)
  }

  @Test func starvationTriggerStaysQuietWhileDeliveryKeepsUp() {
    #expect(playbackDeliveryMediaState(
      videoEnd: 14.6,
      audioEnd: 20
    ).starvationTrigger(
      mediaTime: CMTime(seconds: 14.9, preferredTimescale: 600),
      mediaKindIsAudioOnly: false,
      triggerSeconds: 0.5
    ) == nil)
    #expect(playbackDeliveryMediaState(
      videoEnd: 20,
      audioEnd: 14.0
    ).starvationTrigger(
      mediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaKindIsAudioOnly: false,
      triggerSeconds: 0.5
    ) == nil)
  }

  @Test func starvationTriggerIgnoresLanesWhoseProviderEnded() throws {
    let trigger = playbackDeliveryMediaState(
      videoEnd: 5,
      audioEnd: 14.0,
      providerEndedLanes: [.video]
    ).starvationTrigger(
      mediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaKindIsAudioOnly: false,
      triggerSeconds: 0.5
    )

    let observed = try #require(trigger)
    #expect(observed.lane == .audio)
    #expect(observed.presentationEnd.seconds == 14.0)
  }

  @Test func starvationTriggerUsesAudioForAudioOnlyMedia() throws {
    let mediaState = PlaybackDeliveryContinuityMediaState(
      requiredLanes: [.audio],
      providerEndedLanes: [],
      presentationEndByLane: [
        .audio: CMTime(seconds: 14.0, preferredTimescale: 600),
      ]
    )

    let trigger = try #require(mediaState.starvationTrigger(
      mediaTime: CMTime(seconds: 15.2, preferredTimescale: 600),
      mediaKindIsAudioOnly: true,
      triggerSeconds: 0.5
    ))
    #expect(trigger.lane == .audio)
  }

  @Test func starvationTriggerStaysQuietWhenEveryProviderEnded() {
    #expect(playbackDeliveryMediaState(
      videoEnd: 5,
      audioEnd: 5,
      providerEndedLanes: [.video, .audio]
    ).starvationTrigger(
      mediaTime: CMTime(seconds: 30, preferredTimescale: 600),
      mediaKindIsAudioOnly: false,
      triggerSeconds: 0.5
    ) == nil)
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
