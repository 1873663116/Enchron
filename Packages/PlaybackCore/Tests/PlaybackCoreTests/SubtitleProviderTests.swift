import CoreMedia
import CoreText
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

@Test func sharedDemuxSourceBuildsSubtitleCuesAndFramesWithoutReopening() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let loader = SystemMediaSourceInformationLoader(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let provider = FFmpegSubtitleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let information = try await loader.load(from: fixture)
    let track = try #require(information.playbackSubtitleTracks.first)

    var cues = try await provider.cues(in: fixture, asset: nil, track: track)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, cues.count < 2 {
        cues += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cues.map(\.text) == ["第一行\n第二行", "再见"])
    #expect(try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) != nil)
}

@Test func sharedSourceSubtitleRendererFoldsInQueuedCuesWithoutDuplicatesAfterASeek() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let loader = SystemMediaSourceInformationLoader(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let provider = FFmpegSubtitleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let information = try await loader.load(from: fixture)
    let track = try #require(information.playbackSubtitleTracks.first)

    var cues = try await provider.cues(in: fixture, asset: nil, track: track)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, cues.count < 2 {
        cues += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cues.map(\.text) == ["第一行\n第二行", "再见"])
    #expect(cues.map(\.id) == ["ffmpeg.subtitle.1.cue.0", "ffmpeg.subtitle.1.cue.1"])
    #expect(try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) != nil)

    try demuxSession.seek(to: 0)
    var duplicates: [PlaybackSubtitleCue] = []
    let seekDeadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < seekDeadline {
        duplicates += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(
        duplicates.isEmpty,
        "the packets the shared source re-read after the backward seek came back as duplicate cues"
    )
    #expect(try renderer.ingestPendingCues(for: track).isEmpty)
}

@Test func aSubtitleRendererCreatedAfterAForwardSeekReceivesTheCuesThatFollow() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let loader = SystemMediaSourceInformationLoader(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let provider = FFmpegSubtitleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let information = try await loader.load(from: fixture)
    let track = try #require(information.playbackSubtitleTracks.first)

    let secondsPastTheFirstCue = 2.5
    try demuxSession.seek(to: secondsPastTheFirstCue)

    var cues = try await provider.cues(in: fixture, asset: nil, track: track)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, !cues.map(\.text).contains("再见") {
        cues += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(
        cues.map(\.text).contains("再见"),
        "the cue that follows the seek target never arrived through the shared source's queue"
    )
    #expect(try renderer.frame(
        at: CMTime(seconds: 3.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) != nil)
}

@Test func selectingAnEmbeddedSubtitleOpensNoSecondInputOnTheRemoteSource() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let videoProvider = FFmpegSampleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let session = SampleBufferPlaybackSession(
        traceID: "shared-subtitle-remote-no-second-input",
        provider: videoProvider,
        subtitleProvider: FFmpegSubtitleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    try await session.prepare(
        url: server.url,
        sourceTransport: .remoteByteStream(buffering: .automatic)
    )
    var settledBytes = meter.totalBytesRead
    for _ in 0..<50 {
        try await Task.sleep(for: .milliseconds(100))
        let bytes = meter.totalBytesRead
        if bytes == settledBytes { break }
        settledBytes = bytes
    }
    let connectionsBeforeSelection = server.connections
    let rangesBeforeSelection = server.ranges

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")

    #expect(session.selectedSubtitleTrackID == "ffmpeg.subtitle.1")
    #expect(
        server.connections == connectionsBeforeSelection,
        "selecting an embedded track opened a second connection to the source"
    )
    #expect(
        server.ranges == rangesBeforeSelection,
        "selecting an embedded track requested ranges of the source again"
    )
    videoProvider.cancel()
    session.close()
}

@MainActor
@Test func closingTheControllerWhileASubtitleSelectionIsInFlightSettles() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in SampleBufferPlaybackSession(traceID: sessionID) }
    )
    let session = try await controller.open(
        server.url,
        sourceTransport: .remoteByteStream(buffering: .automatic)
    )
    try await Task.sleep(for: .milliseconds(300))
    #expect(session.availableSubtitleTracks.map(\.id).contains("ffmpeg.subtitle.1"))

    server.stallNextRangeResponse()
    let selection = Task { try await controller.selectSubtitleTrack(id: "ffmpeg.subtitle.1") }
    try await Task.sleep(for: .milliseconds(300))

    let closeStarted = ContinuousClock.now
    await controller.closeAndWait()
    let closeDuration = ContinuousClock.now - closeStarted
    #expect(
        closeDuration < .seconds(2),
        "closing waited \(closeDuration) on the in-flight subtitle selection"
    )
    server.stop()
    _ = try? await selection.value
}

