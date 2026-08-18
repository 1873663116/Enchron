import Foundation
import Network

public enum MediaByteSourceSeekability: Sendable, Equatable {
    case sequential
    case randomAccess
}

public enum MediaByteSourceLiveness: Sendable, Equatable {
    case finite
    case live
}

public enum MediaByteBufferDepth: Sendable, Equatable {
    case none
    case automatic
    case bytes(UInt64)
}

public nonisolated protocol MediaByteSource: AnyObject, Sendable {
    var totalLength: Int64? { get }
    var seekability: MediaByteSourceSeekability { get }
    var liveness: MediaByteSourceLiveness { get }
    var suggestedBufferDepth: MediaByteBufferDepth { get }

    func read(in range: Range<Int64>) async throws -> Data
}

public nonisolated final class MediaByteStreamEndpoint: @unchecked Sendable {
    public enum EndpointError: LocalizedError {
        case lengthUnavailable
        case sourceIsNotSeekable
        case listenerFailed(String)
        case listenerStopped

        public var errorDescription: String? {
            switch self {
            case .lengthUnavailable:
                "The remote media size is unavailable."
            case .sourceIsNotSeekable:
                "The remote media source is not seekable."
            case .listenerFailed(let message):
                "Unable to start the private playback stream: \(message)"
            case .listenerStopped:
                "The private playback stream stopped before it became ready."
            }
        }
    }

    struct Statistics: Sendable, Equatable {
        var acceptedConnectionCount = 0
        var requestCount = 0
        var bytesRead: Int64 = 0
        var largestRequest: Int64 = 0
    }

    private nonisolated final class Registration: @unchecked Sendable {
        let source: any MediaByteSource
        let totalLength: Int64
        let readChunkSize: Int64

        init(source: any MediaByteSource, totalLength: Int64) {
            self.source = source
            self.totalLength = totalLength
            readChunkSize = switch source.suggestedBufferDepth {
            case .bytes(let byteCount):
                max(1, Int64(clamping: byteCount))
            case .none, .automatic:
                1_024 * 1_024
            }
        }
    }

    private struct Transfer {
        let token: String
        let task: Task<Void, Never>
    }

    public static let shared = MediaByteStreamEndpoint()

    private let queue = DispatchQueue(label: "app.enchron.media-byte-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startupWaiters: [CheckedContinuation<NWEndpoint.Port, any Error>] = []
    private var registrations: [String: Registration] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionTokens: [ObjectIdentifier: String] = [:]
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    private var statistics = Statistics()

    private init() {}

    deinit {
        let work = lock.withLock {
            let work = (listener, Array(connections.values), transfers.values.map(\.task))
            listener = nil
            port = nil
            registrations.removeAll()
            connections.removeAll()
            connectionTokens.removeAll()
            transfers.removeAll()
            return work
        }
        work.0?.cancel()
        work.1.forEach { $0.cancel() }
        work.2.forEach { $0.cancel() }
    }

    public func resolve(
        _ source: any MediaByteSource,
        filename: String,
        onTermination: @escaping @Sendable () async -> Void = {}
    ) async throws -> MediaByteStreamHandle {
        guard let totalLength = source.totalLength, totalLength > 0 else {
            throw EndpointError.lengthUnavailable
        }
        guard source.seekability == .randomAccess else {
            throw EndpointError.sourceIsNotSeekable
        }

        let port = try await ensureStarted()
        let token = UUID().uuidString
        let escapedName = filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? "media"
        guard let url = URL(
            string: "http://127.0.0.1:\(port.rawValue)/\(token)/\(escapedName)"
        ) else {
            throw EndpointError.listenerFailed("Invalid loopback URL.")
        }

        let registration = Registration(source: source, totalLength: totalLength)
        lock.withLock { registrations[token] = registration }
        return MediaByteStreamHandle(
            url: url,
            accessLease: MediaAccessLease { [weak self] in
                self?.unregister(token: token, onTermination: onTermination)
            },
            issuance: .loopbackRoute
        )
    }

    func snapshot() -> Statistics {
        lock.withLock { statistics }
    }

    private func ensureStarted() async throws -> NWEndpoint.Port {
        if let port = lock.withLock({ port }) { return port }

        return try await withCheckedThrowingContinuation { continuation in
            let startsListener = lock.withLock {
                if let port {
                    continuation.resume(returning: port)
                    return false
                }
                startupWaiters.append(continuation)
                guard listener == nil else { return false }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(
                        host: "127.0.0.1",
                        port: .any
                    )
                    listener = try NWListener(using: parameters, on: .any)
                    return true
                } catch {
                    let waiters = startupWaiters
                    startupWaiters.removeAll()
                    waiters.forEach { $0.resume(throwing: error) }
                    return false
                }
            }
            guard startsListener, let listener = lock.withLock({ self.listener }) else {
                return
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                switch state {
                case .ready:
                    guard let readyPort = listener.port else { return }
                    let waiters = self.lock.withLock {
                        self.port = readyPort
                        let waiters = self.startupWaiters
                        self.startupWaiters.removeAll()
                        return waiters
                    }
                    waiters.forEach { $0.resume(returning: readyPort) }
                case .failed(let error):
                    self.failStartup(
                        EndpointError.listenerFailed(error.localizedDescription)
                    )
                case .cancelled:
                    self.failStartup(EndpointError.listenerStopped)
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

    private func failStartup(_ error: any Error) {
        let waiters = lock.withLock {
            let waiters = startupWaiters
            startupWaiters.removeAll()
            listener = nil
            port = nil
            return waiters
        }
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        lock.withLock {
            connections[connectionID] = connection
            statistics.acceptedConnectionCount += 1
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data { requestData.append(data) }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                handle(requestData, on: connection)
            } else if error != nil || isComplete || requestData.count >= 64 * 1_024 {
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
        let token = path.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)
        let connectionID = ObjectIdentifier(connection)
        guard method == "GET" || method == "HEAD",
              let token,
              let registration = lock.withLock({ () -> Registration? in
                  guard connections[connectionID] != nil,
                        let registration = registrations[token] else {
                      return nil
                  }
                  connectionTokens[connectionID] = token
                  return registration
              }) else {
            sendError(404, message: "Not Found", on: connection)
            return
        }

        let headers = Self.headers(from: request)
        guard let requestedRange = Self.byteRange(
            from: headers["range"],
            contentLength: registration.totalLength
        ) else {
            sendRangeNotSatisfiable(
                contentLength: registration.totalLength,
                on: connection
            )
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
            response += "Content-Range: bytes \(requestedRange.lowerBound)-\(requestedRange.upperBound - 1)/\(registration.totalLength)\r\n"
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

        let accepted = lock.withLock {
            guard registrations[token] === registration,
                  connections[connectionID] != nil else {
                return false
            }
            let task = Task { [weak self, connection, registration] in
                guard let self else { return }
                defer { self.finishTransfer(connectionID: connectionID) }
                await self.send(
                    range: requestedRange,
                    registration: registration,
                    on: connection
                )
            }
            transfers[connectionID] = Transfer(token: token, task: task)
            return true
        }
        if accepted == false { connection.cancel() }
    }

    private func send(
        range: Range<Int64>,
        registration: Registration,
        on connection: NWConnection
    ) async {
        do {
            var offset = range.lowerBound
            while offset < range.upperBound {
                try Task.checkCancellation()
                let readEnd = min(offset + registration.readChunkSize, range.upperBound)
                let chunk = try await registration.source.read(in: offset..<readEnd)
                try Task.checkCancellation()
                guard chunk.isEmpty == false else {
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

    private func unregister(
        token: String,
        onTermination: @escaping @Sendable () async -> Void
    ) {
        let work = lock.withLock { () -> ([NWConnection], [Task<Void, Never>])? in
            guard registrations.removeValue(forKey: token) != nil else { return nil }

            let connectionIDs = connectionTokens.compactMap { connectionID, registeredToken in
                registeredToken == token ? connectionID : nil
            }
            let routeConnections = connectionIDs.compactMap { connectionID in
                connectionTokens.removeValue(forKey: connectionID)
                return connections.removeValue(forKey: connectionID)
            }
            let transferIDs = transfers.compactMap { connectionID, transfer in
                transfer.token == token ? connectionID : nil
            }
            let routeTasks = transferIDs.compactMap { connectionID in
                transfers.removeValue(forKey: connectionID)?.task
            }
            return (routeConnections, routeTasks)
        }
        guard let work else { return }

        work.1.forEach { $0.cancel() }
        work.0.forEach { $0.cancel() }
        Task {
            for task in work.1 { await task.value }
            await onTermination()
        }
    }

    private func connectionDidEnd(connectionID: ObjectIdentifier) {
        let task = lock.withLock {
            connections.removeValue(forKey: connectionID)
            connectionTokens.removeValue(forKey: connectionID)
            return transfers[connectionID]?.task
        }
        task?.cancel()
    }

    private func finishTransfer(connectionID: ObjectIdentifier) {
        _ = lock.withLock { transfers.removeValue(forKey: connectionID) }
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

    private func sendRangeNotSatisfiable(
        contentLength: Int64,
        on connection: NWConnection
    ) {
        let response = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(contentLength)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
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
                let value = line[line.index(after: separator)...]
                    .trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
    }

    private static func byteRange(
        from header: String?,
        contentLength: Int64
    ) -> Range<Int64>? {
        guard contentLength >= 0 else { return nil }
        guard let header else { return 0..<contentLength }
        guard header.hasPrefix("bytes="), header.contains(",") == false else { return nil }
        let value = header.dropFirst("bytes=".count)
        let bounds = value.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard bounds.count == 2 else { return nil }

        if bounds[0].isEmpty {
            guard let suffixLength = Int64(bounds[1]), suffixLength > 0 else { return nil }
            let start = max(0, contentLength - suffixLength)
            return start..<contentLength
        }

        guard let start = Int64(bounds[0]), start >= 0, start < contentLength else {
            return nil
        }
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
