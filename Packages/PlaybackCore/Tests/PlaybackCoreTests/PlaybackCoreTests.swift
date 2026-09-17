import Foundation
import AVFoundation
import CoreVideo
import PlaybackFFmpegBridge
import Testing
@testable import PlaybackCore

private let playbackCoreTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")

@Test func mediaSourceKindComesFromTheCompleteStreamCatalog() {
    func information(_ categories: [MediaSourceStreamCategory]) -> MediaSourceInformation {
        MediaSourceInformation(
            containerFormat: "fixture",
            durationSeconds: 1,
            streams: categories.enumerated().map { index, category in
                MediaSourceStreamInformation(
                    streamIndex: index,
                    category: category,
                    codecID: 0,
                    codecName: "fixture",
                    codecTag: 0,
                    language: nil,
                    title: nil,
                    disposition: 0,
                    video: nil,
                    audio: nil
                )
            }
        )
    }

    #expect(information([.audio]).playbackMediaKind == .audioOnly)
    #expect(information([.audio, .video]).playbackMediaKind == .video)
    #expect(information([.subtitle]).playbackMediaKind == .unsupported)
}

@Test func avFoundationAssetOptionsDeclareVideoMP4OnlyForTheMovFamily() {
    let movFamily = MediaSourceInformation(
        containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
        durationSeconds: 1,
        streams: [],
        containerSupportsSourceFormatDescription: true
    )
    let matroska = MediaSourceInformation(
        containerFormat: "matroska,webm",
        durationSeconds: 1,
        streams: [],
        containerSupportsSourceFormatDescription: false
    )

    let movOptions = FFmpegSampleProvider.avFoundationAssetOptions(for: movFamily)
    #expect(movOptions[AVURLAssetOverrideMIMETypeKey] as? String == "video/mp4")
    #expect(FFmpegSampleProvider.avFoundationAssetOptions(for: matroska).isEmpty)
    #expect(FFmpegSampleProvider.avFoundationAssetOptions(for: nil).isEmpty)
}

@Test func audioSpectrumAnalyzerDistinguishesSignalFromSilence() {
    let silence = AudioSpectrumAnalyzer.analyze(Array(repeating: 0, count: 256))
    let sine = (0..<256).map { index in
        Float(sin(2 * Double.pi * 0.08 * Double(index)))
    }
    let signal = AudioSpectrumAnalyzer.analyze(sine)

    #expect(silence.allSatisfy { $0 == 0 })
    #expect(signal.max() ?? 0 > 0.25)
    #expect(signal.count == AudioSpectrumAnalyzer.bandCount)
}

@MainActor
@Test func audioRendererAllowsMonoStereoAndMultichannelSpatialization() {
    let session = SampleBufferPlaybackSession(
        traceID: "multichannel-spatialization",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    #expect(
        session.audioRenderer.allowedAudioSpatializationFormats
            == .monoStereoAndMultichannel
    )
}

@Test func ffmpegSourceLocatorPreservesRemoteSchemeHostAndCredentials() throws {
    let remote = try #require(URL(string: "http://user:pass@example.test:5244/dav/video.mkv"))
    #expect(
        FFmpegSourceLocator.argument(for: remote)
            == "http://user:pass@example.test:5244/dav/video.mkv"
    )

    let local = URL(fileURLWithPath: "/tmp/video.mkv")
    #expect(FFmpegSourceLocator.argument(for: local) == "/tmp/video.mkv")
}

@Test func prepareSharesOneMediaSourceInformationValueWithTrackProviders() async throws {
    let information = MediaSourceInformation(
        containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
        durationSeconds: 42,
        streams: [
            MediaSourceStreamInformation(
                streamIndex: 0,
                category: .video,
                codecID: 173,
                codecName: "hevc",
                codecTag: 0x31637668,
                language: nil,
                title: "Main",
                disposition: 1,
                video: MediaSourceVideoInformation(
                    width: 8_192,
                    height: 4_096,
                    nominalFrameRate: 30,
                    colorPrimaries: "bt2020",
                    transferFunction: "smpte2084",
                    yCbCrMatrix: "bt2020nc",
                    colorRange: "tv",
                    projectionKind: "equirectangular"
                ),
                audio: nil
            ),
            MediaSourceStreamInformation(
                streamIndex: 1,
                category: .audio,
                codecID: 86018,
                codecName: "aac",
                codecTag: 0x6134706D,
                language: "eng",
                title: "English",
                disposition: 1,
                video: nil,
                audio: MediaSourceAudioInformation(
                    sampleRate: 48_000,
                    channelCount: 2
                )
            ),
            MediaSourceStreamInformation(
                streamIndex: 2,
                category: .subtitle,
                codecID: 94213,
                codecName: "mov_text",
                codecTag: 0x74786574,
                language: "zho",
                title: "简体中文",
                disposition: 0,
                video: nil,
                audio: nil
            ),
        ]
    )
    let persisted = try JSONEncoder().encode(information)
    #expect(
        try JSONDecoder().decode(MediaSourceInformation.self, from: persisted)
            == information
    )
    let loader = FixedMediaSourceInformationLoader(information)
    let videoProvider = FakeVideoSampleProvider(events: [.end])
    let audioProvider = FakeAudioSampleProvider()
    let subtitleProvider = MediaInformationRecordingSubtitleProvider()
    let session = SampleBufferPlaybackSession(
        traceID: "shared-media-source-information",
        provider: videoProvider,
        audioProvider: audioProvider,
        subtitleProvider: subtitleProvider,
        mediaSourceInformationLoader: loader,
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/source.mp4"),
        startsPaused: true
    )

    #expect(loader.loadCount == 1)
    #expect(videoProvider.sourceInformationReceived == information)
    #expect(audioProvider.sourceInformationReceived == information)
    #expect(subtitleProvider.sourceInformationReceived == information)
}

@MainActor
@Test func everySnapshotCarriesTheFFmpegBuildItWasProducedBy() async throws {
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in
            SampleBufferPlaybackSession(
                traceID: sessionID,
                provider: FakeVideoSampleProvider(events: [.end]),
                rendererSink: FakeRendererInputSink()
            )
        },
        debugRecorderMode: .disabledForVerification
    )
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/build-configuration.mov")
    )
    defer { session.close() }

    let configuration = try #require(
        session.debugSnapshot().ffmpegBuildConfiguration
    )
    #expect(
        configuration.contains("--enable-zlib"),
        Comment(rawValue: "the snapshot's build says nothing about uncompressing Matroska tracks: \(configuration)")
    )
}

@Test func aSubtitleTrackThatDecodesToNothingSaysSoInItsOutcome() async throws {
    let track = PlaybackSubtitleTrack(
        id: "stub.subtitle.1",
        streamIndex: 1,
        codecName: "hdmv_pgs_subtitle",
        language: "eng",
        title: "English"
    )
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-outcome-produced-nothing",
        provider: FakeVideoSampleProvider(events: [.end]),
        subtitleProvider: StubSubtitleProvider(
            tracks: [track],
            renderer: StubSubtitleFrameRenderer(
                holdsUndecodablePackets: true,
                stateDescription: "ingested:177 displaySets:0"
            )
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/subtitle-outcome.mov"),
        startsPaused: true
    )
    #expect(session.debugSnapshot().subtitleState?.outcome == .notSelected)

    try await session.selectSubtitleTrack(id: track.id)
    #expect(
        session.debugSnapshot().subtitleState?.outcome == .producedNothing,
        "committing the selection publishes once and the outcome was not settled by that publication"
    )

    session.publishSubtitleFrame(at: CMTime(seconds: 12, preferredTimescale: 600))
    #expect(session.debugSnapshot().subtitleState?.outcome == .producedNothing)
}

@Test func aSubtitleTrackTheSourceCannotHandOverIsRecordedAsUnsupported() async throws {
    let track = PlaybackSubtitleTrack(
        id: "stub.subtitle.2",
        streamIndex: 2,
        codecName: "dvb_teletext",
        language: nil,
        title: nil
    )
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-outcome-unsupported",
        provider: FakeVideoSampleProvider(events: [.end]),
        subtitleProvider: StubSubtitleProvider(tracks: [track]),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/subtitle-outcome-unsupported.mov"),
        startsPaused: true
    )

    try await session.selectSubtitleTrack(id: track.id)

    #expect(session.debugSnapshot().subtitleState?.outcome == .unsupported)
}

@Test func aSubtitleTrackThatDrawsIsRecordedAsProducing() async throws {
    let track = PlaybackSubtitleTrack(
        id: "stub.subtitle.3",
        streamIndex: 1,
        codecName: "hdmv_pgs_subtitle",
        language: "eng",
        title: "English"
    )
    let frame = PlaybackSubtitleFrame(
        kind: .bitmap,
        canvasWidth: 1_920,
        canvasHeight: 1_080,
        contentX: 0,
        contentY: 0,
        contentWidth: 4,
        contentHeight: 1,
        bytesPerRow: 16,
        premultipliedBGRA: Data(repeating: 0xFF, count: 16),
        changeIdentifier: 1
    )
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-outcome-producing",
        provider: FakeVideoSampleProvider(events: [.end]),
        subtitleProvider: StubSubtitleProvider(
            tracks: [track],
            renderer: StubSubtitleFrameRenderer(frame: frame)
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/subtitle-outcome-producing.mov"),
        startsPaused: true
    )

    try await session.selectSubtitleTrack(id: track.id)
    session.publishSubtitleFrame(at: CMTime(seconds: 12, preferredTimescale: 600))

    #expect(session.debugSnapshot().subtitleState?.outcome == .producing)
}

@Test func aSourceWhoseSubtitleListCannotBeReadStillPlaysItsVideo() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let subtitleProvider = TrackListFailingSubtitleProvider()
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-track-list-failure",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        audioProvider: FakeAudioSampleProvider(),
        subtitleProvider: subtitleProvider,
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/subtitle-track-list-failure.mov"),
        startsPaused: true
    )

    #expect(session.availableSubtitleTracks.isEmpty)
    #expect(session.diagnostics.subtitlesRetired)
    #expect(session.diagnostics.subtitleRetirementReason != nil)
    try session.start()
    try await waitForSampleCount(1, in: session)
}

@Test func aSourceWhoseAudioTrackListCannotBeReadStillPlaysItsVideo() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "audio-track-list-failure",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        audioProvider: FakeAudioSampleProvider(
            trackListError: FakeSampleError.audioRead
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/audio-track-list-failure.mov"),
        startsPaused: true
    )

    #expect(session.availableAudioTracks.isEmpty)
    try session.start()
    try await waitForSampleCount(1, in: session)
}

@Test func audioOnlySessionNeverPreparesOrStartsTheVideoProvider() async throws {
    let information = MediaSourceInformation(
        containerFormat: "mp3",
        durationSeconds: 0.25,
        streams: [
            MediaSourceStreamInformation(
                streamIndex: 0,
                category: .audio,
                codecID: 86_017,
                codecName: "mp3",
                codecTag: 0,
                language: nil,
                title: nil,
                disposition: 1,
                video: nil,
                audio: .init(sampleRate: 48_000, channelCount: 2)
            ),
        ]
    )
    let videoProvider = FakeVideoSampleProvider(events: [.end])
    let audioSample = try makeAudioSample(durationSeconds: 0.25)
    let session = SampleBufferPlaybackSession(
        traceID: "audio-only",
        provider: videoProvider,
        audioProvider: FakeAudioSampleProvider(sampleAfterPrepare: audioSample),
        mediaSourceInformationLoader: FixedMediaSourceInformationLoader(information),
        rendererSink: FakeRendererInputSink(),
        audioRendererSink: FakeAudioRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/song.mp3"))
    try session.start()
    try await waitForAudioSampleCount(1, in: session)

    #expect(session.mediaKind == .audioOnly)
    #expect(videoProvider.sourceInformationReceived == nil)
    #expect(videoProvider.startCount == 0)
    #expect(session.debugSnapshot().rendererState?.timelineConfigured == true)
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
    object.removeValue(forKey: "lhvC")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
        VideoFormatSignalingSummary.self,
        from: legacy
    )
    #expect(decoded.projectionKind.availability == .notExposed)
    #expect(decoded.viewPackingKind.availability == .notExposed)
    #expect(decoded.lhvC.availability == .notExposed)
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
    let deliveryObservation = AudioDeliveryObservation(
        providerKind: "FFmpegDecodedPCM",
        sourceCodecName: "truehd",
        mediaSubtype: "lpcm",
        formatID: "lpcm",
        formatFlags: 41,
        sourceSampleRate: 48_000,
        deliveredSampleRate: 48_000,
        sourceChannelCount: 6,
        deliveredChannelCount: 6,
        bitsPerChannel: 32,
        bytesPerFrame: 24,
        framesPerPacket: 1,
        isFloatPCM: true,
        isInterleaved: true,
        channelLayoutTag: kAudioChannelLayoutTag_WAVE_5_1_A,
        presentationTimestampsMonotonic: true,
        timestampObservationCount: 4
    )
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
        payloadOwnershipState: "retainedCMSampleBuffer",
        deliveryObservation: deliveryObservation
    )
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    #expect(object["rawStreamIndex"] as? Int == 3)
    #expect(object["sampleRate"] as? Int == 48_000)
    #expect(object["channelCount"] as? Int == 6)
    #expect(object["payloadOwnershipState"] as? String == "retainedCMSampleBuffer")
    #expect(current.deliveryObservation == deliveryObservation)

    object.removeValue(forKey: "rawStreamIndex")
    object.removeValue(forKey: "sampleRate")
    object.removeValue(forKey: "channelCount")
    object.removeValue(forKey: "payloadOwnershipState")
    object.removeValue(forKey: "deliveryObservation")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(AudioSampleRecord.self, from: legacy)

    #expect(decoded.rawStreamIndex == -1)
    #expect(decoded.sampleRate == 0)
    #expect(decoded.channelCount == 0)
    #expect(decoded.payloadOwnershipState == "unknown")
    #expect(decoded.deliveryObservation == nil)
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
    #expect(first.debugSnapshot().platform == "visionOSSimulator")
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
@Test func controllerHushStopsTheTimelineWithoutClosingTheSession() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: FakeRendererInputSink()
        )
    }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/hush.mov")
    )
    session.synchronizer.rate = 1
    #expect(session.synchronizer.rate == 1)

    controller.hush()

    #expect(session.synchronizer.rate == 0)
    #expect(controller.activeSession === session)
    await controller.closeAndWait()
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

