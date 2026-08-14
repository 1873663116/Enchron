import Foundation
import PlaybackFFmpegBridge
import Testing

/// Serves one file over HTTP the way Emby 4.9.5.0 serves its WebDAV-backed
/// library: a range whose last byte is named arrives whole, and a range left
/// open-ended is answered with a Content-Length it then fails to deliver.
///
/// Measured against `Blade Runner (1982).mp4`, where `bytes=17129754728-` yielded
/// 81920 of the 112249 bytes it promised. The reader has to survive that, because
/// every container keeps something at the end of the file: an MP4 its moov, a
/// Matroska file its Cues.
private final class TruncatingRangeServer: @unchecked Sendable {
    private let payload: Data
    private let socket: Int32
    private let lock = NSLock()
    private var observedRanges: [String] = []
    private var listening = true

    let port: UInt16

    init(serving payload: Data) throws {
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
            respond(on: connection)
            close(connection)
        }
    }

    private func respond(on connection: Int32) {
        guard let header = readRequestHeader(from: connection) else { return }
        let rangeValue = header
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }

        guard let rangeValue else {
            send(status: "200 OK", body: payload, declaring: payload.count, on: connection)
            return
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
            return
        }

        let promised = payload[start...end]
        // The defect: an open-ended range is answered with a short body. The
        // server cuts it well inside the header so that a reader which takes the
        // body of such a request cannot identify the source at all, which is what
        // the measured shortfall does to a container whose header is far larger.
        let delivered = namedEnd == nil ? promised.prefix(256) : promised
        send(
            status: "206 Partial Content",
            body: Data(delivered),
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
    ) {
        var head = "HTTP/1.1 \(status)\r\nAccept-Ranges: bytes\r\nContent-Length: \(length)\r\n"
        if let contentRange { head += "Content-Range: \(contentRange)\r\n" }
        head += "Connection: close\r\n\r\n"
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

private let mkvFixture = Bundle.module.url(
    forResource: "Fixtures/subtitle-subrip",
    withExtension: "mkv"
)

@_silgen_name("av_log_set_level")
private func setFFmpegLogLevel(_ level: Int32)

private func reportedError(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

/// A server that shorts open-ended ranges can still be read from, because the
/// ranges the reader takes media bytes from name their last byte.
///
/// One open-ended request remains, and it is the one that asks how long the
/// source is. It is answered from the response header and its body is never
/// read, so a short body cannot reach the demuxer through it.
@Test func truncatedOpenEndedRangesDoNotStopAnHTTPSourceBeingRead() throws {
    setFFmpegLogLevel(-8)
    let fixture = try #require(mkvFixture)
    let server = try TruncatingRangeServer(serving: try Data(contentsOf: fixture))
    defer { server.stop() }

    var error = [CChar](repeating: 0, count: 512)
    let reader = server.url.absoluteString.withCString { path in
        PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: reportedError(error)))
    PBFFmpegReaderDestroy(activeReader)

    let bodyReadingRanges = server.ranges.filter { $0.hasSuffix("-") == false }
    #expect(
        bodyReadingRanges.isEmpty == false,
        Comment(rawValue: "no bounded range was requested: \(server.ranges)")
    )
}
