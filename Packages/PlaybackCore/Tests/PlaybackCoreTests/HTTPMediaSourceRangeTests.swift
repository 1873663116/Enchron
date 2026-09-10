import Foundation
import PlaybackFFmpegBridge
import Testing
import CryptoKit
@testable import PlaybackCore

private let tailMoovFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(
        "TestMedia/Samples/Spatial/MVHEVC-Apple-Official/" +
            "spatial_lighthouse_flowers_waves_short.mov"
    )

private let resilienceFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia/TestVectors/Enchron/PlaybackBehavior/av1-flac-avsync-10s.mkv")

private let movFamilyLoopbackFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(
        "TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-video-only-15s.mp4"
    )

@_silgen_name("av_log_set_level")
private func setFFmpegLogLevel(_ level: Int32)

private func reportedError(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

private func waitUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.01,
    _ predicate: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        Thread.sleep(forTimeInterval: pollInterval)
    }
    return predicate()
}

private func defaultDemuxBufferConfiguration(
    isRemote: Bool
) -> PBFFmpegDemuxBufferConfiguration {
    PBFFmpegDemuxBufferConfigurationMake(
        isRemote ? PBFFmpegDemuxBufferModeAutomatic : PBFFmpegDemuxBufferModeNone,
        0
    )
}

private struct DemuxPrefetchObservation {
    let mode: PBFFmpegDemuxBufferMode
    let bufferedDurationSeconds: Double
    let targetDurationSeconds: Double
    let forwardBufferedBytes: Int64
    let forwardLimitBytes: Int64
    let backwardBufferedBytes: Int64
    let backwardLimitBytes: Int64
    let readFrameCount: UInt64
    let readFrameCountAfterSettling: UInt64
}

private func observeDemuxPrefetch(
    path: String,
    isRemote: Bool,
    configuration: PBFFmpegDemuxBufferConfiguration,
    reachesStoppingCondition: (OpaquePointer) -> Bool
) throws -> DemuxPrefetchObservation {
    var error = [CChar](repeating: 0, count: 512)
    let source = path.withCString {
        PBFFmpegDemuxSourceCreate(
            $0,
            isRemote,
            configuration,
            nil,
            &error,
            error.count
        )
    }
    let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }
    let reader = try #require(PBFFmpegReaderAllocate())
    defer { PBFFmpegReaderDestroy(reader) }
    try #require(PBFFmpegReaderOpenWithDemuxSource(
        reader,
        openedSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    ), Comment(rawValue: reportedError(error)))
    #expect(waitUntil(timeout: 3) { reachesStoppingCondition(openedSource) })
    let readFrameCount = PBFFmpegDemuxSourceGetReadFrameCount(openedSource)
    Thread.sleep(forTimeInterval: 0.15)
    return DemuxPrefetchObservation(
        mode: PBFFmpegDemuxSourceGetBufferMode(openedSource),
        bufferedDurationSeconds: PBFFmpegDemuxSourceGetBufferedDurationSeconds(openedSource),
        targetDurationSeconds: PBFFmpegDemuxSourceGetBufferTargetDurationSeconds(openedSource),
        forwardBufferedBytes: PBFFmpegDemuxSourceGetForwardBufferedByteCount(openedSource),
        forwardLimitBytes: PBFFmpegDemuxSourceGetForwardBufferByteLimit(openedSource),
        backwardBufferedBytes: PBFFmpegDemuxSourceGetRetainedByteCount(openedSource),
        backwardLimitBytes: PBFFmpegDemuxSourceGetBackwardBufferByteLimit(openedSource),
        readFrameCount: readFrameCount,
        readFrameCountAfterSettling: PBFFmpegDemuxSourceGetReadFrameCount(openedSource)
    )
}

