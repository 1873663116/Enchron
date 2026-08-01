import Foundation
import AVFoundation
import CoreVideo
import Testing
@testable import PlaybackCore

@Test func ffmpegSourceLocatorPreservesRemoteSchemeHostAndCredentials() throws {
    let remote = try #require(URL(string: "http://user:pass@example.test:5244/dav/video.mkv"))
    #expect(
        FFmpegSourceLocator.argument(for: remote)
            == "http://user:pass@example.test:5244/dav/video.mkv"
    )

    let local = URL(fileURLWithPath: "/tmp/video.mkv")
    #expect(FFmpegSourceLocator.argument(for: local) == "/tmp/video.mkv")
}

@MainActor
@Test func productOpenUsesTheDemuxProviderForURLSources() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: FakeRendererInputSink()
        )
    }

    let localSession = try await controller.open(URL(fileURLWithPath: "/fixtures/movie.mkv"))

    #expect(localSession.debugSnapshot().providerOpen?.providerKind == "Fake")
    await controller.closeAndWait()

    let remoteURL = try #require(URL(string: "https://example.test/media/movie.mkv"))
    let remoteSession = try await controller.open(remoteURL)

    #expect(remoteSession.debugSnapshot().providerOpen?.providerKind == "Fake")
    await controller.closeAndWait()
}

@MainActor
@Test func productOpenKeepsSuppliedAVAssetsOnTheFFmpegProvider() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: FakeRendererInputSink()
        )
    }
    let url = URL(fileURLWithPath: "/fixtures/photos-video.mov")

    let session = try await controller.open(url, asset: PlaybackAsset(AVURLAsset(url: url)))

    #expect(session.debugSnapshot().providerOpen?.providerKind == "Fake")
    await controller.closeAndWait()
}

@Test func projectionFieldsRemainBackwardCompatibleWithDebugSnapshotV1() throws {
    let current = VideoFormatSignalingSummary(provenance: "test")
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "projectionKind")
    object.removeValue(forKey: "viewPackingKind")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
        VideoFormatSignalingSummary.self,
        from: legacy
    )
    #expect(decoded.projectionKind.availability == .notExposed)
    #expect(decoded.viewPackingKind.availability == .notExposed)
}

@Test func debugSnapshotV1DecodesBeforeAudioTrackCatalogWasAdded() throws {
    let current = PlaybackDebugSnapshotV1()
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "availableAudioTracks")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
        PlaybackDebugSnapshotV1.self,
        from: legacy
    )
    #expect(decoded.availableAudioTracks.isEmpty)
}

@Test func audioRendererStateDecodesBeforeGraphIdentitiesWereAdded() throws {
    let current = AudioRendererStateRecord(
        mediaSessionID: "session-1",
        graphID: "graph-1",
        rendererIdentity: "audio-renderer-1",
        videoRendererIdentity: "video-renderer-1",
        synchronizerIdentity: "synchronizer-1",
        streamEpoch: 2,
        enqueuedSampleBufferCount: 3,
        enqueuedAudioFrameCount: 4,
        volume: 0.5,
        muted: false,
        error: nil
    )
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "graphID")
    object.removeValue(forKey: "videoRendererIdentity")
    object.removeValue(forKey: "synchronizerIdentity")
    object.removeValue(forKey: "status")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
        AudioRendererStateRecord.self,
        from: legacy
    )
    #expect(decoded.graphID == "unknown")
    #expect(decoded.videoRendererIdentity == "unknown")
    #expect(decoded.synchronizerIdentity == "unknown")
    #expect(decoded.status == "unknown")
}

@Test func audioSampleRecordPreservesLaneDetailsAndDecodesLegacyV1() throws {
    let current = AudioSampleRecord(
        mediaSessionID: "session-1",
        audioTrackID: "session-1.audio.3",
        streamEpoch: 2,
        rawStreamIndex: 3,
        presentationTimeSeconds: 1.25,
        durationSeconds: 0.02,
        sampleRate: 48_000,
        channelCount: 6,
        sampleCount: 960,
        payloadOwnershipState: "retainedCMSampleBuffer"
    )
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    #expect(object["rawStreamIndex"] as? Int == 3)
    #expect(object["sampleRate"] as? Int == 48_000)
    #expect(object["channelCount"] as? Int == 6)
    #expect(object["payloadOwnershipState"] as? String == "retainedCMSampleBuffer")

    object.removeValue(forKey: "rawStreamIndex")
    object.removeValue(forKey: "sampleRate")
    object.removeValue(forKey: "channelCount")
    object.removeValue(forKey: "payloadOwnershipState")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(AudioSampleRecord.self, from: legacy)

    #expect(decoded.rawStreamIndex == -1)
    #expect(decoded.sampleRate == 0)
    #expect(decoded.channelCount == 0)
    #expect(decoded.payloadOwnershipState == "unknown")
}

@Test func presentationStateIsRetainedByDebugSnapshot() {
    let store = PlaybackDiagnosticsStore()
    let record = PresentationStateRecord(
        mediaSessionID: "session-1",
        requestedMode: "panorama",
        phase: "active",
        platform: "visionOS",
        sceneContainer: .init(known: "ImmersiveSpace(PlaybackImmersiveSpace)"),
        desiredImmersiveViewingMode: .init(known: "progressive"),
        actualImmersiveViewingMode: .init(known: "progressive"),
        desiredViewingMode: .init(known: "mono"),
        actualViewingMode: .init(known: "mono"),
        desiredSpatialVideoMode: .init(known: "screen"),
        actualSpatialVideoMode: .init(known: "screen"),
        transitionResult: .init(known: "opened")
    )

    store.recordPresentationState(record)

    #expect(store.snapshot().presentationState == record)
}

@Test func acceptedOpenBindsSourceToOneSession() {
    var state = MediaSessionState()
    let source = fixtureSource("one.mp4")

    let admission = state.admitOpen(
        source: source,
        initialTimeSeconds: 2.5,
        startsPaused: true,
        mediaSessionID: "session-1"
    )

    guard case .accepted(let session) = admission else {
        Issue.record("Expected accepted open")
        return
    }
    #expect(session.mediaSessionID == "session-1")
    #expect(session.source == source)
    #expect(session.source.accessRequirement == "notRequired")
    #expect(session.initialTimeSeconds == 2.5)
    #expect(session.startsPaused)
    #expect(state.current == session)
}

@Test func occupiedSlotRejectsSecondOpenWithoutCreatingSession() {
    var state = MediaSessionState()
    _ = state.admitOpen(
        source: fixtureSource("one.mp4"),
        mediaSessionID: "session-1"
    )

    let second = state.admitOpen(
        source: fixtureSource("two.mkv"),
        mediaSessionID: "session-2"
    )

    guard case .rejected(let rejection) = second else {
        Issue.record("Expected rejected open")
        return
    }
    #expect(rejection.reason == "currentMediaSlotOccupied")
    #expect(rejection.occupyingMediaSessionID == "session-1")
    #expect(state.current?.mediaSessionID == "session-1")
}

@Test func closeReleasesSlotAndLateUpdateIsStale() {
    var state = MediaSessionState()
    _ = state.admitOpen(
        source: fixtureSource("one.mp4"),
        mediaSessionID: "session-1"
    )

    let didRelease = state.release(mediaSessionID: "session-1")
    #expect(didRelease)
    #expect(state.current == nil)
    let acceptedLateUpdate = state.updateLifecycle(.playing, mediaSessionID: "session-1")
    #expect(!acceptedLateUpdate)
    #expect(state.staleUpdateCount == 1)

    let next = state.admitOpen(
        source: fixtureSource("two.mkv"),
        mediaSessionID: "session-2"
    )
    guard case .accepted(let session) = next else {
        Issue.record("Expected reopen to be accepted")
        return
    }
    #expect(session.mediaSessionID == "session-2")
}

@Test func snapshotPreservesMediaEventEpochRevisionAndTypedCounts() async throws {
    let store = PlaybackDiagnosticsStore()
    let event = MediaEventRecord(
        eventID: "event-1",
        mediaSessionID: "session-1",
        videoTrackID: "video-1",
        streamEpoch: 4,
        formatRevision: 2,
        kind: .sample
    )
    let sample = VideoSampleRecord(
        mediaSessionID: "session-1",
        videoTrackID: "video-1",
        sourceEventID: "event-1",
        streamEpoch: 4,
        formatRevision: 2,
        inputKind: .compressed,
        presentationTimeSeconds: 1,
        decodeTimeSeconds: 0.9,
        durationSeconds: 1 / 30,
        mediaSubtype: "hvc1",
        dimensions: "3840x2160",
        formatSignaling: VideoFormatSignalingSummary(
            provenance: "testFormat",
            transferFunction: .init(known: "PQ"),
            hvcC: .init(known: true),
            dvcC: .init(.none)
        ),
        payloadOwnershipState: "retainedCMSampleBuffer"
    )
    store.recordMediaEvent(event)
    store.recordVideoSample(sample)
    store.recordRendererInput(RendererInputRecord(
        mediaSessionID: "session-1",
        sourceEventID: "event-1",
        streamEpoch: 4,
        graphRevision: 1,
        action: "enqueue",
        outcome: .accepted
    ))

    let snapshot = store.snapshot()
    #expect(snapshot.streamEpoch == 4)
    #expect(snapshot.formatRevision == 2)
    #expect(snapshot.sampleCount == 1)
    #expect(snapshot.acceptedRendererInputCount == 1)
    #expect(snapshot.lastAcceptedRendererInput?.sourceEventID == "event-1")

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(PlaybackDebugSnapshotV1.self, from: data)
    #expect(decoded.lastVideoSample == sample)
    #expect(decoded.lastVideoSample?.formatSignaling.transferFunction.value == "PQ")
    #expect(
        decoded.lastVideoSample?.formatSignaling.dvcC.availability == FactAvailability.none
    )
}

@Test func debugEventStreamUsesMonotonicSequenceNumbers() async {
    let store = PlaybackDiagnosticsStore()
    let stream = store.events()
    let consumer = Task { () -> [PlaybackDebugEvent] in
        var events: [PlaybackDebugEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 { break }
        }
        return events
    }

    store.emit(kind: "open.accepted")
    store.emit(kind: "provider.opened")
    let events = await consumer.value

    #expect(events.map(\.sequenceNumber) == [1, 2])
    #expect(events.map(\.kind) == ["open.accepted", "provider.opened"])
}

@Test func synchronousEventObserverSeesBoundaryBeforeEmitReturns() {
    let store = PlaybackDiagnosticsStore()
    let observed = LockedBox<PlaybackDebugEvent?>(nil)
    let observerID = store.addEventObserver { event in
        observed.withLock { $0 = event }
    }
    defer { store.removeEventObserver(observerID) }

    let emitted = store.emit(kind: "session.cleanup")
    #expect(observed.withLock { $0 } == emitted)
}

@Test func closingCurrentSessionRetainsPrivacySafeLastSessionSummary() {
    let store = PlaybackDiagnosticsStore()
    let session = MediaSessionRecord(
        mediaSessionID: "session-1",
        source: fixtureSource("private-name.mp4"),
        initialTimeSeconds: 0,
        startsPaused: false,
        lifecycle: .playing
    )

    store.recordSession(session)
    store.recordSession(nil)

    let snapshot = store.snapshot()
    #expect(snapshot.lifecycle == .idle)
    #expect(snapshot.mediaSession == nil)
    #expect(snapshot.lastMediaSession?.mediaSessionID == "session-1")
    #expect(snapshot.lastMediaSession?.sourceSummary == "private-name.mp4")
}

