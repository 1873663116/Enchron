import AVFoundation
import Foundation
import Testing

@testable import PlaybackCore

@Suite struct PlaybackActivationReapplyVerificationTests {
  @Test func activationReapplyVerificationIsInertWhenDisabled() throws {
    #expect(
      PlaybackActivationReapplyVerificationConfiguration(environment: [:]).isEnabled
        == false
    )
    #if DEBUG
      #expect(
        PlaybackActivationReapplyVerificationConfiguration(
          environment: [PlaybackActivationReapplyVerificationConfiguration.environmentKey: "1"]
        ).isEnabled
      )
    #endif
    let harness = ActivationReapplyHarness()
    let session = makeActivationReapplySession(
      configuration: .disabled,
      harness: harness
    )
    defer { session.close() }

    let sequence = try #require(
      session.activationObservation.beginActivation(requestedRate: 1, anchorTime: .zero)
    )
    session.activationObservation.rateApplicationReturned(sequence: sequence)
    session.activationObservation.fireReapplyVerificationTimerForTesting()

    #expect(harness.factReadCount.withLock { $0 } == 0)
    #expect(harness.queuedCount == 0)
    #expect(harness.applied.withLock { $0 }.isEmpty)
    #expect(session.debugSnapshot().activationReapplyVerification == nil)
  }

  @Test func activationReapplyVerificationWaitsForSufficientMediaAndStopsWhenRateIsActive() throws {
    let harness = ActivationReapplyHarness(
      facts: .init(
        videoHasSufficientMedia: false,
        audioHasSufficientMedia: false,
        directRate: 0,
        effectiveRate: 0
      )
    )
    let session = makeActivationReapplySession(harness: harness, hasAudio: true)
    defer { session.close() }
    let sequence = try beginActivationReapplyVerification(in: session)

    session.activationObservation.fireReapplyVerificationTimerForTesting()
    #expect(harness.queuedCount == 0)
    #expect(
      session.debugSnapshot().activationReapplyVerification?.outcome
        == .waitingForSufficientMedia
    )

    harness.facts.withLock {
      $0.videoHasSufficientMedia = true
      $0.audioHasSufficientMedia = true
      $0.directRate = 1
      $0.effectiveRate = 1
    }
    session.activationObservation.fireReapplyVerificationTimerForTesting()

    #expect(harness.queuedCount == 0)
    #expect(harness.applied.withLock { $0 }.isEmpty)
    let record = try #require(session.debugSnapshot().activationReapplyVerification)
    #expect(record.activationSequence == sequence)
    #expect(record.attemptCount == 0)
    #expect(record.outcome == .rateAlreadyActive)
  }

  @Test func activationReapplyVerificationClaimsExactlyOnceAndPreservesAnchor() throws {
    let harness = ActivationReapplyHarness(
      facts: .init(
        videoHasSufficientMedia: true,
        audioHasSufficientMedia: false,
        directRate: 0,
        effectiveRate: 0
      )
    )
    let session = makeActivationReapplySession(harness: harness, hasAudio: false)
    defer { session.close() }
    let anchor = CMTime(
      value: 12_345,
      timescale: 600,
      flags: [.valid, .hasBeenRounded],
      epoch: 7
    )
    let rateActivatedEvents = VerificationLockedBox(0)
    let observerID = session.debugStore.addEventObserver { event in
      if event.kind == "audioRenderer.rateActivated" {
        rateActivatedEvents.withLock { $0 += 1 }
      }
    }
    defer { session.debugStore.removeEventObserver(observerID) }
    let sequence = try beginActivationReapplyVerification(
      in: session,
      requestedRate: 1.25,
      anchorTime: anchor
    )

    session.activationObservation.fireReapplyVerificationTimerForTesting()
    session.activationObservation.fireReapplyVerificationTimerForTesting()
    #expect(harness.queuedCount == 1)
    harness.runAllQueued()
    session.activationObservation.fireReapplyVerificationTimerForTesting()

    let applied = harness.applied.withLock { $0 }
    #expect(applied == [.init(rate: 1.25, anchorTime: anchor)])
    #expect(rateActivatedEvents.withLock { $0 } == 0)
    let record = try #require(session.debugSnapshot().activationReapplyVerification)
    #expect(record.activationSequence == sequence)
    #expect(record.videoStreamEpoch == session.streamEpoch)
    #expect(record.audioStreamEpoch == session.audioStreamEpoch)
    #expect(record.requestedRate == 1.25)
    #expect(record.anchorValue == anchor.value)
    #expect(record.anchorTimescale == anchor.timescale)
    #expect(record.anchorFlags == anchor.flags.rawValue)
    #expect(record.anchorEpoch == anchor.epoch)
    #expect(record.audioRequired == false)
    #expect(record.videoHasSufficientMedia)
    #expect(record.audioHasSufficientMedia)
    #expect(record.directRate == 0)
    #expect(record.effectiveRate == 0)
    #expect(record.attemptCount == 1)
    #expect(record.outcome == .reapplied)
  }

  @Test func queuedActivationReapplyVerificationRejectsEveryStaleCause() throws {
    let mutations:
      [(PlaybackActivationReapplyVerificationOutcome, (SampleBufferPlaybackSession) -> Void)] = [
        (
          .invalidatedBySeek,
          { $0.activationObservation.invalidateReapplyVerification(outcome: .invalidatedBySeek) }
        ),
        (
          .invalidatedByPause,
          { $0.activationObservation.invalidateReapplyVerification(outcome: .invalidatedByPause) }
        ),
        (
          .invalidatedByRateChange,
          {
            $0.activationObservation.invalidateReapplyVerification(
              outcome: .invalidatedByRateChange)
          }
        ),
        (
          .invalidatedByClose,
          { $0.activationObservation.invalidateReapplyVerification(outcome: .invalidatedByClose) }
        ),
        (.invalidatedByStop, { $0.activationObservation.stop() }),
        (
          .invalidatedByNewActivation,
          {
            _ = $0.activationObservation.beginActivation(requestedRate: 1, anchorTime: .zero)
          }
        ),
        (.invalidatedByEpochChange, { $0.streamEpoch &+= 1 }),
        (.invalidatedByEpochChange, { $0.audioStreamEpoch &+= 1 }),
      ]

    for (expectedOutcome, mutate) in mutations {
      let harness = ActivationReapplyHarness()
      let session = makeActivationReapplySession(harness: harness)
      _ = try beginActivationReapplyVerification(in: session)
      session.activationObservation.fireReapplyVerificationTimerForTesting()
      #expect(harness.queuedCount == 1)

      mutate(session)
      harness.runAllQueued()

      #expect(harness.applied.withLock { $0 }.isEmpty)
      let outcome = session.debugSnapshot().activationReapplyVerification?.outcome
      #expect(outcome == expectedOutcome)
      session.close()
    }
  }

  @Test func queuedActivationReapplyVerificationRechecksLifecycleDesiredRateAndReset() throws {
    let mutations: [(SampleBufferPlaybackSession) -> Void] = [
      { $0.mediaSessionRecord?.lifecycle = .paused },
      { $0.timelineStartRate = 2 },
      { $0.isResetting = true },
      { session in session.closeLock.withLock { session.isClosing = true } },
    ]

    for mutate in mutations {
      let harness = ActivationReapplyHarness()
      let session = makeActivationReapplySession(harness: harness)
      _ = try beginActivationReapplyVerification(in: session)
      session.activationObservation.fireReapplyVerificationTimerForTesting()
      mutate(session)
      harness.runAllQueued()

      #expect(harness.applied.withLock { $0 }.isEmpty)
      #expect(
        session.debugSnapshot().activationReapplyVerification?.outcome
          == .staleBeforeReapply
      )
      session.closeLock.withLock { session.isClosing = false }
      session.close()
    }
  }

  @Test func activationReapplyVerificationTimesOutWithoutAttempt() throws {
    let harness = ActivationReapplyHarness()
    let session = makeActivationReapplySession(
      configuration: .init(
        isEnabled: true,
        pollIntervalMilliseconds: 10,
        timeoutMilliseconds: 100
      ),
      harness: harness
    )
    defer { session.close() }
    _ = try beginActivationReapplyVerification(in: session)
    harness.uptimeNanoseconds.withLock { $0 = 100_000_000 }

    session.activationObservation.fireReapplyVerificationTimerForTesting()

    let record = try #require(session.debugSnapshot().activationReapplyVerification)
    #expect(record.attemptCount == 0)
    #expect(record.outcome == .timedOut)
    #expect(harness.queuedCount == 0)
    #expect(harness.applied.withLock { $0 }.isEmpty)
  }
}