@Test func cancellingASubtitleSelectionReturnsWhileTheRemoteSourceStalls() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    try demuxSession.configureSource(transport: .remoteByteStream(buffering: .automatic))
    let loader = SystemMediaSourceInformationLoader(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let provider = FFmpegSubtitleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let information = try await loader.load(from: server.url)
    let track = try #require(information.playbackSubtitleTracks.first)
    try await Task.sleep(for: .milliseconds(300))

    server.stallNextRangeResponse()
    let selection = Task { try await provider.cues(in: server.url, asset: nil, track: track) }
    try await Task.sleep(for: .milliseconds(300))
    selection.cancel()
    let returned = SettledFlag()
    Task {
        _ = try? await selection.value
        returned.set()
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline, !returned.isSet {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(returned.isSet, "the cancelled selection kept reading the stalled source")
}

private final class SettledFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}

@Test func cancellingAnExternalSubtitleLoadReturnsWhileItsSourceStalls() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let provider = FFmpegSubtitleProvider()
    let track = PlaybackSubtitleTrack(
        id: "ffmpeg.subtitle.1",
        streamIndex: 1,
        codecName: "subrip",
        language: nil,
        title: nil
    )

    server.stallNextRangeResponse()
    let load = Task { try await provider.cues(in: server.url, asset: nil, track: track) }
    try await Task.sleep(for: .milliseconds(300))
    #expect(server.ranges == ["bytes=0-"], "the load never reached the stalled document request")
    load.cancel()
    let returned = SettledFlag()
    Task {
        _ = try? await load.value
        returned.set()
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline, !returned.isSet {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(returned.isSet, "the cancelled document load kept reading the stalled source")
}

@Test func cancellingAnExternalSubtitleRendererReturnsWhileItsSourceStalls() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let provider = FFmpegSubtitleProvider()
    let track = PlaybackSubtitleTrack(
        id: "ffmpeg.subtitle.1",
        streamIndex: 1,
        codecName: "subrip",
        language: nil,
        title: nil
    )

    server.stallNextRangeResponse()
    let load = Task { try await provider.frameRenderer(in: server.url, asset: nil, track: track) }
    try await Task.sleep(for: .milliseconds(300))
    #expect(server.ranges == ["bytes=0-"], "the load never reached the stalled document request")
    load.cancel()
    let returned = SettledFlag()
    Task {
        _ = try? await load.value
        returned.set()
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline, !returned.isSet {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(returned.isSet, "the cancelled document renderer kept reading the stalled source")
}

@Test func selectingASubtitleTrackCommitsWhileTheRemoteSourceStalls() async throws {
    let server = try RecordingRangeServer(serving: try Data(contentsOf: try subtitleFixtureURL()))
    defer { server.stop() }
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let videoProvider = FFmpegSampleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let session = SampleBufferPlaybackSession(
        traceID: "shared-subtitle-stalled-remote",
        provider: videoProvider,
        subtitleProvider: FFmpegSubtitleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    try await session.prepare(
        url: server.url,
        sourceTransport: .remoteByteStream(buffering: .automatic)
    )
    try await Task.sleep(for: .milliseconds(300))

    server.stallNextRangeResponse()
    let selection = Task { try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1") }
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline, session.selectedSubtitleTrackID == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(
        session.selectedSubtitleTrackID == "ffmpeg.subtitle.1",
        "the selection waited for a read of the stalled source instead of committing"
    )
    #expect(session.activeSubtitleCues(
        at: CMTime(seconds: 1, preferredTimescale: 600)
    ).map(\.text) == ["第一行\n第二行"])
    server.stop()
    _ = try? await selection.value
    videoProvider.cancel()
    session.close()
}

@Test func reselectingASubtitleTrackAfterTheSharedReaderEndedKeepsItsFrames() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let videoProvider = FFmpegSampleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let session = SampleBufferPlaybackSession(
        traceID: "shared-subtitle-reselect",
        provider: videoProvider,
        subtitleProvider: FFmpegSubtitleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    try await session.prepare(url: fixture)
    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    try videoProvider.start()
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        let event = try await videoProvider.nextEvent()
        session.publishSubtitleCues(at: .zero)
        if case .end = event { break }
    }
    func cueTexts() -> [String] {
        session.subtitleStateLock.withLock { session.subtitleState.cues.map(\.text) }
    }
    func frame(at seconds: Double) throws -> PlaybackSubtitleFrame? {
        let renderer = session.subtitleStateLock.withLock { session.subtitleState.frameRenderer }
        return try renderer?.frame(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        )
    }
    #expect(cueTexts() == ["第一行\n第二行", "再见"])
    #expect(try frame(at: 1) != nil)

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.2")
    #expect(cueTexts() == ["English subtitle"])

    try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    #expect(cueTexts() == ["第一行\n第二行", "再见"])
    #expect(try frame(at: 1) != nil)
    #expect(session.activeSubtitleCues(
        at: CMTime(seconds: 1, preferredTimescale: 600)
    ).map(\.text) == ["第一行\n第二行"])

    videoProvider.cancel()
    session.close()
}