@Test func completedOperationMovesFromCurrentToStableHistory() {
    let store = PlaybackDiagnosticsStore()
    let running = PlaybackOperationRecord(
        operationID: "seek-1",
        mediaSessionID: "session-1",
        kind: .seek,
        targetTimeSeconds: 12.5
    )

    store.recordOperation(running)
    #expect(store.snapshot().currentOperation == running)

    let completed = running.finishing(as: .completed)
    store.recordOperation(completed)
    let snapshot = store.snapshot()
    #expect(snapshot.currentOperation == nil)
    #expect(snapshot.lastCompletedOperation == completed)
    #expect(snapshot.lastCompletedOperation?.targetTimeSeconds == 12.5)
}

@Test func staleRejectionIsCountedInSnapshot() {
    let store = PlaybackDiagnosticsStore()
    store.recordStaleRejection()
    store.recordStaleRejection()
    #expect(store.snapshot().staleRejectionCount == 2)
}

@MainActor
@Test func controllerRejectsSecondOpenAndRecordsTheRejection() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let source = URL(fileURLWithPath: "/fixtures/fake.mov")

    let first = try await controller.open(source)
    #expect(first.debugSnapshot().platform == "macOS")
    #expect(first.debugSnapshot().hardwareDisplayFacts == .notAvailable)
    do {
        _ = try await controller.open(source)
        Issue.record("Expected second open to be rejected")
    } catch let error as PlaybackControlError {
        guard case .openRejected(let rejection) = error else {
            Issue.record("Expected openRejected, got \(error)")
            return
        }
        #expect(rejection.occupyingMediaSessionID == first.traceID)
        #expect(first.debugSnapshot().lastOpenRejection == rejection)
    }
}

@Test func debugRecorderModeRequiresTheExplicitVerificationEnvironmentValue() {
    #expect(PlaybackDebugRecorderMode(environment: [:]) == .enabled)
    #expect(PlaybackDebugRecorderMode(environment: [
        PlaybackDebugRecorderMode.verificationDisableEnvironmentKey: "0",
    ]) == .enabled)
    #expect(PlaybackDebugRecorderMode(environment: [
        PlaybackDebugRecorderMode.verificationDisableEnvironmentKey: "1",
    ]) == .disabledForVerification)
}

@MainActor
@Test(arguments: [
    PlaybackDebugRecorderMode.enabled,
    PlaybackDebugRecorderMode.disabledForVerification,
])
func controllerDebugRecorderModeControlsRealRecorderLifecycle(
    _ mode: PlaybackDebugRecorderMode
) async throws {
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in
            SampleBufferPlaybackSession(
                traceID: sessionID,
                provider: FakeVideoSampleProvider(events: [.end]),
                rendererSink: FakeRendererInputSink()
            )
        },
        debugRecorderMode: mode
    )
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/debug-recorder-mode.mov")
    )
    let recorderDirectory = controller.debugDirectoryURL
    let observed = LockedBox<PlaybackDebugEvent?>(nil)
    let observerID = session.debugStore.addEventObserver { event in
        observed.withLock { $0 = event }
    }
    let event = session.debugStore.emit(kind: "verification.inMemoryStore")
    session.debugStore.removeEventObserver(observerID)

    #expect(observed.withLock { $0 } == event)
    #expect((recorderDirectory != nil) == (mode == .enabled))
    #if DEBUG
    #expect((controller.debugEvidenceJSON() != nil) == (mode == .enabled))
    #endif

    await controller.closeAndWait()
    #expect(controller.debugDirectoryURL == nil)
    if let recorderDirectory {
        try? FileManager.default.removeItem(at: recorderDirectory)
    }
}

@MainActor
@Test func startWithoutActiveSessionIsRejected() {
    let controller = PlaybackCoreController()

    do {
        try controller.start()
        Issue.record("Expected start without an active session to be rejected")
    } catch let error as PlaybackControlError {
        guard case .noActiveMediaSession = error else {
            Issue.record("Expected noActiveMediaSession, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected PlaybackControlError, got \(error)")
    }
}

@MainActor
@Test func openWaitsForPendingSynchronousCloseCleanup() async throws {
    let sink = FakeRendererInputSink(completesFlushImmediately: false)
    let sessionCreationCount = LockedBox(0)
    let controller = PlaybackCoreController { sessionID in
        sessionCreationCount.withLock { $0 += 1 }
        return SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: sink
        )
    }
    let source = URL(fileURLWithPath: "/fixtures/fake.mov")
    let first = try await controller.open(source)

    controller.close(clearSource: false)
    try await waitForFlushCount(1, in: sink)
    #expect(sink.flushCount == 1)
    let didFinishSecondOpen = LockedBox(false)
    let (secondOpenStarted, secondOpenStartedContinuation) = AsyncStream.makeStream(of: Void.self)
    let secondOpen = Task { @MainActor in
        secondOpenStartedContinuation.yield()
        secondOpenStartedContinuation.finish()
        let session = try await controller.open(source)
        didFinishSecondOpen.withLock { $0 = true }
        return session
    }
    for await _ in secondOpenStarted { break }

    #expect(sessionCreationCount.withLock { $0 } == 1)
    #expect(!didFinishSecondOpen.withLock { $0 })
    sink.completePendingFlushes()
    let second = try await secondOpen.value
    #expect(second.traceID != first.traceID)

    controller.close()
    sink.completePendingFlushes()
    await controller.closeAndWait()
}

@Test func closeSnapshotRecordsTheCompleteCleanupBarrier() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "cleanup-barrier-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink()
    )
    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/cleanup.mov"))

    await session.closeAndWait()

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lastCompletedOperation?.kind == .close)
    #expect(snapshot.lastCompletedOperation?.state == .completed)
    #expect(snapshot.cleanupState?.videoProviderCancelled == true)
    #expect(snapshot.cleanupState?.audioProviderCancelled == true)
    #expect(snapshot.cleanupState?.audioRendererFlushed == true)
    #expect(snapshot.cleanupState?.videoRendererFlushed == true)
    #expect(snapshot.rendererState?.flushCount == 1)
}

@MainActor
@Test func unrecoverableProviderFailureReleasesCurrentMediaSlot() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [],
                readError: FakeSampleError.providerRead
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/failing.mov"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline, controller.activeSession != nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.activeSession == nil)
    guard case .failed = controller.status else {
        Issue.record("Expected public failed status after cleanup")
        return
    }

    let reopened = try await controller.open(
        URL(fileURLWithPath: "/fixtures/reopen.mov"),
    )
    #expect(reopened.traceID != session.traceID)
}

@MainActor
@Test(arguments: FailedCleanupRecovery.allCases)
func failedSessionCleanupBlocksNewOpenUntilFlushCompletes(
    _ recovery: FailedCleanupRecovery
) async throws {
    let sink = FakeRendererInputSink(completesFlushImmediately: false)
    let sessionCreationCount = LockedBox(0)
    let controller = PlaybackCoreController { sessionID in
        let creation = sessionCreationCount.withLock { count in
            count += 1
            return count
        }
        return SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: creation == 1 ? [] : [.end],
                readError: creation == 1 ? FakeSampleError.providerRead : nil
            ),
            rendererSink: sink
        )
    }
    let source = URL(fileURLWithPath: "/fixtures/failing.mov")
    let failedSession = try await controller.open(source)
    failedSession.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()

    let failureDeadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < failureDeadline, controller.activeSession != nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.activeSession == nil)
    #expect(sink.flushCount == 1)

    let didFinishNextOpen = LockedBox(false)
    let nextOpen = Task { @MainActor in
        let session = switch recovery {
        case .open:
            try await controller.open(source)
        case .reopen:
            try await controller.reopen()
        }
        didFinishNextOpen.withLock { $0 = true }
        return session
    }
    try await Task.sleep(for: .milliseconds(50))

    #expect(sessionCreationCount.withLock { $0 } == 1)
    #expect(!didFinishNextOpen.withLock { $0 })

    sink.completePendingFlushes()
    let reopened = try await nextOpen.value
    #expect(reopened.traceID != failedSession.traceID)
    #expect(controller.activeSession === reopened)
    #expect(controller.status == .loading)

    controller.close()
    sink.completePendingFlushes()
    await controller.closeAndWait()
}

@MainActor
@Test func controllerSeekKeepsSessionAndAdvancesStreamEpoch() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 10)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/fake.mov"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)

    try await controller.seek(
        to: CMTime(seconds: 5, preferredTimescale: 600),
        startsPaused: false
    )
    try await waitForSampleCount(2, in: session)

    #expect(controller.activeSession === session)
    #expect(session.debugSnapshot().streamEpoch == 2)
    #expect(session.debugSnapshot().rendererState?.rate == 1)
    #expect(session.debugSnapshot().lastCompletedOperation?.kind == .seek)
    #expect(session.debugSnapshot().lastCompletedOperation?.targetTimeSeconds == 5)
}

@Test func seekFailsImmediatelyWhenTargetEpochEndsBeforeTarget() async throws {
    for expectedLastPTS in [1.0, nil] as [Double?] {
        let events: [VideoSampleProviderEvent]
        if let expectedLastPTS {
            events = [
                .sample(try makeCompressedH264Sample(
                    presentationTimeSeconds: expectedLastPTS
                )),
                .end,
            ]
        } else {
            events = [.end]
        }
        let lastPTSLabel = expectedLastPTS.map { String($0) } ?? "none"
        let session = SampleBufferPlaybackSession(
            traceID: "seek-target-unavailable-\(lastPTSLabel)",
            provider: FakeVideoSampleProvider(events: events),
            rendererSink: FakeRendererInputSink()
        )
        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/short.mov"))
        try session.start()
        if expectedLastPTS != nil {
            try await waitForSampleCount(1, in: session)
        }

        let startedAt = ContinuousClock.now
        do {
            try await session.seek(
                to: CMTime(seconds: 5, preferredTimescale: 600),
                startsPaused: false
            )
            Issue.record("Expected target-epoch EOF to reject the seek")
        } catch CorePlaybackError.seekTargetUnavailable(let target, let lastPTS) {
            #expect(target == 5)
            #expect(lastPTS == expectedLastPTS)
        } catch {
            Issue.record("Expected seekTargetUnavailable, got \(error)")
        }
        #expect(startedAt.duration(to: .now) < .seconds(1))
        let snapshot = session.debugSnapshot()
        #expect(snapshot.lastFailure?.stage == "control.seek.targetUnavailable")
        #expect(snapshot.lastCompletedOperation?.kind == .seek)
        #expect(snapshot.lastCompletedOperation?.state == .failed)
        await session.closeAndWait()
    }
}