@MainActor
@Test func aTeardownThatNeverFinishesStopsBlockingTheNextOpen() async throws {
    let stalledSink = FakeRendererInputSink(completesFlushImmediately: false)
    let sessionCreationCount = LockedBox(0)
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in
            let creation = sessionCreationCount.withLock { count in
                count += 1
                return count
            }
            return SampleBufferPlaybackSession(
                traceID: sessionID,
                provider: FakeVideoSampleProvider(events: [.end]),
                rendererSink: creation == 1
                    ? stalledSink
                    : FakeRendererInputSink()
            )
        },
        pendingCleanupDeadline: .milliseconds(200)
    )
    let source = URL(fileURLWithPath: "/fixtures/stalled-teardown.mov")
    let first = try await controller.open(source)

    controller.close(clearSource: false)
    try await waitForFlushCount(1, in: stalledSink)

    let started = ContinuousClock.now
    let second = try await controller.open(source)
    let waited = ContinuousClock.now - started

    #expect(second.traceID != first.traceID)
    #expect(controller.activeSession === second)
    #expect(controller.pendingCleanupAbandonmentCount == 1)
    #expect(waited < .seconds(2))

    stalledSink.completePendingFlushes()
    await controller.closeAndWait()
}

@MainActor
@Test func replacementOpenDoesNotWaitForRetiringSessionCleanup() async throws {
    let retiringSink = FakeRendererInputSink(completesFlushImmediately: false)
    let replacementSink = FakeRendererInputSink()
    let sessionCreationCount = LockedBox(0)
    let controller = PlaybackCoreController { sessionID in
        let creation = sessionCreationCount.withLock { count in
            count += 1
            return count
        }
        return SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(events: [.end]),
            rendererSink: creation == 1 ? retiringSink : replacementSink
        )
    }
    let source = URL(fileURLWithPath: "/fixtures/replacement.mov")
    let first = try await controller.open(source)

    let retirement = try #require(
        controller.retireActiveSessionForReplacement()
    )
    try await waitForFlushCount(1, in: retiringSink)
    let second = try await controller.open(source)

    #expect(first.traceID != second.traceID)
    #expect(controller.activeSession === second)
    #expect(sessionCreationCount.withLock { $0 } == 2)

    retiringSink.completePendingFlushes()
    await retirement.value
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
        platform: "visionOSSimulator",
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
        platform: "visionOSSimulator",
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
    let initialSample = try makeCompressedH264Sample()
    let seekSample = try makeCompressedH264Sample(presentationTimeSeconds: 5)
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 7)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(seekSample),
                    .sample(holdingSample),
                    .end,
                ]
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
        platform: "visionOSSimulator",
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

@Test func seekPastTheDeliveredVideoFailsWhenInputIsTruncated() async throws {
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
            traceID: "seek-past-delivered-video-\(lastPTSLabel)",
            provider: FakeVideoSampleProvider(events: events, durationSeconds: 10),
            rendererSink: FakeRendererInputSink()
        )
        let statuses = LockedBox<[PlaybackStatus]>([])
        session.onStatusChange = { status in
            statuses.withLock { $0.append(status) }
        }
        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/short.mov"))
        try session.start()
        if expectedLastPTS != nil {
            try await waitForSampleCount(1, in: session)
        }
        statuses.withLock { $0.removeAll() }

        let startedAt = ContinuousClock.now
        try? await session.seek(
            to: CMTime(seconds: 5, preferredTimescale: 600),
            startsPaused: false
        )

        #expect(startedAt.duration(to: .now) < .seconds(10))
        let snapshot = session.debugSnapshot()
        #expect(snapshot.lifecycle == .failed)
        #expect(statuses.withLock { $0 }.map(playbackEndReason).allSatisfy { $0 == nil })
        await session.closeAndWait()
    }
}

@Test func seekInsideTheLastFrameCompletesWhenTheInputEnds() async throws {
    let frame = 1.0 / 30
    let decodeOrder: [Double] = [1.0, 1.0 + 2 * frame, 1.0 + frame]
    let samples = try decodeOrder.enumerated().map { decodeIndex, presentation in
        try makeCompressedH264Sample(
            presentationTimeSeconds: presentation,
            decodeTimeSeconds: 1.0 + Double(decodeIndex) * frame,
            durationSeconds: frame
        )
    }
    let session = SampleBufferPlaybackSession(
        traceID: "seek-inside-last-frame",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            durationSeconds: 1.0 + 3 * frame + 0.5
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/last-frame.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try session.pause()

    let lastFrame = 1.0 + 2 * frame
    let target = lastFrame + frame / 2
    let startedAt = ContinuousClock.now
    try await session.seek(
        to: CMTime(seconds: target, preferredTimescale: 60_000),
        startsPaused: true
    )

    #expect(startedAt.duration(to: .now) < .seconds(1))
    #expect(session.debugSnapshot().lifecycle == .paused)
    #expect(session.debugSnapshot().lastCompletedOperation?.state == .completed)
    #expect(
        abs(session.currentTime().seconds - lastFrame) < 0.002,
        "seek inside the last frame settled at \(session.currentTime().seconds)"
    )
}

@MainActor
@Test func newerSeekSupersedesOlderSeekAndOwnsFinalTarget() async throws {
    let initialSample = try makeCompressedH264Sample()
    let firstSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 5)
    let secondSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 10)
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 12)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(firstSeekSample),
                    .sample(secondSeekSample),
                    .sample(holdingSample),
                    .end,
                ],
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
        platform: "visionOSSimulator",
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
    let initialSample = try makeCompressedH264Sample()
    let firstSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 5)
    let secondSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 10)
    let thirdSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 15)
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 17)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(firstSeekSample),
                    .sample(secondSeekSample),
                    .sample(thirdSeekSample),
                    .sample(holdingSample),
                    .end,
                ],
                seekPrepareDelay: .seconds(2),
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
        platform: "visionOSSimulator",
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
    let initialSample = try makeCompressedH264Sample()
    let firstSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 10.5)
    let secondSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 20.5)
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 22.5)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(firstSeekSample),
                    .sample(secondSeekSample),
                    .sample(holdingSample),
                    .end,
                ],
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
        platform: "visionOSSimulator",
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

@MainActor
@Test func frameStepDuringInFlightSeekSupersedesInsteadOfRejecting() async throws {
    let initialSample = try makeCompressedH264Sample()
    let firstSeekSample = try makeCompressedH264Sample(presentationTimeSeconds: 5)
    let steppedSample = try makeCompressedH264Sample(presentationTimeSeconds: 5 + 1.0 / 30.0)
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 6)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(firstSeekSample),
                    .sample(steppedSample),
                    .sample(holdingSample),
                    .end
                ],
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
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)

    let firstSeek = Task {
        try await controller.seek(to: CMTime(seconds: 5, preferredTimescale: 600))
    }
    try await Task.sleep(for: .milliseconds(20))
    let step = Task {
        try await controller.stepFrame(.forward)
    }

    do {
        try await firstSeek.value
        Issue.record("Expected the in-flight seek to be superseded by the frame step")
    } catch let error as PlaybackControlError {
        guard case .seekSuperseded(let target) = error else {
            Issue.record("Expected seekSuperseded, got \(error)")
            return
        }
        #expect(target == 5)
    }

    let landing = try await step.value
    let expectedLanding = 5 + 1.0 / 30.0
    #expect(abs(landing.seconds - expectedLanding) < 0.001)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lastCompletedOperation?.kind == .seek)
    #expect(snapshot.lastCompletedOperation?.state == .completed)
    let landedTarget = try #require(snapshot.lastCompletedOperation?.targetTimeSeconds)
    #expect(abs(landedTarget - expectedLanding) < 0.001)
}

@MainActor
@Test func stepFramesByDeltaLandsMultipleFrameDurationsFromBase() async throws {
    let initialSample = try makeCompressedH264Sample()
    let holdingSample = try makeCompressedH264Sample(presentationTimeSeconds: 1.0)
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [
                    .sample(initialSample),
                    .sample(holdingSample),
                    .end
                ]
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
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try controller.pause()
    session.discardVideoFramesInFlight()
    let baseSeconds = session.currentTime().seconds

    let forwardLanding = try await controller.stepFrames(by: 3)
    #expect(abs(forwardLanding.seconds - (baseSeconds + 3.0 / 30.0)) < 0.001)

    let baseAfterForward = session.currentTime().seconds
    let backwardLanding = try await controller.stepFrames(by: -2)
    #expect(abs(backwardLanding.seconds - (baseAfterForward - 2.0 / 30.0)) < 0.001)
}

@MainActor
@Test func forwardStepSeeksEvenWhileTheRendererHoldsTheNextFrame() async throws {
    let samples = try [0.0, 0.033, 0.066, 0.1].map {
        try makeCompressedH264Sample(
            presentationTimeSeconds: $0,
            decodeTimeSeconds: $0,
            durationSeconds: 0.033
        )
    }
    let sink = FakeRendererInputSink()
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: samples.map { .sample($0) } + [.end],
                eventDelay: .milliseconds(20)
            ),
            rendererSink: sink
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/frame-step-burst.mp4"),
        startsPaused: true
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(4, in: session)
    let flushesBeforeStep = sink.flushCount
    let baseSeconds = session.currentTime().seconds
    let rate = session.diagnostics.nominalFrameRate
    let frameSeconds = rate > 0 ? 1 / rate : 1.0 / 30

    let landing = try await controller.stepFrames(by: 2)

    #expect(abs(landing.seconds - (baseSeconds + 2 * frameSeconds)) < 0.001)
    #expect(sink.flushCount == flushesBeforeStep + 1)
    #expect(session.debugSnapshot().lastCompletedOperation?.kind == .seek)

    let noOp = try await controller.stepFrames(by: 0)

    #expect(abs(noOp.seconds - session.currentTime().seconds) < 0.001)
    #expect(sink.flushCount == flushesBeforeStep + 1)
}

@MainActor
@Test func pausedSeekLandsOnTheFrameThatCoversTheTarget() async throws {
    let frame = 1.0 / 30
    let decodeOrder: [(presentation: Double, decode: Double)] = [
        (1.0, 1.0),
        (1.0 + 3 * frame, 1.0 + 3 * frame),
        (1.0 + frame, 1.0),
        (1.0 + 2 * frame, 1.0 + frame),
        (1.0 + 6 * frame, 1.0 + 2 * frame),
        (1.0 + 4 * frame, 1.0 + 3 * frame),
        (1.0 + 5 * frame, 1.0 + 4 * frame),
        (1.0 + 9 * frame, 1.0 + 5 * frame),
        (1.0 + 7 * frame, 1.0 + 6 * frame),
        (1.0 + 8 * frame, 1.0 + 7 * frame),
        (1.0 + 12 * frame, 1.0 + 8 * frame)
    ]
    let initialSample = try makeCompressedH264Sample()
    let reorderedSamples = try decodeOrder.map {
        try makeCompressedH264Sample(
            presentationTimeSeconds: $0.presentation,
            decodeTimeSeconds: $0.decode,
            durationSeconds: frame
        )
    }
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(initialSample)] + reorderedSamples.map { .sample($0) } + [.end],
                seekPrepareDelay: .milliseconds(20)
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/reordered.mp4"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try controller.pause()

    let target = 1.0 + 1.5 * frame
    let coveringFrame = 1.0 + frame
    try await controller.seek(to: CMTime(seconds: target, preferredTimescale: 600), after: .pause)
    let clock = ContinuousClock()
    let startedAt = clock.now
    while abs(session.currentTime().seconds - coveringFrame) > 0.002,
          clock.now - startedAt < .seconds(3) {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        abs(session.currentTime().seconds - coveringFrame) < 0.002,
        "paused seek to \(target) settled at \(session.currentTime().seconds)"
    )
    #expect(session.synchronizer.rate == 0)

    let boundaryFrame = 1.0 + 7 * frame
    let justBelowBoundary = boundaryFrame - 0.0003
    try await controller.seek(
        to: CMTime(seconds: justBelowBoundary, preferredTimescale: 60_000),
        after: .pause
    )
    let secondStartedAt = clock.now
    while abs(session.currentTime().seconds - boundaryFrame) > 0.002,
          clock.now - secondStartedAt < .seconds(3) {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        abs(session.currentTime().seconds - boundaryFrame) < 0.002,
        "paused seek to \(justBelowBoundary) settled at \(session.currentTime().seconds)"
    )
}

@MainActor
@Test func pausedSeekWaitsForTheCoveringFrameBehindItsLaterReferences() async throws {
    let frame = 1.0 / 30
    let decodeOrder = [0, 4, 2, 1, 3, 8, 6, 5, 7, 12, 10, 9, 11]
    let initialSample = try makeCompressedH264Sample()
    let reorderedSamples = try decodeOrder.enumerated().map { decodeIndex, displayIndex in
        try makeCompressedH264Sample(
            presentationTimeSeconds: 1.0 + Double(displayIndex) * frame,
            decodeTimeSeconds: 1.0 + Double(decodeIndex) * frame,
            durationSeconds: frame
        )
    }
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(initialSample)] + reorderedSamples.map { .sample($0) } + [.end],
                eventDelay: .milliseconds(5)
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/reordered-pyramid.mp4"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try controller.pause()

    let coveringFrame = 1.0 + 5 * frame
    let target = coveringFrame - 0.0006
    try await controller.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), after: .pause)
    let clock = ContinuousClock()
    let startedAt = clock.now
    while abs(session.currentTime().seconds - coveringFrame) > 0.002,
          clock.now - startedAt < .seconds(3) {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        abs(session.currentTime().seconds - coveringFrame) < 0.002,
        "paused seek to \(target) settled at \(session.currentTime().seconds)"
    )
}