@Test func sharedSourceSubtitleSelectionCommitsWhileVideoIsStillQueued() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let videoProvider = FFmpegSampleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let session = SampleBufferPlaybackSession(
        traceID: "shared-subtitle-incremental",
        provider: videoProvider,
        subtitleProvider: FFmpegSubtitleProvider(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
            sourceReadMeter: meter,
            demuxSession: demuxSession
        ),
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    try await session.prepare(url: fixture)
    #expect(session.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])

    let selection = Task { try await session.selectSubtitleTrack(id: "ffmpeg.subtitle.1") }
    let selectionDeadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < selectionDeadline,
          session.selectedSubtitleTrackID == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(session.selectedSubtitleTrackID == "ffmpeg.subtitle.1")
    guard session.selectedSubtitleTrackID != nil else {
        Issue.record("The selection waited for the shared source to end instead of committing")
        session.close()
        return
    }
    try await selection.value

    func ingestedCueTexts() -> [String] {
        session.subtitleStateLock.withLock { session.subtitleState.cues.map(\.text) }
    }
    func drainVideoToTheEnd() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let event = try await videoProvider.nextEvent()
            session.publishSubtitleCues(at: .zero)
            if case .end = event { return }
        }
        Issue.record("Timed out draining the fixture video")
    }

    try videoProvider.start()
    try await drainVideoToTheEnd()
    #expect(ingestedCueTexts() == ["第一行\n第二行", "再见"])
    #expect(session.activeSubtitleCues(
        at: CMTime(seconds: 1, preferredTimescale: 600)
    ).map(\.text) == ["第一行\n第二行"])
    #expect(session.activeSubtitleCues(
        at: CMTime(seconds: 3.5, preferredTimescale: 600)
    ).map(\.text) == ["再见"])

    try demuxSession.seek(to: 0)
    try await drainVideoToTheEnd()
    #expect(
        ingestedCueTexts() == ["第一行\n第二行", "再见"],
        "the packets the shared source re-read after the backward seek were folded in more than once"
    )

    videoProvider.cancel()
    session.close()
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
    #expect(frame.kind == .coreText)
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

@Test func textSubtitleRendererDrawsDistinctCJKCharactersInsteadOfMissingGlyphBoxes() async throws {
    let fixture = try cjkSubtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    #expect(renderer is CoreTextSubtitleFrameRenderer)
    let frame = try #require(try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ))
    #expect(frame.kind == .coreText)
    #expect(frame.canvasWidth == 1_920)
    #expect(frame.canvasHeight == 1_080)
    #expect(
        frame.contentY + frame.contentHeight
            <= 1_080 - Int(CoreTextSubtitleStyle.bottomMargin(canvasHeight: 1_080))
    )
    #expect(frame.premultipliedBGRA.count == frame.bytesPerRow * frame.contentHeight)
    let glyphs = visibleGlyphFingerprints(in: frame)
    #expect(glyphs.count == 4)
    #expect(Set(glyphs).count == 4)
    #expect(visibleGlyphsWithInkInTheirCentre(in: frame) == 4)
    #expect(try renderer.frame(
        at: CMTime(seconds: 2.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) == nil)
}

@Test func subtitleStyleDerivesFromTheCanvasAndTheCaptionFont() throws {
    let style = CoreTextSubtitleStyle()
    let emSize = style.emSize(canvasHeight: 1_080)
    #expect(emSize == 54)
    #expect(abs(style.lineAdvance(emSize: emSize) - 64.8) < 0.001)
    #expect(abs(style.outlineWidth(emSize: emSize) - 3.24) < 0.001)
    #expect(CoreTextSubtitleStyle.horizontalMargin(canvasWidth: 1_920) == 96)
    #expect(CoreTextSubtitleStyle.bottomMargin(canvasHeight: 1_080) == 54)
    #expect(style.edgeShadow == .none)
    #expect(style.shadowOffset(emSize: emSize) == nil)
    #expect(CoreTextSubtitleStyle.edgeShadow(for: .uniform) == .none)
    #expect(CoreTextSubtitleStyle.edgeShadow(for: .raised) == .raised)
    #expect(CoreTextSubtitleStyle.edgeShadow(for: .dropShadow) == .dropShadow)
    for candidate in [style, CoreTextSubtitleStyle.captionAppearance()] {
        let font = candidate.font(emSize: emSize)
        #expect(CTFontGetSize(font) == emSize)
        let traits = CTFontCopyTraits(font) as NSDictionary
        let weight = traits[kCTFontWeightTrait] as? Double ?? 0
        #expect(weight > 0)
    }
    let appearance = CoreTextSubtitleStyle.captionAppearance()
    #expect(appearance.relativeCharacterSize > 0)
    #expect(appearance.fillColor.alpha > 0)
}

@Test func subtitleStyleScalesWithTheUserCaptionCharacterSize() throws {
    let regular = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        "字幕",
        changeIdentifier: 1,
        style: CoreTextSubtitleStyle(relativeCharacterSize: 1)
    ))
    let large = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        "字幕",
        changeIdentifier: 2,
        style: CoreTextSubtitleStyle(relativeCharacterSize: 1.5)
    ))
    #expect(abs(Double(large.contentHeight) - Double(regular.contentHeight) * 1.5) <= 4)
    #expect(abs(Double(large.contentWidth) - Double(regular.contentWidth) * 1.5) <= 6)
    #expect(large.contentX >= Int(CoreTextSubtitleStyle.horizontalMargin(canvasWidth: 1_920)))
    #expect(
        large.contentY + large.contentHeight
            <= 1_080 - Int(CoreTextSubtitleStyle.bottomMargin(canvasHeight: 1_080))
    )
}