@Test func demuxBufferDefaultsMatchMpvDesktopDefaults() {
    let none = PBFFmpegDemuxBufferConfigurationMake(
        PBFFmpegDemuxBufferModeNone,
        0
    )
    #expect(none.forwardByteLimit == 150 * 1_024 * 1_024)
    #expect(none.backwardByteLimit == 50 * 1_024 * 1_024)
    #expect(none.targetDurationSeconds == 1)

    let automatic = PBFFmpegDemuxBufferConfigurationMake(
        PBFFmpegDemuxBufferModeAutomatic,
        0
    )
    #expect(automatic.forwardByteLimit == 150 * 1_024 * 1_024)
    #expect(automatic.backwardByteLimit == 50 * 1_024 * 1_024)
    #expect(automatic.targetDurationSeconds == 1_000 * 60 * 60)

    let explicit = PBFFmpegDemuxBufferConfigurationMake(
        PBFFmpegDemuxBufferModeBytes,
        32 * 1_024 * 1_024
    )
    #expect(explicit.forwardByteLimit == 32 * 1_024 * 1_024)
    #expect(explicit.backwardByteLimit == 50 * 1_024 * 1_024)
    #expect(explicit.targetDurationSeconds == 1_000 * 60 * 60)
}

@Suite(.serialized)
struct DemuxNetworkResilienceTests {
    @Test func localNoneStopsTheReadThreadAtTheDurationTarget() throws {
        let configuration = PBFFmpegDemuxBufferConfigurationMake(
            PBFFmpegDemuxBufferModeNone,
            0
        )
        let observation = try observeDemuxPrefetch(
            path: resilienceFixture.path,
            isRemote: false,
            configuration: configuration
        ) {
            PBFFmpegDemuxSourceGetBufferedDurationSeconds($0) >= 1
        }

        #expect(observation.mode == PBFFmpegDemuxBufferModeNone)
        #expect(observation.bufferedDurationSeconds >= 1)
        #expect(observation.targetDurationSeconds == 1)
        #expect(observation.forwardBufferedBytes < observation.forwardLimitBytes)
        #expect(
            observation.backwardBufferedBytes > 0,
            "nothing was retained for the unclaimed streams, so a track chosen part way through the film finds no recent past"
        )
        #expect(
            observation.backwardBufferedBytes <= observation.backwardLimitBytes,
            "the retained packets grew past the budget they are held in, apart from read-ahead"
        )
        #expect(observation.backwardLimitBytes == 50 * 1_024 * 1_024)
        #expect(observation.readFrameCountAfterSettling == observation.readFrameCount)
    }

    @Test func aStreamNothingReadsCannotStopTheReadThread() throws {
        let fixture = try bitmapSubtitleResilienceFixtureURL()
        let forwardLimitSmallerThanOneSubtitlePacket: Int64 = 2 * 1_024
        var error = [CChar](repeating: 0, count: 512)
        let source = fixture.path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                false,
                PBFFmpegDemuxBufferConfigurationMake(
                    PBFFmpegDemuxBufferModeBytes,
                    forwardLimitSmallerThanOneSubtitlePacket
                ),
                nil,
                &error,
                error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ), Comment(rawValue: reportedError(error)))

        var samples = 0
        var reachedEnd = false
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            var sample: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            if result == PBFFmpegReadResultEnd {
                reachedEnd = true
                break
            }
            try #require(
                result == PBFFmpegReadResultSample,
                Comment(rawValue: reportedError(error))
            )
            sample?.release()
            samples += 1
        }

        #expect(reachedEnd, "the reader stopped after \(samples) samples")
        #expect(PBFFmpegDemuxSourceGetForwardBufferedByteCount(openedSource) <= forwardLimitSmallerThanOneSubtitlePacket)
        #expect(
            PBFFmpegDemuxSourceGetRetainedByteCount(openedSource)
                <= PBFFmpegDemuxSourceGetBackwardBufferByteLimit(openedSource)
        )
    }

    @Test func aSubscribedSubtitleNobodyDrainsCannotStopTheReadThread() throws {
        let fixture = try bitmapSubtitleResilienceFixtureURL()
        let forwardLimitSmallerThanOneSubtitlePacket: Int64 = 2 * 1_024
        var error = [CChar](repeating: 0, count: 512)
        let source = fixture.path.withCString {
            PBFFmpegDemuxSourceCreate(
                $0,
                false,
                PBFFmpegDemuxBufferConfigurationMake(
                    PBFFmpegDemuxBufferModeBytes,
                    forwardLimitSmallerThanOneSubtitlePacket
                ),
                nil,
                &error,
                error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }
        let bitmapSubtitleStreamIndex: Int32 = 1
        let subtitles = try #require(
            PBSubtitleFrameRendererCreateWithDemuxSource(
                openedSource,
                bitmapSubtitleStreamIndex,
                &error,
                error.count
            ),
            Comment(rawValue: reportedError(error))
        )
        defer { PBSubtitleFrameRendererDestroy(subtitles) }
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ), Comment(rawValue: reportedError(error)))

        var samples = 0
        var reachedEnd = false
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            var sample: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            if result == PBFFmpegReadResultEnd {
                reachedEnd = true
                break
            }
            try #require(
                result == PBFFmpegReadResultSample,
                Comment(rawValue: reportedError(error))
            )
            sample?.release()
            samples += 1
        }

        #expect(reachedEnd, "the reader stopped after \(samples) samples")
        #expect(PBFFmpegDemuxSourceGetForwardBufferedByteCount(openedSource) <= forwardLimitSmallerThanOneSubtitlePacket)
        #expect(
            PBFFmpegDemuxSourceGetAuxiliaryBufferedByteCount(openedSource) > forwardLimitSmallerThanOneSubtitlePacket,
            "the undrained subtitle packets are not in the auxiliary pool, so they were counted somewhere that can park the reader"
        )
    }

    @Test func automaticStopsTheReadThreadAtItsForwardByteLimit() throws {
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture)
        )
        defer { server.stop() }
        var configuration = PBFFmpegDemuxBufferConfigurationMake(
            PBFFmpegDemuxBufferModeAutomatic,
            0
        )
        configuration.forwardByteLimit = 128 * 1_024
        let observation = try observeDemuxPrefetch(
            path: server.url.absoluteString,
            isRemote: true,
            configuration: configuration
        ) {
            PBFFmpegDemuxSourceGetForwardBufferedByteCount($0) >=
                configuration.forwardByteLimit
        }

        #expect(observation.mode == PBFFmpegDemuxBufferModeAutomatic)
        #expect(observation.targetDurationSeconds == 1_000 * 60 * 60)
        #expect(observation.forwardBufferedBytes >= configuration.forwardByteLimit)
        #expect(observation.bufferedDurationSeconds < observation.targetDurationSeconds)
        #expect(observation.readFrameCountAfterSettling == observation.readFrameCount)
    }

    @Test func explicitBytesStopsBeforeTheAutomaticByteLimit() throws {
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture)
        )
        defer { server.stop() }
        let explicitLimit: Int64 = 64 * 1_024
        let configuration = PBFFmpegDemuxBufferConfigurationMake(
            PBFFmpegDemuxBufferModeBytes,
            explicitLimit
        )
        let observation = try observeDemuxPrefetch(
            path: server.url.absoluteString,
            isRemote: true,
            configuration: configuration
        ) {
            PBFFmpegDemuxSourceGetForwardBufferedByteCount($0) >= explicitLimit
        }

        #expect(observation.mode == PBFFmpegDemuxBufferModeBytes)
        #expect(observation.forwardLimitBytes == explicitLimit)
        #expect(observation.forwardBufferedBytes >= explicitLimit)
        #expect(observation.bufferedDurationSeconds < 1)
        #expect(observation.bufferedDurationSeconds < observation.targetDurationSeconds)
        #expect(observation.readFrameCountAfterSettling == observation.readFrameCount)
    }

    @Test func sharedDemuxPrefetchesWithoutABlockedConsumer() throws {
        setFFmpegLogLevel(-8)
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture),
            responseChunkSize: 4_096,
            responseChunkDelay: 0.002
        )
        defer { server.stop() }
        let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
        defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
        var error = [CChar](repeating: 0, count: 512)
        var bufferConfiguration = defaultDemuxBufferConfiguration(isRemote: true)
        bufferConfiguration.forwardByteLimit = 128 * 1_024
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate(
                $0, true, bufferConfiguration,
                monitor, &error, error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }

        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ))
        let bytesAfterOpen = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)

        #expect(
            waitUntil(timeout: 3) {
                PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor) > bytesAfterOpen + 64 * 1_024
            },
            Comment(rawValue: "the read thread did not prefetch while no consumer was waiting")
        )
        #expect(
            waitUntil(timeout: 3) {
                PBFFmpegDemuxSourceGetForwardBufferedByteCount(openedSource) >=
                    bufferConfiguration.forwardByteLimit
            }
        )
        let bytesAfterPrefetch = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
        let forwardBufferedBytes = PBFFmpegDemuxSourceGetForwardBufferedByteCount(openedSource)
        let fixtureDigest = SHA256.hash(data: try Data(contentsOf: resilienceFixture))
            .map { String(format: "%02x", $0) }
            .joined()
        print(
            "ENCHRON_ASSERTION {\"consumerWaiting\":false,\"fixtureDigest\":\"sha256:\(fixtureDigest)\",\"fixtureIdentity\":\"av1-flac-avsync-10s.mkv\",\"bytesAfterOpen\":\(bytesAfterOpen),\"bytesAfterPrefetch\":\(bytesAfterPrefetch),\"forwardBufferedBytes\":\(forwardBufferedBytes),\"forwardByteLimit\":\(bufferConfiguration.forwardByteLimit)}"
        )
    }

    @Test func sharedDemuxReconnectsAfterOneReadFailureAndContinuesFromCheckpoint() throws {
        setFFmpegLogLevel(-8)
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture),
            responseChunkSize: 4_096,
            responseChunkDelay: 0.002
        )
        defer { server.stop() }
        var error = [CChar](repeating: 0, count: 512)
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate(
                $0, true, defaultDemuxBufferConfiguration(isRemote: true),
                nil, &error, error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ))

        server.disconnectOnce(afterSendingAdditionalBytes: 64 * 1_024)
        var lastPresentationSeconds = 0.0
        var terminalResult = PBFFmpegReadResultError
        for _ in 0..<1_000 {
            var sample: Unmanaged<CMSampleBuffer>?
            terminalResult = PBFFmpegReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            if terminalResult != PBFFmpegReadResultSample { break }
            let buffer = try #require(sample?.takeRetainedValue())
            lastPresentationSeconds = max(
                lastPresentationSeconds,
                CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            )
        }

        #expect(server.disconnections == 1)
        #expect(PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource) == 1)
        #expect(terminalResult == PBFFmpegReadResultEnd, Comment(rawValue: reportedError(error)))
        #expect(
            lastPresentationSeconds >= 9,
            Comment(rawValue: "playback stopped at \(lastPresentationSeconds) seconds after reconnect")
        )
    }

    @Test func interruptingAReconnectedSourceStopsItsReadThread() throws {
        setFFmpegLogLevel(-8)
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture),
            responseChunkSize: 4_096,
            responseChunkDelay: 0.02
        )
        defer { server.stop() }
        var error = [CChar](repeating: 0, count: 512)
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate(
                $0, true, defaultDemuxBufferConfiguration(isRemote: true),
                nil, &error, error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        let reader = try #require(PBFFmpegReaderAllocate())
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ))

        server.disconnectOnce(afterSendingAdditionalBytes: 64 * 1_024)
        var reconnected = false
        for _ in 0..<1_000 where !reconnected {
            var sample: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(reader, &sample, &error, error.count)
            sample?.release()
            guard result == PBFFmpegReadResultSample else { break }
            reconnected = PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource) == 1
        }
        reconnected = reconnected || PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource) == 1
        guard reconnected else {
            PBFFmpegReaderDestroy(reader)
            PBFFmpegDemuxSourceDestroy(openedSource)
            Issue.record("the source never reconnected")
            return
        }
        #expect(
            PBFFmpegDemuxSourceInterruptTargetsOwnReadContext(openedSource),
            "the reconnected context's interrupt callback points away from the source's read context"
        )

        let secondsForTheReadThreadToReachATransportWait = 0.3
        server.pauseResponses()
        Thread.sleep(forTimeInterval: secondsForTheReadThreadToReachATransportWait)
        PBFFmpegReaderDestroy(reader)
        let destroyed = DispatchSemaphore(value: 0)
        nonisolated(unsafe) let sourceToDestroy = openedSource
        Thread.detachNewThread {
            PBFFmpegDemuxSourceDestroy(sourceToDestroy)
            destroyed.signal()
        }
        let destroyedPromptly = destroyed.wait(timeout: .now() + .seconds(3)) == .success
        server.resumeResponses()
        if !destroyedPromptly { destroyed.wait() }
        #expect(
            destroyedPromptly,
            "destroying the reconnected source waited on its read thread after the interrupt"
        )
    }

    @Test func sharedDemuxReportsErrorOnlyAfterFiniteReconnectAttemptsAreExhausted() throws {
        setFFmpegLogLevel(-8)
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture),
            responseChunkSize: 4_096,
            responseChunkDelay: 0.002
        )
        defer { server.stop() }
        var error = [CChar](repeating: 0, count: 512)
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate(
                $0, true, defaultDemuxBufferConfiguration(isRemote: true),
                nil, &error, error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ))

        server.rejectResponsesAndDisconnect()
        var terminalResult = PBFFmpegReadResultSample
        for _ in 0..<1_000 {
            var sample: Unmanaged<CMSampleBuffer>?
            terminalResult = PBFFmpegReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            if terminalResult != PBFFmpegReadResultSample { break }
            _ = sample?.takeRetainedValue()
        }
        let connectionsAtFailure = server.connections
        Thread.sleep(forTimeInterval: 0.5)

        #expect(terminalResult == PBFFmpegReadResultError)
        #expect(reportedError(error).isEmpty == false)
        #expect(PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource) == 3)
        #expect(server.rejections > 0)
        #expect(server.connections == connectionsAtFailure, "reconnects continued after terminal failure")
    }

    @Test func sharedDemuxDoesNotReconnectHTTPWhenTheSourceIsNotRemote() throws {
        setFFmpegLogLevel(-8)
        let server = try RecordingRangeServer(
            serving: try Data(contentsOf: resilienceFixture),
            responseChunkSize: 4_096,
            responseChunkDelay: 0.002
        )
        defer { server.stop() }
        var error = [CChar](repeating: 0, count: 512)
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate(
                $0, false, defaultDemuxBufferConfiguration(isRemote: false),
                nil, &error, error.count
            )
        }
        let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
        defer { PBFFmpegDemuxSourceDestroy(openedSource) }
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ))

        server.rejectResponsesAndDisconnect()
        var terminalResult = PBFFmpegReadResultSample
        for _ in 0..<1_000 {
            var sample: Unmanaged<CMSampleBuffer>?
            terminalResult = PBFFmpegReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            if terminalResult != PBFFmpegReadResultSample { break }
            _ = sample?.takeRetainedValue()
        }

        #expect(terminalResult == PBFFmpegReadResultError)
        #expect(PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource) == 0)
    }
}