@MainActor
@Test func prerollReportsTheSeekTargetNotTheKeyframeAnchor() async throws {
    let frame = 1.0 / 30
    let decodeOrder: [(presentation: Double, decode: Double)] = [
        (1.0, 1.0),
        (1.0 + 3 * frame, 1.0 + 3 * frame),
        (1.0 + frame, 1.0),
        (1.0 + 2 * frame, 1.0 + frame),
        (1.0 + 6 * frame, 1.0 + 2 * frame),
        (1.0 + 4 * frame, 1.0 + 3 * frame),
        (1.0 + 5 * frame, 1.0 + 4 * frame),
        (1.0 + 9 * frame, 1.0 + 5 * frame),
        (1.0 + 7 * frame, 1.0 + 6 * frame),
        (1.0 + 8 * frame, 1.0 + 7 * frame),
        (1.0 + 12 * frame, 1.0 + 8 * frame)
    ]
    let initialSample = try makeCompressedH264Sample()
    let reorderedSamples = try decodeOrder.map {
        try makeCompressedH264Sample(
            presentationTimeSeconds: $0.presentation,
            decodeTimeSeconds: $0.decode,
            durationSeconds: frame
        )
    }
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(initialSample)] + reorderedSamples.map { .sample($0) } + [.end],
                eventDelay: .milliseconds(5)
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/reordered.mp4"),
    )
    session.recordPresentationBinding(
        realityViewIdentity: "testRealityView",
        platform: "visionOSSimulator",
        attached: true
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try controller.pause()

    let reported = ReportedPositions()
    session.onDiagnosticsChange = { diagnostics in
        reported.append(diagnostics.currentSeconds)
    }
    try await Task.sleep(for: .milliseconds(100))
    reported.removeAll()
    let target = 1.0 + 1.5 * frame
    let coveringFrame = 1.0 + frame
    try await controller.seek(to: CMTime(seconds: target, preferredTimescale: 600), after: .pause)
    let clock = ContinuousClock()
    let startedAt = clock.now
    while abs(session.currentTime().seconds - coveringFrame) > 0.002,
          clock.now - startedAt < .seconds(3) {
        try await Task.sleep(for: .milliseconds(10))
    }

    let positions = reported.values
    #expect(!positions.isEmpty)
    #expect(
        positions.allSatisfy { $0 >= coveringFrame - 0.002 },
        "the keyframe anchor leaked into the reported position: \(positions)"
    )
    #expect(abs(positions.last.map { $0 - coveringFrame } ?? 1) < 0.002)
}

private final class ReportedPositions: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }

    var values: [Double] {
        lock.withLock { storage }
    }

    func removeAll() {
        lock.withLock { storage.removeAll() }
    }
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

#if DEBUG
@Test func armedPlaybackSwitchSamplingRecordsEveryAcceptedVideoInput() async throws {
    let acceptedInputCount = 4
    let samples = try (0..<acceptedInputCount).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30
        )
    }
    let session = SampleBufferPlaybackSession(
        traceID: "playback-switch-sampling-armed",
        provider: FakeVideoSampleProvider(
            events: samples.map(VideoSampleProviderEvent.sample) + [.end]
        ),
        rendererSink: FakeRendererInputSink()
    )
    let sampleSink = PlaybackSwitchRendererSampleSpy()
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/fake.mov"))
    session.setPlaybackSwitchRendererSampleSink(sampleSink)
    try session.start()
    try await waitForAcceptedRendererInputCount(UInt64(acceptedInputCount), in: session)

    let acceptedInputSamples = sampleSink.samples.filter { sample in
        switch sample.trigger {
        case .firstInputAccepted, .inputAccepted:
            true
        case .periodic, .graphChanged, .lifecycleChanged:
            false
        }
    }
    #expect(acceptedInputSamples.map(\.acceptedInputCount) == [1, 2, 3, 4])
}

@Test func disarmedPlaybackSwitchSamplingRecordsNoAcceptedVideoInputs() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "playback-switch-sampling-disarmed",
        provider: FakeVideoSampleProvider(
            events: [.sample(try makeCompressedH264Sample()), .end]
        ),
        rendererSink: FakeRendererInputSink()
    )
    let sampleSink = PlaybackSwitchRendererSampleSpy()
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/fake.mov"))
    session.setPlaybackSwitchRendererSampleSink(sampleSink)
    session.setPlaybackSwitchRendererSampleSink(nil)
    try session.start()
    try await waitForAcceptedRendererInputCount(1, in: session)

    #expect(sampleSink.samples.isEmpty)
}
#endif

@Test func seekPrerollRequiresTargetVideoAndPointTwoSecondsOfAudio() {
    let target = CMTime(seconds: 12, preferredTimescale: 60_000)

    let requirement = PlaybackBufferingPolicy.seekRequirement(
        target: target,
        durationSeconds: 120
    )

    #expect(requirement.videoEnd.seconds == 12)
    #expect(requirement.audioEnd.seconds == 12.2)

    let endClampedRequirement = PlaybackBufferingPolicy.seekRequirement(
        target: target,
        durationSeconds: 12.1
    )
    #expect(endClampedRequirement.audioEnd.seconds == 12.1)
}

@Test func audioLeadLimitRemainsAnOpportunisticPlatformCeiling() {
    #if os(visionOS)
        #expect(PlaybackBufferingPolicy.opportunisticAudioMaximumLeadSeconds == 6)
    #else
        #expect(PlaybackBufferingPolicy.opportunisticAudioMaximumLeadSeconds == 1)
    #endif
}

@Suite(.serialized)
struct RendererLeadBudgetTests {
    @Test func theLeadBudgetRampsFromTheReorderFloorToTheSourceCeiling() {
        let floor = RendererLeadBudget.frames(
            reorderDepth: 3, isRemoteSource: false, secondsSinceDeliveryStart: nil, memoryPressure: .normal
        )
        #expect(floor == 3 + RendererLeadBudget.schedulingSlackFrames)

        let halfway = RendererLeadBudget.frames(
            reorderDepth: 3,
            isRemoteSource: false,
            secondsSinceDeliveryStart: RendererLeadBudget.rampSeconds / 2,
            memoryPressure: .normal
        )
        #expect(halfway > floor)
        #expect(halfway < RendererLeadBudget.localMaximumFrames)

        let local = RendererLeadBudget.frames(
            reorderDepth: 3, isRemoteSource: false, secondsSinceDeliveryStart: 10, memoryPressure: .normal
        )
        #expect(local == RendererLeadBudget.localMaximumFrames)

        let remote = RendererLeadBudget.frames(
            reorderDepth: 3, isRemoteSource: true, secondsSinceDeliveryStart: 10, memoryPressure: .normal
        )
        #expect(remote == RendererLeadBudget.remoteMaximumFrames)
        #expect(remote > local)
    }

    @Test func theLeadBudgetNeverSitsBelowTheEncoderReorderDepth() {
        let deepReorder = RendererLeadBudget.frames(
            reorderDepth: 40, isRemoteSource: false, secondsSinceDeliveryStart: 10, memoryPressure: .normal
        )
        #expect(deepReorder == 40 + RendererLeadBudget.schedulingSlackFrames)
    }

    @Test func theLeadBudgetStepsDownUnderSystemPressureAndStopsAtSixteen() {
        func ramped(_ pressure: RendererLeadBudget.MemoryPressure) -> Int {
            RendererLeadBudget.frames(
                reorderDepth: 1,
                isRemoteSource: true,
                secondsSinceDeliveryStart: 10,
                memoryPressure: pressure
            )
        }

        #expect(ramped(.normal) == RendererLeadBudget.remoteMaximumFrames)
        #expect(ramped(.warning) == RendererLeadBudget.warningCeilingFrames)
        #expect(ramped(.critical) == RendererLeadBudget.criticalCeilingFrames)

        #expect(
            ramped(.critical) > RendererLeadBudget.floorFrames(reorderDepth: 1),
            "the critical step fell to the reorder floor instead of stopping at the bottom of the ladder"
        )
        #expect(ramped(.warning) > ramped(.critical))
        #expect(ramped(.normal) > ramped(.warning))
    }

    @Test func theCorrectnessFloorOutranksEveryStepOfTheMemoryLadder() {
        for pressure in [
            RendererLeadBudget.MemoryPressure.normal, .warning, .critical
        ] {
            for reorderDepth in 0...40 {
                let floor = RendererLeadBudget.floorFrames(reorderDepth: reorderDepth)
                let ceiling = RendererLeadBudget.ceilingFrames(
                    reorderDepth: reorderDepth,
                    isRemoteSource: false,
                    memoryPressure: pressure
                )
                #expect(
                    ceiling >= min(floor, RendererLeadBudget.localMaximumFrames),
                    "reorder depth \(reorderDepth) under \(pressure) lost the frames a paused seek needs to settle"
                )
            }
        }
    }

    @Test func theLeadBudgetIgnoresTheProcessAllowanceThatOnlyOurOwnGrowthMoves() {
        let underPlenty = RendererLeadBudget.frames(
            reorderDepth: 3, isRemoteSource: false, secondsSinceDeliveryStart: 10, memoryPressure: .normal
        )
        #expect(
            underPlenty == RendererLeadBudget.localMaximumFrames,
            "the ceiling moved without a system pressure signal, so it read the process allowance"
        )
    }

    @Test func theLeadFloorAdmitsTheFramesAPausedSeekNeedsToSettle() {
        for reorderDepth in 0...16 {
            let floor = RendererLeadBudget.floorFrames(reorderDepth: reorderDepth)
            let framesBeyondTarget = floor - 1
            #expect(
                framesBeyondTarget > RendererLeadBudget.outputLagFrames(reorderDepth: reorderDepth),
                "reorder depth \(reorderDepth)"
            )
        }
    }

    @Test
    func suspendedVideoSampleDeliveryCancelsTheLeadGateBeforeReturning() async throws {
        let sample = try makeCompressedH264Sample(durationSeconds: 30)
        let sink = FakeRendererInputSink()
        let session = SampleBufferPlaybackSession(
            traceID: "suspend-video-sample-delivery",
            provider: FakeVideoSampleProvider(
                events: Array(repeating: .sample(sample), count: 1_000) + [.end]
            ),
            rendererSink: sink
        )
        RendererLeadBudget.setFixedFramesOverride(8)
        defer {
            RendererLeadBudget.setFixedFramesOverride(nil)
            session.close()
        }

        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/suspend.mov"))
        try session.start()
        try await waitForSampleCount(UInt64(session.videoLeadFrames), in: session)

        await session.suspendVideoSampleDelivery(flushingRenderer: true)

        #expect(session.videoSampleDeliveryIsSuspended)
        #expect(session.debugSnapshot().sampleCount == UInt64(session.videoLeadFrames))
        #expect(sink.flushCount == 1)
        #expect(sink.enqueuedSampleCount == 0)

        session.resumeVideoSampleDelivery()
        try await waitForSampleCount(UInt64(session.videoLeadFrames + 1), in: session)
        #expect(session.videoSampleDeliveryIsSuspended == false)
        #expect((1...session.videoLeadFrames).contains(sink.enqueuedSampleCount))
    }
}

@Test func framesInFlightRetireInDisplayOrderNotDeliveryOrder() {
    var inFlight = RendererFramesInFlight()
    for end in [1.0, 4.0, 2.0, 3.0] {
        inFlight.record(presentationEnd: end)
    }
    #expect(inFlight.earliestRetirement() == 1.0)
    #expect(inFlight.count(timelineSeconds: 0) == 4)
    #expect(inFlight.count(timelineSeconds: 2.0) == 2)
    #expect(inFlight.earliestRetirement() == 3.0)

    inFlight.removeAll()
    #expect(inFlight.count(timelineSeconds: 0) == 0)
    #expect(inFlight.earliestRetirement() == nil)
}

@Test func deliveryLagRecoveryNeverAsksForMoreThanTheGateAdmits() {
    let timelineTime = CMTime(seconds: 30, preferredTimescale: 60_000)

    let ample = PlaybackBufferingPolicy.deliveryLagRecoveryRequirement(
        timelineTime: timelineTime,
        durationSeconds: 120,
        leadFrames: 48,
        nominalFrameRate: 24
    )
    #expect(ample.videoEnd.seconds == 31)
    #expect(ample.audioEnd.seconds == 31)

    let gated = PlaybackBufferingPolicy.deliveryLagRecoveryRequirement(
        timelineTime: timelineTime,
        durationSeconds: 120,
        leadFrames: 4,
        nominalFrameRate: 60
    )
    #expect(gated.videoEnd.seconds < 31)
    #expect(gated.videoEnd.seconds > 30)
    #expect(gated.audioEnd.seconds == 31)

    for (budget, rate) in [(4, 60.0), (4, 23.976), (12, 30.0), (48, 24.0), (2, 60.0)] {
        let requirement = PlaybackBufferingPolicy.deliveryLagRecoveryRequirement(
            timelineTime: timelineTime,
            durationSeconds: 3_600,
            leadFrames: budget,
            nominalFrameRate: rate
        )
        let deepestReachableEnd = timelineTime.seconds + Double(budget - 1) / rate
        #expect(requirement.videoEnd.seconds <= deepestReachableEnd)
    }

    let endClamped = PlaybackBufferingPolicy.deliveryLagRecoveryRequirement(
        timelineTime: timelineTime,
        durationSeconds: 30.5,
        leadFrames: 48,
        nominalFrameRate: 24
    )
    #expect(endClamped.videoEnd.seconds == 30.5)
    #expect(endClamped.audioEnd.seconds == 30.5)
}