@Test func subtitleBlockNeverExceedsThreeLines() throws {
    let style = CoreTextSubtitleStyle()
    let emSize = style.emSize(canvasHeight: 1_080)
    let lineAdvance = style.lineAdvance(emSize: emSize)
    let padding = ceil(style.outlineWidth(emSize: emSize) + 2)
    let three = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        (1...3).map { "第\($0)行" }.joined(separator: "\n"),
        changeIdentifier: 1,
        style: style
    ))
    let six = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        (1...6).map { "第\($0)行" }.joined(separator: "\n"),
        changeIdentifier: 2,
        style: style
    ))
    #expect(Double(three.contentHeight) > Double(lineAdvance) * 2)
    #expect(Double(six.contentHeight) <= Double(lineAdvance) * 3 + Double(padding) * 2)
    #expect(abs(six.contentHeight - three.contentHeight) <= 2)
}

@Test func subtitleDefaultStyleDrawsNoShadowUnlessTheUserPicksAnEdgeStyle() throws {
    let plain = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        "字幕",
        changeIdentifier: 1,
        style: CoreTextSubtitleStyle()
    ))
    let shadowed = try #require(CoreTextSubtitleFrameRenderer.rasterize(
        "字幕",
        changeIdentifier: 2,
        style: CoreTextSubtitleStyle(edgeShadow: .dropShadow)
    ))
    let shadowOffset = CoreTextSubtitleStyle().emSize(canvasHeight: 1_080)
        * CoreTextSubtitleStyle.shadowOffsetEmFraction
    #expect(Double(shadowed.contentHeight - plain.contentHeight) >= Double(shadowOffset))
    #expect(shadowed.contentWidth >= plain.contentWidth)
}

@Test func assSubtitleRendererDrawsHanCharactersInsteadOfMissingGlyphBoxes() async throws {
    let fixture = try hanASSSubtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    #expect(track.codecName == "ass")
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    #expect(renderer is FFmpegSubtitleFrameRenderer)
    var glyphs: [Data] = []
    for second in 1...5 {
        let frame = try #require(try renderer.frame(
            at: CMTime(seconds: Double(second) + 0.25, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        ))
        #expect(frame.kind == .libass)
        #expect(visibleGlyphsWithInkInTheirCentre(in: frame) == 1)
        glyphs.append(frame.premultipliedBGRA)
    }
    #expect(Set(glyphs).count == 5)
}

@Test func textSubtitleRendererKeepsOneFramePerCueTextAndFollowsIngestedCues() async throws {
    let fixture = try subtitleFixtureURL()
    let meter = PlaybackSourceReadMeter()
    let demuxSession = FFmpegDemuxSession(sourceReadMeter: meter)
    let loader = SystemMediaSourceInformationLoader(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let provider = FFmpegSubtitleProvider(
        sourceReadMeter: meter,
        demuxSession: demuxSession
    )
    let information = try await loader.load(from: fixture)
    let track = try #require(information.playbackSubtitleTracks.first)
    _ = try await provider.cues(in: fixture, asset: nil, track: track)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    #expect(renderer is CoreTextSubtitleFrameRenderer)
    var arrived = 0
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline, arrived < 2 {
        arrived += try renderer.ingestPendingCues(for: track).count
        try await Task.sleep(for: .milliseconds(10))
    }
    let first = try #require(try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ))
    let again = try #require(try renderer.frame(
        at: CMTime(seconds: 1.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ))
    #expect(again.changeIdentifier == first.changeIdentifier)
    let second = try #require(try renderer.frame(
        at: CMTime(seconds: 3.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ))
    #expect(second.changeIdentifier != first.changeIdentifier)
    #expect(visibleGlyphsWithInkInTheirCentre(in: second) >= 1)
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

@MainActor
@Test func externalSubtitleSourceJoinsTheCurrentMediaSessionAndUsesItsOwnFile() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: SubtitleTestVideoProvider(),
            subtitleProvider: FFmpegSubtitleProvider()
        )
    }
    let session = try await controller.open(try subtitleFixtureURL())
    let sessionID = session.traceID
    let externalTracks = try await controller.addExternalSubtitleSource(
        PlaybackExternalSubtitleSource(
            id: "manual-english",
            url: try externalSubtitleFixtureURL(),
            displayName: "English sidecar"
        )
    )

    #expect(controller.activeSession?.traceID == sessionID)
    #expect(externalTracks.map(\.id) == ["external.subtitle.manual-english.0"])
    #expect(controller.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
        "external.subtitle.manual-english.0",
    ])
    #expect(externalTracks.first?.label == "English sidecar")

    try await controller.selectSubtitleTrack(id: "external.subtitle.manual-english.0")
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1.5, preferredTimescale: 600)
    )
    #expect(controller.activeSubtitleCues.map(\.text) == ["English subtitle"])
    #expect(controller.activeSession?.traceID == sessionID)

    await controller.closeAndWait()
    #expect(controller.availableSubtitleTracks.isEmpty)
}

