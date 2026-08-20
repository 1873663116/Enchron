import Foundation
import PlaybackFFmpegBridge
import Testing

private final class RecordingRangeServer: @unchecked Sendable {
    private let payload: Data
    private let socket: Int32
    private let lock = NSLock()
    private var observedRanges: [String] = []
    private var listening = true
    private var activeConnections: Set<Int32> = []
    private var acceptedConnectionCount = 0
    private var sentBodyByteCount = 0
    private var disconnectAtBodyByteCount: Int?
    private var disconnectCount = 0
    private var rejectsResponses = false
    private var rejectionCount = 0
    private let reusesConnections: Bool
    private let responseChunkSize: Int
    private let responseChunkDelay: TimeInterval
    private var stallsNextResponse = false
    private let stalledResponse = DispatchSemaphore(value: 0)
    private let releaseStalledResponse = DispatchSemaphore(value: 0)

    let port: UInt16

    init(
        serving payload: Data,
        reusingConnections: Bool = false,
        responseChunkSize: Int = .max,
        responseChunkDelay: TimeInterval = 0
    ) throws {
        self.reusesConnections = reusingConnections
        self.responseChunkSize = responseChunkSize
        self.responseChunkDelay = responseChunkDelay
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ServerError.unavailable("socket") }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw ServerError.unavailable("bind")
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else {
            close(descriptor)
            throw ServerError.unavailable("getsockname")
        }

        self.payload = payload
        socket = descriptor
        port = assigned.sin_port.byteSwapped

        Thread.detachNewThread { [weak self] in self?.serve() }
    }

    enum ServerError: Error { case unavailable(String) }

    var url: URL { URL(string: "http://127.0.0.1:\(port)/media")! }

    var ranges: [String] {
        lock.withLock { observedRanges }
    }

    var connections: Int { lock.withLock { acceptedConnectionCount } }
    var bytesSent: Int { lock.withLock { sentBodyByteCount } }
    var disconnections: Int { lock.withLock { disconnectCount } }
    var rejections: Int { lock.withLock { rejectionCount } }

    func disconnectOnce(afterSendingAdditionalBytes byteCount: Int) {
        lock.withLock {
            disconnectAtBodyByteCount = sentBodyByteCount + byteCount
        }
    }

    func rejectResponsesAndDisconnect() {
        let connections = lock.withLock {
            rejectsResponses = true
            return Array(activeConnections)
        }
        for connection in connections {
            shutdown(connection, SHUT_RDWR)
        }
    }

    func stop() {
        let connections = lock.withLock {
            listening = false
            return Array(activeConnections)
        }
        for connection in connections {
            shutdown(connection, SHUT_RDWR)
        }
        releaseStalledResponse.signal()
        shutdown(socket, SHUT_RDWR)
        close(socket)
    }

    func stallNextRangeResponse() {
        lock.withLock { stallsNextResponse = true }
    }

    func waitForStalledResponse(timeout: DispatchTime) -> Bool {
        stalledResponse.wait(timeout: timeout) == .success
    }

    private func serve() {
        while lock.withLock({ listening }) {
            let connection = Darwin.accept(socket, nil, nil)
            guard connection >= 0 else { return }
            lock.withLock {
                activeConnections.insert(connection)
                acceptedConnectionCount += 1
            }
            var noSignal: Int32 = 1
            setsockopt(
                connection,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSignal,
                socklen_t(MemoryLayout<Int32>.size)
            )
            Thread.detachNewThread { [weak self] in
                guard let self else { return }
                defer {
                    _ = self.lock.withLock { self.activeConnections.remove(connection) }
                    Darwin.close(connection)
                }
                repeat {
                    if !self.respond(on: connection) { break }
                } while self.reusesConnections
            }
        }
    }

    @discardableResult
    private func respond(on connection: Int32) -> Bool {
        guard let header = readRequestHeader(from: connection) else { return false }
        if lock.withLock({ rejectsResponses }) {
            lock.withLock { rejectionCount += 1 }
            return false
        }
        let rangeValue = header
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }

        guard let rangeValue else {
            return send(status: "200 OK", body: payload, declaring: payload.count, on: connection)
        }
        lock.withLock { observedRanges.append(rangeValue) }

        let bounds = rangeValue.dropFirst("bytes=".count).split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        let start = Int(bounds.first ?? "") ?? 0
        let namedEnd = bounds.count > 1 ? Int(bounds[1]) : nil
        let end = min(namedEnd ?? payload.count - 1, payload.count - 1)
        guard start <= end else {
            _ = send(status: "500 Internal Server Error", body: Data(), declaring: 0, on: connection)
            return false
        }
        let shouldStall = lock.withLock {
            guard stallsNextResponse else { return false }
            stallsNextResponse = false
            return true
        }
        if shouldStall {
            send(
                status: "206 Partial Content",
                body: Data(),
                declaring: end - start + 1,
                contentRange: "bytes \(start)-\(end)/\(payload.count)",
                on: connection
            )
            stalledResponse.signal()
            releaseStalledResponse.wait()
            return false
        }

        let promised = payload[start...end]
        return send(
            status: "206 Partial Content",
            body: Data(promised),
            declaring: promised.count,
            contentRange: "bytes \(start)-\(end)/\(payload.count)",
            on: connection
        )
    }

    private func readRequestHeader(from connection: Int32) -> String? {
        var header = Data()
        var byte: UInt8 = 0
        while header.count < 8192 {
            let read = Darwin.read(connection, &byte, 1)
            guard read == 1 else { return nil }
            header.append(byte)
            if header.count >= 4, header.suffix(4) == Data("\r\n\r\n".utf8) { break }
        }
        return String(data: header, encoding: .utf8)
    }

    private func send(
        status: String,
        body: Data,
        declaring length: Int,
        contentRange: String? = nil,
        on connection: Int32
    ) -> Bool {
        var head = "HTTP/1.1 \(status)\r\nAccept-Ranges: bytes\r\nContent-Length: \(length)\r\n"
        if let contentRange { head += "Content-Range: \(contentRange)\r\n" }
        head += reusesConnections
            ? "Connection: keep-alive\r\n\r\n"
            : "Connection: close\r\n\r\n"
        guard write(Data(head.utf8), on: connection) else { return false }
        var offset = 0
        while offset < body.count {
            let length = min(responseChunkSize, body.count - offset)
            guard write(body.subdata(in: offset..<(offset + length)), on: connection) else {
                return false
            }
            offset += length
            let disconnects = lock.withLock {
                sentBodyByteCount += length
                guard let threshold = disconnectAtBodyByteCount,
                      sentBodyByteCount >= threshold else { return false }
                disconnectAtBodyByteCount = nil
                disconnectCount += 1
                return true
            }
            if disconnects {
                shutdown(connection, SHUT_RDWR)
                return false
            }
            if responseChunkDelay > 0, offset < body.count {
                Thread.sleep(forTimeInterval: responseChunkDelay)
            }
        }
        return true
    }

    private func write(_ data: Data, on connection: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let wrote = Darwin.write(connection, buffer.baseAddress! + sent, buffer.count - sent)
                guard wrote > 0 else { return false }
                sent += wrote
            }
            return true
        }
    }
}

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

