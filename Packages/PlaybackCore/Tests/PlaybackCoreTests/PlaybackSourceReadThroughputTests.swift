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
        PBFFmpegDemuxSourceCreate(
            $0,
            false,
            PBFFmpegDemuxBufferConfigurationMake(PBFFmpegDemuxBufferModeNone, 0),
            monitor,
            &error,
            error.count
        )
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

private final class LockedDemuxSourceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: OpaquePointer?
    private var storedError = [CChar](repeating: 0, count: 512)

    var value: OpaquePointer? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    var error: [CChar] {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }
}

private func waitForCondition(
    timeout: TimeInterval,
    _ predicate: @escaping () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return predicate()
}

@Test func sourceReadMonitorReportsPendingWhileRemoteOpenStalls() throws {
    let fixture = playbackSourceReadTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    let server = try RecordingRangeServer(
        serving: try Data(contentsOf: fixture),
        reusingConnections: true
    )
    defer { server.stop() }
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }

    server.stallNextRangeResponse()
    let box = LockedDemuxSourceBox()
    let created = DispatchSemaphore(value: 0)
    let path = server.url.absoluteString
    let monitorAddress = Int(bitPattern: monitor)
    DispatchQueue.global().async {
        var error = [CChar](repeating: 0, count: 512)
        box.value = path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                true,
                PBFFmpegDemuxBufferConfigurationMake(
                    PBFFmpegDemuxBufferModeAutomatic,
                    0
                ),
                OpaquePointer(bitPattern: monitorAddress),
                &error,
                error.count
            )
        }
        box.error = error
        created.signal()
    }

    try #require(server.waitForStalledResponse(timeout: .now() + 5))
    #expect(PBFFmpegSourceReadMonitorGetPendingReadCount(monitor) > 0)
    #expect(waitForCondition(timeout: 3) {
        PBFFmpegSourceReadMonitorGetPendingReadUptimeMilliseconds(monitor) > 20
    })

    PBFFmpegSourceReadMonitorInterrupt(monitor)
    server.stop()
    #expect(created.wait(timeout: .now() + 15) == .success)
    #expect(waitForCondition(timeout: 3) {
        PBFFmpegSourceReadMonitorGetPendingReadCount(monitor) == 0
    })
    if let openedSource = box.value {
        PBFFmpegDemuxSourceDestroy(openedSource)
    }
}

@Test func sourceReadMonitorReportsPendingWhileRemoteSeekStalls() throws {
    let fixture = playbackSourceReadTestMedia.appendingPathComponent(
        "TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv"
    )
    let server = try RecordingRangeServer(
        serving: try Data(contentsOf: fixture),
        reusingConnections: true
    )
    defer { server.stop() }
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    var error = [CChar](repeating: 0, count: 512)

    let source: OpaquePointer? = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(
            path,
            true,
            PBFFmpegDemuxBufferConfigurationMake(
                PBFFmpegDemuxBufferModeAutomatic,
                0
            ),
            monitor,
            &error,
            error.count
        )
    }
    let openError = pendingReadErrorText(error)
    guard let openedSource = source else {
        Issue.record(Comment(rawValue: "demux source open failed: \(openError)"))
        return
    }
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }

    // Let the read thread settle (drain to EOF) so only the seek is pending.
    #expect(waitForCondition(timeout: 10) {
        PBFFmpegSourceReadMonitorGetPendingReadCount(monitor) == 0
    })

    server.stallNextRangeResponse()
    // Seek back to the start; after the EOF drain this always misses the
    // buffer and issues a fresh range request, which the server stalls.
    let seekFinished = DispatchSemaphore(value: 0)
    let sourceAddress = Int(bitPattern: openedSource)
    DispatchQueue.global().async {
        var seekError = [CChar](repeating: 0, count: 512)
        _ = PBFFmpegDemuxSourceSeek(
            OpaquePointer(bitPattern: sourceAddress),
            0,
            &seekError,
            seekError.count
        )
        seekFinished.signal()
    }

    try #require(server.waitForStalledResponse(timeout: .now() + 5))
    #expect(PBFFmpegSourceReadMonitorGetPendingReadCount(monitor) > 0)

    PBFFmpegDemuxSourceInterrupt(openedSource)
    server.stop()
    #expect(seekFinished.wait(timeout: .now() + 15) == .success)
    #expect(waitForCondition(timeout: 3) {
        PBFFmpegSourceReadMonitorGetPendingReadCount(monitor) == 0
    })
}

private func pendingReadErrorText(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

private let playbackSourceReadTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")
