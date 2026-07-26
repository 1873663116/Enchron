import CoreMedia
import Foundation
import Testing
@testable import PlaybackCore

@Test func ffmpegSubtitleProviderBuildsStableTracksAndTimedCuesFromSubRip() async throws {
    let fixture = try subtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()

    let firstTracks = try await provider.tracks(in: fixture, asset: nil)
    let secondTracks = try await provider.tracks(in: fixture, asset: nil)

    #expect(firstTracks == secondTracks)
    #expect(firstTracks.map(\.id) == ["ffmpeg.subtitle.1", "ffmpeg.subtitle.2"])
    #expect(firstTracks.map(\.codecName) == ["subrip", "subrip"])
    #expect(firstTracks.map(\.language) == ["zho", "eng"])
    #expect(firstTracks.map(\.title) == ["简体中文", "English"])

    let cues = try await provider.cues(
        in: fixture,
        asset: nil,
        track: try #require(firstTracks.first)
    )
    #expect(cues.map(\.id) == ["ffmpeg.subtitle.1.cue.0", "ffmpeg.subtitle.1.cue.1"])
    #expect(cues[0].trackID == firstTracks[0].id)
    #expect(cues[0].text == "第一行\n第二行")
    #expect(abs(cues[0].timeRange.start.seconds - 0.5) < 0.001)
    #expect(abs(cues[0].timeRange.duration.seconds - 1.5) < 0.001)
    #expect(cues[1].text == "再见")
    #expect(abs(cues[1].timeRange.start.seconds - 3.0) < 0.001)
    #expect(abs(cues[1].timeRange.end.seconds - 4.25) < 0.001)
}

@Test func libassRendererProducesPremultipliedSubtitleFrameAtCueTime() async throws {
    let fixture = try subtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))

    let renderedFrame = try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    )
    let frame = try #require(renderedFrame)
    #expect(frame.kind == .libass)
    #expect(frame.canvasWidth == 1_920)
    #expect(frame.canvasHeight == 1_080)
    #expect(frame.contentWidth > 0)
    #expect(frame.contentHeight > 0)
    #expect(frame.premultipliedBGRA.count == frame.bytesPerRow * frame.contentHeight)
    #expect(stride(from: 3, to: frame.premultipliedBGRA.count, by: 4).contains {
        frame.premultipliedBGRA[$0] > 0
    })

    #expect(try renderer.frame(
        at: CMTime(seconds: 2.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) == nil)
}

@Test func bitmapSubtitleRendererPreservesDecodedPixelsAndCanvasPlacement() async throws {
    let fixture = try bitmapSubtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    #expect(track.codecName == "dvb_subtitle")
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))

    let renderedFrame = try renderer.frame(
        at: CMTime(seconds: 0.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    )
    let frame = try #require(renderedFrame)
    #expect(frame.kind == .bitmap)
    #expect(frame.canvasWidth >= frame.contentX + frame.contentWidth)
    #expect(frame.canvasHeight >= frame.contentY + frame.contentHeight)
    #expect(frame.contentWidth > 0)
    #expect(frame.contentHeight > 0)
    #expect(frame.premultipliedBGRA.count == frame.bytesPerRow * frame.contentHeight)
    #expect(stride(from: 3, to: frame.premultipliedBGRA.count, by: 4).contains {
        frame.premultipliedBGRA[$0] > 0
    })
}

@Test func mediaSessionSelectsSubtitlesAndUsesSynchronizerTimeForActiveCues() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-selection",
        provider: SubtitleTestVideoProvider(),
        subtitleProvider: FFmpegSubtitleProvider()
    )
    try await session.prepare(url: try subtitleFixtureURL())

    #expect(session.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])
    #expect(session.selectedSubtitleTrackID == nil)
    #expect(session.activeSubtitleCues.isEmpty)

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )
    #expect(session.selectedSubtitleTrackID == "ffmpeg.subtitle.1")
    #expect(session.activeSubtitleCues.map(\.text) == ["第一行\n第二行"])

    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 2.25, preferredTimescale: 600)
    )
    #expect(session.activeSubtitleCues.isEmpty)

    try await session.selectSubtitleTrack(id: nil)
    #expect(session.selectedSubtitleTrackID == nil)
    #expect(session.activeSubtitleCues.isEmpty)
    await session.closeAndWait()
}

@MainActor
@Test func controllerPublishesSubtitleSelectionAndOffState() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: SubtitleTestVideoProvider(),
            subtitleProvider: FFmpegSubtitleProvider()
        )
    }
    let session = try await controller.open(
        try subtitleFixtureURL(),
    )

    #expect(controller.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])
    try await controller.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )
    #expect(controller.selectedSubtitleTrackID == "ffmpeg.subtitle.1")
    #expect(controller.activeSubtitleCues.map(\.text) == ["第一行\n第二行"])

    try await controller.selectSubtitleTrack(id: nil)
    #expect(controller.selectedSubtitleTrackID == nil)
    #expect(controller.activeSubtitleCues.isEmpty)
    await controller.closeAndWait()
}