@MainActor
@Test func failedExternalSubtitleSourceLeavesTheCurrentSelectionAndSessionUntouched() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: SubtitleTestVideoProvider(),
            subtitleProvider: FFmpegSubtitleProvider()
        )
    }
    let session = try await controller.open(try subtitleFixtureURL())
    let sessionID = session.traceID
    try await controller.selectSubtitleTrack(id: "ffmpeg.subtitle.1")
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1, preferredTimescale: 600)
    )
    let selectedTrackID = controller.selectedSubtitleTrackID
    let activeCues = controller.activeSubtitleCues
    let unsupportedFile = FileManager.default.temporaryDirectory
        .appending(path: "unsupported-subtitle-\(UUID().uuidString).txt")
    try Data("not a subtitle container".utf8).write(to: unsupportedFile)
    defer { try? FileManager.default.removeItem(at: unsupportedFile) }

    await #expect(throws: PlaybackControlError.self) {
        try await controller.addExternalSubtitleSource(
            PlaybackExternalSubtitleSource(
                id: "unsupported",
                url: unsupportedFile,
                displayName: unsupportedFile.lastPathComponent
            )
        )
    }

    #expect(controller.activeSession?.traceID == sessionID)
    #expect(controller.selectedSubtitleTrackID == selectedTrackID)
    #expect(controller.activeSubtitleCues == activeCues)
    #expect(controller.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])
    await controller.closeAndWait()
}

@MainActor
@Test func removingExternalSubtitleSourceClearsOnlyItsTracksAndKeepsTheSession() async throws {
    let controller = PlaybackCoreController { sessionID in
        SampleBufferPlaybackSession(
            traceID: sessionID,
            provider: SubtitleTestVideoProvider(),
            subtitleProvider: FFmpegSubtitleProvider()
        )
    }
    let session = try await controller.open(try subtitleFixtureURL())
    let sessionID = session.traceID
    let externalTracks = try await controller.addExternalSubtitleSource(
        PlaybackExternalSubtitleSource(
            id: "removable",
            url: try externalSubtitleFixtureURL(),
            displayName: "Removable subtitle"
        )
    )
    let externalTrackID = try #require(externalTracks.first?.id)
    try await controller.selectSubtitleTrack(id: externalTrackID)
    session.synchronizer.setRate(
        0,
        time: CMTime(seconds: 1.5, preferredTimescale: 600)
    )
    #expect(controller.activeSubtitleCues.map(\.text) == ["English subtitle"])

    try await controller.removeExternalSubtitleSource(id: "removable")

    #expect(controller.activeSession?.traceID == sessionID)
    #expect(controller.selectedSubtitleTrackID == nil)
    #expect(controller.activeSubtitleCues.isEmpty)
    #expect(controller.availableSubtitleTracks.map(\.id) == [
        "ffmpeg.subtitle.1",
        "ffmpeg.subtitle.2",
    ])
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

private func cjkSubtitleFixtureURL() throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: "subtitle-cjk",
            withExtension: "srt",
            subdirectory: "Fixtures"
        )
    )
}

private func visibleGlyphFingerprints(in frame: PlaybackSubtitleFrame) -> [Data] {
    let alphaThreshold: UInt8 = 32
    let occupiedColumns = (0..<frame.contentWidth).map { x in
        (0..<frame.contentHeight).contains { y in
            frame.premultipliedBGRA[y * frame.bytesPerRow + x * 4 + 3] > alphaThreshold
        }
    }
    var ranges: [Range<Int>] = []
    var rangeStart: Int?
    for (column, occupied) in occupiedColumns.enumerated() {
        if occupied {
            if rangeStart == nil {
                rangeStart = column
            }
        } else if let existingStart = rangeStart {
            ranges.append(existingStart..<column)
            rangeStart = nil
        }
    }
    if let rangeStart {
        ranges.append(rangeStart..<frame.contentWidth)
    }

    return ranges.map { range in
        let occupiedRows = (0..<frame.contentHeight).filter { y in
            range.contains(where: { x in
                frame.premultipliedBGRA[y * frame.bytesPerRow + x * 4 + 3] > alphaThreshold
            })
        }
        guard let firstRow = occupiedRows.first, let lastRow = occupiedRows.last else {
            return Data()
        }
        var fingerprint = Data()
        fingerprint.append(UInt8(truncatingIfNeeded: range.count))
        fingerprint.append(UInt8(truncatingIfNeeded: range.count >> 8))
        let height = lastRow - firstRow + 1
        fingerprint.append(UInt8(truncatingIfNeeded: height))
        fingerprint.append(UInt8(truncatingIfNeeded: height >> 8))
        for y in firstRow...lastRow {
            for x in range {
                fingerprint.append(
                    frame.premultipliedBGRA[y * frame.bytesPerRow + x * 4 + 3] > alphaThreshold ? 1 : 0
                )
            }
        }
        return fingerprint
    }
}