@MainActor
@Test func newerSeekSupersedesOlderSeekAndOwnsFinalTarget() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 20)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(sample), .end],
                seekPrepareDelay: .milliseconds(150)
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/fake.mov"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)

    let first = Task {
        try await controller.seek(to: CMTime(seconds: 5, preferredTimescale: 600))
    }
    try await Task.sleep(for: .milliseconds(20))
    let second = Task {
        try await controller.seek(to: CMTime(seconds: 10, preferredTimescale: 600))
    }

    do {
        try await first.value
        Issue.record("Expected the first seek to be superseded")
    } catch let error as PlaybackControlError {
        guard case .seekSuperseded(let target) = error else {
            Issue.record("Expected seekSuperseded, got \(error)")
            return
        }
        #expect(target == 5)
    }
    try await second.value

    let snapshot = session.debugSnapshot()
    #expect(snapshot.streamEpoch == 3)
    #expect(snapshot.lastCompletedOperation?.kind == .seek)
    #expect(snapshot.lastCompletedOperation?.targetTimeSeconds == 10)
    #expect(snapshot.lastCompletedOperation?.state == .completed)
}

@MainActor
@Test func threeRapidSeeksOnlyAllowNewestWaiterToEnterSession() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 20)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(sample), .end],
                seekPrepareDelay: .milliseconds(150),
                seekPrepareIgnoresCancellation: true
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/fake.mov"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)

    let first = Task {
        try await controller.seek(to: CMTime(seconds: 5, preferredTimescale: 600))
    }
    try await Task.sleep(for: .milliseconds(20))
    let second = Task {
        try await controller.seek(to: CMTime(seconds: 10, preferredTimescale: 600))
    }
    try await Task.sleep(for: .milliseconds(20))
    let third = Task {
        try await controller.seek(to: CMTime(seconds: 15, preferredTimescale: 600))
    }

    for (task, target) in [(first, 5.0), (second, 10.0)] {
        do {
            try await task.value
            Issue.record("Expected seek to \(target) seconds to be superseded")
        } catch let error as PlaybackControlError {
            guard case .seekSuperseded(let actualTarget) = error else {
                Issue.record("Expected seekSuperseded, got \(error)")
                continue
            }
            #expect(actualTarget == target)
        }
    }
    try await third.value

    let snapshot = session.debugSnapshot()
    #expect(snapshot.streamEpoch == 3)
    #expect(snapshot.lastCompletedOperation?.kind == .seek)
    #expect(snapshot.lastCompletedOperation?.targetTimeSeconds == 15)
    #expect(snapshot.lastCompletedOperation?.state == .completed)
}

@MainActor
@Test func rapidRelativeSeeksAccumulateInsideTheCore() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 30)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(sample), .end],
                seekPrepareDelay: .milliseconds(150)
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/fake.mov"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "macOS",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try controller.pause()
    let baseSeconds = session.currentTime().seconds

    let first = Task {
        try await controller.seek(by: CMTime(seconds: 10, preferredTimescale: 600))
    }
    try await Task.sleep(for: .milliseconds(20))
    let second = Task {
        try await controller.seek(by: CMTime(seconds: 10, preferredTimescale: 600))
    }

    do {
        try await first.value
        Issue.record("Expected the first relative seek to be superseded")
    } catch let error as PlaybackControlError {
        guard case .seekSuperseded(let target) = error else {
            Issue.record("Expected seekSuperseded, got \(error)")
            return
        }
        #expect(abs(target - (baseSeconds + 10)) < 0.001)
    }
    try await second.value

    let finalTarget = try #require(
        session.debugSnapshot().lastCompletedOperation?.targetTimeSeconds
    )
    #expect(abs(finalTarget - (baseSeconds + 20)) < 0.001)
}

@Test func injectedProviderProducesMediaEventSampleAndRendererIntent() async throws {
    let sample = try makeCompressedH264Sample()
    try expectCompressedH264Contract(sample)
    let provider = FakeVideoSampleProvider(events: [.sample(sample), .end])
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "fake-compressed-session",
        provider: provider,
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/fake.mov"))
    try session.start()

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        let snapshot = session.debugSnapshot()
        if snapshot.sampleCount == 1,
           snapshot.acceptedRendererInputCount == 1,
           snapshot.lastMediaEvent?.kind == .end {
            #expect(snapshot.lastVideoSample?.inputKind == .compressed)
            #expect(snapshot.lastVideoSample?.mediaSubtype == "avc1")
            #expect(snapshot.lastVideoSample?.dimensions == "640x360")
            #expect(snapshot.lastVideoSample?.streamEpoch == 1)
            #expect(
                snapshot.lastVideoSample?.formatSignaling.provenance
                    == "CMFormatDescription.sampleDescription"
            )
            #expect(snapshot.lastVideoSample?.payloadOwnershipState == "retainedCMSampleBuffer")
            #expect(snapshot.providerOpen?.schemaVersion == 1)
            #expect(snapshot.providerOpen?.sourceSummary == "fake.mov")
            #expect(snapshot.providerOpen?.seekability.value == "providerRebuild")
            #expect(snapshot.videoTrack?.sourceSnapshotID == snapshot.providerOpen?.snapshotID)
            #expect(snapshot.lastRendererInput?.videoTrackID == "fake-compressed-session.video.0")
            #expect(snapshot.lastRendererInput?.inputKind == .compressed)
            #expect(snapshot.lastRendererInput?.timelineConfiguredBeforeFirstEnqueue == true)
            #expect(snapshot.lastRendererInput?.outcome == .accepted)
            #expect(sink.enqueuedSampleCount == 1)
            #expect(sink.renderingEventObservationCount == 1)
            #expect(!sink.startedRenderingEventObservationBeforeFirstEnqueue)
            try expectCompressedH264Contract(try #require(sink.lastEnqueuedSample))
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record(
        "Provider sample did not reach renderer input coordination: \(session.debugSnapshot())"
    )
}

@Test func zeroRequestedStartOwnsTimelineWhenFirstVideoSampleStartsLater() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 0.021)
    let session = SampleBufferPlaybackSession(
        traceID: "offset-first-video-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    let eventStream = session.debugEvents()
    let targetEvent = Task<PlaybackDebugEvent?, Never> {
        for await event in eventStream where event.kind == "timeline.targetApplied" {
            return event
        }
        return nil
    }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/offset-first-video.mkv"),
        startTime: .zero
    )
    try session.start()
    try await waitForSampleCount(1, in: session)

    let event = try #require(await targetEvent.value)
    #expect(event.details["time"] == "0.0")
}

@Test func decoderPrerollBootstrapsBeforeReceiverBackpressure() async throws {
    let firstSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0.021,
        decodeTimeSeconds: -0.066,
        durationSeconds: 1.0 / 30.0
    )
    let secondSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0.054,
        decodeTimeSeconds: -0.033,
        durationSeconds: 1.0 / 30.0
    )
    let thirdSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0.087,
        decodeTimeSeconds: 0,
        durationSeconds: 1.0 / 30.0
    )
    let fourthSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0.120,
        decodeTimeSeconds: 0.033,
        durationSeconds: 1.0 / 30.0
    )
    let sink = FakeRendererInputSink(automaticallyRunsRequests: false)
    let session = SampleBufferPlaybackSession(
        traceID: "first-video-preroll-session",
        provider: FakeVideoSampleProvider(
            events: [
                .sample(firstSample),
                .sample(secondSample),
                .sample(thirdSample),
                .sample(fourthSample),
                .end,
            ]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/delayed-video.mkv"))
    try session.start()
    try await waitForPendingRequestCount(1, in: sink)

    #expect(sink.enqueuedSampleCount == 3)
    #expect(sink.immediateEnqueueCount == 3)
    #expect(session.synchronizer.rate == 1)
    sink.runNextPendingRequest()
    try await waitForSampleCount(4, in: session)
    #expect(sink.immediateEnqueueCount == 3)
}

@Test func boundedImmediateStrategyDoesNotWaitForReceiverReadiness() async throws {
    let samples = try [
        makeCompressedH264Sample(
            presentationTimeSeconds: 0,
            decodeTimeSeconds: 0
        ),
        makeCompressedH264Sample(
            presentationTimeSeconds: 0.033,
            decodeTimeSeconds: 0.033
        ),
    ]
    let sink = FakeRendererInputSink(
        enqueueStrategy: .boundedImmediateLead,
        automaticallyRunsRequests: false
    )
    let session = SampleBufferPlaybackSession(
        traceID: "bounded-immediate-strategy",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/bounded-immediate.mkv"))
    try session.start()
    try await waitForSampleCount(2, in: session)

    #expect(sink.immediateEnqueueCount == 2)
    #expect(sink.pendingRequestCount == 0)
    let firstSampleStages = events.withLock { events in
        events.compactMap { event -> String? in
            guard event.kind.hasPrefix("playbackDelivery.stage.video."),
                  event.details["sampleOrdinal"] == "1",
                  event.kind.contains("boundedLead")
                    || event.kind.contains("enqueueImmediately") else { return nil }
            return String(event.kind.dropFirst("playbackDelivery.stage.video.".count))
        }
    }
    #expect(firstSampleStages == [
        "boundedLead.enter",
        "boundedLead.returned",
        "enqueueImmediately.enter",
        "enqueueImmediately.returned",
        "enqueueImmediately.outcome",
    ])
}

@Test func timelineRemainsStoppedUntilDecodeBootstrapReachesTheRequestedTime() async throws {
    let samples = try [
        makeCompressedH264Sample(
            presentationTimeSeconds: 0.021,
            decodeTimeSeconds: -0.066
        ),
        makeCompressedH264Sample(
            presentationTimeSeconds: 0.054,
            decodeTimeSeconds: -0.033
        ),
        makeCompressedH264Sample(
            presentationTimeSeconds: 0.087,
            decodeTimeSeconds: 0.033
        ),
    ]
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "timeline-bootstrap-gate",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            eventDelay: .milliseconds(100)
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/bootstrap-gate.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    #expect(session.synchronizer.rate == 0)
    #expect(session.debugSnapshot().decoderBootstrap?.complete == false)

    try await waitForSampleCount(3, in: session)
    let bootstrap = try #require(session.debugSnapshot().decoderBootstrap)
    #expect(abs(bootstrap.targetDecodeTimeSeconds) < 0.000_001)
    let crossingDecodeTime = CMSampleBufferGetDecodeTimeStamp(samples[2]).seconds
    #expect(
        abs((bootstrap.lastDecodeTimeSeconds ?? 0) - crossingDecodeTime) < 0.000_001
    )
    #expect(bootstrap.immediateEnqueueCount == 3)
    #expect(bootstrap.complete)
    #expect(sink.immediateEnqueueCount == 3)
    #expect(session.synchronizer.rate == 1)
}

@Test func seekToExactDurationPublishesEndedWithoutReopeningTheProvider() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let provider = FakeVideoSampleProvider(events: [.sample(sample), .end])
    let session = SampleBufferPlaybackSession(
        traceID: "seek-to-end-session",
        provider: provider,
        rendererSink: FakeRendererInputSink()
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-to-end.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let startCount = provider.startCount

    try await session.seek(
        to: CMTime(seconds: 1, preferredTimescale: 600),
        startsPaused: false
    )

    #expect(provider.startCount == startCount)
    #expect(session.debugSnapshot().lifecycle == .ended)
    #expect(statuses.withLock { $0.last } == .ended(.seekToEnd))
    #expect(session.renderer.displayedPixelBuffer() == nil)
}

@Test func seekToTargetCoveredByFinalVideoSampleDoesNotFail() async throws {
    let sample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0.96,
        durationSeconds: 0.04
    )
    let session = SampleBufferPlaybackSession(
        traceID: "seek-to-final-sample-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-to-final-sample.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    try await session.seek(
        to: CMTime(seconds: 0.99, preferredTimescale: 600),
        startsPaused: true
    )

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lastFailure == nil)
    #expect(snapshot.lastCompletedOperation?.kind == .seek)
    #expect(snapshot.lastCompletedOperation?.state == .completed)
    #expect(snapshot.lastVideoSample?.presentationTimeSeconds == 0.96)
}