@Test func seekSuppressesOldCueUntilTheNewSynchronizerPositionCommits() async throws {
    let sink = SubtitleTestRendererInputSink(flushDelay: .milliseconds(100))
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-seek",
        provider: FFmpegSampleProvider(),
        subtitleProvider: FFmpegSubtitleProvider(),
        rendererSink: sink
    )
    try await session.prepare(url: try subtitleFixtureURL())
    try session.start()
    try await waitForSubtitleTestSample(in: session)
    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )
    #expect(session.activeSubtitleCues.map(\.text) == ["第一行\n第二行"])

    let seek = Task {
        try await session.seek(
            to: CMTime(seconds: 2.5, preferredTimescale: 600),
            startsPaused: true
        )
    }
    try await Task.sleep(for: .milliseconds(20))
    #expect(session.activeSubtitleCues.isEmpty)
    try await seek.value
    #expect(session.activeSubtitleCues.isEmpty)
    await session.closeAndWait()
}

@MainActor
@Test func rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition() async throws {
    let sink = SubtitleTestRendererInputSink(flushDelay: .milliseconds(100))
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: FFmpegSampleProvider(),
            subtitleProvider: FFmpegSubtitleProvider(),
            rendererSink: sink
        )
    }
    let session = try await controller.open(
        try subtitleFixtureURL(),
    )
    try controller.start()
    try await waitForSubtitleTestSample(in: session)
    try await controller.selectSubtitleTrack(id: "ffmpeg.subtitle.1")

    let first = Task { @MainActor in
        try await controller.seek(
            to: CMTime(seconds: 1.25, preferredTimescale: 600),
            startsPaused: true
        )
    }
    try await Task.sleep(for: .milliseconds(20))
    #expect(controller.activeSubtitleCues.isEmpty)
    let second = Task { @MainActor in
        try await controller.seek(
            to: CMTime(seconds: 3.5, preferredTimescale: 600),
            startsPaused: true
        )
    }

    do {
        try await first.value
        Issue.record("Expected the first subtitle seek to be superseded")
    } catch let error as PlaybackControlError {
        guard case .seekSuperseded(let target) = error else {
            Issue.record("Expected seekSuperseded, got \(error)")
            return
        }
        #expect(target == 1.25)
    }
    try await second.value

    #expect(controller.selectedSubtitleTrackID == "ffmpeg.subtitle.1")
    #expect(controller.activeSubtitleCues.map(\.text) == ["再见"])
    await controller.closeAndWait()
}

@Test func closeClearsSubtitleStateAndRejectsLateCueLoad() async throws {
    let subtitleProvider = DelayedSubtitleTestProvider()
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-close",
        provider: SubtitleTestVideoProvider(),
        subtitleProvider: subtitleProvider,
        rendererSink: SubtitleTestRendererInputSink()
    )
    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/subtitle-close.mkv"))

    let selection = Task {
        try await session.selectSubtitleTrack(id: "fake.subtitle.1")
    }
    try await Task.sleep(for: .milliseconds(20))
    await session.closeAndWait()
    _ = try? await selection.value

    #expect(session.availableSubtitleTracks.isEmpty)
    #expect(session.selectedSubtitleTrackID == nil)
    #expect(session.activeSubtitleCues.isEmpty)
}

@Test func debugSnapshotCorrelatesSubtitleSelectionGenerationAndEpoch() async throws {
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-diagnostics",
        provider: SubtitleTestVideoProvider(),
        subtitleProvider: FFmpegSubtitleProvider(),
        rendererSink: SubtitleTestRendererInputSink()
    )
    try await session.prepare(url: try subtitleFixtureURL())
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )

    let prepared = try #require(session.debugSnapshot().subtitleState)
    #expect(prepared.availableTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])
    #expect(prepared.selectedTrackID == nil)
    #expect(prepared.streamEpoch == 1)
    #expect(prepared.selectionGeneration == 0)

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    let selected = try #require(session.debugSnapshot().subtitleState)
    #expect(selected.selectedTrackID == "ffmpeg.subtitle.1")
    #expect(selected.activeCueIDs == ["ffmpeg.subtitle.1.cue.0"])
    #expect(selected.streamEpoch == 2)
    #expect(selected.selectionGeneration == 1)

    try await session.selectSubtitleTrack(id: nil)
    let off = try #require(session.debugSnapshot().subtitleState)
    #expect(off.selectedTrackID == nil)
    #expect(off.activeCueIDs.isEmpty)
    #expect(off.streamEpoch == 3)
    #expect(off.selectionGeneration == 2)
    await session.closeAndWait()
}