@Test func openedHTTPContextUsesFFmpegDefaultOpenEndedRanges() throws {
    setFFmpegLogLevel(-8)
    let server = try RecordingRangeServer(serving: try Data(contentsOf: tailMoovFixture))
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let reader = server.url.absoluteString.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: reportedError(error)))
    PBFFmpegReaderDestroy(activeReader)

    #expect(
        server.ranges.isEmpty == false &&
            server.ranges.allSatisfy { $0.hasSuffix("-") },
        Comment(rawValue: "FFmpeg did not retain its default open-ended ranges: \(server.ranges)")
    )
}

@Test func httpPlaybackReadsTheWholeSourceWithoutStalling() throws {
    setFFmpegLogLevel(-8)
    let payload = try Data(contentsOf: tailMoovFixture)
    let server = try RecordingRangeServer(serving: payload, reusingConnections: true)
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(
            path, true, defaultDemuxBufferConfiguration(isRemote: true),
            monitor, &error, error.count
        )
    }
    let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }

    let videoReader = try #require(PBFFmpegReaderAllocate())
    defer { PBFFmpegReaderDestroy(videoReader) }
    try #require(
        PBFFmpegReaderOpenWithDemuxSource(
            videoReader, openedSource, PBFFmpegModeCompressed, &error, error.count
        ),
        Comment(rawValue: reportedError(error))
    )
    let audioReader = try #require(PBFFmpegAudioReaderAllocate())
    defer { PBFFmpegAudioReaderDestroy(audioReader) }
    try #require(
        PBFFmpegAudioReaderOpenWithDemuxSource(
            audioReader, openedSource, -1, &error, error.count
        ),
        Comment(rawValue: reportedError(error))
    )

    let outcome = DrainOutcome()
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        var scratch = [CChar](repeating: 0, count: 512)
        var videoSeconds = 0.0
        var audioSeconds = 0.0
        var videoEnded = false
        var audioEnded = false
        while !videoEnded || !audioEnded {
            var sample: Unmanaged<CMSampleBuffer>?
            if !videoEnded && (audioEnded || videoSeconds <= audioSeconds) {
                let result = PBFFmpegReaderCopyNextSample(
                    videoReader, &sample, &scratch, scratch.count
                )
                if result == PBFFmpegReadResultEnd { videoEnded = true; continue }
                guard result == PBFFmpegReadResultSample, let sample else {
                    outcome.fail("video read failed: \(reportedError(scratch))")
                    break
                }
                let buffer = sample.takeRetainedValue()
                videoSeconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                outcome.add(bytes: CMSampleBufferGetTotalSampleSize(buffer))
            } else {
                var metadata = PBFFmpegAudioSampleMetadata()
                let result = PBFFmpegAudioReaderCopyNextSample(
                    audioReader, &sample, &metadata, &scratch, scratch.count
                )
                if result == PBFFmpegReadResultEnd { audioEnded = true; continue }
                guard result == PBFFmpegReadResultSample, let sample else {
                    outcome.fail("audio read failed: \(reportedError(scratch))")
                    break
                }
                let buffer = sample.takeRetainedValue()
                audioSeconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                outcome.add(bytes: CMSampleBufferGetTotalSampleSize(buffer))
            }
        }
        finished.signal()
    }

    if finished.wait(timeout: .now() + 30) != .success {
        PBFFmpegReaderCancel(videoReader)
        PBFFmpegAudioReaderCancel(audioReader)
        let drained = finished.wait(timeout: .now() + 30) == .success
        Issue.record(
            Comment(rawValue: "playback stalled after \(outcome.samples) samples and "
                + "\(outcome.bytes) bytes, short of the whole \(payload.count)-byte source"
                + "; ranges=\(server.ranges.count) connections=\(server.connections)"
                + " reconnects=\(PBFFmpegDemuxSourceGetReconnectAttemptCount(openedSource))"
                + (drained ? "" : "; the read did not unblock after cancellation"))
        )
        return
    }
    #expect(outcome.failure == nil, Comment(rawValue: outcome.failure ?? ""))
    #expect(outcome.samples > 0)
    #expect(
        outcome.bytes > 131_072,
        Comment(rawValue: "read \(outcome.bytes) bytes from \(outcome.samples) "
            + "samples, too few to cross a request window")
    )
}