@Test func endOfStreamAudioMayUseTheAvailablePartialStartupBuffer() {
    let session = SampleBufferPlaybackSession(traceID: "partial-end-audio-preroll")
    defer { session.close() }
    session.endStateLock.withLock {
        session.endState.audioPresentationEnd = CMTime(
            seconds: 12.1,
            preferredTimescale: 48_000
        )
        session.endState.audioProviderEnded = true
    }

    #expect(session.audioHasPrerolled(
        through: CMTime(seconds: 12.2, preferredTimescale: 48_000),
        after: CMTime(seconds: 12, preferredTimescale: 48_000)
    ))
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

@Test func negativePrerollBeforeZeroTimelineIsDecodeOnly() async throws {
    let prerollSample = try makeCompressedH264Sample(
        presentationTimeSeconds: -0.033,
        decodeTimeSeconds: -0.066,
        durationSeconds: 0.016
    )
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "negative-preroll-before-zero",
        provider: FakeVideoSampleProvider(events: [.sample(prerollSample), .end]),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/negative-preroll.mp4"),
        startTime: .zero
    )
    try session.start()
    try await waitForSinkSampleCount(1, in: sink)

    let renderedSample = try #require(sink.lastEnqueuedSample)
    let attachments = try #require(
        CMSampleBufferGetSampleAttachmentsArray(
            renderedSample,
            createIfNecessary: false
        ) as? [[String: Any]]
    )
    let firstAttachment = try #require(attachments.first)
    #expect(firstAttachment[kCMSampleAttachmentKey_DoNotDisplay as String] as? Bool == true)
}

@Test func pausedHandoffPopulatesBoundedLeadWithoutSuspendingOnReceiverCapacity() async throws {
    let samples = try [0.0, 0.033, 0.066].map {
        try makeCompressedH264Sample(
            presentationTimeSeconds: $0,
            decodeTimeSeconds: $0
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "paused-handoff-bounded-lead",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            eventDelay: .milliseconds(100)
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/paused-handoff.mkv"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(2, in: session)

    #expect(session.synchronizer.rate == 0)
    #expect(sink.immediateEnqueueCount == 2)

    try session.play()
    try await waitForSampleCount(3, in: session)
    #expect(sink.immediateEnqueueCount == 3)
}

@Test func videoDeliveryGatesBeforeEnqueueingImmediately() async throws {
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
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "gated-immediate-delivery",
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

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/gated-immediate.mkv"))
    try session.start()
    try await waitForSampleCount(2, in: session)

    #expect(sink.immediateEnqueueCount == 2)
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

@Test func playDuringDecoderBootstrapBecomesTheTimelineActivationIntent() async throws {
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
    let session = SampleBufferPlaybackSession(
        traceID: "play-during-decoder-bootstrap",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            eventDelay: .milliseconds(100)
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/play-during-bootstrap.mkv"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(1, in: session)
    #expect(session.debugSnapshot().decoderBootstrap?.complete == false)

    try session.play()
    try await waitForSampleCount(3, in: session)

    let bootstrap = try #require(session.debugSnapshot().decoderBootstrap)
    #expect(bootstrap.complete)
    #expect(bootstrap.targetRate == 1)
    #expect(session.debugSnapshot().lifecycle == .playing)
    #expect(session.synchronizer.rate == 1)
}

@Test func pausedPrerollDoesNotScheduleAHostTimeRateZeroActivation() async throws {
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
    let session = SampleBufferPlaybackSession(
        traceID: "paused-preroll-no-rate-zero-host-time",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            eventDelay: .milliseconds(100)
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/paused-preroll-no-rate-zero.mkv"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(3, in: session)

    let beforePlay = session.debugSnapshot()
    #expect(beforePlay.decoderBootstrap?.complete == true)
    #expect(session.synchronizer.rate == 0)
    #expect(beforePlay.timelineControlState?.isPrerolling == true)
    #expect(beforePlay.timelineControlState?.timelineStartRate == 0)
    #expect(beforePlay.timelineControlState?.lastRateActivation == nil)

    try session.play()
    #expect(session.synchronizer.rate == 1)
    let afterPlay = try #require(session.debugSnapshot().timelineControlState?.lastRateActivation)
    #expect(afterPlay.reason == .play)
    #expect(afterPlay.synchronousApplicationReturned)
}

@Test func pauseAfterSeekBehaviourReportsPausedToTheProduct() async throws {
    let samples = try (0..<4).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) * 0.25,
            durationSeconds: 0.25
        )
    }
    let session = SampleBufferPlaybackSession(
        traceID: "seek-pause-status-session",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            durationSeconds: 1
        ),
        rendererSink: FakeRendererInputSink()
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-pause.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    try await session.seek(
        to: CMTime(seconds: 0.5, preferredTimescale: 600),
        startsPaused: true
    )

    #expect(statuses.withLock { $0.last } == .paused)
    #expect(session.debugSnapshot().lifecycle == .paused)
}

@Test func aSeekThatKeepsMakingProgressCompletesAfterTheOldDeadline() async throws {
    let samples = try (0...7).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index),
            durationSeconds: 1
        )
    }
    let trace = SeekTraceRecorder()
    trace.install()
    defer { trace.uninstall() }
    let session = SampleBufferPlaybackSession(
        traceID: "seek-progress-outlasts-the-old-deadline",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
            postSeekEventDelay: .seconds(1),
            durationSeconds: 30
        ),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/slow-seek.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let startedAt = ContinuousClock.now
    try await session.seek(
        to: CMTime(seconds: 6, preferredTimescale: 600),
        startsPaused: true
    )
    let elapsed = ContinuousClock.now - startedAt

    #expect(elapsed > PlaybackBufferingPolicy.seekProgressStallTimeout)
    #expect(session.debugSnapshot().lastFailure == nil)
    #expect(
        trace.events.contains {
            $0.hasPrefix("session.seek.stalled seconds=6.0 lastProgressMs=")
        },
        "traces: \(trace.events)"
    )
}

@Test func aSeekWithNoProgressFailsAfterTheStallTimeout() async throws {
    let initialSample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "seek-without-progress-stalls",
        provider: FakeVideoSampleProvider(
            events: [.sample(initialSample), .end],
            postSeekEventDelay: .seconds(20),
            durationSeconds: 30
        ),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/dead-seek.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let startedAt = ContinuousClock.now
    await #expect(throws: CorePlaybackError.self) {
        try await session.seek(
            to: CMTime(seconds: 6, preferredTimescale: 600),
            startsPaused: true
        )
    }
    let elapsed = ContinuousClock.now - startedAt

    #expect(elapsed >= PlaybackBufferingPolicy.seekProgressStallTimeout)
    #expect(elapsed < .seconds(9))
    let failure = try #require(session.debugSnapshot().lastFailure)
    #expect(failure.stage == "control.seek.failed")
    #expect((failure.progressAgeMilliseconds ?? 0) >= 5_000)
}

@Test(arguments: [false, true])
func repeatedPauseAfterSeeksReportEveryPausedStateToTheProduct(
    hasAudio: Bool
) async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 4)
    let audioProvider: any AudioSampleProvider = if hasAudio {
        FakeAudioSampleProvider(sampleAfterPrepare: try makeAudioSample(durationSeconds: 4))
    } else {
        NoAudioSampleProvider()
    }
    let session = SampleBufferPlaybackSession(
        traceID: "repeated-seek-pause-\(hasAudio ? "audio" : "video-only")",
        provider: FakeVideoSampleProvider(
            events: [.sample(videoSample), .end],
            durationSeconds: 4
        ),
        audioProvider: audioProvider,
        rendererSink: FakeRendererInputSink()
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/repeated-seek.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    if hasAudio {
        try await waitForAudioSampleCount(1, in: session)
    }
    statuses.withLock { $0.removeAll() }

    for target in [1.0, 0.0, 2.0] {
        let statusCountBeforeSeek = statuses.withLock(\.count)
        try await session.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            startsPaused: true
        )

        #expect(statuses.withLock { Array($0.dropFirst(statusCountBeforeSeek)) } == [.paused])
        #expect(session.debugSnapshot().lifecycle == .paused)
    }

    #expect(statuses.withLock { $0 } == [.paused, .paused, .paused])
}

@Test func pauseAfterSeekThenPlayThenSeekReportsTheLatestPause() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 4)
    let session = SampleBufferPlaybackSession(
        traceID: "seek-pause-play-seek-pause",
        provider: FakeVideoSampleProvider(
            events: [.sample(sample), .end],
            durationSeconds: 4
        ),
        rendererSink: FakeRendererInputSink()
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-play-seek.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    statuses.withLock { $0.removeAll() }

    try await session.seek(
        to: CMTime(seconds: 1, preferredTimescale: 600),
        startsPaused: true
    )
    try session.play()
    try await session.seek(
        to: CMTime(seconds: 2, preferredTimescale: 600),
        startsPaused: true
    )

    #expect(statuses.withLock { $0 } == [.paused, .playing, .paused])
    #expect(session.debugSnapshot().lifecycle == .paused)
}

@Test func preservingAfterSeekStateReportsPlayingAndPausedToTheProduct() async throws {
    let initialSample = try makeCompressedH264Sample(durationSeconds: 0.25)
    let targetSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 2,
        durationSeconds: 0.25
    )
    let session = SampleBufferPlaybackSession(
        traceID: "seek-preserves-product-state",
        provider: FakeVideoSampleProvider(
            events: [.sample(initialSample), .sample(targetSample), .end],
            durationSeconds: 4
        ),
        rendererSink: FakeRendererInputSink()
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/preserve-seek.mkv"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    statuses.withLock { $0.removeAll() }

    try await session.seek(
        to: CMTime(seconds: 1, preferredTimescale: 600),
        startsPaused: false
    )
    #expect(statuses.withLock { $0.last } == .playing)
    #expect(session.debugSnapshot().lifecycle == .playing)

    try session.pause()
    try await session.seek(
        to: CMTime(seconds: 2, preferredTimescale: 600),
        startsPaused: true
    )

    #expect(statuses.withLock { $0 } == [.playing, .paused, .paused])
    #expect(session.debugSnapshot().lifecycle == .paused)
}

@MainActor
@Test func supersededSeekCannotPublishPlayingAfterTheNewestSeekPauses() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 4)
    let provider = GenerationDelayedVideoSampleProvider(
        sample: sample,
        durationSeconds: 4,
        firstReadDelays: [2: .milliseconds(250), 3: .milliseconds(25)]
    )
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: provider,
            rendererSink: FakeRendererInputSink()
        )
    }
    let statuses = LockedBox<[PlaybackStatus]>([])
    controller.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { controller.close() }

    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/superseded-seek-status.mkv")
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try await waitForLifecycle(.playing, in: session)
    statuses.withLock { $0.removeAll() }

    let superseded = Task {
        try await controller.seek(
            to: CMTime(seconds: 1, preferredTimescale: 600),
            after: .play
        )
    }
    try await provider.waitUntilFirstReadStarts(forGeneration: 2)
    let newest = Task {
        try await controller.seek(
            to: CMTime(seconds: 2, preferredTimescale: 600),
            after: .pause
        )
    }

    do {
        try await superseded.value
        Issue.record("Expected the first seek to be superseded")
    } catch let error as PlaybackControlError {
        guard case .seekSuperseded(let target) = error else {
            Issue.record("Expected seekSuperseded, got \(error)")
            return
        }
        #expect(target == 1)
    }
    try await newest.value
    try await provider.waitUntilFirstReadReturns(forGeneration: 2)
    try await Task.sleep(for: .milliseconds(25))

    #expect(statuses.withLock { $0 } == [.paused])
    #expect(controller.status == .paused)
    #expect(session.debugSnapshot().lifecycle == .paused)
}

@Test func seekToExactDurationPublishesEndedWithoutReopeningTheProvider() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let provider = FakeVideoSampleProvider(
        events: [.sample(sample), .end],
        durationSeconds: 1
    )
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
    statuses.withLock { $0.removeAll() }

    try await session.seek(
        to: CMTime(seconds: 1, preferredTimescale: 600),
        startsPaused: true
    )

    #expect(provider.startCount == startCount)
    #expect(session.debugSnapshot().lifecycle == .ended)
    #expect(statuses.withLock { $0 }.map(playbackEndReason) == [.seekToEnd])
    #expect(session.renderer.displayedPixelBuffer() == nil)
}

@MainActor
@Test func seekWithTheEndIntentEndsPlaybackWithoutMatchingTheDuration() async throws {
    let frame = 1.0 / 30
    let samples = try [1.0, 1.0 + frame, 1.0 + 2 * frame].map {
        try makeCompressedH264Sample(presentationTimeSeconds: $0, durationSeconds: frame)
    }
    let provider = FakeVideoSampleProvider(
        events: samples.map { .sample($0) } + [.end],
        durationSeconds: 10
    )
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: provider,
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/end-intent.mkv"),
        startsPaused: true
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    try controller.start()
    try await waitForSampleCount(1, in: session)
    let startCount = provider.startCount
    statuses.withLock { $0.removeAll() }

    try await controller.seek(to: CMTime(seconds: 9.9, preferredTimescale: 600), after: .end)

    #expect(provider.startCount == startCount)
    #expect(session.debugSnapshot().lifecycle == .ended)
    #expect(statuses.withLock { $0 }.map(playbackEndReason) == [.seekToEnd])
    #expect(abs(session.currentTime().seconds - 10) < 0.001)
}

