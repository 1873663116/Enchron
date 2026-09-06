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

    // On the shared source the selection returns what is queued and the rest
    // arrives as the reader passes it; neither step reopens the file.
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

@Test func sharedSourceSubtitleRendererIngestsOnDemandInsteadOfScanningTheSource() async throws {
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

    func readFrameCount() throws -> UInt64 {
        try #require(demuxSession.bufferDiagnostics()).readFrameCount
    }
    func readFrameCountOnceSettled() async throws -> UInt64 {
        var previous = try readFrameCount()
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(150))
            let current = try readFrameCount()
            if current == previous { return current }
            previous = current
        }
        Issue.record("The shared reader never settled")
        return previous
    }

    // Selecting the track takes what the shared source has queued and
    // returns; it must not read the source to its end.
    var cues = try await provider.cues(in: fixture, asset: nil, track: track)
    let renderer = try #require(try await provider.frameRenderer(
        in: fixture,
        asset: nil,
        track: track
    ))
    let readFramesAfterSelection = try await readFrameCountOnceSettled()

    // The renderer keeps its stream subscription and folds in packets as the
    // reader passes them; each ingest lets the reader move on.
    let cueDeadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < cueDeadline, cues.count < 2 {
        cues += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cues.map(\.text) == ["第一行\n第二行", "再见"])
    #expect(cues.map(\.id) == ["ffmpeg.subtitle.1.cue.0", "ffmpeg.subtitle.1.cue.1"])
    let readFramesAfterIngest = try await readFrameCountOnceSettled()
    #expect(readFramesAfterIngest > readFramesAfterSelection)
    #expect(try renderer.frame(
        at: CMTime(seconds: 1, preferredTimescale: 600),
        viewportWidth: 1_920,
        viewportHeight: 1_080
    ) != nil)

    // After a backward seek the source re-reads the same packets; the
    // renderer recognises them and produces no duplicate cues.
    try demuxSession.seek(to: 0)
    var duplicates: [PlaybackSubtitleCue] = []
    let seekDeadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < seekDeadline {
        duplicates += try renderer.ingestPendingCues(for: track)
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(duplicates.isEmpty)
    #expect(try renderer.ingestPendingCues(for: track).isEmpty)
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
    // prepare subscribes the video stream on the shared source and nothing
    // drains it until the test pulls samples itself, so the shared reader
    // parks a second or so past the playhead, the way it parks behind 4K
    // video that playback has not consumed yet.
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

    // A backward seek makes the shared source re-read the same packets; the
    // renderer folds each packet in once.
    try demuxSession.seek(to: 0)
    try await drainVideoToTheEnd()
    #expect(ingestedCueTexts() == ["第一行\n第二行", "再见"])

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
    #expect(frame.contentY + frame.contentHeight <= 1_080 - 54)
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