@Test func interruptingDemuxSourceAbortsBlockedHTTPRead() throws {
    setFFmpegLogLevel(-8)
    let payload = try Data(contentsOf: tailMoovFixture)
    let server = try RecordingRangeServer(serving: payload)
    defer { server.stop() }
    var error = [CChar](repeating: 0, count: 512)
    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(
            path, true, defaultDemuxBufferConfiguration(isRemote: true),
            nil, &error, error.count
        )
    }
    let openedSource = try #require(source, Comment(rawValue: reportedError(error)))
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }
    try #require(PBFFmpegDemuxSourceSeek(
        openedSource,
        0,
        &error,
        error.count
    ))
    let reader = try #require(PBFFmpegReaderAllocate())
    defer { PBFFmpegReaderDestroy(reader) }
    try #require(
        PBFFmpegReaderOpenWithDemuxSource(
            reader,
            openedSource,
            PBFFmpegModeCompressed,
            &error,
            error.count
        ),
        Comment(rawValue: reportedError(error))
    )
    server.stallNextRangeResponse()
    let readResult = LockedReadResult()
    let finished = DispatchSemaphore(value: 0)
    let readerAddress = Int(bitPattern: reader)
    DispatchQueue.global().async {
        var sample: Unmanaged<CMSampleBuffer>?
        var readError = [CChar](repeating: 0, count: 512)
        readResult.value = PBFFmpegReaderCopyNextSample(
            OpaquePointer(bitPattern: readerAddress),
            &sample,
            &readError,
            readError.count
        )
        _ = sample?.takeRetainedValue()
        finished.signal()
    }
    try #require(server.waitForStalledResponse(timeout: .now() + 5))

    PBFFmpegDemuxSourceInterrupt(openedSource)

    #expect(finished.wait(timeout: .now() + 5) == .success)
    #expect(readResult.value == PBFFmpegReadResultCancelled)
}