@MainActor
@Test func playingSeekIntoTheLastFrameEndsWhenTheInputEnds() async throws {
    let frame = 1.0 / 30
    let samples = try [1.0, 1.0 + frame, 1.0 + 2 * frame].map {
        try makeCompressedH264Sample(presentationTimeSeconds: $0, durationSeconds: frame)
    }
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: samples.map { .sample($0) } + [.end],
                durationSeconds: 1.5
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(URL(fileURLWithPath: "/fixtures/last-frame-playing.mkv"))
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    try controller.start()
    try await waitForSampleCount(1, in: session)
    statuses.withLock { $0.removeAll() }

    let target = 1.0 + 2 * frame + frame / 2
    let startedAt = ContinuousClock.now
    try await controller.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), after: .play)
    while session.debugSnapshot().lifecycle != .ended, startedAt.duration(to: .now) < .seconds(2) {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(session.debugSnapshot().lifecycle == .ended)
    #expect(statuses.withLock { $0 }.map(playbackEndReason) == [.seekToEnd])
    #expect(session.debugSnapshot().lastError == nil)
    #expect(abs(session.currentTime().seconds - 1.5) < 0.001)
    #expect(abs(session.diagnostics.currentSeconds - 1.5) < 0.001)
}

@Test func seekClampsFiniteTargetsToTheKnownMediaRange() async throws {
    let cases: [(requested: Double, expected: Double)] = [
        (-5, 0),
        (5, 1),
    ]

    for testCase in cases {
        let sample = try makeCompressedH264Sample(durationSeconds: 1)
        let session = SampleBufferPlaybackSession(
            traceID: "seek-clamp-\(testCase.expected)",
            provider: FakeVideoSampleProvider(
                events: [.sample(sample), .end],
                durationSeconds: 1
            ),
            rendererSink: FakeRendererInputSink()
        )
        defer { session.close() }
        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-clamp.mkv"))
        try session.start()
        try await waitForSampleCount(1, in: session)

        try await session.seek(
            to: CMTime(seconds: testCase.requested, preferredTimescale: 600),
            startsPaused: true
        )

        #expect(
            session.debugSnapshot().lastCompletedOperation?.targetTimeSeconds
                == testCase.expected
        )
        #expect(session.debugSnapshot().lifecycle != .failed)
    }
}

@Test func seekRejectsNonFiniteTargetsWithoutChangingTheMediaSession() async throws {
    for requested in [
        CMTime.invalid,
        CMTime.positiveInfinity,
        CMTime.negativeInfinity,
        CMTime.indefinite,
    ] {
        let sample = try makeCompressedH264Sample(durationSeconds: 1)
        let provider = FakeVideoSampleProvider(
            events: [.sample(sample), .end],
            durationSeconds: 1
        )
        let session = SampleBufferPlaybackSession(
            traceID: "seek-reject-non-finite",
            provider: provider,
            rendererSink: FakeRendererInputSink()
        )
        defer { session.close() }
        try await session.prepare(url: URL(fileURLWithPath: "/fixtures/seek-invalid.mkv"))
        try session.start()
        try await waitForSampleCount(1, in: session)
        let before = session.debugSnapshot()
        let startCount = provider.startCount

        do {
            try await session.seek(
                to: requested,
                startsPaused: true
            )
            Issue.record("Expected non-finite seek time to be rejected")
        } catch PlaybackControlError.invalidSeekTime(let rejected) {
            #expect(!rejected.isFinite)
        }

        let after = session.debugSnapshot()
        #expect(after.streamEpoch == before.streamEpoch)
        #expect(after.lifecycle == before.lifecycle)
        #expect(provider.startCount == startCount)
    }
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

@Test func finalDisplayableVideoTimeUsesMaximumPresentationTime() throws {
    let session = SampleBufferPlaybackSession(traceID: "final-displayable-time")
    defer { session.close() }
    let finalPresentationTime = CMTime(value: 29_988, timescale: 1_000)

    session.recordVideoPresentation(
        presentationTime: finalPresentationTime,
        presentationEnd: CMTime(value: 30_021, timescale: 1_000)
    )
    session.recordVideoPresentation(
        presentationTime: CMTime(value: 29_954, timescale: 1_000),
        presentationEnd: CMTime(value: 29_987, timescale: 1_000)
    )

    let resolvedTime = try #require(session.finalDisplayableVideoPresentationTime)
    #expect(CMTimeCompare(resolvedTime, finalPresentationTime) == 0)
}

@Test func finalDisplayableVideoTimeRequiresAnAcceptedPresentationBeforeDuration() {
    let session = SampleBufferPlaybackSession(
        traceID: "final-displayable-time-fallback",
        provider: FakeVideoSampleProvider(events: [], durationSeconds: 60),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    #expect(session.finalDisplayableVideoPresentationTime == nil)
}

@Test func finalDisplayableVideoTimeUsesLastAcceptedPresentationBeforeDuration() throws {
    let session = SampleBufferPlaybackSession(
        traceID: "final-displayable-time-at-end",
        provider: FakeVideoSampleProvider(
            events: [],
            durationSeconds: 60.025167,
            nominalFrameRate: 12.345
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }
    let lastPresentationBeforeDuration = CMTime(
        seconds: 59.981234,
        preferredTimescale: 60_000
    )
    session.recordVideoPresentation(
        presentationTime: lastPresentationBeforeDuration,
        presentationEnd: CMTime(seconds: 60.025167, preferredTimescale: 60_000)
    )
    session.recordVideoPresentation(
        presentationTime: CMTime(seconds: 60.025167, preferredTimescale: 60_000),
        presentationEnd: CMTime(seconds: 60.041850, preferredTimescale: 60_000)
    )

    let resolvedTime = try #require(session.finalDisplayableVideoPresentationTime)

    #expect(CMTimeCompare(resolvedTime, lastPresentationBeforeDuration) == 0)
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
func liveStereoOverridePublishesAcceptedRevisionsAndKeepsImmutableRendererGraph() async throws {
    let samples = try (0..<120).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30,
            decodeTimeSeconds: Double(index) / 30
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-live",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end]
        ),
        rendererSink: sink
    )
    let acceptedFormatRevisions = LockedBox<[UInt64]>([])
    session.onAcceptedVideoFormatRevisionChange = { revision in
        acceptedFormatRevisions.withLock { $0.append(revision) }
    }
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let baselineRate = session.currentRate()
    let rendererIdentity = PlaybackTrace.identity(session.renderer)
    let audioRendererIdentity = PlaybackTrace.identity(session.audioRenderer)
    let synchronizerIdentity = PlaybackTrace.identity(session.synchronizer)
    let graphRevision = session.graphRevision
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
    #expect(PlaybackTrace.identity(session.audioRenderer) == audioRendererIdentity)
    #expect(PlaybackTrace.identity(session.synchronizer) == synchronizerIdentity)
    #expect(session.graphRevision == graphRevision)
    #expect(acceptedFormatRevisions.withLock { $0 } == [1, 2, 3, 4])
}


@Test
func rendererGraphContinuityRejectsASingleStaticFirstFrame() {
    let baseline = RendererGraphPlaybackObservation(
        graphRevision: 7,
        acceptedInputCount: 12,
        actualTimebaseRate: 1,
        displayedFrameObservationCount: 0
    )
    let current = RendererGraphPlaybackObservation(
        graphRevision: 7,
        acceptedInputCount: 13,
        actualTimebaseRate: 1,
        displayedFrameObservationCount: 1
    )

    #expect(
        RendererGraphPlaybackContinuity.evaluate(
            baseline: baseline,
            current: current,
            requiredGraphRevision: 7
        ) == .awaitingDisplayedFrameAdvance
    )
}

@Test
func rendererGraphContinuityBecomesReadyOnlyAfterExplicitPlaybackAdvancesEveryOutputFact() {
    let baseline = RendererGraphPlaybackObservation(
        graphRevision: 8,
        acceptedInputCount: 40,
        actualTimebaseRate: 0,
        displayedFrameObservationCount: 10
    )
    let stillPaused = RendererGraphPlaybackObservation(
        graphRevision: 8,
        acceptedInputCount: 41,
        actualTimebaseRate: 0,
        displayedFrameObservationCount: 12
    )
    let playing = RendererGraphPlaybackObservation(
        graphRevision: 8,
        acceptedInputCount: 41,
        actualTimebaseRate: 1,
        displayedFrameObservationCount: 12
    )

    #expect(
        RendererGraphPlaybackContinuity.evaluate(
            baseline: baseline,
            current: stillPaused,
            requiredGraphRevision: 8
        ) == .awaitingActualTimebaseRate
    )
    #expect(
        RendererGraphPlaybackContinuity.evaluate(
            baseline: baseline,
            current: playing,
            requiredGraphRevision: 8
        ) == .ready
    )
}

@Test
func rendererGraphContinuityRejectsInputThatDidNotAdvanceAfterExplicitPlay() {
    let baseline = RendererGraphPlaybackObservation(
        graphRevision: 9,
        acceptedInputCount: 977,
        actualTimebaseRate: 0,
        displayedFrameObservationCount: 4
    )
    let playingFromBufferedInput = RendererGraphPlaybackObservation(
        graphRevision: 9,
        acceptedInputCount: 977,
        actualTimebaseRate: 1,
        displayedFrameObservationCount: 4
    )

    #expect(
        RendererGraphPlaybackContinuity.evaluate(
            baseline: baseline,
            current: playingFromBufferedInput,
            requiredGraphRevision: 9
        ) == .awaitingAcceptedSample
    )
}

@Test
func explicitPlayContinuesWhenOnlyDisplayedFrameIdentityRemainsUnproven() {
    #expect(RendererGraphPlaybackContinuity.ready.explicitPlayMayContinue)
    #expect(
        RendererGraphPlaybackContinuity.awaitingDisplayedFrameAdvance
            .explicitPlayMayContinue
    )
    #expect(
        RendererGraphPlaybackContinuity.awaitingAcceptedSample
            .explicitPlayMayContinue == false
    )
    #expect(
        RendererGraphPlaybackContinuity.awaitingActualTimebaseRate
            .explicitPlayMayContinue == false
    )
    #expect(
        RendererGraphPlaybackContinuity.wrongGraphRevision
            .explicitPlayMayContinue == false
    )
}

@MainActor
@Test
func explicitPlayStartsTheTimebaseBeforeRendererGraphContinuityIsEvaluated() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 30)
    let session = SampleBufferPlaybackSession(
        traceID: "explicit-play-continuity",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end]
        ),
        rendererSink: FakeRendererInputSink()
    )
    let controller = PlaybackCoreController(
        sessionFactory: { _ in session },
        debugRecorderMode: .disabledForVerification
    )
    defer { session.close() }

    _ = try await controller.open(
        URL(fileURLWithPath: "/fixtures/explicit-play-continuity.mov")
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try await setRateWhenTimelineIsReady(1, in: session)
    try controller.pause()

    let result = try await controller.playAndVerifyRendererGraphContinuity(
        timeout: .zero
    )

    #expect(controller.status == .playing)
    #expect(session.currentRate() == 1)
    #expect(CMTimebaseGetRate(session.synchronizer.timebase) > 0)
    #expect(result != .ready)
}

@MainActor
@Test
func explicitPauseDuringTheContinuityProofSupersedesTheProofInsteadOfFailingIt() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 30)
    let session = SampleBufferPlaybackSession(
        traceID: "pause-during-continuity-proof",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end]
        ),
        rendererSink: FakeRendererInputSink()
    )
    let controller = PlaybackCoreController(
        sessionFactory: { _ in session },
        debugRecorderMode: .disabledForVerification
    )
    defer { session.close() }

    _ = try await controller.open(
        URL(fileURLWithPath: "/fixtures/pause-during-continuity-proof.mov")
    )
    try controller.start()
    try await waitForSampleCount(1, in: session)
    try await setRateWhenTimelineIsReady(1, in: session)
    try controller.pause()

    let proof = Task {
        try await controller.playAndVerifyRendererGraphContinuity(timeout: .seconds(2))
    }
    try await Task.sleep(for: .milliseconds(100))
    try controller.pause()
    let started = ContinuousClock.now
    let result = try await proof.value

    #expect(result == .supersededByPause)
    #expect(result.explicitPlayMayContinue)
    #expect(ContinuousClock.now - started < .seconds(1))
    #expect(controller.status == .paused)
}

@Test
func liveProjectionOverrideKeepsImmutableRendererGraphAndTimeline() async throws {
    let sourceProjection = kCMFormatDescriptionProjectionKind_Equirectangular as String
    let samples = try (0..<120).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30,
            decodeTimeSeconds: Double(index) / 30,
            projectionKind: kCMFormatDescriptionProjectionKind_Equirectangular
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "projection-live",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end],
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
    let samples = try (0..<120).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30,
            decodeTimeSeconds: Double(index) / 30
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "projection-panorama",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end]
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

@Test
func stereoAndProjectionOverridesCommitAtOneFormatRevision() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 30)
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "atomic-format-overrides",
        provider: FakeVideoSampleProvider(
            events: Array(repeating: .sample(sample), count: 1_000) + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/atomic-format.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    let baseline = session.debugSnapshot()
    let baselineFlushCount = sink.flushCount
    let rendererIdentity = PlaybackTrace.identity(session.renderer)

    let revision = try await session.setFormatOverrides(
        stereoLayout: .sideBySide,
        projection: .halfEquirectangular
    )
    let snapshot = session.debugSnapshot()

    #expect(revision == 2)
    #expect(snapshot.streamEpoch == baseline.streamEpoch + 1)
    #expect(sink.flushCount == baselineFlushCount + 1)
    #expect(sink.lastFlushRemovedDisplayedImage == false)
    #expect(PlaybackTrace.identity(session.renderer) == rendererIdentity)
    #expect(snapshot.lastVideoSample?.formatRevision == revision)
    #expect(
        snapshot.lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
    #expect(
        snapshot.lastVideoSample?.formatSignaling.projectionKind.value
            == kCMFormatDescriptionProjectionKind_HalfEquirectangular as String
    )
    #expect(
        snapshot.lastAcceptedRendererInput?.formatSignaling?.projectionKind.value
            == kCMFormatDescriptionProjectionKind_HalfEquirectangular as String
    )
    #expect(
        snapshot.lastAcceptedRendererInput?.formatSignaling?.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
    #expect(
        snapshot.lastAcceptedRendererInput?.formatSignaling?.hasLeftStereoEyeView.value == true
    )
    #expect(
        snapshot.lastAcceptedRendererInput?.formatSignaling?.hasRightStereoEyeView.value == true
    )
}