private func visibleGlyphsWithInkInTheirCentre(in frame: PlaybackSubtitleFrame) -> Int {
    let alphaThreshold: UInt8 = 32
    func occupied(_ x: Int, _ y: Int) -> Bool {
        frame.premultipliedBGRA[y * frame.bytesPerRow + x * 4 + 3] > alphaThreshold
    }
    let occupiedColumns = (0..<frame.contentWidth).map { x in
        (0..<frame.contentHeight).contains { y in occupied(x, y) }
    }
    var ranges: [Range<Int>] = []
    var rangeStart: Int?
    for (column, isOccupied) in occupiedColumns.enumerated() {
        if isOccupied {
            if rangeStart == nil { rangeStart = column }
        } else if let existingStart = rangeStart {
            ranges.append(existingStart..<column)
            rangeStart = nil
        }
    }
    if let rangeStart { ranges.append(rangeStart..<frame.contentWidth) }
    return ranges.filter { range in
        let rows = (0..<frame.contentHeight).filter { y in
            range.contains { x in occupied(x, y) }
        }
        guard let top = rows.first, let bottom = rows.last, bottom > top else { return false }
        let innerColumns = range.lowerBound + range.count / 3 ..< range.upperBound - range.count / 3
        let innerRows = top + (bottom - top) / 3 ... bottom - (bottom - top) / 3
        return innerRows.contains { y in innerColumns.contains { x in occupied(x, y) } }
    }.count
}

