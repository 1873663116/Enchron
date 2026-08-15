import Foundation
import PlaybackFFmpegBridge
import Testing
@testable import PlaybackCore

@Test func sourceReadRatePublishesOncePerSecondAndClearsOnStall() {
    var sampler = PlaybackSourceReadRateSampler(startedAt: 100)

    #expect(sampler.observe(totalBytesRead: 0, at: 100) == 0)
    #expect(sampler.observe(totalBytesRead: 500, at: 100.5) == 0)
    #expect(sampler.observe(totalBytesRead: 1_000, at: 101) == 1_000)
    #expect(sampler.observe(totalBytesRead: 1_000, at: 101.5) == 1_000)
    #expect(sampler.observe(totalBytesRead: 1_000, at: 102) == 0)
}

@Test func sourceReadRateUsesElapsedTimeAndRebasesARegressedCounter() {
    var sampler = PlaybackSourceReadRateSampler(startedAt: 40)

    #expect(sampler.observe(totalBytesRead: 5_000, at: 42.5) == 2_000)
    #expect(sampler.observe(totalBytesRead: 100, at: 43.5) == 0)
    #expect(sampler.observe(totalBytesRead: 1_100, at: 44.5) == 1_000)
}

@Test func sourceReadMonitorCountsMediaInformationReads() throws {
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }

    let audioFixture = playbackSourceReadTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    var error = [CChar](repeating: 0, count: 512)
    let audioInformation = audioFixture.path.withCString {
        PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
            $0,
            monitor,
            &error,
            error.count
        )
    }
    let openedAudioInformation = try #require(audioInformation)
    PBFFmpegMediaSourceInformationDestroy(openedAudioInformation)
    let bytesAfterAudioScan = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    #expect(bytesAfterAudioScan > 0)

    let subtitleFixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
    let subtitleInformation = subtitleFixture.path.withCString {
        PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
            $0,
            monitor,
            &error,
            error.count
        )
    }
    let openedSubtitleInformation = try #require(subtitleInformation)
    PBFFmpegMediaSourceInformationDestroy(openedSubtitleInformation)
    #expect(PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor) > bytesAfterAudioScan)
}

@Test func sourceReadMonitorCountsLongLivedVideoAndAudioReaders() throws {
    let fixture = playbackSourceReadTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    var error = [CChar](repeating: 0, count: 512)

    let videoReader = try #require(PBFFmpegReaderAllocate())
    PBFFmpegReaderSetSourceReadMonitor(videoReader, monitor)
    let videoOpened = fixture.path.withCString {
        PBFFmpegReaderOpen(
            videoReader,
            $0,
            PBFFmpegModeCompressed,
            0,
            &error,
            error.count
        )
    }
    try #require(videoOpened)
    defer { PBFFmpegReaderDestroy(videoReader) }
    let bytesAfterVideoOpen = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    #expect(bytesAfterVideoOpen > 0)

    let audioReader = try #require(PBFFmpegAudioReaderAllocate())
    PBFFmpegAudioReaderSetSourceReadMonitor(audioReader, monitor)
    let audioOpened = fixture.path.withCString {
        PBFFmpegAudioReaderOpen(audioReader, $0, 0, -1, &error, error.count)
    }
    try #require(audioOpened)
    defer { PBFFmpegAudioReaderDestroy(audioReader) }
    #expect(PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor) > bytesAfterVideoOpen)
}

private let playbackSourceReadTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")