@Test func clearingStereoOverrideWaitsForASourceFormatSample() async throws {
    let samples = try (0..<120).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30,
            decodeTimeSeconds: Double(index) / 30
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-clear-source-format",
        provider: FakeVideoSampleProvider(
            events: samples.map { .sample($0) } + [.end]
        ),
        rendererSink: sink
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/stereo.mov"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    _ = try await session.setStereoLayout(.mono)
    let explicitSnapshot = session.debugSnapshot()
    #expect(explicitSnapshot.lastVideoSample?.formatSignaling.viewPackingKind.value == nil)

    let sourceRevision = try await session.clearStereoLayoutOverride()
    let sourceSnapshot = session.debugSnapshot()
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
    let samples = try (0..<120).map { index in
        try makeCompressedH264Sample(
            presentationTimeSeconds: Double(index) / 30,
            decodeTimeSeconds: Double(index) / 30
        )
    }
    let sink = FakeRendererInputSink(completesFlushImmediately: false)
    let session = SampleBufferPlaybackSession(
        traceID: "stereo-provider-reset",
        provider: FakeVideoSampleProvider(
            events: [.sample(samples[0]), reset.event]
                + samples.dropFirst().map { .sample($0) }
                + [.end]
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
    try await waitForSampleCount(baseline.sampleCount + 1, in: session)

    let acceptedRevision = try await session.setStereoLayout(.sideBySide)
    let final = session.debugSnapshot()
    let expectedRevision = initialFormatRevision + (reset == .formatChanged ? 2 : 1)
    #expect(acceptedRevision == expectedRevision)
    #expect(final.lastVideoSample?.formatRevision == acceptedRevision)
    #expect(final.sampleCount >= baseline.sampleCount + 2)
    #expect(
        final.lastVideoSample?.formatSignaling.viewPackingKind.value
            == kCMFormatDescriptionViewPackingKind_SideBySide as String
    )
    #expect(final.streamEpoch == initialStreamEpoch + (reset == .flush ? 1 : 0))
    #expect(sink.flushCount == 1)
}

@MainActor
@Test func cancelledStereoCommandCannotMutateANewControllerSession() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 30)
    let firstSink = FakeRendererInputSink()
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
                events: Array(repeating: .sample(sample), count: 120) + [.end]
            ),
            rendererSink: creation == 1 ? firstSink : laterSink
        )
    }
    defer { controller.close() }

    let url = URL(fileURLWithPath: "/fixtures/stereo-controller.mov")
    let first = try await controller.open(url)
    try controller.start()
    try await waitForSampleCount(UInt64(first.videoLeadFrames), in: first)

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
        platform: "visionOSSimulator",
        attached: true
    )
    session.recordPresentationBinding(
        realityViewIdentity: "view-b",
        platform: "visionOSSimulator",
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

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/two-audio.mp4"),
        startTime: CMTime(seconds: 12, preferredTimescale: 600)
    )
    #expect(session.availableAudioTracks.map(\.streamIndex) == [1, 2])
    #expect(audio.preparedStreamIndices == [nil])
    let videoEpochBeforeSelection = session.debugSnapshot().streamEpoch

    try await session.selectAudioTrack(streamIndex: 2)
    let controlState = try #require(session.debugSnapshot().timelineControlState)
    #expect(controlState.timelineStartRate == 1)
    #expect(controlState.requestedTimelineStartSeconds == 12)
    #expect(session.debugSnapshot().sampleCount == 0)
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
        provider: FakeVideoSampleProvider(
            events: [.sample(videoSample), .end],
            durationSeconds: 0.75
        ),
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

@MainActor
@Test func providerEndBeforeDeclaredDurationFailsInsteadOfEnding() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 0.05)
    let session = SampleBufferPlaybackSession(
        traceID: "truncated-input-session",
        provider: FakeVideoSampleProvider(
            events: [.sample(videoSample), .end],
            durationSeconds: 60
        ),
        rendererSink: FakeRendererInputSink()
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/truncated.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
          session.debugSnapshot().lifecycle != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.debugSnapshot().lifecycle == .failed)
}

@Test func playbackEndReceiptRequiresDeliveredEndToReachDeclaredDuration() {
    #expect(PlaybackEndReceipt.completion(
        reason: .naturalCompletion,
        deliveredEndSeconds: 60,
        declaredDurationSeconds: 60
    ) != nil)
    #expect(PlaybackEndReceipt.completion(
        reason: .naturalCompletion,
        deliveredEndSeconds: 5,
        declaredDurationSeconds: 60
    ) == nil)
    #expect(PlaybackEndReceipt.completion(
        reason: .naturalCompletion,
        deliveredEndSeconds: nil,
        declaredDurationSeconds: 60
    ) == nil)
    #expect(PlaybackEndReceipt.completion(
        reason: .naturalCompletion,
        deliveredEndSeconds: 5,
        declaredDurationSeconds: nil
    ) != nil)
    #expect(PlaybackEndReceipt.seekToEnd(endSeconds: 60).reason == .seekToEnd)
}

@MainActor
@Test func inputEndingBeforeActivationFailsWhenShortOfDeclaredDuration() async throws {
    let videoSample = try makeCompressedH264Sample(
        presentationTimeSeconds: 0,
        durationSeconds: 0.05
    )
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FakeVideoSampleProvider(
                events: [.sample(videoSample), .end],
                durationSeconds: 60
            ),
            rendererSink: FakeRendererInputSink()
        )
    }
    defer { controller.close() }
    let session = try await controller.open(
        URL(fileURLWithPath: "/fixtures/truncated-open.mp4"),
        startTime: CMTime(seconds: 30, preferredTimescale: 600)
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    try controller.start()

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
          session.debugSnapshot().lifecycle != .failed {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.debugSnapshot().lifecycle == .failed)
    #expect(statuses.withLock { $0 }.map(playbackEndReason).allSatisfy { $0 == nil })
}

@Test func endedUsesVideoPresentationEndWhenNoAudioIsSelected() async throws {
    let videoSample = try makeCompressedH264Sample(durationSeconds: 0.05)
    let session = SampleBufferPlaybackSession(
        traceID: "video-only-end-session",
        provider: FakeVideoSampleProvider(
            events: [.sample(videoSample), .end],
            durationSeconds: 0.05
        ),
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
        rendererSink: FakeRendererInputSink()
    )
    let recorder = PlaybackDebugRecorder(session: session, platform: "visionOSSimulator")
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

@Test func audioDeliveryObservationExposesFormatAndEpochMonotonicity() throws {
    let sample = try makeAudioSample(durationSeconds: 0.5)
    let session = SampleBufferPlaybackSession(traceID: "audio-delivery-observation")
    defer { session.close() }
    let first = session.recordAudioDeliveryPresentationTime(.zero)
    let second = session.recordAudioDeliveryPresentationTime(
        CMTime(value: 1, timescale: 2)
    )
    CMSetAttachment(
        sample,
        key: "com.enchron.playbackcore.ffmpegAudioMetadata" as CFString,
        value: [
            "trueHDDecoderInputPacketCount": 120,
            "trueHDDecoderBatchCount": 2,
            "trueHDAggregatedDecoderBatchCount": 2,
            "trueHDOutputSampleBufferCount": 1,
            "trueHDLastDecoderBatchInputPacketCount": 60
        ] as CFDictionary,
        attachmentMode: kCMAttachmentMode_ShouldNotPropagate
    )
    let observation = try #require(
        session.audioDeliveryObservation(
            for: sample,
            providerInfo: AudioSampleProviderInfo(
                providerKind: "FFmpegDecodedPCM",
                streamIndex: 2,
                codecName: "truehd",
                sampleRate: 48_000,
                channelCount: 2
            ),
            timestampsMonotonic: second.monotonic,
            timestampObservationCount: second.count
        )
    )

    #expect(first.monotonic)
    #expect(first.count == 1)
    #expect(observation.providerKind == "FFmpegDecodedPCM")
    #expect(observation.sourceCodecName == "truehd")
    #expect(observation.formatID == "lpcm")
    #expect(observation.isFloatPCM)
    #expect(observation.isInterleaved == true)
    #expect(observation.sourceSampleRate == 48_000)
    #expect(observation.deliveredSampleRate == 48_000)
    #expect(observation.bitsPerChannel == 32)
    #expect(observation.presentationTimestampsMonotonic)
    #expect(observation.timestampObservationCount == 2)
    #expect(observation.trueHDDecoderInputPacketCount == 120)
    #expect(observation.trueHDDecoderBatchCount == 2)
    #expect(observation.trueHDAggregatedDecoderBatchCount == 2)
    #expect(observation.trueHDOutputSampleBufferCount == 1)
    #expect(observation.trueHDLastDecoderBatchInputPacketCount == 60)

    let duplicate = session.recordAudioDeliveryPresentationTime(
        CMTime(value: 1, timescale: 2)
    )
    #expect(duplicate.monotonic == false)
    #expect(duplicate.count == 3)

    session.audioStreamEpoch &+= 1
    let nextEpoch = session.recordAudioDeliveryPresentationTime(.zero)
    #expect(nextEpoch.monotonic)
    #expect(nextEpoch.count == 1)
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

@Test func audioOpenFailureRetiresAudioButVideoStillDelivers() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "audio-open-error-session",
        provider: FakeVideoSampleProvider(
            events: try audioRetirementVideoEvents(),
            eventDelay: .milliseconds(25)
        ),
        audioProvider: FailingAudioOpenProvider(),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-error.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lifecycle != .failed)
    #expect(snapshot.lastFailure?.stage == "audioProvider.openFailed.videoContinues")
    #expect(snapshot.lastFailure?.message == MisleadingAudioOpenError.failed.localizedDescription)
    #expect(snapshot.lastFailure?.recoverability == "audioRetiredVideoContinues")
    try await expectRetiredAudioAllowsSeek(
        in: session,
        check: "audio-retirement-open",
        expectedStage: "audioProvider.openFailed.videoContinues"
    )
}

@Test func audioPrerollFailureRetiresAudioButVideoStillDelivers() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "audio-preroll-error-session",
        provider: FakeVideoSampleProvider(
            events: try audioRetirementVideoEvents(),
            eventDelay: .milliseconds(25)
        ),
        audioProvider: FakeAudioSampleProvider(),
        rendererSink: FakeRendererInputSink(),
        audioRendererSink: FakeAudioRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-preroll-error.mp4"))
    try session.start()
    try await waitForAudioRetirement(in: session)
    try await waitForSampleCount(1, in: session)

    try await expectRetiredAudioAllowsSeek(
        in: session,
        check: "audio-retirement-prewarm",
        expectedStage: "audioRenderer.prerollFailed.videoContinues"
    )
}

@Test func retiredAudioStaysNonfatalAcrossRepeatedSeeks() async throws {
    let fixture = try unsupportedAC4Fixture()
    defer { try? FileManager.default.removeItem(at: fixture) }
    let videoSamples = try [0.0, 5.0, 10.0].map {
        try makeCompressedH264Sample(
            presentationTimeSeconds: $0,
            durationSeconds: 1
        )
    }
    let sink = FakeRendererInputSink()
    let session = SampleBufferPlaybackSession(
        traceID: "retired-audio-repeated-seek-session",
        provider: FakeVideoSampleProvider(
            events: videoSamples.map(VideoSampleProviderEvent.sample) + [.end]
        ),
        audioProvider: FFmpegAudioSampleProvider(),
        rendererSink: sink
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(url: fixture)
    #expect(session.hasAudio == false)
    #expect(session.debugSnapshot().lastError == nil)
    #expect(session.debugSnapshot().lastFailure?.message.contains("ac4") == true)

    for target in [5.0, 10.0] {
        let streamEpochBeforeSeek = session.debugSnapshot().streamEpoch
        try await session.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            startsPaused: true
        )
        let snapshot = session.debugSnapshot()
        #expect(session.hasAudio == false)
        #expect(snapshot.lifecycle != .failed)
        #expect(snapshot.streamEpoch > streamEpochBeforeSeek)
        #expect((snapshot.lastVideoSample?.presentationTimeSeconds ?? -.infinity) >= target)
    }

    #expect(statuses.withLock { values in
        values.contains { status in
            if case .failed = status { true } else { false }
        }
    } == false)
}

@Test func audioReadFailureRetiresAudioButVideoStillDelivers() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "audio-read-error-session",
        provider: FakeVideoSampleProvider(
            events: try audioRetirementVideoEvents(),
            eventDelay: .milliseconds(25)
        ),
        audioProvider: FakeAudioSampleProvider(readError: FakeSampleError.audioRead),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-read-error.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lifecycle != .failed)
    #expect(snapshot.lastFailure?.stage == "audioProvider.readFailed.videoContinues")
    #expect(snapshot.lastFailure?.message == FakeSampleError.audioRead.localizedDescription)
    #expect(snapshot.lastFailure?.recoverability == "audioRetiredVideoContinues")
    try await expectRetiredAudioAllowsSeek(
        in: session,
        check: "audio-retirement-playback",
        expectedStage: "audioProvider.readFailed.videoContinues"
    )
}