@Test func markerOnlySampleDoesNotBlockFollowingVideoSample() async throws {
    let marker = try makeMarkerOnlySample(presentationTimeSeconds: 1.0 / 15.0)
    let video = try makeCompressedH264Sample(presentationTimeSeconds: 1.0 / 15.0)
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "marker-then-video-session",
        provider: FakeVideoSampleProvider(
            events: [.sample(marker), .sample(video), .end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/marker-then-video.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    #expect(session.debugSnapshot().sampleCount == 1)
    #expect(sink.enqueuedSampleCount == 1)
}

@Test func invalidRateIsRejectedAndRecorded() async throws {
    let sample = try makeCompressedH264Sample()
    let session = SampleBufferPlaybackSession(
        traceID: "invalid-rate-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/fake.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    do {
        try session.setRate(-1)
        Issue.record("Expected an invalid rate rejection")
    } catch let error as PlaybackControlError {
        guard case .invalidRate(let rate) = error else {
            Issue.record("Expected invalidRate, got \(error)")
            return
        }
        #expect(rate == -1)
    }
    let rejection = session.debugSnapshot().lastControlRejection
    #expect(rejection?.kind == .setRate)
    #expect(rejection?.reason == "invalidRate")
    #expect(rejection?.targetRate == -1)
}

@Test func playResumesPreferredRateAfterPause() async throws {
    let sample = try makeCompressedH264Sample()
    let session = SampleBufferPlaybackSession(
        traceID: "preferred-rate-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/fake.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    try await setRateWhenTimelineIsReady(2, in: session)
    try session.pause()
    #expect(session.currentRate() == 0)
    #expect(session.preferredPlaybackRate == 2)

    try session.play()
    #expect(session.currentRate() == 2)
    #expect(CMTimebaseGetRate(session.synchronizer.timebase) == 2)
}

@MainActor
@Test func providerFormatChangeAdvancesRevisionAndFlushesRenderer() async throws {
    let sample = try makeCompressedH264Sample()
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "format-change-session",
        provider: FakeVideoSampleProvider(
            events: [.formatChanged, .sample(sample), .end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/change.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.formatRevision == 2)
    #expect(snapshot.lastVideoSample?.formatRevision == 2)
    #expect(sink.flushCount >= 1)
}

@Test func providerFlushAdvancesStreamEpoch() async throws {
    let sample = try makeCompressedH264Sample()
    let session = SampleBufferPlaybackSession(
        traceID: "provider-flush-session",
        provider: FakeVideoSampleProvider(events: [.flush, .sample(sample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/flush.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.streamEpoch == 2)
    #expect(snapshot.lastVideoSample?.streamEpoch == 2)
}

@Test
func stereoOverrideBeforeFirstSampleKeepsInitialRevision() async throws {
    let sample = try makeCompressedH264Sample()
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-before-start",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    let revision = try await session.setStereoLayout(.sideBySide)
    #expect(revision == 1)
    #expect(session.effectiveStereoLayout == .sideBySide)

    try session.start()
    try await waitForSampleCount(1, in: session)
    let snapshot = session.debugSnapshot()
    #expect(snapshot.streamEpoch == 1)
    #expect(snapshot.formatRevision == 1)
    #expect(
        snapshot.lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
}

@Test
func liveStereoOverrideUsesSharedSeamWithoutChangingTimeline() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 30)
    let sink = FakeRendererInputSink(pausesAfterEachEnqueue: true)
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-live",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let baselineRate = session.currentRate()
    let rendererIdentity = PlaybackTrace.identity(session.renderer)
    let baselineFlushCount = sink.flushCount

    let sideBySideRevision = try await session.setStereoLayout(.sideBySide)
    #expect(sideBySideRevision == 2)
    #expect(session.effectiveStereoLayout == .sideBySide)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.hasLeftStereoEyeView.value == true
    )
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.hasRightStereoEyeView.value == true
    )

    let overUnderRevision = try await session.setStereoLayout(.overUnder)
    #expect(overUnderRevision == 3)
    #expect(session.effectiveStereoLayout == .overUnder)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_OverUnder as String
    )

    let monoRevision = try await session.setStereoLayout(.mono)
    let final = session.debugSnapshot()
    #expect(monoRevision == 4)
    #expect(session.effectiveStereoLayout == .mono)
    #expect(final.lastVideoSample?.formatSignaling.viewPackingKind.value == nil)
    #expect(final.lastVideoSample?.formatSignaling.hasLeftStereoEyeView.value == false)
    #expect(final.lastVideoSample?.formatSignaling.hasRightStereoEyeView.value == false)
    #expect(final.streamEpoch == baseline.streamEpoch)
    #expect(final.rendererState?.graphRevision == baseline.rendererState?.graphRevision)
    #expect(sink.flushCount == baselineFlushCount)
    #expect(final.rendererState?.flushCount == UInt64(sink.flushCount))
    #expect(session.currentRate() == baselineRate)
    #expect(PlaybackTrace.identity(session.renderer) == rendererIdentity)
}

@Test
func liveProjectionOverrideUsesSharedSeamWithoutChangingTimeline() async throws {
    let sourceProjection = kCMFormatDescriptionProjectionKind_Equirectangular as String
    let sample = try makeCompressedH264Sample(
        projectionKind: kCMFormatDescriptionProjectionKind_Equirectangular
    )
    let sink = FakeRendererInputSink(pausesAfterEachEnqueue: true)
    let session = SampleBufferPlaybackSession(
        traceID: "projection-live",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end],
            projectionKind: sourceProjection
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/projection.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let baselineRate = session.currentRate()
    let rendererIdentity = PlaybackTrace.identity(session.renderer)
    let baselineFlushCount = sink.flushCount

    let flatRevision = try await session.setProjectionOverride(.rectilinear)
    #expect(flatRevision == 2)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.projectionKind.value
            == kCMFormatDescriptionProjectionKind_Rectilinear as String
    )

    let sourceRevision = try await session.clearProjectionOverride()
    #expect(sourceRevision == 3)
    #expect(session.effectiveProjectionKind == sourceProjection)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.projectionKind.value
            == sourceProjection
    )

    let final = session.debugSnapshot()
    #expect(final.streamEpoch == baseline.streamEpoch)
    #expect(sink.flushCount == baselineFlushCount)
    #expect(final.rendererState?.flushCount == UInt64(sink.flushCount))
    #expect(session.currentRate() == baselineRate)
    #expect(PlaybackTrace.identity(session.renderer) == rendererIdentity)
}

@Test
func panoramicProjectionOverrideMakesUntaggedInputEffectiveWithoutChangingTimeline() async throws {
    let sample = try makeCompressedH264Sample()
    let sink = FakeRendererInputSink(pausesAfterEachEnqueue: true)
    let session = SampleBufferPlaybackSession(
        traceID: "projection-panorama",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/untagged-360.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let baselineRate = session.currentRate()
    let rendererIdentity = PlaybackTrace.identity(session.renderer)

    let fullRevision = try await session.setProjectionOverride(.equirectangular)
    #expect(fullRevision == 2)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.projectionKind.value
            == kCMFormatDescriptionProjectionKind_Equirectangular as String
    )

    let halfRevision = try await session.setProjectionOverride(.halfEquirectangular)
    #expect(halfRevision == 3)
    #expect(
        session.debugSnapshot().lastVideoSample?.formatSignaling.projectionKind.value
            == kCMFormatDescriptionProjectionKind_HalfEquirectangular as String
    )

    let final = session.debugSnapshot()
    #expect(final.streamEpoch == baseline.streamEpoch)
    #expect(final.rendererState?.graphRevision == baseline.rendererState?.graphRevision)
    #expect(session.currentRate() == baselineRate)
    #expect(PlaybackTrace.identity(session.renderer) == rendererIdentity)
}

@Test func clearingStereoOverrideWaitsForASourceFormatSample() async throws {
    let sample = try makeCompressedH264Sample()
    let sink = FakeRendererInputSink(
        pausesAfterEachEnqueue: true,
        automaticallyRunsRequests: false
    )
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-clear-source-format",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 3) + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForPendingRequestCount(1, in: sink)

    let explicitCancellationCount = sink.cancelledRequestCount
    let explicitMono = Task {
        try await session.setStereoLayout(.mono)
    }
    try await waitForCancelledRequestCount(explicitCancellationCount + 1, in: sink)
    try await waitForPendingRequestCount(1, in: sink)
    sink.runNextPendingRequest()
    _ = try await explicitMono.value
    let explicitSnapshot = session.debugSnapshot()
    #expect(explicitSnapshot.lastVideoSample?.formatSignaling.viewPackingKind.value == nil)
    try await waitForPendingRequestCount(1, in: sink)

    let didFinishClear = LockedBox(false)
    let clearCancellationCount = sink.cancelledRequestCount
    let clear = Task {
        let revision = try await session.clearStereoLayoutOverride()
        didFinishClear.withLock { $0 = true }
        return revision
    }
    try await waitForCancelledRequestCount(clearCancellationCount + 1, in: sink)
    try await waitForPendingRequestCount(1, in: sink)

    #expect(!didFinishClear.withLock { $0 })
    #expect(session.debugSnapshot().lastVideoSample?.sourceEventID == explicitSnapshot.lastVideoSample?.sourceEventID)

    sink.runNextPendingRequest()
    let sourceRevision = try await clear.value
    let sourceSnapshot = session.debugSnapshot()
    #expect(didFinishClear.withLock { $0 })
    #expect(sourceRevision == explicitSnapshot.formatRevision + 1)
    #expect(sourceSnapshot.lastVideoSample?.formatRevision == sourceRevision)
    #expect(sourceSnapshot.lastVideoSample?.sourceEventID != explicitSnapshot.lastVideoSample?.sourceEventID)
    #expect(sourceSnapshot.lastVideoSample?.formatSignaling.viewPackingKind.value == nil)
}

enum StereoProviderReset: CaseIterable {
    case formatChanged
    case flush

    var event: VideoSampleProviderEvent {
        switch self {
        case .formatChanged: .formatChanged
        case .flush: .flush
        }
    }
}

