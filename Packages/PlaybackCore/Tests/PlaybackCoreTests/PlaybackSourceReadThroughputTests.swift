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

@Test func sourceReadMonitorCountsSharedDemuxReads() throws {
    let fixture = playbackSourceReadTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    var error = [CChar](repeating: 0, count: 512)

    let source = fixture.path.withCString {
        PBFFmpegDemuxSourceCreate($0, false, monitor, &error, error.count)
    }
    let openedSource = try #require(source)
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }
    let bytesAfterSourceOpen = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    #expect(bytesAfterSourceOpen > 0)

    let videoReader = try #require(PBFFmpegReaderAllocate())
    let videoOpened = PBFFmpegReaderOpenWithDemuxSource(
        videoReader,
        openedSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    )
    try #require(videoOpened)
    defer { PBFFmpegReaderDestroy(videoReader) }

    let audioReader = try #require(PBFFmpegAudioReaderAllocate())
    let audioOpened = PBFFmpegAudioReaderOpenWithDemuxSource(
        audioReader,
        openedSource,
        -1,
        &error,
        error.count
    )
    try #require(audioOpened)
    defer { PBFFmpegAudioReaderDestroy(audioReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    let result = PBFFmpegReaderCopyNextSample(
        videoReader,
        &sample,
        &error,
        error.count
    )
    try #require(result == PBFFmpegReadResultSample)
    _ = sample?.takeRetainedValue()
    #expect(PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor) >= bytesAfterSourceOpen)

    try #require(PBFFmpegDemuxSourceSeek(
        openedSource,
        5,
        &error,
        error.count
    ))
    var videoSeconds = -Double.infinity
    var audioSeconds = -Double.infinity
    while videoSeconds < 5 || audioSeconds < 5 {
        if videoSeconds <= audioSeconds {
            var videoSample: Unmanaged<CMSampleBuffer>?
            let readResult = PBFFmpegReaderCopyNextSample(
                videoReader,
                &videoSample,
                &error,
                error.count
            )
            try #require(readResult == PBFFmpegReadResultSample)
            let buffer = try #require(videoSample?.takeRetainedValue())
            videoSeconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        } else {
            var audioSample: Unmanaged<CMSampleBuffer>?
            var metadata = PBFFmpegAudioSampleMetadata()
            let readResult = PBFFmpegAudioReaderCopyNextSample(
                audioReader,
                &audioSample,
                &metadata,
                &error,
                error.count
            )
            try #require(readResult == PBFFmpegReadResultSample)
            let buffer = try #require(audioSample?.takeRetainedValue())
            audioSeconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        }
    }
    #expect(videoSeconds >= 5)
    #expect(audioSeconds >= 5)
}

private let playbackSourceReadTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")
