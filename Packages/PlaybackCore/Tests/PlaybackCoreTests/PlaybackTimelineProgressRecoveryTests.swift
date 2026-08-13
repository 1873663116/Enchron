import CoreMedia
@testable import PlaybackCore
import Testing

@Suite struct PlaybackTimelineProgressRecoveryTests {
  @Test func frozenAudioAndVideoLanesClaimOneSharedReanchor() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 4,
      audioStreamEpoch: 7
    )
    let requiredLanes: Set<PlaybackDeliveryLane> = [.video, .audio]

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: requiredLanes
    ) == .none)
    #expect(recovery.observeBlockedLane(
      .audio,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: requiredLanes
    ) == .none)
    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 102),
      requiredLanes: requiredLanes
    ) == .none)

    let decision = recovery.observeBlockedLane(
      .audio,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 102),
      requiredLanes: requiredLanes
    )

    guard case .reanchor(let incident) = decision else {
      Issue.record("Expected the shared frozen timeline to request one reanchor")
      return
    }
    #expect(incident.run.videoStreamEpoch == 4)
    #expect(incident.run.audioStreamEpoch == 7)
    #expect(incident.frozenMediaTime == timelineTime(5))
    #expect(Set(incident.frozenLanes.keys) == requiredLanes)
  }

  @Test func laneObservationsCannotPairAcrossAudioAndVideo() {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: [.video, .audio]
    ) == .none)
    #expect(recovery.observeBlockedLane(
      .audio,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 102),
      requiredLanes: [.video, .audio]
    ) == .none)
  }

  @Test func progressingMediaTimeClearsFrozenEvidence() {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )

    _ = recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: [.video]
    )
    let moving = PlaybackTimelineClockReading(
      mediaTime: CMTime(value: 5_001, timescale: 1_000),
      sourceTime: timelineTime(2),
      ultimateSourceTime: timelineTime(102),
      directRate: 1,
      effectiveRate: 1
    )

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: moving,
      requiredLanes: [.video]
    ) == .none)
  }

  @Test func reanchorIsSingleFlightUntilProgressResumes() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )
    _ = recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: [.video]
    )
    let decision = recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 102),
      requiredLanes: [.video]
    )
    guard case .reanchor(let incident) = decision else {
      Issue.record("Expected a video-only frozen timeline to request a reanchor")
      return
    }
    let appliedIncident = recovery.didApplyReanchor(
      incident,
      at: timelineTime(103)
    )
    let applied = try #require(appliedIncident)

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 104),
      requiredLanes: [.video]
    ) == .notResumed(applied, frozenReading(host: 104)))
    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 105),
      requiredLanes: [.video]
    ) == .none)

    let resumed = PlaybackTimelineClockReading(
      mediaTime: timelineTime(6),
      sourceTime: timelineTime(3),
      ultimateSourceTime: timelineTime(106),
      directRate: 1,
      effectiveRate: 1
    )
    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(8),
      reading: resumed,
      requiredLanes: [.video]
    ) == .resumed(applied, resumed))
  }

  @Test func stoppedPlayingTimelineAtBoundedLeadClaimsOneSharedReanchor() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 4,
      audioStreamEpoch: 7
    )
    let requiredLanes: Set<PlaybackDeliveryLane> = [.video, .audio]

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: stoppedReading(host: 101),
      requiredLanes: requiredLanes
    ) == .none)
    #expect(recovery.observeBlockedLane(
      .audio,
      blockedPresentationTime: timelineTime(7),
      reading: stoppedReading(host: 101),
      requiredLanes: requiredLanes
    ) == .none)
    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: stoppedReading(host: 102),
      requiredLanes: requiredLanes
    ) == .none)

    let decision = recovery.observeBlockedLane(
      .audio,
      blockedPresentationTime: timelineTime(7),
      reading: stoppedReading(host: 102),
      requiredLanes: requiredLanes
    )

    guard case .reanchor(let incident) = decision else {
      Issue.record("Expected a stopped playing timeline to request one reanchor")
      return
    }
    #expect(incident.run.requestedRate == 1)
    #expect(incident.frozenMediaTime == timelineTime(5))
    #expect(Set(incident.frozenLanes.keys) == requiredLanes)
  }

  @Test func transportInvalidationRejectsAClaimedIncident() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    _ = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )
    _ = recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 101),
      requiredLanes: [.video]
    )
    let decision = recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: frozenReading(host: 102),
      requiredLanes: [.video]
    )
    guard case .reanchor(let incident) = decision else {
      Issue.record("Expected a claimed timeline incident")
      return
    }

    recovery.invalidate()

    #expect(recovery.didApplyReanchor(incident, at: timelineTime(103)) == nil)
    #expect(recovery.matches(
      videoStreamEpoch: 1,
      audioStreamEpoch: 1,
      requestedRate: 1
    ) == false)
  }

  @Test func periodicHeartbeatObservesAStoppedPlayingTimelineAndRequestsReanchor() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    let run = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 4,
      audioStreamEpoch: 7
    )

    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 101)
    ) == .none)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 102)
    ) == .none)
    let decision = recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 103)
    )

    guard case .reanchor(let incident) = decision else {
      Issue.record("Expected the periodic heartbeat to request a reanchor")
      return
    }
    guard case .hostWatchdog(let evidence) = incident.evidence else {
      Issue.record("Expected truthful host-watchdog evidence")
      return
    }
    #expect(evidence.cause == .stoppedTimebase)
    #expect(evidence.consecutiveObservationCount == 3)
  }

  @Test func lingeringDeliveryPrerollDoesNotDisablePlayingTimelineWatchdog() {
    #expect(timelineProgressHostWatchdogIsEligible(
      isClosed: false,
      isResetting: false,
      isCloseInProgress: false,
      deliveryPrerollIsPending: true,
      videoSampleDeliveryIsSuspended: false,
      lifecycleIsPlaying: true,
      timelineStartRate: 1,
      hasActiveOperation: false
    ))
  }

  @Test func mediaProgressResetsHostWatchdogEvidence() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    let run = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )

    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 101)
    ) == .none)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 102)
    ) == .none)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: progressingReading(media: 6, host: 103)
    ) == .none)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(media: 6, host: 104)
    ) == .none)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(media: 6, host: 105)
    ) == .none)
    guard case .reanchor(let incident) = recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(media: 6, host: 106)
    ) else {
      Issue.record("Expected three new stopped observations after media progress")
      return
    }
    guard case .hostWatchdog(let evidence) = incident.evidence else {
      Issue.record("Expected host-watchdog evidence after the reset")
      return
    }
    #expect(evidence.first.ultimateSourceTime == timelineTime(104))
    #expect(evidence.consecutiveObservationCount == 3)
  }

  @Test func watchdogAndLanePathsShareOneClaim() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    let run = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )

    _ = recovery.observeHostWatchdog(run: run, reading: stoppedReading(host: 101))
    _ = recovery.observeHostWatchdog(run: run, reading: stoppedReading(host: 102))
    guard case .reanchor(let watchdogIncident) = recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 103)
    ) else {
      Issue.record("Expected the watchdog to own the shared claim")
      return
    }

    #expect(recovery.observeBlockedLane(
      .video,
      blockedPresentationTime: timelineTime(7),
      reading: stoppedReading(host: 104),
      requiredLanes: [.video]
    ) == .none)
    #expect(watchdogIncident.incidentID == 1)
    #expect(timelineProgressDecisionIsEligible(
      incident: watchdogIncident,
      blockedLaneIsEligible: true,
      hostWatchdogIsEligible: false
    ) == false)
  }

  @Test func transportInvalidationRejectsAWatchdogClaimAndStaleTick() throws {
    var recovery = PlaybackTimelineProgressRecovery()
    let run = recovery.activate(
      requestedRate: 1,
      applicationHostTime: timelineTime(100),
      videoStreamEpoch: 1,
      audioStreamEpoch: 1
    )
    _ = recovery.observeHostWatchdog(run: run, reading: stoppedReading(host: 101))
    _ = recovery.observeHostWatchdog(run: run, reading: stoppedReading(host: 102))
    guard case .reanchor(let incident) = recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 103)
    ) else {
      Issue.record("Expected a claimed watchdog incident")
      return
    }

    recovery.invalidate()

    #expect(recovery.matches(run) == false)
    #expect(recovery.didApplyReanchor(incident, at: timelineTime(104)) == nil)
    #expect(recovery.observeHostWatchdog(
      run: run,
      reading: stoppedReading(host: 105)
    ) == .none)
  }
}

private func timelineTime(_ seconds: Int64) -> CMTime {
  CMTime(value: seconds * 1_000, timescale: 1_000)
}

private func frozenReading(host: Int64) -> PlaybackTimelineClockReading {
  PlaybackTimelineClockReading(
    mediaTime: timelineTime(5),
    sourceTime: timelineTime(2),
    ultimateSourceTime: timelineTime(host),
    directRate: 1,
    effectiveRate: 1
  )
}

private func stoppedReading(media: Int64 = 5, host: Int64) -> PlaybackTimelineClockReading {
  PlaybackTimelineClockReading(
    mediaTime: timelineTime(media),
    sourceTime: timelineTime(2),
    ultimateSourceTime: timelineTime(host),
    directRate: 0,
    effectiveRate: 0
  )
}

private func progressingReading(media: Int64, host: Int64) -> PlaybackTimelineClockReading {
  PlaybackTimelineClockReading(
    mediaTime: timelineTime(media),
    sourceTime: timelineTime(2),
    ultimateSourceTime: timelineTime(host),
    directRate: 1,
    effectiveRate: 1
  )
}