@Test func audioSeekOpenFailureRetiresAudioButVideoStillDelivers() async throws {
    let audioSample = try makeAudioSample(durationSeconds: 5)
    let session = SampleBufferPlaybackSession(
        traceID: "audio-seek-open-error-session",
        provider: FakeVideoSampleProvider(
            events: try audioRetirementVideoEvents(),
            eventDelay: .milliseconds(25)
        ),
        audioProvider: FakeAudioSampleProvider(
            sampleAfterPrepare: audioSample,
            failingPrepareOrdinal: 2
        ),
        rendererSink: FakeRendererInputSink(),
        audioRendererSink: FakeAudioRendererInputSink(),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/audio-seek-open-error.mp4"))
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForAudioSampleCount(1, in: session)

    try await expectRetiredAudioAllowsSeek(
        in: session,
        check: "audio-retirement-seek",
        expectedStage: "audioProvider.seekOpenFailed.videoContinues",
        retirementOccursDuringSeek: true
    )
}

@Test func missingFirstDisplayedFrameFailsWithoutGuessingTheCause() async throws {
    let fixture = playbackCoreTestMedia.appendingPathComponent(
        "Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS/DoVi_P20_09180_t1080p/fileSequence0.mp4"
    )
    let session = SampleBufferPlaybackSession(
        traceID: "missing-first-displayed-frame-session",
        provider: FakeVideoSampleProvider(events: [.end]),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameDeadline: .milliseconds(20),
        firstVideoFrameObservation: { false }
    )
    defer { session.close() }

    #expect(
        try #require(
            FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as? NSNumber
        ).intValue == 1_055
    )
    try await session.prepare(url: fixture)
    try session.start()
    try await waitForLifecycle(.failed, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.lastFailure?.stage == "videoRenderer.firstFrameTimedOut")
    #expect(snapshot.lastFailure?.message == "No video frame was displayed within 0.02 seconds after playback started.")
    #expect(snapshot.lastFailure?.message.contains("HLS") == false)
}

@Test func pausedStartBeginsFirstFrameDeadlineOnlyAfterPlay() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "paused-first-frame-deadline-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameDeadline: .milliseconds(20),
        firstVideoFrameObservation: { false }
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/paused.mp4"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await Task.sleep(for: .milliseconds(50))

    #expect(session.debugSnapshot().lifecycle != .failed)

    try session.play()
    try await waitForLifecycle(.failed, in: session)
    #expect(
        session.debugSnapshot().lastFailure?.stage
            == "videoRenderer.firstFrameTimedOut"
    )
}

@Test func rendererHandoffCancelsAnArmedFirstFrameDeadline() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "handoff-cancels-first-frame-deadline-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameDeadline: .milliseconds(40),
        firstVideoFrameObservation: { false }
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/handoff.mp4"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(1, in: session)
    try session.play()
    await session.suspendVideoSampleDelivery()
    session.allowVideoSampleDeliveryRestart()
    try await Task.sleep(for: .milliseconds(80))

    #expect(session.debugSnapshot().lifecycle != .failed)
    #expect(session.debugSnapshot().lastFailure == nil)
}

@Test func externallyManagedFirstFrameDeadlineDoesNotFailPlayback() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "externally-managed-first-frame-deadline-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameDeadline: .milliseconds(20),
        firstVideoFrameObservation: { false }
    )
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/externally-managed.mp4"),
        startsPaused: true
    )
    try session.start()
    try await waitForSampleCount(1, in: session)
    try session.play(armingFirstVideoFrameDeadline: false)
    try await Task.sleep(for: .milliseconds(50))

    #expect(session.debugSnapshot().lifecycle != .failed)
    #expect(session.debugSnapshot().lastFailure == nil)
}

@Test func acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim() async throws {
    let sample = try firstCompressedVideoSample(
        relativePath: "TestVectors/Upstream/FATE/ProRes/Sequence_1-Apple_ProRes_422.mov"
    )
    let sink = FakeRendererInputSink(
        enqueueOutcomes: [.acceptedWithWarnings(["Cannot Decode"])]
    )
    let session = SampleBufferPlaybackSession(
        traceID: "accepted-prores-without-displayed-frame-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: sink,
        firstVideoFrameDeadline: .milliseconds(20),
        firstVideoFrameObservation: { false }
    )
    defer { session.close() }

    try await session.prepare(
        url: playbackCoreTestMedia.appendingPathComponent(
            "TestVectors/Upstream/FATE/ProRes/Sequence_1-Apple_ProRes_422.mov"
        )
    )
    try session.start()
    try await waitForLifecycle(.failed, in: session)

    let snapshot = session.debugSnapshot()
    #expect(snapshot.acceptedRendererInputCount == 1)
    #expect(snapshot.lastFailure?.stage == "videoRenderer.firstFrameTimedOut")
    #expect(snapshot.lastFailure?.message == "Cannot Decode")
}

@Test func displayedFrameSatisfiesFirstFrameDeadline() async throws {
    let sample = try makeCompressedH264Sample(durationSeconds: 1)
    let session = SampleBufferPlaybackSession(
        traceID: "displayed-first-frame-session",
        provider: FakeVideoSampleProvider(events: [.sample(sample), .end]),
        rendererSink: FakeRendererInputSink(),
        firstVideoFrameDeadline: .milliseconds(20),
        firstVideoFrameObservation: { true }
    )
    defer { session.close() }

    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/displayed.mp4"))
    try session.start()
    try await Task.sleep(for: .milliseconds(50))

    #expect(session.debugSnapshot().lifecycle != .failed)
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

@Test(arguments: [RendererFailureKind.video])
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

@Test func audioRendererFailureRetiresAudioAndVideoContinues() async throws {
    let audioSample = try makeAudioSample(durationSeconds: 5)
    let sink = FakeRendererInputSink()
    let monitor = FakeRendererFailureMonitor()
    let session = SampleBufferPlaybackSession(
        traceID: "audio-renderer-retirement-session",
        provider: FakeVideoSampleProvider(
            events: try audioRetirementVideoEvents(),
            eventDelay: .milliseconds(25)
        ),
        audioProvider: FakeAudioSampleProvider(sampleAfterPrepare: audioSample),
        rendererSink: sink,
        audioRendererSink: FakeAudioRendererInputSink(),
        rendererFailureMonitor: monitor,
        firstVideoFrameObservation: { true }
    )
    let statuses = LockedBox<[PlaybackStatus]>([])
    session.onStatusChange = { status in
        statuses.withLock { $0.append(status) }
    }
    defer { session.close() }

    try await session.prepare(
        url: URL(fileURLWithPath: "/fixtures/audio-renderer-failure.mp4")
    )
    try session.start()
    try await waitForSampleCount(1, in: session)
    try await waitForAudioSampleCount(1, in: session)
    let samplesBeforeFailure = sink.enqueuedSampleCount
    let fact = RendererFailureFact(
        rendererKind: .audio,
        errorType: "InjectedAudioRendererError",
        message: "Injected audio renderer failure",
        requiresFlushToResumeDecoding: nil
    )

    monitor.send(fact)

    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline,
        session.debugSnapshot().audioRendererState?.error != fact.message {
        try await Task.sleep(for: .milliseconds(10))
    }
    try await waitForSampleCount(UInt64(samplesBeforeFailure + 1), in: session)

    let snapshot = session.debugSnapshot()
    #expect(session.hasAudio == false)
    #expect(snapshot.lifecycle != .failed)
    #expect(snapshot.lastFailure?.stage == "audioRenderer.failed.videoContinues")
    #expect(snapshot.lastFailure?.recoverability == "audioRetiredVideoContinues")
    #expect(snapshot.lastFailure?.rendererKind == RendererFailureKind.audio.rawValue)
    #expect(snapshot.lastFailure?.errorType == fact.errorType)
    #expect(snapshot.audioRendererState?.error == fact.message)
    #expect(snapshot.lastError == nil)
    try await expectRetiredAudioAllowsSeek(
        in: session,
        check: "audio-retirement-renderer",
        expectedStage: "audioRenderer.failed.videoContinues"
    )
    #expect(statuses.withLock { values in
        values.contains { status in
            if case .failed = status { true } else { false }
        }
    } == false)
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
    #expect(snapshot.providerOpen?.isMVHEVC == false)
    #expect(snapshot.videoTrack?.selected == true)
}