private func beginActivationReapplyVerification(
  in session: SampleBufferPlaybackSession,
  requestedRate: Float = 1,
  anchorTime: CMTime = .zero
) throws -> UInt64 {
  session.timelineStartRate = requestedRate
  let sequence = try #require(
    session.activationObservation.beginActivation(
      requestedRate: requestedRate,
      anchorTime: anchorTime
    )
  )
  session.activationObservation.rateApplicationReturned(sequence: sequence)
  return sequence
}

private func makeActivationReapplySession(
  configuration: PlaybackActivationReapplyVerificationConfiguration = .init(
    isEnabled: true
  ),
  harness: ActivationReapplyHarness,
  hasAudio: Bool = true
) -> SampleBufferPlaybackSession {
  let session = SampleBufferPlaybackSession(
    traceID: "activation-reapply-\(UUID().uuidString)",
    provider: ReapplyNullVideoProvider(),
    audioProvider: NoAudioSampleProvider(),
    subtitleProvider: NoSubtitleProvider(),
    rendererSink: ReapplyNullVideoSink(),
    audioRendererSink: ReapplyNullAudioSink(),
    activationReapplyVerificationConfiguration: configuration,
    activationReapplyVerificationHooks: harness.hooks
  )
  session.hasAudio = hasAudio
  session.timelineStartRate = 1
  session.mediaSessionRecord = MediaSessionRecord(
    mediaSessionID: session.traceID,
    source: MediaSourceRecord(
      locator: URL(fileURLWithPath: "/fixtures/activation-reapply.mov"),
      provenance: "test",
      privacySafeSummary: "activation-reapply.mov",
      accessRequirement: "none"
    ),
    initialTimeSeconds: 0,
    startsPaused: false,
    lifecycle: .playing
  )
  return session
}

