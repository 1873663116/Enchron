import Foundation
import Network

nonisolated protocol ByteRangeStreamingSource: AnyObject, Sendable {
    var contentLength: Int64 { get }
    func read(in range: Range<Int64>) async throws -> Data
}

nonisolated final class HTTPRangeStreamingServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case invalidContentLength
        case listenerFailed(String)
        case listenerStopped

        var errorDescription: String? {
            switch self {
            case .invalidContentLength:
                "The remote media size is unavailable."
            case .listenerFailed(let message):
                "Unable to start the private playback stream: \(message)"
            case .listenerStopped:
                "The private playback stream stopped before it became ready."
            }
        }
    }

    struct Statistics: Sendable, Equatable {
        var requestCount = 0
        var bytesRead: Int64 = 0
        var largestRequest: Int64 = 0
    }

    private let source: ByteRangeStreamingSource
    private let filename: String
    private let token = UUID().uuidString
    private let readChunkSize: Int64
    private let queue = DispatchQueue(label: "app.enchron.range-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var transferTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var isStopping = false
    private var statistics = Statistics()

    init(
        source: ByteRangeStreamingSource,
        filename: String,
        readChunkSize: Int64 = 1024 * 1024
    ) {
        self.source = source
        self.filename = filename
        self.readChunkSize = max(1, readChunkSize)
    }

    deinit {
        stop()
    }

    func start() async throws -> URL {
        guard source.contentLength >= 0 else { throw ServerError.invalidContentLength }
        lock.withLock { isStopping = false }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                switch state {
                case .ready:
                    guard resumed.claim(), let port = listener.port else { return }
                    let escapedName = filename.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed
                    ) ?? "media"
                    guard let url = URL(
                        string: "http://127.0.0.1:\(port.rawValue)/\(token)/\(escapedName)"
                    ) else {
                        continuation.resume(throwing: ServerError.listenerFailed("Invalid loopback URL."))
                        return
                    }
                    continuation.resume(returning: url)
                case .failed(let error):
                    guard resumed.claim() else { return }
                    continuation.resume(throwing: ServerError.listenerFailed(error.localizedDescription))
                case .cancelled:
                    guard resumed.claim() else { return }
                    continuation.resume(throwing: ServerError.listenerStopped)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        let work = cancelActiveWork()
        work.listener?.cancel()
        work.tasks.forEach { $0.cancel() }
        work.connections.forEach { $0.cancel() }
    }

    func stopAndWait() async {
        let work = cancelActiveWork()
        work.listener?.cancel()
        work.tasks.forEach { $0.cancel() }
        work.connections.forEach { $0.cancel() }
        for task in work.tasks {
            await task.value
        }
    }

    func snapshot() -> Statistics {
        lock.withLock { statistics }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        let accepted = lock.withLock {
            guard isStopping == false else { return false }
            connections[connectionID] = connection
            return true
        }
        guard accepted else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.connectionDidEnd(connectionID: connectionID)
                connection?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data { requestData.append(data) }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                handle(requestData, on: connection)
            } else if error != nil || isComplete || requestData.count >= 64 * 1024 {
                sendError(400, message: "Bad Request", on: connection)
            } else {
                receiveRequest(on: connection, accumulated: requestData)
            }
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            sendError(400, message: "Bad Request", on: connection)
            return
        }
        let components = firstLine.split(separator: " ")
        guard components.count >= 2 else {
            sendError(400, message: "Bad Request", on: connection)
            return
        }
        let method = String(components[0])
        let path = String(components[1]).removingPercentEncoding ?? String(components[1])
        guard method == "GET" || method == "HEAD",
              path.hasPrefix("/\(token)/") else {
            sendError(404, message: "Not Found", on: connection)
            return
        }

        let headers = Self.headers(from: request)
        guard let requestedRange = Self.byteRange(
            from: headers["range"],
            contentLength: source.contentLength
        ) else {
            sendRangeNotSatisfiable(on: connection)
            return
        }
        let isPartial = headers["range"] != nil
        let responseLength = Int64(requestedRange.count)
        lock.withLock {
            statistics.requestCount += 1
            statistics.largestRequest = max(statistics.largestRequest, responseLength)
        }

        var response = "HTTP/1.1 \(isPartial ? "206 Partial Content" : "200 OK")\r\n"
        response += "Accept-Ranges: bytes\r\n"
        response += "Content-Type: application/octet-stream\r\n"
        response += "Content-Length: \(responseLength)\r\n"
        if isPartial {
            response += "Content-Range: bytes \(requestedRange.lowerBound)-\(requestedRange.upperBound - 1)/\(source.contentLength)\r\n"
        }
        response += "Connection: close\r\n\r\n"

        connection.send(
            content: Data(response.utf8),
            contentContext: .defaultStream,
            isComplete: method == "HEAD",
            completion: .contentProcessed { [connection] error in
                if error != nil { connection.cancel() }
            }
        )
        guard method == "GET" else { return }

        let connectionID = ObjectIdentifier(connection)
        let task = Task { [weak self, connection] in
            guard let self else { return }
            defer { self.finishTransfer(connectionID: connectionID) }
            await self.send(range: requestedRange, on: connection)
        }
        let accepted = lock.withLock {
            guard isStopping == false else { return false }
            transferTasks[connectionID] = task
            return true
        }
        if accepted == false {
            task.cancel()
            connection.cancel()
        }
    }

    private func send(range: Range<Int64>, on connection: NWConnection) async {
        do {
            var offset = range.lowerBound
            while offset < range.upperBound {
                try Task.checkCancellation()
                let readEnd = min(offset + readChunkSize, range.upperBound)
                let chunk = try await source.read(in: offset..<readEnd)
                try Task.checkCancellation()
                guard !chunk.isEmpty else {
                    connection.cancel()
                    return
                }
                let remaining = range.upperBound - offset
                let payload = chunk.prefix(Int(min(Int64(chunk.count), remaining)))
                try await send(
                    Data(payload),
                    isComplete: readEnd == range.upperBound,
                    on: connection
                )
                let sent = Int64(payload.count)
                offset += sent
                lock.withLock { statistics.bytesRead += sent }
            }
        } catch {
            connection.cancel()
        }
    }

    private func cancelActiveWork() -> (
        listener: NWListener?,
        connections: [NWConnection],
        tasks: [Task<Void, Never>]
    ) {
        lock.withLock {
            isStopping = true
            let work = (
                listener,
                Array(connections.values),
                Array(transferTasks.values)
            )
            listener = nil
            connections.removeAll()
            transferTasks.removeAll()
            return work
        }
    }

    private func connectionDidEnd(connectionID: ObjectIdentifier) {
        let task = lock.withLock {
            connections.removeValue(forKey: connectionID)
            return transferTasks[connectionID]
        }
        task?.cancel()
    }

    private func finishTransfer(connectionID: ObjectIdentifier) {
        _ = lock.withLock {
            transferTasks.removeValue(forKey: connectionID)
        }
    }

    private func send(
        _ data: Data,
        isComplete: Bool,
        on connection: NWConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                contentContext: .defaultStream,
                isComplete: isComplete,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func sendRangeNotSatisfiable(on connection: NWConnection) {
        let response = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(source.contentLength)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(response.utf8),
            contentContext: .defaultStream,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    private func sendError(_ status: Int, message: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status) \(message)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(response.utf8),
            contentContext: .defaultStream,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    private static func headers(from request: String) -> [String: String] {
        request.components(separatedBy: "\r\n")
            .dropFirst()
            .reduce(into: [:]) { headers, line in
                guard let separator = line.firstIndex(of: ":") else { return }
                let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
    }

    private static func byteRange(
        from header: String?,
        contentLength: Int64
    ) -> Range<Int64>? {
        guard contentLength >= 0 else { return nil }
        guard let header else { return 0..<contentLength }
        guard header.hasPrefix("bytes="), !header.contains(",") else { return nil }
        let value = header.dropFirst("bytes=".count)
        let bounds = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }

        if bounds[0].isEmpty {
            guard let suffixLength = Int64(bounds[1]), suffixLength > 0 else { return nil }
            let start = max(0, contentLength - suffixLength)
            return start..<contentLength
        }

        guard let start = Int64(bounds[0]), start >= 0, start < contentLength else { return nil }
        let inclusiveEnd: Int64
        if bounds[1].isEmpty {
            inclusiveEnd = contentLength - 1
        } else {
            guard let parsedEnd = Int64(bounds[1]), parsedEnd >= start else { return nil }
            inclusiveEnd = min(parsedEnd, contentLength - 1)
        }
        return start..<(inclusiveEnd + 1)
    }
}

private nonisolated final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