@Test func subtitleCueChangesArePublishedFromSynchronizerTime() async throws {
    let recorder = SubtitleCueRecorder()
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-callback",
        provider: SubtitleTestVideoProvider(),
        subtitleProvider: FFmpegSubtitleProvider(),
        rendererSink: SubtitleTestRendererInputSink()
    )
    session.onSubtitleCuesChange = { cues in
        recorder.append(cues.map(\.text))
    }
    try await session.prepare(url: try subtitleFixtureURL())
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    try await session.selectSubtitleTrack(id: nil)

    #expect(recorder.values == [["第一行\n第二行"], []])
    await session.closeAndWait()
}

@Test func debugSnapshotDecodesBeforeSubtitleStateWasAdded() throws {
    let current = PlaybackDebugSnapshotV1()
    let encoded = try JSONEncoder().encode(current)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "subtitleState")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(PlaybackDebugSnapshotV1.self, from: legacy)
    #expect(decoded.subtitleState == nil)
}

@Test func changingSubtitleSelectionClearsThePreviousCueBeforeLoadingCompletes() async throws {
    let recorder = SubtitleCueRecorder()
    let session = SampleBufferPlaybackSession(
        traceID: "subtitle-selection-stale",
        provider: SubtitleTestVideoProvider(),
        subtitleProvider: DelayedSubtitleTestProvider(),
        rendererSink: SubtitleTestRendererInputSink()
    )
    session.onSubtitleCuesChange = { cues in
        recorder.append(cues.map(\.text))
    }
    try await session.prepare(url: URL(fileURLWithPath: "/fixtures/subtitle-stale.mkv"))
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )
    try await session.selectSubtitleTrack(id: "fake.subtitle.1")
    #expect(session.activeSubtitleCues.map(\.text) == ["late"])

    let replacement = Task {
        try await session.selectSubtitleTrack(id: "fake.subtitle.1")
    }
    try await Task.sleep(for: .milliseconds(20))

    #expect(session.activeSubtitleCues.isEmpty)
    #expect(recorder.values.last == [])
    try await replacement.value
    await session.closeAndWait()
}

private func subtitleFixtureURL() throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
}

private func bitmapSubtitleFixtureURL() throws -> URL {
    let encodedPackets = try #require(
        Bundle.module.url(
            forResource: "bitmap-generated.mks",
            withExtension: "base64",
            subdirectory: "Fixtures"
        )
    )
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "PlaybackCoreBitmapSubtitleFixture")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let fixture = directory.appending(path: "bitmap-generated.mks")
    let encoded = try Data(contentsOf: encodedPackets)
    let decoded = try #require(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
    try decoded.write(to: fixture, options: .atomic)
    return fixture
}

private final class SubtitleTestVideoProvider: VideoSampleProvider {
    let info = VideoSampleProviderInfo(
        providerKind: "SubtitleTestVideo",
        containerFormat: "matroska",
        durationSeconds: 5,
        nominalFrameRate: 24,
        codecName: "h264",
        codecTag: "avc1",
        dimensions: "160x90"
    )

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {}
    func start() throws {}
    func nextEvent() async throws -> VideoSampleProviderEvent { .end }
    func cancel() {}
}

private final class SubtitleTestRendererInputSink: RendererInputSink, @unchecked Sendable {
    private let flushDelay: Duration

    init(flushDelay: Duration = .zero) {
        self.flushDelay = flushDelay
    }

    func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome {
        .accepted
    }

    func enqueue(_ sample: RendererInputSample) async throws -> RendererEnqueueOutcome {
        .accepted
    }

    func flush(removingDisplayedImage: Bool) async {
        try? await Task.sleep(for: flushDelay)
    }
}

private final class DelayedSubtitleTestProvider: SubtitleProvider {
    private let track = PlaybackSubtitleTrack(
        id: "fake.subtitle.1",
        streamIndex: 1,
        codecName: "subrip",
        language: "zho",
        title: "简体中文"
    )

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] {
        [track]
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        await Task.detached {
            try? await Task.sleep(for: .milliseconds(100))
        }.value
        return [PlaybackSubtitleCue(
            id: "fake.subtitle.1.cue.0",
            trackID: track.id,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 5, preferredTimescale: 600)
            ),
            text: "late"
        )]
    }

    func cancel() {}
}

private final class SubtitleCueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [[String]] = []

    var values: [[String]] {
        lock.withLock { storedValues }
    }

    func append(_ value: [String]) {
        lock.withLock { storedValues.append(value) }
    }
}

private func waitForSubtitleTestSample(in session: SampleBufferPlaybackSession) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if session.debugSnapshot().sampleCount > 0 { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for subtitle fixture video sample")
}