private final class ActivationReapplyHarness: @unchecked Sendable {
  struct AppliedRate: Equatable, @unchecked Sendable {
    var rate: Float
    var anchorTime: CMTime
  }

  let facts: VerificationLockedBox<PlaybackActivationReapplyVerificationFacts>
  let uptimeNanoseconds = VerificationLockedBox<UInt64>(0)
  let factReadCount = VerificationLockedBox(0)
  let applied = VerificationLockedBox<[AppliedRate]>([])
  private let queued = VerificationLockedBox<[@Sendable () -> Void]>([])

  init(
    facts: PlaybackActivationReapplyVerificationFacts = .init(
      videoHasSufficientMedia: true,
      audioHasSufficientMedia: true,
      directRate: 0,
      effectiveRate: 0
    )
  ) {
    self.facts = VerificationLockedBox(facts)
  }

  var queuedCount: Int { queued.withLock { $0.count } }

  var hooks: PlaybackActivationReapplyVerificationHooks {
    var hooks = PlaybackActivationReapplyVerificationHooks()
    hooks.automaticallySchedulesTimer = false
    hooks.uptimeNanoseconds = { [self] in uptimeNanoseconds.withLock { $0 } }
    hooks.readFacts = { [self] _ in
      factReadCount.withLock { $0 += 1 }
      return facts.withLock { $0 }
    }
    hooks.enqueueOnDeliveryQueue = { [self] _, operation in
      queued.withLock { $0.append(operation) }
    }
    hooks.reapplyRate = { [self] _, rate, anchorTime in
      applied.withLock { $0.append(.init(rate: rate, anchorTime: anchorTime)) }
    }
    return hooks
  }

  func runAllQueued() {
    let operations = queued.withLock { queued -> [@Sendable () -> Void] in
      defer { queued.removeAll() }
      return queued
    }
    operations.forEach { $0() }
  }
}

private final class VerificationLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try lock.withLock { try body(&value) }
  }
}

private final class ReapplyNullVideoProvider: VideoSampleProvider {
  var info = VideoSampleProviderInfo(providerKind: "ReapplyNull")
  func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {}
  func start() throws {}
  func nextEvent() async throws -> VideoSampleProviderEvent { .end }
  func cancel() {}
}

private final class ReapplyNullVideoSink: RendererInputSink {
  func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome {
    .accepted
  }
  func enqueue(_ sample: RendererInputSample) async throws -> RendererEnqueueOutcome {
    .accepted
  }
  func flush(removingDisplayedImage: Bool) async {}
}

private final class ReapplyNullAudioSink: AudioRendererInputSink {
  func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome {
    .accepted
  }
  func enqueue(_ sample: RendererInputSample) async throws -> RendererEnqueueOutcome {
    .accepted
  }
  func flush() {}
}