@Test
func repeatedSessionStartDoesNotRestartThePreparedProvider() async throws {
    let provider = FakeVideoSampleProvider(events: [.end])
    let session = SampleBufferPlaybackSession(
        traceID: "idempotent-session-start",
        provider: provider,
        rendererSink: FakeRendererInputSink()
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

private func playbackEndReason(of status: PlaybackStatus) -> PlaybackEndReason? {
    guard case .ended(let receipt) = status else { return nil }
    return receipt.reason
}

private func fixtureSource(_ name: String) -> MediaSourceRecord {
    MediaSourceRecord(
        locator: URL(fileURLWithPath: "/fixtures/\(name)"),
        provenance: "testAutomation",
        privacySafeSummary: name,
        accessRequirement: "notRequired"
    )
}

private final class GenerationDelayedVideoSampleProvider: VideoSampleProvider {
    let info: VideoSampleProviderInfo

    private let lock = NSLock()
    private let sample: CMSampleBuffer
    private let firstReadDelays: [Int: Duration]
    private var prepareGeneration = 0
    private var readCountByGeneration: [Int: Int] = [:]
    private var firstReadStartedGenerations: Set<Int> = []
    private var firstReadReturnedGenerations: Set<Int> = []

    init(
        sample: CMSampleBuffer,
        durationSeconds: Double,
        firstReadDelays: [Int: Duration]
    ) {
        self.sample = sample
        self.firstReadDelays = firstReadDelays
        info = FakeVideoSampleProvider(
            events: [],
            durationSeconds: durationSeconds
        ).info
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?,
        startTime: CMTime
    ) async throws {
        lock.withLock {
            prepareGeneration += 1
            readCountByGeneration[prepareGeneration] = 0
        }
    }

    func start() throws {}

    func nextEvent() async throws -> VideoSampleProviderEvent {
        let read = lock.withLock { () -> (generation: Int, ordinal: Int, delay: Duration) in
            let generation = prepareGeneration
            let ordinal = readCountByGeneration[generation, default: 0]
            readCountByGeneration[generation] = ordinal + 1
            if ordinal == 0 {
                firstReadStartedGenerations.insert(generation)
            }
            return (generation, ordinal, firstReadDelays[generation] ?? .zero)
        }
        if read.delay > .zero {
            await Task.detached {
                try? await Task.sleep(for: read.delay)
            }.value
        }
        if read.ordinal == 0 {
            _ = lock.withLock {
                firstReadReturnedGenerations.insert(read.generation)
            }
            return .sample(sample)
        }
        return .end
    }

    func cancel() {}

    func waitUntilFirstReadStarts(forGeneration generation: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if lock.withLock({ firstReadStartedGenerations.contains(generation) }) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for generation \(generation) to start reading")
    }

    func waitUntilFirstReadReturns(forGeneration generation: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if lock.withLock({ firstReadReturnedGenerations.contains(generation) }) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for generation \(generation) to finish reading")
    }
}

final class FakeVideoSampleProvider: VideoSampleProvider {
    let info: VideoSampleProviderInfo

    private var events: [VideoSampleProviderEvent]
    private var index = 0
    private let seekPrepareDelay: Duration?
    private let seekPrepareIgnoresCancellation: Bool
    private let readError: Error?
    private let eventDelay: Duration?
    private let postSeekEventDelay: Duration?
    private var deliversAfterSeek = false
    private(set) var startCount = 0
    private(set) var sourceInformationReceived: MediaSourceInformation?

    init(
        events: [VideoSampleProviderEvent],
        seekPrepareDelay: Duration? = nil,
        seekPrepareIgnoresCancellation: Bool = false,
        readError: Error? = nil,
        eventDelay: Duration? = nil,
        postSeekEventDelay: Duration? = nil,
        projectionKind: String? = nil,
        durationSeconds: Double = 60,
        nominalFrameRate: Double = 30
    ) {
        info = VideoSampleProviderInfo(
            providerKind: "Fake",
            containerFormat: "fixture",
            durationSeconds: durationSeconds,
            nominalFrameRate: nominalFrameRate,
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
        self.postSeekEventDelay = postSeekEventDelay
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?,
        startTime: CMTime
    ) async throws {
        sourceInformationReceived = sourceInformation
        deliversAfterSeek = startTime > .zero
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
        if deliversAfterSeek, let postSeekEventDelay {
            try await Task.sleep(for: postSeekEventDelay)
        }
        guard index < events.count else { return .end }
        defer { index += 1 }
        return events[index]
    }

    func cancel() {}
}

private final class FakeRendererInputSink: RendererInputSink, @unchecked Sendable {
    private let lock = NSLock()
    private let completesFlushImmediately: Bool
    private var samples: [CMSampleBuffer] = []
    private var rendererFlushCount = 0
    private var lastFlushRemovedImage: Bool?
    private var pendingFlushContinuations: [CheckedContinuation<Void, Never>] = []
    private var availableFlushCompletions = 0
    private var enqueueOutcomes: [RendererEnqueueOutcome]
    private var immediateEnqueueCounter = 0
    private var eventObservationCount = 0
    private var eventObservationStartedWithoutSample = false

    init(
        completesFlushImmediately: Bool = true,
        enqueueOutcomes: [RendererEnqueueOutcome] = []
    ) {
        self.completesFlushImmediately = completesFlushImmediately
        self.enqueueOutcomes = enqueueOutcomes
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

    var lastFlushRemovedDisplayedImage: Bool? {
        lock.withLock { lastFlushRemovedImage }
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

    func flush(removingDisplayedImage: Bool) async {
        let waitsForCompletion = lock.withLock {
            samples.removeAll()
            rendererFlushCount += 1
            lastFlushRemovedImage = removingDisplayedImage
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

}

#if DEBUG
private final class PlaybackSwitchRendererSampleSpy:
    PlaybackSwitchRendererSampleSink,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedSamples: [PlaybackSwitchRendererSample] = []

    var samples: [PlaybackSwitchRendererSample] {
        lock.withLock { recordedSamples }
    }

    func recordPlaybackSwitchRendererSample(_ sample: PlaybackSwitchRendererSample) {
        lock.withLock { recordedSamples.append(sample) }
    }
}
#endif

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
    private(set) var sourceInformationReceived: MediaSourceInformation?
    private let failingStreamIndex: Int?
    private let sampleAfterPrepare: CMSampleBuffer?
    private let repeatsSample: Bool
    private let readError: Error?
    private let failingPrepareOrdinal: Int?
    private let trackListError: Error?
    private var nextSample: CMSampleBuffer?
    private var prepareOrdinal = 0

    init(
        failingStreamIndex: Int? = nil,
        sampleAfterPrepare: CMSampleBuffer? = nil,
        repeatsSample: Bool = false,
        readError: Error? = nil,
        failingPrepareOrdinal: Int? = nil,
        trackListError: Error? = nil
    ) {
        self.failingStreamIndex = failingStreamIndex
        self.sampleAfterPrepare = sampleAfterPrepare
        self.repeatsSample = repeatsSample
        self.readError = readError
        self.failingPrepareOrdinal = failingPrepareOrdinal
        self.trackListError = trackListError
    }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        if let trackListError { throw trackListError }
        return [
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

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) async throws -> [PlaybackAudioTrack] {
        sourceInformationReceived = sourceInformation
        if let trackListError { throw trackListError }
        if let sourceInformation {
            return sourceInformation.playbackAudioTracks
        }
        return try await tracks(in: url, asset: asset)
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
        prepareOrdinal += 1
        preparedStreamIndices.append(streamIndex)
        if prepareOrdinal == failingPrepareOrdinal {
            throw FakeSampleError.audioPrepare
        }
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
        if let readError { throw readError }
        let sample = nextSample
        if !repeatsSample { nextSample = nil }
        return sample
    }

    func cancel() {
        info = nil
        nextSample = nil
    }
}

private final class FixedMediaSourceInformationLoader:
    MediaSourceInformationLoading,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let information: MediaSourceInformation
    private var storedLoadCount = 0

    init(_ information: MediaSourceInformation) {
        self.information = information
    }

    var loadCount: Int { lock.withLock { storedLoadCount } }

    func load(from url: URL) async throws -> MediaSourceInformation {
        lock.withLock { storedLoadCount += 1 }
        return information
    }
}

private final class MediaInformationRecordingSubtitleProvider: SubtitleProvider {
    private(set) var sourceInformationReceived: MediaSourceInformation?

    func tracks(
        in url: URL,
        asset: PlaybackAsset?
    ) async throws -> [PlaybackSubtitleTrack] {
        []
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) async throws -> [PlaybackSubtitleTrack] {
        sourceInformationReceived = sourceInformation
        return sourceInformation?.playbackSubtitleTracks ?? []
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        []
    }

    func cancel() {}
}

private final class StubSubtitleFrameRenderer: SubtitleFrameRendering, @unchecked Sendable {
    let stateDescription: String
    let holdsUndecodablePackets: Bool
    private let producedFrame: PlaybackSubtitleFrame?

    init(
        frame: PlaybackSubtitleFrame? = nil,
        holdsUndecodablePackets: Bool = false,
        stateDescription: String = ""
    ) {
        producedFrame = frame
        self.holdsUndecodablePackets = holdsUndecodablePackets
        self.stateDescription = stateDescription
    }

    func frame(
        at time: CMTime,
        viewportWidth: Int,
        viewportHeight: Int
    ) throws -> PlaybackSubtitleFrame? {
        producedFrame
    }
}

private final class StubSubtitleProvider: SubtitleProvider {
    private let tracks: [PlaybackSubtitleTrack]
    private let trackCues: [PlaybackSubtitleCue]
    private let renderer: SubtitleFrameRendering?

    init(
        tracks: [PlaybackSubtitleTrack],
        cues: [PlaybackSubtitleCue] = [],
        renderer: SubtitleFrameRendering? = nil
    ) {
        self.tracks = tracks
        trackCues = cues
        self.renderer = renderer
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?
    ) async throws -> [PlaybackSubtitleTrack] {
        tracks
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        trackCues
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? {
        renderer
    }

    func cancel() {}
}

private final class TrackListFailingSubtitleProvider: SubtitleProvider {
    private(set) var cancelCount = 0

    func tracks(
        in url: URL,
        asset: PlaybackAsset?
    ) async throws -> [PlaybackSubtitleTrack] {
        throw FakeSampleError.subtitleTrackList
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        throw FakeSampleError.subtitleTrackList
    }

    func cancel() { cancelCount += 1 }
}

private final class FakeAudioRendererInputSink: AudioRendererInputSink, @unchecked Sendable {
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
        "Audio codec ac4 is unsupported because FFmpeg has no decoder"
    }
}

private func unsupportedAC4Fixture() throws -> URL {
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("playbackcore-unsupported-\(UUID().uuidString).ac4")
    let probeableFrame: [UInt8] = [0xAC, 0x40, 0x00, 0x04, 0, 0, 0, 0]
    try Data((0..<32).flatMap { _ in probeableFrame }).write(
        to: fixture,
        options: .atomic
    )
    return fixture
}

private func audioRetirementVideoEvents() throws -> [VideoSampleProviderEvent] {
    try [0.0, 30.0, 31.0, 32.0]
        .map {
            try makeCompressedH264Sample(
                presentationTimeSeconds: $0,
                durationSeconds: 1
            )
        }
        .map(VideoSampleProviderEvent.sample) + [.end]
}

private func waitForAudioRetirement(
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(7)
    while ContinuousClock.now < deadline {
        if session.diagnostics.audioRetired { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for audio retirement")
}

private func expectRetiredAudioAllowsSeek(
    in session: SampleBufferPlaybackSession,
    check structuralCheck: String,
    expectedStage: String,
    retirementOccursDuringSeek: Bool = false
) async throws {
    let before = session.debugSnapshot()
    let sessionID = try #require(before.mediaSession?.mediaSessionID)
    let audioRetiredBeforeSeek = session.diagnostics.audioRetired
    #expect(before.lifecycle == .playing || before.lifecycle == .paused)
    if retirementOccursDuringSeek {
        #expect(audioRetiredBeforeSeek == false)
    } else {
        #expect(audioRetiredBeforeSeek)
        #expect(before.lastFailure?.stage == expectedStage)
    }

    let seekTargetSeconds = 30.0
    try await session.seek(
        to: CMTime(seconds: seekTargetSeconds, preferredTimescale: 600),
        startsPaused: true
    )

    let after = session.debugSnapshot()
    let audioRetiredAfterSeek = session.diagnostics.audioRetired
    #expect(audioRetiredAfterSeek)
    #expect(after.lifecycle == .paused)
    #expect(after.mediaSession?.mediaSessionID == sessionID)
    #expect(after.lastFailure?.stage == expectedStage)
    let videoPresentationTimeSecondsAfterSeek = after.lastVideoSample?
        .presentationTimeSeconds
    #expect((videoPresentationTimeSecondsAfterSeek ?? -.infinity) >= seekTargetSeconds)

    let fields = [
        "\"assertion\":\"audio-retirement-nonfatal-seek\"",
        "\"check\":\"\(structuralCheck)\"",
        "\"expectedStage\":\"\(expectedStage)\"",
        "\"retirementOccursDuringSeek\":\(retirementOccursDuringSeek)",
        "\"lifecycleBeforeSeek\":\"\(before.lifecycle.rawValue)\"",
        "\"lifecycleAfterSeek\":\"\(after.lifecycle.rawValue)\"",
        "\"audioRetiredBeforeSeek\":\(audioRetiredBeforeSeek)",
        "\"audioRetiredAfterSeek\":\(audioRetiredAfterSeek)",
        "\"mediaSessionIDBeforeSeek\":\"\(sessionID)\"",
        "\"mediaSessionIDAfterSeek\":\"\(after.mediaSession?.mediaSessionID ?? "")\"",
        "\"failureStageBeforeSeek\":\"\(before.lastFailure?.stage ?? "")\"",
        "\"failureStageAfterSeek\":\"\(after.lastFailure?.stage ?? "")\"",
        "\"failureRecoverabilityAfterSeek\":\"\(after.lastFailure?.recoverability ?? "")\"",
        "\"seekTargetSeconds\":\(seekTargetSeconds)",
        "\"videoPresentationTimeSecondsAfterSeek\":"
            + (videoPresentationTimeSecondsAfterSeek.map { String($0) } ?? "null"),
        "\"lastErrorPresentAfterSeek\":\(after.lastError != nil)",
    ]
    print("ENCHRON_ASSERTION {\(fields.joined(separator: ","))}")
}

func makeCompressedH264Sample(
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

private func waitForAcceptedRendererInputCount(
    _ count: UInt64,
    in session: SampleBufferPlaybackSession
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if session.debugSnapshot().acceptedRendererInputCount >= count { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for accepted renderer input count \(count)")
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

private func firstCompressedVideoSample(relativePath: String) throws -> CMSampleBuffer {
    let fixture = playbackCoreTestMedia.appendingPathComponent(relativePath)
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(
        reader,
        Comment(rawValue: "\(relativePath): \(String(cString: error))")
    )
    defer { PBFFmpegReaderDestroy(activeReader) }
    var sample: Unmanaged<CMSampleBuffer>?
    #expect(
        PBFFmpegReaderCopyNextSample(
            activeReader,
            &sample,
            &error,
            error.count
        ) == PBFFmpegReadResultSample,
        Comment(rawValue: "\(relativePath): \(String(cString: error))")
    )
    return try #require(sample?.takeRetainedValue())
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
    case audioRead
    case subtitleTrackList
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

private let audioSwitchTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")

@Test func audioTrackSelectionWhilePlayingRestartsTheTimelineThroughPreroll() async throws {
    let fixture = audioSwitchTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv"
    )
    try #require(FileManager.default.fileExists(atPath: fixture.path))
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let session = SampleBufferPlaybackSession(
        traceID: "audio-switch-while-playing",
        provider: FFmpegSampleProvider(sourceReadMeter: meter, demuxSession: demuxSession),
        audioProvider: FFmpegAudioSampleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession,
        rendererSink: FakeRendererInputSink()
    )
    try await session.prepare(url: fixture)
    try session.start()
    func actualTimebaseRate() -> Float {
        session.debugSnapshot().rendererState?.actualTimebaseRate ?? 0
    }
    func currentTimeSeconds() -> Double {
        session.debugSnapshot().rendererState?.currentTimeSeconds ?? 0
    }
    var deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline,
          actualTimebaseRate() <= 0 || currentTimeSeconds() < 0.5 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(actualTimebaseRate() > 0)
    let tracks = session.availableAudioTracks
    let replacement = try #require(
        tracks.first { $0.streamIndex != session.selectedAudioStreamIndex }
    )

    try await session.selectAudioTrack(streamIndex: replacement.streamIndex)

    deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, actualTimebaseRate() <= 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
    let snapshot = session.debugSnapshot()
    #expect(snapshot.rendererState?.actualTimebaseRate ?? 0 > 0)
    #expect(snapshot.lifecycle == .playing)
    #expect(session.currentRate() == 1)
    #expect(session.selectedAudioStreamIndex == replacement.streamIndex)
    #expect(snapshot.audioTrack?.rawStreamIndex == replacement.streamIndex)
    #expect(snapshot.timelineControlState?.lastRateActivation?.reason == .decoderBootstrap)
    await session.closeAndWait()
}

@Test func audioTrackRestoreWhileOpeningKeepsTheRequestedStartRateAndPosition() async throws {
    let fixture = audioSwitchTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv"
    )
    try #require(FileManager.default.fileExists(atPath: fixture.path))
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let session = SampleBufferPlaybackSession(
        traceID: "audio-restore-while-opening",
        provider: FFmpegSampleProvider(sourceReadMeter: meter, demuxSession: demuxSession),
        audioProvider: FFmpegAudioSampleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession,
        rendererSink: FakeRendererInputSink()
    )
    try await session.prepare(
        url: fixture,
        startTime: CMTime(seconds: 8, preferredTimescale: 600),
        initialRate: 0.5
    )
    try session.start()
    let replacement = try #require(
        session.availableAudioTracks.first { $0.streamIndex != session.selectedAudioStreamIndex }
    )

    try await session.selectAudioTrack(streamIndex: replacement.streamIndex)

    let controlState = try #require(session.debugSnapshot().timelineControlState)
    #expect(controlState.timelineStartRate == 0.5)
    #expect(controlState.requestedTimelineStartSeconds == 8)
    func actualTimebaseRate() -> Float {
        session.debugSnapshot().rendererState?.actualTimebaseRate ?? 0
    }
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, actualTimebaseRate() <= 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
    let snapshot = session.debugSnapshot()
    #expect(snapshot.rendererState?.actualTimebaseRate ?? 0 > 0.4)
    #expect(snapshot.rendererState?.currentTimeSeconds ?? 0 >= 7.9)
    #expect(session.selectedAudioStreamIndex == replacement.streamIndex)
    await session.closeAndWait()
}

private final class SeekTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] {
        lock.withLock { recorded }
    }

    func install() {
        PlaybackTrace.installSink { [weak self] event in
            guard let self else { return }
            lock.withLock { recorded.append(event) }
        }
    }

    func uninstall() {
        PlaybackTrace.installSink(nil)
    }
}