@Test(arguments: StereoProviderReset.allCases)
func stereoOverrideAfterProviderResetDoesNotOwnItsFlush(
    reset: StereoProviderReset
) async throws {
    let sample = try makeCompressedH264Sample()
    let sink = FakeRendererInputSink(
        completesFlushImmediately: false,
        pausesAfterEachEnqueue: true,
        automaticallyRunsRequests: false
    )
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-provider-reset",
        provider: FakeVideoSampleProvider(
            events: [.sample(sample), reset.event, .sample(sample), .end]
        ),
        rendererSink: sink
    )
    defer {
        session.close()
        sink.completePendingFlushes()
    }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let initialStreamEpoch = try #require(baseline.lastVideoSample?.streamEpoch)
    let initialFormatRevision = try #require(baseline.lastVideoSample?.formatRevision)
    try await waitForFlushCount(1, in: sink)

    #expect(sink.flushCount == 1)
    switch reset {
    case .formatChanged:
        #expect(session.debugSnapshot().streamEpoch == initialStreamEpoch)
    case .flush:
        #expect(session.debugSnapshot().streamEpoch == initialStreamEpoch + 1)
    }

    sink.completePendingFlushes()
    try await waitForPendingRequestCount(1, in: sink)

    let didFinishStereo = LockedBox(false)
    let didStartStereo = LockedBox(false)
    let observerID = session.debugStore.addEventObserver { event in
        if event.kind == "control.stereo.started" {
            didStartStereo.withLock { $0 = true }
        }
    }
    defer { session.debugStore.removeEventObserver(observerID) }
    let stereo = Task {
        let revision = try await session.setStereoLayout(.sideBySide)
        didFinishStereo.withLock { $0 = true }
        return revision
    }
    await Task.yield()
    try await waitForFlag(didStartStereo, description: "stereo command start")
    try await waitForPendingRequestCount(1, in: sink)
    #expect(!didFinishStereo.withLock { $0 })
    sink.runNextPendingRequest()

    let acceptedRevision = try await stereo.value
    let final = session.debugSnapshot()
    let expectedRevision = initialFormatRevision + (reset == .formatChanged ? 2 : 1)
    #expect(didFinishStereo.withLock { $0 })
    #expect(acceptedRevision == expectedRevision)
    #expect(final.lastVideoSample?.formatRevision == acceptedRevision)
    #expect(final.sampleCount == baseline.sampleCount + 1)
    #expect(
        final.lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
    #expect(final.streamEpoch == initialStreamEpoch + (reset == .flush ? 1 : 0))
    #expect(sink.flushCount == 1)
}

@MainActor
@Test func cancelledStereoCommandCannotMutateANewControllerSession() async throws {
    let sample = try makeCompressedH264Sample()
    let firstSink = FakeRendererInputSink(
        pausesAfterEachEnqueue: true,
        automaticallyRunsRequests: false
    )
    let laterSink = FakeRendererInputSink()
    let sessionCreationCount = LockedBox(0)
    let controller = PlaybackCoreController { sessionID in
        let creation = sessionCreationCount.withLock { count in
            count += 1
            return count
        }
        return SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: Array(repeating: .sample(sample), count: 3) + [.end]
            ),
            rendererSink: creation == 1 ? firstSink : laterSink
        )
    }
    defer { controller.close() }

    let url = URL(fileURLWithPath: "/fixtures/stereo-controller.mov")
    let first = try await controller.open(url)
    try controller.start()
    try await waitForPendingRequestCount(1, in: firstSink)
    firstSink.runNextPendingRequest()
    try await waitForSampleCount(2, in: first)
    try await waitForPendingRequestCount(1, in: firstSink)

    let didFinishOldCommand = LockedBox(false)
    let didStartOldCommand = LockedBox(false)
    let observerID = first.debugStore.addEventObserver { event in
        if event.kind == "control.stereo.started" {
            didStartOldCommand.withLock { $0 = true }
        }
    }
    defer { first.debugStore.removeEventObserver(observerID) }
    let oldCommand = Task { @MainActor in
        defer { didFinishOldCommand.withLock { $0 = true } }
        return try await controller.setStereoLayout(.sideBySide)
    }
    await Task.yield()
    try await waitForFlag(didStartOldCommand, description: "old stereo command start")
    #expect(!didFinishOldCommand.withLock { $0 })

    controller.close(clearSource: false)
    let second = try await controller.open(url)
    firstSink.runNextPendingRequest()

    do {
        _ = try await oldCommand.value
        Issue.record("Expected the old stereo command to be cancelled by close")
    } catch is CancellationError {
    } catch let error as PlaybackControlError {
        guard case .openTerminatedByCleanup = error else {
            Issue.record("Expected cleanup cancellation, got \(error)")
            return
        }
    }

    try await Task.sleep(for: .milliseconds(20))
    #expect(didFinishOldCommand.withLock { $0 })
    #expect(controller.activeSession === second)
    #expect(controller.selectedStereoLayout == nil)
    #expect(second.effectiveStereoLayout == .mono)
}

@Test func bindingRecordsRejectSecondActiveIdentity() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "binding-identity-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/binding.mov"))

    session.recordRealityKitBinding(entityIdentity: "entity-a", active: true)
    session.recordRealityKitBinding(entityIdentity: "entity-b", active: true)
    session.recordPresentationBinding(
        realityViewIdentity: "view-a",
        platform: "macOS",
        attached: true
    )
    session.recordPresentationBinding(
        realityViewIdentity: "view-b",
        platform: "macOS",
        attached: true
    )

    let snapshot = session.debugSnapshot()
    #expect(snapshot.realityKitBinding?.entityIdentity == "entity-a")
    #expect(snapshot.presentationBinding?.realityViewIdentity == "view-a")
    #expect(snapshot.staleRejectionCount == 2)
}

@Test func audioTrackSelectionAndRendererControlsStayInsideCurrentSession() async throws {
    let audio = FakeAudioSampleProvider()
    let session = SampleBufferPlaybackSession(
        traceID: "audio-control-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        audioProvider: audio,
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/two-audio.mp4"))
    #expect(session.availableAudioTracks.map(\.streamIndex) == [1, 2])
    #expect(audio.preparedStreamIndices == [nil])
    let videoEpochBeforeSelection = session.debugSnapshot().streamEpoch

    try await session.selectAudioTrack(streamIndex: 2)
    try session.setVolume(0.35)
    session.setMuted(true)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.availableAudioTracks == session.availableAudioTracks)
    #expect(audio.preparedStreamIndices == [nil, 2])
    #expect(snapshot.mediaSession?.mediaSessionID == "audio-control-session")
    #expect(snapshot.audioTrack?.rawStreamIndex == 2)
    #expect(snapshot.audioRendererState?.streamEpoch == 2)
    #expect(snapshot.audioRendererState?.status == "unknown")
    #expect(snapshot.streamEpoch == videoEpochBeforeSelection)
    #expect(snapshot.audioRendererState?.volume == 0.35)
    #expect(snapshot.audioRendererState?.muted == true)
    let audioRendererState = try #require(snapshot.audioRendererState)
    #expect(audioRendererState.graphID == "audio-control-session.rendererGraph")
    #expect(audioRendererState.rendererIdentity == PlaybackTrace.identity(session.audioRenderer))
    #expect(audioRendererState.videoRendererIdentity == PlaybackTrace.identity(session.renderer))
    #expect(audioRendererState.synchronizerIdentity == PlaybackTrace.identity(session.synchronizer))
}

@Test func endedWaitsForLongerSelectedAudioPresentation() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 0.05)
    let audioSample = try makeAudioSample(durationSeconds: 0.75)
    let session = SampleBufferPlaybackSession(
        traceID: "longer-audio-session",
        provider: FakeVideoSampleProvider(events: [.sample(videoSample), .end]),
        audioProvider: FakeAudioSampleProvider(sampleAfterPrepare: audioSample),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/longer-audio.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForAudioSampleCount(1, in: session)
    let audioRecord = try #require(session.debugSnapshot().lastAudioSample)
    #expect(audioRecord.rawStreamIndex == 1)
    #expect(audioRecord.sampleRate == 48_000)
    #expect(audioRecord.channelCount == 2)
    #expect(audioRecord.payloadOwnershipState == "retainedCMSampleBuffer")

    try await Task.sleep(for: .milliseconds(300))
    #expect(session.debugSnapshot().lifecycle != .ended)

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
          session.debugSnapshot().lifecycle != .ended {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.debugSnapshot().lifecycle == .ended)
}

@Test func endedUsesVideoPresentationEndWhenNoAudioIsSelected() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 0.05)
    let session = SampleBufferPlaybackSession(
        traceID: "video-only-end-session",
        provider: FakeVideoSampleProvider(events: [.sample(videoSample), .end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/video-only.mp4"))
    #expect(session.availableAudioTracks.isEmpty)
    try session.start()
    try await waitForSampleCount(1, in: session)

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
          session.debugSnapshot().lifecycle != .ended {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.debugSnapshot().lifecycle == .ended)
}

@Test func videoOnlySessionRetainsAudioRendererPreferencesInSnapshot() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "video-only-audio-preferences-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/video-only.mp4"))
    try session.setVolume(0.35)
    session.setMuted(true)

    let state = try #require(session.debugSnapshot().audioRendererState)
    #expect(state.graphID == "video-only-audio-preferences-session.rendererGraph")
    #expect(state.rendererIdentity == PlaybackTrace.identity(session.audioRenderer))
    #expect(state.videoRendererIdentity == PlaybackTrace.identity(session.renderer))
    #expect(state.synchronizerIdentity == PlaybackTrace.identity(session.synchronizer))
    #expect(state.enqueuedSampleBufferCount == 0)
    #expect(state.enqueuedAudioFrameCount == 0)
    #expect(state.volume == 0.35)
    #expect(state.muted)
}

@Test func firstAudioEnqueueEventPersistsTheUpdatedRendererState() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 5)
    let audioSample = try makeAudioSample(durationSeconds: 5)
    let session = SampleBufferPlaybackSession(
        traceID: "first-audio-enqueue-snapshot",
        provider: FakeVideoSampleProvider(events: [.sample(videoSample), .end]),
        audioProvider: FakeAudioSampleProvider(
            sampleAfterPrepare: audioSample,
            repeatsSample: false
        ),
        rendererSink: FakeRendererInputSink(automaticallyRunsRequests: false)
    )
    let recorder = PlaybackDebugRecorder(session: session, platform: "macOS")
    defer {
        recorder.stop()
        session.close()
        try? FileManager.default.removeItem(at: recorder.directoryURL)
    }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-snapshot.mp4"))
    try session.start()
    let deadline = ContinuousClock.now + .seconds(2)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var persisted: PlaybackDebugSnapshotV1?
    while ContinuousClock.now < deadline {
        if let data = try? Data(contentsOf: recorder.snapshotURL),
           let snapshot = try? decoder.decode(PlaybackDebugSnapshotV1.self, from: data),
           snapshot.audioRendererState?.enqueuedSampleBufferCount == 1 {
            persisted = snapshot
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let capturedSnapshot = try #require(persisted)
    #expect(capturedSnapshot.audioRendererState?.enqueuedSampleBufferCount == 1)
    #expect(capturedSnapshot.audioRendererState?.enqueuedAudioFrameCount == 240_000)
}

@Test func firstAudioSampleDiagnosticDetailsIncludeCompleteASBDAndStableHash() throws {
    let sample = try makeAudioSample(durationSeconds: 0.5)
    let session = SampleBufferPlaybackSession(traceID: "audio-format-diagnostics")
    defer { session.close() }

    let details = session.audioSampleFormatDetails(sample)

    #expect(details["asbd.sampleRate"] == "48000.0")
    #expect(details["asbd.channelsPerFrame"] == "2")
    #expect(details["asbd.bitsPerChannel"] == "32")
    #expect(details["asbd.reserved"] == "0")
    #expect(details["magicCookieSize"] == "0")
    #expect(details["magicCookieHash"] == "none")
    #expect(details["duration.value"] != nil)
    #expect(details["duration.timescale"] != nil)
}

@Test func audioPrerollsBeforeTimelineStartsAndResumeKeepsQueuedAudio() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 5)
    let audioSample = try makeAudioSample(durationSeconds: 0.5)
    let audioSink = FakeAudioRendererInputSink()
    var session: SampleBufferPlaybackSession!
    audioSink.rateProvider = { session.synchronizer.rate }
    session = SampleBufferPlaybackSession(
        traceID: "audio-preroll-session",
        provider: FakeVideoSampleProvider(events: [.sample(videoSample), .end]),
        audioProvider: FakeAudioSampleProvider(sampleAfterPrepare: audioSample),
        rendererSink: FakeRendererInputSink(),
        audioRendererSink: audioSink
    )
    defer { session.close() }
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-preroll.mp4"))
    try session.start()
    try await waitForAudioSampleCount(1, in: session)
    let playbackDeadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < playbackDeadline,
          session.synchronizer.rate != 1 {
        try await Task.sleep(for: .milliseconds(5))
    }
    while ContinuousClock.now < playbackDeadline,
          events.withLock({ events in
              !events.contains {
                  $0.kind == "audioRenderer.rateActivated"
                      && $0.details["reason"] == "decoderBootstrap"
              }
          }) {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(audioSink.ratesAtEnqueue == [0])
    #expect(session.synchronizer.rate == 1)
    let capturedEvents = events.withLock { $0 }
    let prerollIndex = try #require(
        capturedEvents.firstIndex { $0.kind == "audioRenderer.prerollCompleted" }
    )
    let activationIndex = try #require(
        capturedEvents.firstIndex {
            $0.kind == "audioRenderer.rateActivated"
                && $0.details["reason"] == "decoderBootstrap"
        }
    )
    #expect(prerollIndex < activationIndex)
    let activation = capturedEvents[activationIndex]
    #expect(activation.details["rate"] == "1.0")
    #expect(activation.details["timeSeconds"] == "0.0")
    #expect(activation.details["application"] == "setRateAtHostTime")
    #expect(activation.details["immediateActualRate"] != nil)
    #expect(activation.details["immediateCurrentTimeSeconds"] != nil)

    try session.pause()
    let flushCountBeforeResume = audioSink.flushCount
    try session.play()

    #expect(audioSink.flushCount == flushCountBeforeResume)
}