private final class LockedReadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = PBFFmpegReadResultError

    var value: PBFFmpegReadResult {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class DrainOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var totalBytes = 0
    private var totalSamples = 0
    private var reportedFailure: String?

    func add(bytes: Int) {
        lock.withLock { totalBytes += bytes; totalSamples += 1 }
    }

    func fail(_ message: String) {
        lock.withLock { if reportedFailure == nil { reportedFailure = message } }
    }

    var bytes: Int { lock.withLock { totalBytes } }
    var samples: Int { lock.withLock { totalSamples } }
    var failure: String? { lock.withLock { reportedFailure } }
}

@Test func sharedDemuxSourceOpensHTTPContainerOnceForAllReaders() throws {
    setFFmpegLogLevel(-8)
    let server = try RecordingRangeServer(serving: try Data(contentsOf: tailMoovFixture))
    defer { server.stop() }
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    var error = [CChar](repeating: 0, count: 512)

    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(
            path,
            true,
            defaultDemuxBufferConfiguration(isRemote: true),
            monitor,
            &error,
            error.count
        )
    }
    let openedSource = try #require(
        source,
        Comment(rawValue: reportedError(error))
    )
    defer { PBFFmpegDemuxSourceDestroy(openedSource) }
    let information = PBFFmpegDemuxSourceCopyInformation(
        openedSource,
        &error,
        error.count
    )
    let openedInformation = try #require(information)
    PBFFmpegMediaSourceInformationDestroy(openedInformation)
    let rangesAfterSourceOpen = server.ranges

    let videoReader = try #require(PBFFmpegReaderAllocate())
    let videoOpened = PBFFmpegReaderOpenWithDemuxSource(
        videoReader,
        openedSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    )
    try #require(videoOpened, Comment(rawValue: reportedError(error)))
    defer { PBFFmpegReaderDestroy(videoReader) }
    let bytesBeforeVideoSample = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)

    let audioReader = try #require(PBFFmpegAudioReaderAllocate())
    let audioOpened = PBFFmpegAudioReaderOpenWithDemuxSource(
        audioReader,
        openedSource,
        -1,
        &error,
        error.count
    )
    try #require(audioOpened, Comment(rawValue: reportedError(error)))
    defer { PBFFmpegAudioReaderDestroy(audioReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    let readResult = PBFFmpegReaderCopyNextSample(
        videoReader,
        &sample,
        &error,
        error.count
    )
    try #require(
        readResult == PBFFmpegReadResultSample,
        Comment(rawValue: reportedError(error))
    )
    _ = sample?.takeRetainedValue()
    let bytesAfterVideoSample = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    #expect(rangesAfterSourceOpen.allSatisfy { $0.hasSuffix("-") })
    #expect(server.ranges.allSatisfy { $0.hasSuffix("-") })
    #expect(bytesAfterVideoSample >= bytesBeforeVideoSample)
}

@Test func extensionlessHTTPMovFamilySourceOpensThroughTheRealVideoProvider() async throws {
    setFFmpegLogLevel(-8)
    let server = try RecordingRangeServer(
        serving: try Data(contentsOf: movFamilyLoopbackFixture)
    )
    defer { server.stop() }
    let provider = FFmpegSampleProvider()
    defer { provider.cancel() }

    do {
        try await provider.prepare(url: server.url, asset: nil, startTime: .zero)
    } catch {
        Issue.record(
            Comment(rawValue: "expected the mov-family source to open over the "
                + "extensionless loopback URL, got \(error)")
        )
        return
    }

    #expect(provider.info.containerFormat == "mov,mp4,m4a,3gp,3g2,mj2")
    #expect(provider.info.formatSignaling.provenance == "AVAssetTrack.sourceFormatDescription")
}

private func bitmapSubtitleResilienceFixtureURL() throws -> URL {
    let encoded = try #require(
        Bundle.module.url(
            forResource: "uhd-with-1080p-bitmap-subtitle.mkv",
            withExtension: "base64",
            subdirectory: "Fixtures"
        )
    )
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "PlaybackCoreBitmapSubtitleResilienceFixture")
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