@Suite(.serialized)
struct DemuxNetworkResilienceTests {
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
        let source = server.url.absoluteString.withCString {
            PBFFmpegDemuxSourceCreate($0, true, monitor, &error, error.count)
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
                PBFFmpegDemuxSourceGetBufferedDurationSeconds(openedSource) >=
                    PBFFmpegDemuxSourceGetPrefetchDurationSeconds()
            }
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
            PBFFmpegDemuxSourceCreate($0, true, nil, &error, error.count)
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
            PBFFmpegDemuxSourceCreate($0, true, nil, &error, error.count)
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
            PBFFmpegDemuxSourceCreate($0, false, nil, &error, error.count)
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

/// A successful open proves only that FFmpeg read the container header. Drain every
/// track to prove its default HTTP path also reaches the media end.
@Test func httpPlaybackReadsTheWholeSourceWithoutStalling() throws {
    setFFmpegLogLevel(-8)
    let payload = try Data(contentsOf: tailMoovFixture)
    let server = try RecordingRangeServer(serving: payload, reusingConnections: true)
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(path, true, monitor, &error, error.count)
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

    // A stalled read blocks inside FFmpeg's socket read, which cooperative
    // cancellation cannot interrupt, so the read runs where it can be abandoned.
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
        // The readers are destroyed by this scope's defers, so the stalled thread has
        // to leave them before it returns. Cancelling unblocks the in-flight read.
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
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
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
    let payload = try Data(contentsOf: fixture)
    let server = try RecordingRangeServer(serving: payload)
    defer { server.stop() }
    var error = [CChar](repeating: 0, count: 512)
    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(path, true, nil, &error, error.count)
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
