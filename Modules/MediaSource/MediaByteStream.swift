import Foundation
import Network

public enum MediaByteBufferDepth: Sendable, Equatable {
    case none
    case automatic
    case bytes(Int64)
}

public struct MediaByteStreamAttributes: Sendable, Equatable {
    /// A pre-open hint. A range read's `contentLength` is authoritative.
    public let contentLength: Int64?
    public let supportsSeeking: Bool
    public let isLive: Bool
    public let preferredBufferDepth: MediaByteBufferDepth

    public init(
        contentLength: Int64?,
        supportsSeeking: Bool,
        isLive: Bool,
        preferredBufferDepth: MediaByteBufferDepth
    ) {
        self.contentLength = contentLength
        self.supportsSeeking = supportsSeeking
        self.isLive = isLive
        self.preferredBufferDepth = preferredBufferDepth
    }
}

public struct MediaByteRangeRead: Sendable, Equatable {
    public let data: Data
    /// The source's current answer, not a size retained from directory browsing.
    public let contentLength: Int64?
    public let supportsSeeking: Bool

    public init(data: Data, contentLength: Int64?, supportsSeeking: Bool) {
        self.data = data
        self.contentLength = contentLength
        self.supportsSeeking = supportsSeeking
    }
}

public protocol MediaByteRangeSource: AnyObject, Sendable {
    var byteStreamAttributes: MediaByteStreamAttributes { get }
    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead
}

public final class MediaByteStreamHandle: @unchecked Sendable {
    public let url: URL

    private weak var server: MediaByteStreamServer?
    private let token: String
    private let lock = NSLock()
    private var isReleased = false

    fileprivate init(url: URL, token: String, server: MediaByteStreamServer) {
        self.url = url
        self.token = token
        self.server = server
    }

    public func useContainerIndex(for revision: ContentRevision?) {
        server?.configureContainerIndex(token: token, revision: revision)
    }

    /// Ends the only interval whose bytes are container-open input. Reads after this call are media.
    public func finishContainerIndex() {
        server?.finishContainerIndex(token: token)
    }

    public func discardContainerIndex() {
        server?.discardContainerIndex(token: token)
    }

    public func release() {
        let shouldRelease = lock.withLock {
            guard isReleased == false else { return false }
            isReleased = true
            return true
        }
        if shouldRelease { server?.unregister(token: token) }
    }

    deinit {
        release()
    }
}

public final class ContainerIndexCache: @unchecked Sendable {
    public static let shared = ContainerIndexCache()

    private let rootURL: URL
    private let queue = DispatchQueue(label: "app.enchron.container-index-cache", qos: .utility)

    public init(fileManager: FileManager = .default) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = caches.appending(path: "container-indexes", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func diskUsageInBytes() async -> Int64 {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
                let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: Array(keys)
                )
                var total: Int64 = 0
                while let url = enumerator?.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: keys)
                    if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
                }
                continuation.resume(returning: total)
            }
        }
    }

    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                try? FileManager.default.removeItem(at: rootURL)
                try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                continuation.resume()
            }
        }
    }

    fileprivate func session(for revision: ContentRevision) -> ContainerIndexSession {
        ContainerIndexSession(
            directoryURL: rootURL.appending(path: revision.storageKey, directoryHint: .isDirectory),
            queue: queue
        )
    }
}

private final class ContainerIndexSession: @unchecked Sendable {
    private struct StoredRange {
        let range: Range<Int64>
        let url: URL
    }

    private let directoryURL: URL
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var storedRanges: [StoredRange]
    private var pending: [Int64: Data] = [:]
    private var authoritativeContentLength: Int64?
    private var recordsReads = true

    init(directoryURL: URL, queue: DispatchQueue) {
        self.directoryURL = directoryURL
        self.queue = queue
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        storedRanges = urls.compactMap { url in
            guard url.lastPathComponent != "length.txt" else { return nil }
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard parts.count == 2,
                  let offset = Int64(parts[0]),
                  let length = Int64(parts[1]),
                  length > 0 else { return nil }
            return StoredRange(range: offset..<(offset + length), url: url)
        }
        authoritativeContentLength = try? Int64(
            String(contentsOf: directoryURL.appending(path: "length.txt"), encoding: .utf8)
        )
    }