@Test func activationObservationPlanUsesOrderedBoundedSamplingPhases() {
    #expect(
        PlaybackActivationObservation.samplingPhases == [
            PlaybackActivationObservationPhase(
                phase: "call.before",
                delayMilliseconds: 0
            ),
            PlaybackActivationObservationPhase(
                phase: "call.returned",
                delayMilliseconds: 0
            ),
            PlaybackActivationObservationPhase(
                phase: "scheduledSample",
                delayMilliseconds: 10
            ),
            PlaybackActivationObservationPhase(
                phase: "scheduledSample",
                delayMilliseconds: 50
            ),
            PlaybackActivationObservationPhase(
                phase: "scheduledSample",
                delayMilliseconds: 100
            ),
            PlaybackActivationObservationPhase(
                phase: "scheduledSample",
                delayMilliseconds: 500
            ),
            PlaybackActivationObservationPhase(
                phase: "scheduledSample",
                delayMilliseconds: 2_000
            ),
        ]
    )
    #expect(PlaybackActivationObservation.delayedTaskMarkerPhases == [
        "delayedTask.enter",
        "delayedTask.sleepReturned",
        "delayedTask.beforeStateRead",
    ])
}

@Test func activationObservationUnregistersNotificationCallbacks() throws {
    let session = SampleBufferPlaybackSession(traceID: "activation-observer-unregister")
    defer { session.close() }
    let center = NotificationCenter()
    let observation = PlaybackActivationObservation(
        session: session,
        notificationCenter: center
    )
    observation.start()
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }
    _ = try #require(observation.beginActivation(requestedRate: 1, anchorTime: .zero))

    center.post(
        name: AVSampleBufferRenderSynchronizer.rateDidChangeNotification,
        object: session.synchronizer
    )
    observation.stop()
    center.post(
        name: AVSampleBufferRenderSynchronizer.rateDidChangeNotification,
        object: session.synchronizer
    )

    let notificationEvents = events.withLock { events in
        events.filter {
            $0.kind == "playbackActivation.observation"
                && $0.details["phase"] == "notification.synchronizerRateDidChange"
        }
    }
    #expect(notificationEvents.count == 1)
}

@Test func activationObservationRejectsOldActivationAfterEpochChange() throws {
    let session = SampleBufferPlaybackSession(traceID: "activation-observer-epoch")
    defer { session.close() }
    let center = NotificationCenter()
    let observation = PlaybackActivationObservation(
        session: session,
        notificationCenter: center
    )
    observation.start()
    defer { observation.stop() }
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }
    let sequence = try #require(
        observation.beginActivation(requestedRate: 1, anchorTime: .zero)
    )

    session.streamEpoch &+= 1
    session.audioStreamEpoch &+= 1
    #expect(observation.recordStageMarkerIfCurrent(
        sequence: sequence,
        phase: "delayedTask.beforeStateRead",
        delayMilliseconds: 500
    ) == false)
    observation.recordScheduledSample(sequence: sequence, delayMilliseconds: 500)
    observation.recordScheduledSample(sequence: sequence, delayMilliseconds: 2_000)
    center.post(
        name: AVSampleBufferRenderSynchronizer.rateDidChangeNotification,
        object: session.synchronizer
    )

    let oldActivationEvents = events.withLock { events in
        events.filter {
            $0.kind == "playbackActivation.observation"
                && ($0.details["phase"] == "scheduledSample"
                    || $0.details["phase"] == "notification.synchronizerRateDidChange")
        }
    }
    #expect(oldActivationEvents.isEmpty)
    #expect(events.withLock { events in
        events.contains { $0.kind == "playbackActivation.stageMarker" }
    } == false)
}

@Test func activationStageMarkerDoesNotWriteAfterObservationStops() throws {
    let session = SampleBufferPlaybackSession(traceID: "activation-stage-stop")
    defer { session.close() }
    let observation = PlaybackActivationObservation(
        session: session,
        notificationCenter: NotificationCenter()
    )
    observation.start()
    let sequence = try #require(
        observation.beginActivation(requestedRate: 1, anchorTime: .zero)
    )
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }

    observation.stop()

    #expect(observation.recordStageMarkerIfCurrent(
        sequence: sequence,
        phase: "delayedTask.beforeStateRead",
        delayMilliseconds: 2_000
    ) == false)
    #expect(events.withLock { events in
        events.contains { $0.kind == "playbackActivation.stageMarker" }
    } == false)
}

@Test func activationObservationRecordsRuntimePolicyAndCurrentEpochCoverage() throws {
    let session = SampleBufferPlaybackSession(traceID: "activation-observer-coverage")
    defer { session.close() }
    let observation = PlaybackActivationObservation(session: session)
    defer { observation.stop() }
    let events = LockedBox<[PlaybackDebugEvent]>([])
    let observerID = session.debugStore.addEventObserver { event in
        events.withLock { $0.append(event) }
    }
    defer { session.debugStore.removeEventObserver(observerID) }
    observation.recordAcceptedVideo(
        epoch: session.streamEpoch,
        presentationTime: CMTime(value: 12, timescale: 10),
        decodeTime: CMTime(value: 10, timescale: 10),
        presentationEnd: CMTime(value: 13, timescale: 10)
    )
    observation.recordAcceptedVideo(
        epoch: session.streamEpoch,
        presentationTime: CMTime(value: 8, timescale: 10),
        decodeTime: CMTime(value: 6, timescale: 10),
        presentationEnd: CMTime(value: 9, timescale: 10)
    )
    _ = try #require(observation.beginActivation(requestedRate: 1, anchorTime: .zero))

    let event = try #require(events.withLock { events in
        events.last { event in
            event.kind == "playbackActivation.observation"
                && event.details["phase"] == "call.before"
        }
    })
    #expect(event.details["delaysRateChangeUntilHasSufficientMediaData"] == "false")
    #expect(event.details["videoAcceptedMinPTSSeconds"] == "0.8")
    #expect(event.details["videoAcceptedMaxPTSSeconds"] == "1.2")
    #expect(event.details["videoAcceptedMinDTSSeconds"] == "0.6")
    #expect(event.details["videoAcceptedMaxDTSSeconds"] == "1.0")
    #expect(event.details["videoAcceptedMaxEndSeconds"] == "1.3")
    #expect(event.details["videoAcceptedCount"] == "2")
}

@Test func audioOpenFailureIsNotClassifiedByMessageText() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "audio-open-error-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        audioProvider: FailingAudioOpenProvider(),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    do {
        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-error.mp4"))
        Issue.record("Expected audio open failure to propagate")
    } catch MisleadingAudioOpenError.failed {
    } catch {
        Issue.record("Expected MisleadingAudioOpenError.failed, got \(error)")
    }
}

@Test func failedAudioTrackSelectionPreservesActiveTrackAndPlaybackState() async throws {
    let audioSample = try makeAudioSample(durationSeconds: 5)
    let audio = FakeAudioSampleProvider(
        failingStreamIndex: 2,
        sampleAfterPrepare: audioSample
    )
    let sample = try makeCompressedH264Sample(durationSeconds: 10)
    let session = SampleBufferPlaybackSession(
        traceID: "failed-audio-selection-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        audioProvider: audio,
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/two-audio.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForAudioSampleCount(1, in: session)
    try await setRateWhenTimelineIsReady(1.5, in: session)

    do {
        try await session.selectAudioTrack(streamIndex: 2)
        Issue.record("Expected replacement audio track preparation to fail")
    } catch FakeSampleError.audioPrepare {
    } catch {
        Issue.record("Expected audioPrepare, got \(error)")
    }

    try await waitForAudioSampleCount(2, in: session)
    let snapshot = session.debugSnapshot()
    #expect(session.selectedAudioStreamIndex == 1)
    #expect(audio.info?.streamIndex == 1)
    #expect(session.currentRate() == 1.5)
    #expect(snapshot.mediaSession?.lifecycle == .playing)
    #expect(snapshot.audioTrack?.rawStreamIndex == 1)
}

@Test(arguments: [RendererFailureKind.video, .audio])
func terminalRendererFailurePublishesFailedOnce(
    _ rendererKind: RendererFailureKind
) async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 5)
    let audioSample = try makeAudioSample(durationSeconds: 5)
    let sink = FakeRendererInputSink()
    let monitor = FakeRendererFailureMonitor()
    let session = SampleBufferPlaybackSession(
        traceID: "\(rendererKind.rawValue)-renderer-failure-session",
        provider: FakeVideoSampleProvider(events: [.sample(videoSample), .end]),
        audioProvider: FakeAudioSampleProvider(sampleAfterPrepare: audioSample),
        rendererSink: sink,
        rendererFailureMonitor: monitor
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/renderer-failure.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForAudioSampleCount(1, in: session)
    try await setRateWhenTimelineIsReady(1, in: session)
    let requiresFlush = rendererKind == .video ? true : nil
    let fact = RendererFailureFact(
        rendererKind: rendererKind,
        errorType: "Injected\(rendererKind.rawValue.capitalized)RendererError",
        message: "Injected \(rendererKind.rawValue) renderer failure",
        requiresFlushToResumeDecoding: requiresFlush
    )

    monitor.send(fact)
    monitor.send(fact)

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
          session.debugSnapshot().lifecycle != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(50))

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lifecycle == .failed)
    #expect(snapshot.lastFailure?.stage == "\(rendererKind.rawValue)Renderer.failed")
    #expect(snapshot.lastFailure?.rendererKind == rendererKind.rawValue)
    #expect(snapshot.lastFailure?.errorType == fact.errorType)
    #expect(snapshot.lastFailure?.message == fact.message)
    #expect(snapshot.lastFailure?.requiresFlushToResumeDecoding == requiresFlush)
    #expect(session.synchronizer.rate == 0)
    #expect(statuses.withLock { values in
        values.filter {
            if case .failed = $0 { true } else { false }
        }.count
    } == 1)
}

