import Foundation
import PlaybackFFmpegBridge
import Testing

private final class RecordingRangeServer: @unchecked Sendable {
    private let payload: Data
    private let socket: Int32
    private let lock = NSLock()
    private var observedRanges: [String] = []
    private var listening = true
    private let reusesConnections: Bool

    let port: UInt16

    init(serving payload: Data, reusingConnections: Bool = false) throws {
        self.reusesConnections = reusingConnections
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

    func stop() {
        lock.withLock { listening = false }
        shutdown(socket, SHUT_RDWR)
        close(socket)
    }

    private func serve() {
        while lock.withLock({ listening }) {
            let connection = Darwin.accept(socket, nil, nil)
            guard connection >= 0 else { return }
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
                repeat {
                    if !self.respond(on: connection) { break }
                } while self.reusesConnections
                Darwin.close(connection)
            }
        }
    }

    @discardableResult
    private func respond(on connection: Int32) -> Bool {
        guard let header = readRequestHeader(from: connection) else { return false }
        let rangeValue = header
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }

        guard let rangeValue else {
            send(status: "200 OK", body: payload, declaring: payload.count, on: connection)
            return true
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
            send(status: "500 Internal Server Error", body: Data(), declaring: 0, on: connection)
            return false
        }

        // Emby 4.9.5 over a WebDAV mount answers an open-ended range from a
        // region the mount has not materialized with a Content-Length it then
        // fails to deliver. Measured 2026-08-15 against three cold files: every
        // `bytes=<len-4096>-` was short or 500, while every `bytes=0-` arrived
        // whole. So the defect is reproduced only past the start of the file.
        let promised = payload[start...end]
        let delivered = namedEnd == nil && start > 0 ? promised.prefix(256) : promised
        send(
            status: "206 Partial Content",
            body: Data(delivered),
            declaring: promised.count,
            contentRange: "bytes \(start)-\(end)/\(payload.count)",
            on: connection
        )
        return delivered.count == promised.count
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
    ) {
        var head = "HTTP/1.1 \(status)\r\nAccept-Ranges: bytes\r\nContent-Length: \(length)\r\n"
        if let contentRange { head += "Content-Range: \(contentRange)\r\n" }
        head += reusesConnections
            ? "Connection: keep-alive\r\n\r\n"
            : "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        response.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let wrote = Darwin.write(connection, buffer.baseAddress! + sent, buffer.count - sent)
                guard wrote > 0 else { return }
                sent += wrote
            }
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

@_silgen_name("av_log_set_level")
private func setFFmpegLogLevel(_ level: Int32)

private func reportedError(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

@Test func openedHTTPContextBoundsRangesAfterTheInitialRequest() throws {
    setFFmpegLogLevel(-8)
    let server = try RecordingRangeServer(serving: try Data(contentsOf: tailMoovFixture))
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let reader = server.url.absoluteString.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: reportedError(error)))
    PBFFmpegReaderDestroy(activeReader)

    #expect(server.ranges.first?.hasSuffix("-") == true)
    let bodyReadingRanges = server.ranges.dropFirst()
    #expect(
        bodyReadingRanges.isEmpty == false &&
            bodyReadingRanges.allSatisfy { $0.hasSuffix("-") == false },
        Comment(rawValue: "later ranges were not bounded: \(server.ranges)")
    )
}

/// Bounding an HTTP request to a fixed window makes FFmpeg apply that window to every
/// later request too, and playback then stalls at the first byte past one window with
/// no further request on the wire. Opening a source only reads its header, so the
/// stall is invisible until something reads the body to the end.
@Test func httpPlaybackReadsTheWholeSourceWithoutStalling() throws {
    setFFmpegLogLevel(-8)
    let payload = try Data(contentsOf: tailMoovFixture)
    let server = try RecordingRangeServer(serving: payload, reusingConnections: true)
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let monitor = try #require(PBFFmpegSourceReadMonitorCreate())
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let source = server.url.absoluteString.withCString { path in
        PBFFmpegDemuxSourceCreate(path, monitor, &error, error.count)
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
    #expect(rangesAfterSourceOpen.first?.hasSuffix("-") == true)
    #expect(
        rangesAfterSourceOpen.dropFirst().allSatisfy { !$0.hasSuffix("-") }
    )
    #expect(server.ranges.count == rangesAfterSourceOpen.count + 1)
    #expect(bytesAfterVideoSample > bytesBeforeVideoSample)
}