private func hanASSSubtitleFixtureURL() throws -> URL {
    let script = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: 1920
    PlayResY: 1080

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, \
    Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, \
    Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Helvetica Neue,64,&H00FFFFFF,&H000000FF,&H00101010,&H80000000,0,0,0,0,100,100,0,0,1,3,0,2,80,80,54,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:01.50,Default,,0,0,0,,验
    Dialogue: 0,0:00:02.00,0:00:02.50,Default,,0,0,0,,证
    Dialogue: 0,0:00:03.00,0:00:03.50,Default,,0,0,0,,字
    Dialogue: 0,0:00:04.00,0:00:04.50,Default,,0,0,0,,日
    Dialogue: 0,0:00:05.00,0:00:05.50,Default,,0,0,0,,體
    """
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("han-\(UUID().uuidString)")
        .appendingPathExtension("ass")
    try script.write(to: fixture, atomically: true, encoding: .utf8)
    return fixture
}

private func externalSubtitleFixtureURL() throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: "subtitle-en",
            withExtension: "srt",
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

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?,
        startTime: CMTime
    ) async throws {}
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

private enum GeneratedPresentationGraphicStream {
    static let videoWidth = 1_920
    static let videoHeight = 1_080
    static let objectWidth = 600
    static let objectHeight = 80
    static let windowX = 660
    static let windowY = 900
    static let firstStartSeconds = 2.0
    static let repeatSeconds = 2.0
    static let visibleSeconds = 1.6
    static let presentationCompositionSegment: UInt8 = 0x16
    static let windowDefinitionSegment: UInt8 = 0x17
    static let paletteDefinitionSegment: UInt8 = 0x14
    static let objectDefinitionSegment: UInt8 = 0x15
    static let endOfDisplaySetSegment: UInt8 = 0x80
    static let segmentsPerDisplaySet = 5

    static func startSeconds(ofDisplaySet index: Int) -> Double {
        firstStartSeconds + Double(index) * repeatSeconds
    }

    static func write(displaySetCount: Int, to url: URL) throws {
        var stream = Data()
        for index in 0..<displaySetCount {
            let start = startSeconds(ofDisplaySet: index)
            let end = start + visibleSeconds
            stream.append(segment(
                at: start,
                type: presentationCompositionSegment,
                payload: presentation(index, showing: true)
            ))
            stream.append(segment(at: start, type: windowDefinitionSegment, payload: window()))
            stream.append(segment(at: start, type: paletteDefinitionSegment, payload: palette()))
            stream.append(segment(at: start, type: objectDefinitionSegment, payload: object(index)))
            stream.append(segment(at: start, type: endOfDisplaySetSegment, payload: Data()))
            stream.append(segment(
                at: end,
                type: presentationCompositionSegment,
                payload: presentation(index, showing: false)
            ))
            stream.append(segment(at: end, type: windowDefinitionSegment, payload: window()))
            stream.append(segment(at: end, type: endOfDisplaySetSegment, payload: Data()))
        }
        try stream.write(to: url, options: .atomic)
    }

    private static func big16(_ value: Int) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func big32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }

    private static func segment(at seconds: Double, type: UInt8, payload: Data) -> Data {
        var segment = Data("PG".utf8)
        segment.append(big32(UInt32(seconds * 90_000)))
        segment.append(big32(0))
        segment.append(type)
        segment.append(big16(payload.count))
        segment.append(payload)
        return segment
    }

    private static func presentation(_ index: Int, showing: Bool) -> Data {
        var payload = big16(videoWidth)
        payload.append(big16(videoHeight))
        payload.append(0x10)
        payload.append(big16(index * 2 + (showing ? 0 : 1)))
        payload.append(showing ? 0x80 : 0x00)
        payload.append(contentsOf: [0x00, 0x00, showing ? 0x01 : 0x00])
        if showing {
            payload.append(big16(0))
            payload.append(contentsOf: [0x00, 0x00])
            payload.append(big16(windowX))
            payload.append(big16(windowY))
        }
        return payload
    }

    private static func window() -> Data {
        var payload = Data([0x01, 0x00])
        payload.append(big16(windowX))
        payload.append(big16(windowY))
        payload.append(big16(objectWidth))
        payload.append(big16(objectHeight))
        return payload
    }

    private static func palette() -> Data {
        Data([0x00, 0x00, 0x01, 235, 128, 128, 255, 0x02, 16, 128, 128, 255])
    }

    private static func object(_ index: Int) -> Data {
        let pixels = runLength(index)
        var payload = big16(0)
        payload.append(contentsOf: [0x00, 0xC0])
        let length = pixels.count + 4
        payload.append(contentsOf: [
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ])
        payload.append(big16(objectWidth))
        payload.append(big16(objectHeight))
        payload.append(pixels)
        return payload
    }

    static func inkPixels(ofDisplaySet index: Int) -> Int {
        (barWidth(index) + 120) * (objectHeight - 20)
    }

    private static func barWidth(_ index: Int) -> Int { 40 + (index % 5) * 40 }

    private static func runLength(_ index: Int) -> Data {
        var pixels = Data()
        for row in 0..<objectHeight {
            if row >= 10, row < objectHeight - 10 {
                let bar = barWidth(index)
                pixels.append(line([
                    (0, 20), (1, bar), (0, 20), (1, 120), (0, objectWidth - 160 - bar),
                ]))
            } else {
                pixels.append(line([(0, objectWidth)]))
            }
        }
        return pixels
    }

    private static func line(_ runs: [(UInt8, Int)]) -> Data {
        var encoded = Data()
        for (colour, length) in runs {
            var remaining = length
            while remaining > 0 {
                let run = min(remaining, 16_383)
                remaining -= run
                if colour == 0 {
                    if run < 64 {
                        encoded.append(contentsOf: [0x00, UInt8(run)])
                    } else {
                        encoded.append(contentsOf: [
                            0x00, UInt8(0x40 | (run >> 8)), UInt8(run & 0xFF),
                        ])
                    }
                } else if run < 64 {
                    encoded.append(contentsOf: [0x00, UInt8(0x80 | run), colour])
                } else {
                    encoded.append(contentsOf: [
                        0x00, UInt8(0xC0 | (run >> 8)), UInt8(run & 0xFF), colour,
                    ])
                }
            }
        }
        encoded.append(contentsOf: [0x00, 0x00])
        return encoded
    }
}

private func presentationGraphicFixtureURL(displaySetCount: Int) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "PlaybackCorePresentationGraphicFixture")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let fixture = directory.appending(path: "generated-\(displaySetCount).sup")
    try GeneratedPresentationGraphicStream.write(displaySetCount: displaySetCount, to: fixture)
    return fixture
}

@Test func presentationGraphicRendererDrawsTheDisplaySetThatCoversTheTime() async throws {
    let fixture = try presentationGraphicFixtureURL(displaySetCount: 8)
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    #expect(track.codecName == "hdmv_pgs_subtitle")
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))

    func frame(at seconds: Double) throws -> PlaybackSubtitleFrame? {
        try renderer.frame(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        )
    }

    #expect(try frame(at: 1.0) == nil, "something was drawn before the first display set")
    #expect(
        try frame(at: 3.9) == nil,
        "something was drawn in the gap the clearing display set leaves behind"
    )

    let second = try #require(try frame(at: 4.5))
    #expect(second.kind == .bitmap)
    #expect(second.canvasWidth == GeneratedPresentationGraphicStream.videoWidth)
    #expect(second.canvasHeight == GeneratedPresentationGraphicStream.videoHeight)
    #expect(second.contentX == GeneratedPresentationGraphicStream.windowX)
    #expect(second.contentY == GeneratedPresentationGraphicStream.windowY)
    #expect(second.contentWidth == GeneratedPresentationGraphicStream.objectWidth)
    #expect(second.contentHeight == GeneratedPresentationGraphicStream.objectHeight)
    #expect(
        opaquePixelCount(in: second)
            == GeneratedPresentationGraphicStream.inkPixels(ofDisplaySet: 1)
    )

    let first = try #require(try frame(at: 2.5))
    #expect(
        opaquePixelCount(in: first)
            == GeneratedPresentationGraphicStream.inkPixels(ofDisplaySet: 0),
        "asking for an earlier time drew a display set other than the one covering it"
    )
    let third = try #require(try frame(at: 6.5))
    #expect(
        opaquePixelCount(in: third)
            == GeneratedPresentationGraphicStream.inkPixels(ofDisplaySet: 2),
        "asking for a later time drew a display set other than the one covering it"
    )
}

@Test func aBitmapSubtitleRequestDecodesTheDisplaySetItNeedsAndNotTheTrack() async throws {
    let packetsPerDisplaySet = GeneratedPresentationGraphicStream.segmentsPerDisplaySet
    let displaySets = 1_200
    let fixture = try presentationGraphicFixtureURL(displaySetCount: displaySets)
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    let renderer = try #require(
        try await provider.frameRenderer(in: fixture, asset: nil, track: track)
            as? FFmpegSubtitleFrameRenderer
    )

    func frame(at seconds: Double) throws -> PlaybackSubtitleFrame? {
        try renderer.frame(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        )
    }

    let late = GeneratedPresentationGraphicStream.startSeconds(ofDisplaySet: displaySets - 40)
    #expect(try frame(at: late + 0.5) != nil)
    let afterFirstRequest = renderer.decodedPacketCount
    #expect(
        afterFirstRequest <= UInt64(packetsPerDisplaySet * 2),
        "a first request decoded \(afterFirstRequest) packets of a \(displaySets) display set track"
    )

    var time = late + 0.5
    let walkSeconds = 4.0
    for _ in 0..<40 {
        time += walkSeconds / 40
        _ = try frame(at: time)
    }
    let passed = Int(walkSeconds / GeneratedPresentationGraphicStream.repeatSeconds) + 1
    let afterWalk = renderer.decodedPacketCount
    #expect(
        afterWalk - afterFirstRequest <= UInt64(passed * packetsPerDisplaySet * 2),
        "walking forward decoded \(afterWalk - afterFirstRequest) packets for the \(passed) display sets it passed"
    )

    for step in 1...20 {
        _ = try frame(at: time - Double(step) * 0.05)
        _ = try frame(at: time)
    }
    #expect(
        renderer.decodedPacketCount == afterWalk,
        "stepping back decoded \(renderer.decodedPacketCount - afterWalk) packets again"
    )
}

@Test func aBitmapSubtitleDocumentKeepsTheTimesItWasAuthoredWith() async throws {
    let fixture = try presentationGraphicFixtureURL(displaySetCount: 8)
    let provider = FFmpegSubtitleProvider()
    let track = try #require(try await provider.tracks(in: fixture, asset: nil).first)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let firstStart = GeneratedPresentationGraphicStream.startSeconds(ofDisplaySet: 0)
    #expect(firstStart > 0)
    #expect(try renderer.frame(
        at: CMTime(seconds: firstStart - 0.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) == nil)
    #expect(try renderer.frame(
        at: CMTime(seconds: firstStart + 0.5, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) != nil)
}

@Test func aBitmapSubtitleIsLaidOutAgainstItsOwnAuthoringResolution() async throws {
    let fixture = try ultraHighDefinitionBitmapSubtitleFixtureURL()
    let provider = FFmpegSubtitleProvider()
    let track = try #require(
        try await provider.tracks(in: fixture, asset: nil)
            .first { $0.codecName == "hdmv_pgs_subtitle" }
    )
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let secondsInsideTheFirstDisplaySet = 120.5
    let frame = try #require(try renderer.frame(
        at: CMTime(seconds: secondsInsideTheFirstDisplaySet, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ))
    #expect(
        frame.canvasWidth == 1_920,
        "the bitmap canvas is \(frame.canvasWidth) wide, not the resolution the subtitle was authored against"
    )
    #expect(
        frame.canvasHeight == 1_080,
        "the bitmap canvas is \(frame.canvasHeight) tall, not the resolution the subtitle was authored against"
    )
    #expect(frame.contentX == GeneratedPresentationGraphicStream.windowX)
    #expect(frame.contentY == GeneratedPresentationGraphicStream.windowY)
}

private func ultraHighDefinitionBitmapSubtitleFixtureURL() throws -> URL {
    let encoded = try #require(
        Bundle.module.url(
            forResource: "uhd-with-1080p-bitmap-subtitle.mkv",
            withExtension: "base64",
            subdirectory: "Fixtures"
        )
    )
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "PlaybackCoreUltraHighDefinitionBitmapSubtitleFixture")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let fixture = directory.appending(path: "uhd-with-1080p-bitmap-subtitle.mkv")
    let decoded = try #require(
        Data(base64Encoded: try Data(contentsOf: encoded), options: .ignoreUnknownCharacters)
    )
    try decoded.write(to: fixture, options: .atomic)
    return fixture
}

private func opaquePixelCount(in frame: PlaybackSubtitleFrame) -> Int {
    stride(from: 3, to: frame.premultipliedBGRA.count, by: 4)
        .count { frame.premultipliedBGRA[$0] > 0 }
}