@Test func receiverDecodeWarningsAcceptTheVideoSample() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 5)
    let sink = FakeRendererInputSink(
        enqueueOutcomes: [.acceptedWithWarnings(["Injected decode warning"])]
    )
    let session = SampleBufferPlaybackSession(
        traceID: "receiver-warning-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/receiver-warning.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lifecycle != .failed)
    #expect(snapshot.lastFailure == nil)
    #expect(snapshot.rendererState?.rendererStatus == "readyWithDecodeFailures")
    #expect(snapshot.rendererState?.rendererError == "Injected decode warning")
}

@Test func receiverFlushCancellationDoesNotAcceptOrFailTheVideoSample() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 5)
    let sink = FakeRendererInputSink(enqueueOutcomes: [.cancelledByFlush])
    let session = SampleBufferPlaybackSession(
        traceID: "receiver-flush-cancellation-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/receiver-flush.mp4"))
    try session.start()
    try await waitForSinkSampleCount(1, in: sink)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.sampleCount == 0)
    #expect(snapshot.lifecycle != .failed)
    #expect(snapshot.lastFailure == nil)
}

@Test func receiverRequiresFlushPublishesTerminalVideoFailure() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 5)
    let sink = FakeRendererInputSink(
        enqueueOutcomes: [.requiresFlush("Injected flush requirement")]
    )
    let session = SampleBufferPlaybackSession(
        traceID: "receiver-requires-flush-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/receiver-requires-flush.mp4"))
    try session.start()
    try await waitForLifecycle(.failed, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lastFailure?.rendererKind == RendererFailureKind.video.rawValue)
    #expect(snapshot.lastFailure?.message == "Injected flush requirement")
    #expect(snapshot.lastFailure?.requiresFlushToResumeDecoding == true)
}

@Test
func providerOpenContractRecordsTheActiveProvider() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "provider-open",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/movie.mov"))
    let snapshot = session.debugSnapshot()
    #expect(snapshot.providerOpen?.providerKind == "Fake")
    #expect(snapshot.providerOpen?.openStatus == "opened")
    #expect(snapshot.videoTrack?.selected == true)
}

@Test
func repeatedSessionStartDoesNotRestartThePreparedProvider() async throws {
    let provider = FakeVideoSampleProvider(events: [.end])
    let session = SampleBufferPlaybackSession(
        traceID: "idempotent-session-start",
        provider: provider,
        rendererSink: FakeRendererInputSink(automaticallyRunsRequests: false)
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/idempotent-start.mov"))
    try session.start()
    try session.start()

    #expect(provider.startCount == 1)
}

enum FailedCleanupRecovery: CaseIterable {
    case open
    case reopen
}

private func fixtureSource(_ name: String) -> MediaSourceRecord {
    MediaSourceRecord(
        locator: URL(fileURLWithPath: "/fixtures/\(name)"),
        provenance: "testAutomation",
        privacySafeSummary: name,
        accessRequirement: "notRequired"
    )
}

private final class FakeVideoSampleProvider: VideoSampleProvider {
    let info: VideoSampleProviderInfo

    private var events: [VideoSampleProviderEvent]
    private var index = 0
    private let seekPrepareDelay: Duration?
    private let seekPrepareIgnoresCancellation: Bool
    private let readError: Error?
    private let eventDelay: Duration?
    private(set) var startCount = 0

    init(
        events: [VideoSampleProviderEvent],
        seekPrepareDelay: Duration? = nil,
        seekPrepareIgnoresCancellation: Bool = false,
        readError: Error? = nil,
        eventDelay: Duration? = nil,
        projectionKind: String? = nil
    ) {
        info = VideoSampleProviderInfo(
            providerKind: "Fake",
            containerFormat: "fixture",
            durationSeconds: 1,
            nominalFrameRate: 30,
            codecName: "fake",
            codecTag: "fake",
            dimensions: "64x64",
            colorPrimaries: "ITU_R_2020",
            transferFunction: "SMPTE_ST_2084_PQ",
            yCbCrMatrix: "ITU_R_2020",
            range: "video",
            seekability: .init(known: "providerRebuild"),
            selectedRawTrackMapping: .init(known: "fake.video.0"),
            timebase: .init(known: "1/600"),
            codecConfigurationSummary: .init(.none),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "fakeProvider",
                colorPrimaries: .init(known: "ITU_R_2020"),
                transferFunction: .init(known: "SMPTE_ST_2084_PQ"),
                yCbCrMatrix: .init(known: "ITU_R_2020"),
                range: .init(known: "video"),
                projectionKind: projectionKind.map {
                    .init(known: $0)
                } ?? .init(.notExposed)
            )
        )
        self.events = events
        self.seekPrepareDelay = seekPrepareDelay
        self.seekPrepareIgnoresCancellation = seekPrepareIgnoresCancellation
        self.readError = readError
        self.eventDelay = eventDelay
    }

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {
        if startTime > .zero, let seekPrepareDelay {
            if seekPrepareIgnoresCancellation {
                await Task.detached {
                    try? await Task.sleep(for: seekPrepareDelay)
                }.value
            } else {
                try await Task.sleep(for: seekPrepareDelay)
            }
        }
        index = 0
    }

    func start() throws { startCount += 1 }

    func nextEvent() async throws -> VideoSampleProviderEvent {
        if let readError { throw readError }
        if let eventDelay {
            try await Task.sleep(for: eventDelay)
        }
        guard index < events.count else { return .end }
        defer { index += 1 }
        return events[index]
    }

    func cancel() {}
}

private final class FakeRendererInputSink: RendererInputSink, @unchecked Sendable {
    private let lock = NSLock()
    let enqueueStrategy: RendererEnqueueStrategy
    private let completesFlushImmediately: Bool
    private let pausesAfterEachEnqueue: Bool
    private let automaticallyRunsRequests: Bool
    private var samples: [CMSampleBuffer] = []
    private var rendererFlushCount = 0
    private var pendingFlushContinuations: [CheckedContinuation<Void, Never>] = []
    private var availableFlushCompletions = 0
    private var waitingEnqueueCount = 0
    private var availableEnqueuePermits: Int
    private var enqueueOutcomes: [RendererEnqueueOutcome]
    private var cancelledEnqueueCount = 0
    private var immediateEnqueueCounter = 0
    private var eventObservationCount = 0
    private var eventObservationStartedWithoutSample = false

    init(
        enqueueStrategy: RendererEnqueueStrategy = .receiverBackpressure,
        completesFlushImmediately: Bool = true,
        pausesAfterEachEnqueue: Bool = false,
        automaticallyRunsRequests: Bool = true,
        enqueueOutcomes: [RendererEnqueueOutcome] = []
    ) {
        self.enqueueStrategy = enqueueStrategy
        self.completesFlushImmediately = completesFlushImmediately
        self.pausesAfterEachEnqueue = pausesAfterEachEnqueue
        self.automaticallyRunsRequests = automaticallyRunsRequests
        self.enqueueOutcomes = enqueueOutcomes
        availableEnqueuePermits = automaticallyRunsRequests && pausesAfterEachEnqueue ? 1 : 0
    }

    var recommendedPixelBufferAttributes: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
        ]
    }

    var enqueuedSampleCount: Int {
        lock.withLock { samples.count }
    }

    var lastEnqueuedSample: CMSampleBuffer? {
        lock.withLock { samples.last }
    }

    var flushCount: Int {
        lock.withLock { rendererFlushCount }
    }

    var pendingRequestCount: Int {
        lock.withLock { waitingEnqueueCount }
    }

    var cancelledRequestCount: Int {
        lock.withLock { cancelledEnqueueCount }
    }

    var immediateEnqueueCount: Int {
        lock.withLock { immediateEnqueueCounter }
    }

    var renderingEventObservationCount: Int {
        lock.withLock { eventObservationCount }
    }

    var startedRenderingEventObservationBeforeFirstEnqueue: Bool {
        lock.withLock { eventObservationStartedWithoutSample }
    }

    func enqueueImmediately(
        _ input: RendererInputSample
    ) throws -> RendererEnqueueOutcome {
        lock.withLock {
            immediateEnqueueCounter += 1
            samples.append(input.sampleBuffer)
            guard !enqueueOutcomes.isEmpty else { return .accepted }
            return enqueueOutcomes.removeFirst()
        }
    }

    func enqueue(
        _ input: RendererInputSample
    ) async throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !automaticallyRunsRequests || pausesAfterEachEnqueue {
            lock.withLock { waitingEnqueueCount += 1 }
            defer {
                lock.withLock {
                    waitingEnqueueCount -= 1
                    if Task.isCancelled {
                        cancelledEnqueueCount += 1
                    }
                }
            }
            while true {
                try Task.checkCancellation()
                let acquiredPermit = lock.withLock {
                    guard availableEnqueuePermits > 0 else { return false }
                    availableEnqueuePermits -= 1
                    return true
                }
                if acquiredPermit { break }
                if automaticallyRunsRequests {
                    try await Task.sleep(for: .milliseconds(25))
                    lock.withLock { availableEnqueuePermits += 1 }
                } else {
                    try await Task.sleep(for: .milliseconds(1))
                }
            }
        }
        return lock.withLock {
            samples.append(sample)
            guard !enqueueOutcomes.isEmpty else { return .accepted }
            return enqueueOutcomes.removeFirst()
        }
    }

    func flush(removingDisplayedImage: Bool) async {
        let waitsForCompletion = lock.withLock {
            samples.removeAll()
            rendererFlushCount += 1
            return !completesFlushImmediately
        }
        guard waitsForCompletion else { return }
        await withCheckedContinuation { continuation in
            let completesImmediately = lock.withLock {
                guard availableFlushCompletions > 0 else {
                    pendingFlushContinuations.append(continuation)
                    return false
                }
                availableFlushCompletions -= 1
                return true
            }
            if completesImmediately { continuation.resume() }
        }
    }

    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {
        lock.withLock {
            eventObservationCount += 1
            if samples.isEmpty {
                eventObservationStartedWithoutSample = true
            }
        }
    }

    func completePendingFlushes() {
        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard !pendingFlushContinuations.isEmpty else {
                availableFlushCompletions += 1
                return []
            }
            let continuations = pendingFlushContinuations
            pendingFlushContinuations.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume() }
    }

    func runNextPendingRequest() {
        lock.withLock {
            availableEnqueuePermits += 1
        }
    }
}

private final class FakeRendererFailureMonitor: RendererFailureMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (RendererFailureFact) -> Void)?

    func start(handler: @escaping @Sendable (RendererFailureFact) -> Void) {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock { handler = nil }
    }

    func send(_ fact: RendererFailureFact) {
        let currentHandler = lock.withLock { handler }
        currentHandler?(fact)
    }
}

