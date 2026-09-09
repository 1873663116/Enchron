import Foundation

final class RecordingRangeServer: @unchecked Sendable {
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