    func data(in range: Range<Int64>) -> (data: Data, contentLength: Int64?)? {
        let cached = lock.withLock {
            (
                storedRanges.first {
                    $0.range.lowerBound <= range.lowerBound && $0.range.upperBound >= range.upperBound
                },
                authoritativeContentLength
            )
        }
        guard let stored = cached.0, let data = try? Data(contentsOf: stored.url) else { return nil }
        let lower = Int(range.lowerBound - stored.range.lowerBound)
        let upper = lower + range.count
        guard lower >= 0, upper <= data.count else { return nil }
        return (Data(data[lower..<upper]), cached.1)
    }

    func record(_ data: Data, at offset: Int64, contentLength: Int64?) {
        lock.withLock {
            guard recordsReads, data.isEmpty == false else { return }
            pending[offset] = data
            if let contentLength { authoritativeContentLength = contentLength }
        }
    }

    func finish() {
        let writes: [(Int64, Data)] = lock.withLock {
            guard recordsReads else { return [] }
            recordsReads = false
            let values = pending.map { ($0.key, $0.value) }
            pending.removeAll()
            return values
        }
        guard writes.isEmpty == false else { return }
        queue.sync { [directoryURL] in
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            for (offset, data) in writes {
                let url = directoryURL.appending(path: "\(offset)-\(data.count).bin")
                try? data.write(to: url, options: .atomic)
            }
            if let contentLength = lock.withLock({ authoritativeContentLength }) {
                try? String(contentLength).write(
                    to: directoryURL.appending(path: "length.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
        let added = writes.map { offset, data in
            StoredRange(
                range: offset..<(offset + Int64(data.count)),
                url: directoryURL.appending(path: "\(offset)-\(data.count).bin")
            )
        }
        lock.withLock { storedRanges.append(contentsOf: added) }
    }

    func discard() {
        lock.withLock {
            recordsReads = false
            pending.removeAll()
        }
    }
}

public final class MediaByteStreamServer: @unchecked Sendable {
    public enum ServerError: LocalizedError {
        case listenerFailed(String)
        case listenerStopped

        public var errorDescription: String? {
            switch self {
            case .listenerFailed(let message): "Unable to start the private media stream: \(message)"
            case .listenerStopped: "The private media stream stopped before it became ready."
            }
        }
    }

    public struct Statistics: Sendable, Equatable {
        public var acceptedConnectionCount = 0
        public var requestCount = 0
        public var bytesRead: Int64 = 0
        public var largestRequest: Int64 = 0
    }

    private final class Registration: @unchecked Sendable {
        let source: any MediaByteRangeSource
        let filename: String
        let lock = NSLock()
        var indexSession: ContainerIndexSession?

        init(source: any MediaByteRangeSource, filename: String) {
            self.source = source
            self.filename = filename
        }
    }

    public static let shared = MediaByteStreamServer()

    private let readChunkSize: Int64
    private let queue = DispatchQueue(label: "app.enchron.media-byte-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startupWaiters: [CheckedContinuation<NWEndpoint.Port, any Error>] = []
    private var registrations: [String: Registration] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var transferTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var statistics = Statistics()

    public init(readChunkSize: Int64 = 1_048_576) {
        self.readChunkSize = max(1, readChunkSize)
    }

    public func register(
        source: any MediaByteRangeSource,
        filename: String
    ) async throws -> MediaByteStreamHandle {
        let port = try await ensureStarted()
        let token = UUID().uuidString
        lock.withLock { registrations[token] = Registration(source: source, filename: filename) }
        let escapedName = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "media"
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/\(escapedName)") else {
            unregister(token: token)
            throw ServerError.listenerFailed("Invalid loopback URL.")
        }
        return MediaByteStreamHandle(url: url, token: token, server: self)
    }

    public func snapshot() -> Statistics {
        lock.withLock { statistics }
    }

    public func stopAndWait() async {
        let work = lock.withLock { () -> (NWListener?, [NWConnection], [Task<Void, Never>]) in
            let work = (listener, Array(connections.values), Array(transferTasks.values))
            listener = nil
            port = nil
            registrations.removeAll()
            connections.removeAll()
            transferTasks.removeAll()
            return work
        }
        work.0?.cancel()
        work.1.forEach { $0.cancel() }
        work.2.forEach { $0.cancel() }
        for task in work.2 { await task.value }
    }

    fileprivate func configureContainerIndex(token: String, revision: ContentRevision?) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        registration.lock.withLock {
            registration.indexSession = revision.map { ContainerIndexCache.shared.session(for: $0) }
        }
    }

    fileprivate func finishContainerIndex(token: String) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        registration.lock.withLock { registration.indexSession }?.finish()
    }

    fileprivate func discardContainerIndex(token: String) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        registration.lock.withLock { registration.indexSession }?.discard()
    }

    fileprivate func unregister(token: String) {
        _ = lock.withLock { registrations.removeValue(forKey: token) }
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
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    listener = try NWListener(using: parameters, on: .any)
                    return true
                } catch {
                    let waiters = startupWaiters
                    startupWaiters.removeAll()
                    waiters.forEach { $0.resume(throwing: error) }
                    return false
                }
            }
            guard startsListener, let listener = lock.withLock({ self.listener }) else { return }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                switch state {
                case .ready:
                    guard let readyPort = listener.port else { return }
                    let waiters = self.lock.withLock {
                        self.port = readyPort
                        let values = self.startupWaiters
                        self.startupWaiters.removeAll()
                        return values
                    }
                    waiters.forEach { $0.resume(returning: readyPort) }
                case .failed(let error): self.failStartup(error)
                case .cancelled: self.failStartup(ServerError.listenerStopped)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)
        }
    }

    private func failStartup(_ error: Error) {
        let waiters = lock.withLock {
            let values = startupWaiters
            startupWaiters.removeAll()
            listener = nil
            return values
        }
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.withLock {
            connections[id] = connection
            statistics.acceptedConnectionCount += 1
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state { self?.connectionDidEnd(id, connection: connection) }
            if case .cancelled = state { self?.connectionDidEnd(id, connection: connection) }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func connectionDidEnd(_ id: ObjectIdentifier, connection: NWConnection?) {
        let task = lock.withLock {
            connections.removeValue(forKey: id)
            return transferTasks.removeValue(forKey: id)
        }
        task?.cancel()
        connection?.cancel()
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var requestData = accumulated
            if let data { requestData.append(data) }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.handle(requestData, on: connection)
            } else if error != nil || isComplete || requestData.count >= 65_536 {
                self.sendError(400, message: "Bad Request", on: connection)
            } else {
                self.receiveRequest(on: connection, accumulated: requestData)
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
        guard components.count >= 2 else { sendError(400, message: "Bad Request", on: connection); return }
        let method = String(components[0])
        let path = String(components[1]).removingPercentEncoding ?? String(components[1])
        let token = path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
        guard (method == "GET" || method == "HEAD"),
              let token,
              let registration = lock.withLock({ registrations[token] }) else {
            sendError(404, message: "Not Found", on: connection)
            return
        }
        let header = Self.headers(from: request)["range"]
        let id = ObjectIdentifier(connection)
        let task = Task { [weak self, connection] in
            guard let self else { return }
            defer { _ = self.lock.withLock { self.transferTasks.removeValue(forKey: id) } }
            await self.respond(method: method, rangeHeader: header, registration: registration, on: connection)
        }
        lock.withLock { transferTasks[id] = task }
    }

    private func respond(
        method: String,
        rangeHeader: String?,
        registration: Registration,
        on connection: NWConnection
    ) async {
        let attributes = registration.source.byteStreamAttributes
        if method == "HEAD" {
            let length = attributes.contentLength
            var response = "HTTP/1.1 200 OK\r\n"
            response += "Accept-Ranges: \(attributes.supportsSeeking && length != nil ? "bytes" : "none")\r\n"
            response += "Content-Type: application/octet-stream\r\n"
            if let length { response += "Content-Length: \(length)\r\n" }
            response += "\r\n"
            try? await send(Data(response.utf8), on: connection)
            receiveRequest(on: connection, accumulated: Data())
            return
        }

        guard attributes.supportsSeeking else {
            guard Self.canServeSequentially(rangeHeader) else {
                sendRangeNotSatisfiable(length: nil, on: connection)
                return
            }
            await sendChunked(registration: registration, on: connection)
            return
        }
        let hintedLength = attributes.contentLength
        let initialRange = if let hintedLength {
            Self.byteRange(from: rangeHeader, contentLength: hintedLength)
        } else {
            Self.initialByteRange(from: rangeHeader, chunkSize: readChunkSize)
        }
        guard var requestedRange = initialRange else {
            sendRangeNotSatisfiable(length: hintedLength, on: connection)
            return
        }
        do {
            let firstEnd = min(requestedRange.lowerBound + readChunkSize, requestedRange.upperBound)
            let first = try await read(requestedRange.lowerBound..<firstEnd, registration: registration)
            guard let actualLength = first.contentLength ?? hintedLength else {
                guard Self.canServeSequentially(rangeHeader), requestedRange.lowerBound == 0 else {
                    sendRangeNotSatisfiable(length: nil, on: connection)
                    return
                }
                await sendChunked(registration: registration, initial: first, on: connection)
                return
            }
            guard first.supportsSeeking else {
                guard Self.canServeSequentially(rangeHeader) else {
                    sendRangeNotSatisfiable(length: actualLength, on: connection)
                    return
                }
                await sendChunked(registration: registration, initial: first, on: connection)
                return
            }
            guard let corrected = Self.byteRange(from: rangeHeader, contentLength: actualLength) else {
                sendRangeNotSatisfiable(length: actualLength, on: connection)
                return
            }
            requestedRange = corrected
            let isPartial = rangeHeader != nil
            let responseLength = Int64(requestedRange.count)
            lock.withLock {
                statistics.requestCount += 1
                statistics.largestRequest = max(statistics.largestRequest, responseLength)
            }
            var response = "HTTP/1.1 \(isPartial ? "206 Partial Content" : "200 OK")\r\n"
            response += "Accept-Ranges: bytes\r\nContent-Type: application/octet-stream\r\n"
            response += "Content-Length: \(responseLength)\r\n"
            if isPartial {
                response += "Content-Range: bytes \(requestedRange.lowerBound)-\(requestedRange.upperBound - 1)/\(actualLength)\r\n"
            }
            response += "\r\n"
            try await send(Data(response.utf8), on: connection)
            var offset = requestedRange.lowerBound
            if first.data.isEmpty == false {
                let payload = first.data.prefix(Int(min(Int64(first.data.count), requestedRange.upperBound - offset)))
                try await send(Data(payload), on: connection)
                offset += Int64(payload.count)
                lock.withLock { statistics.bytesRead += Int64(payload.count) }
            }
            while offset < requestedRange.upperBound {
                let end = min(offset + readChunkSize, requestedRange.upperBound)
                let result = try await read(offset..<end, registration: registration)
                guard result.data.isEmpty == false else { connection.cancel(); return }
                let payload = result.data.prefix(Int(min(Int64(result.data.count), requestedRange.upperBound - offset)))
                try await send(Data(payload), on: connection)
                offset += Int64(payload.count)
                lock.withLock { statistics.bytesRead += Int64(payload.count) }
            }
            receiveRequest(on: connection, accumulated: Data())
        } catch {
            connection.cancel()
        }
    }

    private func read(
        _ range: Range<Int64>,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        let session = registration.lock.withLock { registration.indexSession }
        if let cached = session?.data(in: range) {
            return MediaByteRangeRead(
                data: cached.data,
                contentLength: cached.contentLength
                    ?? registration.source.byteStreamAttributes.contentLength,
                supportsSeeking: true
            )
        }
        let result = try await registration.source.read(in: range)
        session?.record(
            result.data,
            at: range.lowerBound,
            contentLength: result.contentLength
        )
        return result
    }

    private func sendChunked(
        registration: Registration,
        initial: MediaByteRangeRead? = nil,
        on connection: NWConnection
    ) async {
        do {
            let header = "HTTP/1.1 200 OK\r\nAccept-Ranges: none\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\n\r\n"
            try await send(Data(header.utf8), on: connection)
            var offset: Int64 = 0
            if let initial, initial.data.isEmpty == false {
                try await sendChunk(initial.data, on: connection)
                offset = Int64(initial.data.count)
                lock.withLock { statistics.bytesRead += offset }
                if let length = initial.contentLength, offset >= length {
                    try await send(Data("0\r\n\r\n".utf8), on: connection)
                    receiveRequest(on: connection, accumulated: Data())
                    return
                }
            }
            while true {
                try Task.checkCancellation()
                let result = try await registration.source.read(in: offset..<(offset + readChunkSize))
                guard result.data.isEmpty == false else { break }
                try await sendChunk(result.data, on: connection)
                offset += Int64(result.data.count)
                lock.withLock { statistics.bytesRead += Int64(result.data.count) }
                if let length = result.contentLength, offset >= length { break }
            }
            try await send(Data("0\r\n\r\n".utf8), on: connection)
            receiveRequest(on: connection, accumulated: Data())
        } catch {
            connection.cancel()
        }
    }

    private func sendChunk(_ data: Data, on connection: NWConnection) async throws {
        try await send(Data(String(data.count, radix: 16).utf8), on: connection)
        try await send(Data("\r\n".utf8), on: connection)
        try await send(data, on: connection)
        try await send(Data("\r\n".utf8), on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                contentContext: .defaultStream,
                isComplete: false,
                completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: ()) }
                }
            )
        }
    }

    private func sendRangeNotSatisfiable(length: Int64?, on connection: NWConnection) {
        var response = "HTTP/1.1 416 Range Not Satisfiable\r\n"
        if let length { response += "Content-Range: bytes */\(length)\r\n" }
        response += "Content-Length: 0\r\n\r\n"
        connection.send(content: Data(response.utf8), contentContext: .defaultStream, isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            if error == nil { self?.receiveRequest(on: connection, accumulated: Data()) }
        })
    }

    private func sendError(_ status: Int, message: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status) \(message)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), contentContext: .defaultStream, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func headers(from request: String) -> [String: String] {
        request.components(separatedBy: "\r\n").dropFirst().reduce(into: [:]) { headers, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
    }

    private static func byteRange(from header: String?, contentLength: Int64) -> Range<Int64>? {
        guard contentLength >= 0 else { return nil }
        guard let header else { return 0..<contentLength }
        guard header.hasPrefix("bytes="), header.contains(",") == false else { return nil }
        let bounds = header.dropFirst("bytes=".count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty {
            guard let suffix = Int64(bounds[1]), suffix > 0 else { return nil }
            return max(0, contentLength - suffix)..<contentLength
        }
        guard let start = Int64(bounds[0]), start >= 0, start < contentLength else { return nil }
        let end: Int64
        if bounds[1].isEmpty { end = contentLength - 1 }
        else {
            guard let parsed = Int64(bounds[1]), parsed >= start else { return nil }
            end = min(parsed, contentLength - 1)
        }
        return start..<(end + 1)
    }

    private static func initialByteRange(
        from header: String?,
        chunkSize: Int64
    ) -> Range<Int64>? {
        guard let header else { return 0..<chunkSize }
        guard header.hasPrefix("bytes="), header.contains(",") == false else { return nil }
        let bounds = header.dropFirst("bytes=".count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              start >= 0 else { return nil }
        let chunkEnd = start.addingReportingOverflow(chunkSize)
        guard chunkEnd.overflow == false else { return nil }
        if bounds[1].isEmpty { return start..<chunkEnd.partialValue }
        guard let requestedEnd = Int64(bounds[1]), requestedEnd >= start else { return nil }
        let exclusiveEnd = requestedEnd.addingReportingOverflow(1)
        guard exclusiveEnd.overflow == false else { return nil }
        return start..<min(exclusiveEnd.partialValue, chunkEnd.partialValue)
    }

    private static func canServeSequentially(_ rangeHeader: String?) -> Bool {
        guard let rangeHeader else { return true }
        return rangeHeader.contains(",") == false
            && rangeHeader.lowercased().hasPrefix("bytes=0-")
    }
}