private final class FakeAudioSampleProvider: AudioSampleProvider {
    private(set) var info: AudioSampleProviderInfo?
    private(set) var preparedStreamIndices: [Int?] = []
    private let failingStreamIndex: Int?
    private let sampleAfterPrepare: CMSampleBuffer?
    private let repeatsSample: Bool
    private var nextSample: CMSampleBuffer?

    init(
        failingStreamIndex: Int? = nil,
        sampleAfterPrepare: CMSampleBuffer? = nil,
        repeatsSample: Bool = false
    ) {
        self.failingStreamIndex = failingStreamIndex
        self.sampleAfterPrepare = sampleAfterPrepare
        self.repeatsSample = repeatsSample
    }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        [
            PlaybackAudioTrack(
                streamIndex: 1, codecName: "aac", sampleRate: 48_000,
                channelCount: 2, language: "eng", title: "English"
            ),
            PlaybackAudioTrack(
                streamIndex: 2, codecName: "aac", sampleRate: 48_000,
                channelCount: 2, language: "jpn", title: "Japanese"
            ),
        ]
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
        preparedStreamIndices.append(streamIndex)
        let selected = streamIndex ?? 1
        if selected == failingStreamIndex {
            throw FakeSampleError.audioPrepare
        }
        info = AudioSampleProviderInfo(
            providerKind: "FakeAudio", streamIndex: selected, codecName: "aac",
            sampleRate: 48_000, channelCount: 2
        )
        nextSample = sampleAfterPrepare
    }

    func copyNextSample() async throws -> CMSampleBuffer? {
        let sample = nextSample
        if !repeatsSample { nextSample = nil }
        return sample
    }

    func cancel() {
        info = nil
        nextSample = nil
    }
}

private final class FakeAudioRendererInputSink: AudioRendererInputSink, @unchecked Sendable {
    let enqueueStrategy: RendererEnqueueStrategy = .receiverBackpressure
    var rateProvider: (() -> Float)?

    private let lock = NSLock()
    private var enqueueRates: [Float] = []
    private var rendererFlushCount = 0

    var ratesAtEnqueue: [Float] {
        lock.withLock { enqueueRates }
    }

    var flushCount: Int {
        lock.withLock { rendererFlushCount }
    }

    func enqueueImmediately(
        _ sample: RendererInputSample
    ) throws -> RendererEnqueueOutcome {
        recordEnqueue()
        return .accepted
    }

    func enqueue(
        _ sample: RendererInputSample
    ) async throws -> RendererEnqueueOutcome {
        recordEnqueue()
        return .accepted
    }

    func flush() {
        lock.withLock { rendererFlushCount += 1 }
    }

    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {}

    func stopRenderingEventObservation() {}

    private func recordEnqueue() {
        let rate = rateProvider?() ?? -.infinity
        lock.withLock { enqueueRates.append(rate) }
    }
}

private final class FailingAudioOpenProvider: AudioSampleProvider {
    var info: AudioSampleProviderInfo? { nil }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        [
            PlaybackAudioTrack(
                streamIndex: 1, codecName: "aac", sampleRate: 0,
                channelCount: 0, language: nil, title: nil
            ),
        ]
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
        throw MisleadingAudioOpenError.failed
    }

    func copyNextSample() async throws -> CMSampleBuffer? { nil }
    func cancel() {}
}

private enum MisleadingAudioOpenError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Decoder failed after no audio stream probe"
    }
}

private func makeCompressedH264Sample(
    presentationTimeSeconds: Double = 0,
    decodeTimeSeconds: Double? = nil,
    durationSeconds: Double = 1.0 / 30.0,
    projectionKind: CFString? = nil
) throws -> CMSampleBuffer {
    let sequenceParameterSet: [UInt8] = [
        0x67, 0x64, 0x00, 0x1e, 0xac, 0xd9, 0x40, 0xa0,
        0x2f, 0xf9, 0x70, 0x11, 0x00, 0x00, 0x03, 0x00,
        0x01, 0x00, 0x00, 0x03, 0x00, 0x3c, 0x0f, 0x16,
        0x2d, 0x96,
    ]
    let pictureParameterSet: [UInt8] = [0x68, 0xeb, 0xe3, 0xcb, 0x22, 0xc0]
    var formatDescription: CMFormatDescription?
    var status = sequenceParameterSet.withUnsafeBufferPointer { sequencePointer in
        pictureParameterSet.withUnsafeBufferPointer { picturePointer in
            let pointers = [sequencePointer.baseAddress!, picturePointer.baseAddress!]
            let sizes = [sequencePointer.count, picturePointer.count]
            return pointers.withUnsafeBufferPointer { pointerBuffer in
                sizes.withUnsafeBufferPointer { sizeBuffer in
                    CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: pointerBuffer.count,
                        parameterSetPointers: pointerBuffer.baseAddress!,
                        parameterSetSizes: sizeBuffer.baseAddress!,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &formatDescription
                    )
                }
            }
        }
    }
    guard status == noErr, let baseFormatDescription = formatDescription else {
        throw FakeSampleError.sampleBuffer(status)
    }

    let effectiveFormatDescription: CMFormatDescription
    if let projectionKind {
        var extensions = CMFormatDescriptionGetExtensions(baseFormatDescription) as? [String: Any]
            ?? [:]
        extensions[kCMFormatDescriptionExtension_ProjectionKind as String] = projectionKind
        extensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] = 360_000
        let dimensions = CMVideoFormatDescriptionGetDimensions(baseFormatDescription)
        var projectedFormat: CMFormatDescription?
        status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: CMFormatDescriptionGetMediaSubType(baseFormatDescription),
            width: dimensions.width,
            height: dimensions.height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &projectedFormat
        )
        guard status == noErr, let projectedFormat else {
            throw FakeSampleError.sampleBuffer(status)
        }
        effectiveFormatDescription = projectedFormat
    } else {
        effectiveFormatDescription = baseFormatDescription
    }

    let idrNALUnit: [UInt8] = [0x65, 0x88, 0x84, 0x00, 0x0a, 0xf2, 0x62, 0x80]
    let bigEndianLength = UInt32(idrNALUnit.count).bigEndian
    var payload = withUnsafeBytes(of: bigEndianLength) { Array($0) }
    payload.append(contentsOf: idrNALUnit)

    var blockBuffer: CMBlockBuffer?
    status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: payload.count,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: payload.count,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard status == noErr, let blockBuffer else {
        throw FakeSampleError.sampleBuffer(status)
    }
    status = payload.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: payload.count
        )
    }
    guard status == noErr else {
        throw FakeSampleError.sampleBuffer(status)
    }

    let timestamp = CMTime(
        seconds: presentationTimeSeconds,
        preferredTimescale: 600
    )
    var timing = CMSampleTimingInfo(
        duration: CMTime(seconds: durationSeconds, preferredTimescale: 60_000),
        presentationTimeStamp: timestamp,
        decodeTimeStamp: CMTime(
            seconds: decodeTimeSeconds ?? presentationTimeSeconds,
            preferredTimescale: 600
        )
    )
    var sampleSize = payload.count
    var sample: CMSampleBuffer?
    status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: effectiveFormatDescription,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
        sampleBufferOut: &sample
    )
    guard status == noErr, let sample else {
        throw FakeSampleError.sampleBuffer(status)
    }
    return sample
}

private func makeMarkerOnlySample(presentationTimeSeconds: Double) throws -> CMSampleBuffer {
    var marker: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: CMTime(seconds: presentationTimeSeconds, preferredTimescale: 600),
        decodeTimeStamp: .invalid
    )
    let status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: nil,
        formatDescription: nil,
        sampleCount: 0,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &marker
    )
    guard status == noErr, let marker else {
        throw FakeSampleError.sampleBuffer(status)
    }
    return marker
}

private func expectCompressedH264Contract(_ sample: CMSampleBuffer) throws {
    #expect(CMSampleBufferGetImageBuffer(sample) == nil)
    #expect(CMSampleBufferDataIsReady(sample))
    #expect(CMSampleBufferGetNumSamples(sample) == 1)
    let dataBuffer = try #require(CMSampleBufferGetDataBuffer(sample))
    #expect(CMBlockBufferGetDataLength(dataBuffer) > 0)
    let formatDescription = try #require(CMSampleBufferGetFormatDescription(sample))
    #expect(CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Video)
    #expect(CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_H264)
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    #expect(dimensions.width == 640)
    #expect(dimensions.height == 360)
}

private func makeAudioSample(durationSeconds: Double) throws -> CMSampleBuffer {
    let sampleRate = 48_000
    let channelCount = 2
    let frameCount = Int((Double(sampleRate) * durationSeconds).rounded())
    let bytesPerFrame = channelCount * MemoryLayout<Float>.size
    let byteCount = frameCount * bytesPerFrame
    var formatDescription: CMAudioFormatDescription?
    var streamDescription = AudioStreamBasicDescription(
        mSampleRate: Double(sampleRate),
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(bytesPerFrame),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(bytesPerFrame),
        mChannelsPerFrame: UInt32(channelCount),
        mBitsPerChannel: 32,
        mReserved: 0
    )
    var status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &streamDescription,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard status == noErr, let formatDescription else {
        throw FakeSampleError.sampleBuffer(status)
    }

    var blockBuffer: CMBlockBuffer?
    status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard status == noErr, let blockBuffer else {
        throw FakeSampleError.sampleBuffer(status)
    }
    let silence = Data(count: byteCount)
    status = silence.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
    }
    guard status == noErr else {
        throw FakeSampleError.sampleBuffer(status)
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
        presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    status = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDescription,
        sampleCount: frameCount,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sample
    )
    guard status == noErr, let sample else {
        throw FakeSampleError.sampleBuffer(status)
    }
    return sample
}

private func waitForSampleCount(
    _ count: UInt64,
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if session.debugSnapshot().sampleCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for sample count \(count)")
}

private func waitForSinkSampleCount(
    _ count: Int,
    in sink: FakeRendererInputSink
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if sink.enqueuedSampleCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for renderer sink sample count \(count)")
}

private func waitForLifecycle(
    _ lifecycle: PlaybackLifecycle,
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if session.debugSnapshot().lifecycle == lifecycle { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for lifecycle \(lifecycle.rawValue)")
}

private func waitForPendingRequestCount(
    _ count: Int,
    in sink: FakeRendererInputSink
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if sink.pendingRequestCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for pending renderer request count \(count)")
}

private func waitForCancelledRequestCount(
    _ count: Int,
    in sink: FakeRendererInputSink
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if sink.cancelledRequestCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for cancelled renderer request count \(count)")
}

private func waitForFlushCount(
    _ count: Int,
    in sink: FakeRendererInputSink
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if sink.flushCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for renderer flush count \(count)")
}

private func waitForFlag(
    _ flag: LockedBox<Bool>,
    description: String
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if flag.withLock({ $0 }) { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for \(description)")
}

private func waitForAudioSampleCount(
    _ count: UInt64,
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if session.debugSnapshot().audioSampleBufferCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for audio sample count \(count)")
}

private func setRateWhenTimelineIsReady(
    _ rate: Float,
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        do {
            try session.setRate(rate)
            return
        } catch PlaybackControlError.timelineNotReady {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    Issue.record("Timed out waiting for renderer timeline")
}

private enum FakeSampleError: Error {
    case pixelBuffer(CVReturn)
    case sampleBuffer(OSStatus)
    case providerRead
    case audioPrepare
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
