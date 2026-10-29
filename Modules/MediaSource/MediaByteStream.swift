import Foundation
import Network
#if DEBUG
import CryptoKit
import os
#endif

#if DEBUG
public struct MediaByteStreamDebugCounters: Sendable, Equatable {
    public var scope: UInt64
    public var acceptedConnectionCount: UInt64
    public var requestCount: UInt64
    public var containerIndexOpen: MediaByteStreamContainerIndexDebugSnapshot?

    public init(
        scope: UInt64,
        acceptedConnectionCount: UInt64,
        requestCount: UInt64,
        containerIndexOpen: MediaByteStreamContainerIndexDebugSnapshot? = nil
    ) {
        self.scope = scope
        self.acceptedConnectionCount = acceptedConnectionCount
        self.requestCount = requestCount
        self.containerIndexOpen = containerIndexOpen
    }
}

private struct MediaByteStreamDebugCounterState: Sendable {
    var acceptedConnectionCount: UInt64 = 0
    var requestCount: UInt64 = 0
}
#endif

public enum MediaSourceDebugTrace {
    public static func event(_ message: @autoclosure () -> String) {
#if DEBUG
        sinkLock.withLock { sinkStorage }?(message())
#endif
    }

#if DEBUG
    private static let sinkLock = NSLock()
    nonisolated(unsafe) private static var sinkStorage: (@Sendable (String) -> Void)?

    public static func installSink(_ sink: (@Sendable (String) -> Void)?) {
        sinkLock.withLock { sinkStorage = sink }
    }
#endif
}

public enum MediaByteBufferDepth: Sendable, Equatable {
    case none
    case automatic
    case bytes(Int64)
}

public enum MediaSourceReadFailure: Error, Sendable, Equatable {
    case transportInterrupted
    case resourceMissing
    case accessDenied
    case invalidData

    public init?(classifying error: any Error) {
        if let failure = error as? Self {
            self = failure
            return
        }

        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []
        while let candidate = current {
            let identity = ObjectIdentifier(candidate)
            guard visited.insert(identity).inserted else { return nil }
            if let failure = Self(classifying: candidate) {
                self = failure
                return
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    public init?(httpStatusCode: Int) {
        switch httpStatusCode {
        case 401, 403:
            self = .accessDenied
        case 404, 410:
            self = .resourceMissing
        case 408, 429, 500, 502, 503, 504:
            self = .transportInterrupted
        case 416:
            self = .invalidData
        default:
            return nil
        }
    }

    private init?(classifying error: NSError) {
        switch error.domain {
        case NSURLErrorDomain:
            switch URLError.Code(rawValue: error.code) {
            case .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .networkConnectionLost, .dnsLookupFailed,
                 .notConnectedToInternet, .cannotLoadFromNetwork, .dataNotAllowed,
                 .internationalRoamingOff, .callIsActive,
                 .backgroundSessionWasDisconnected, .secureConnectionFailed:
                self = .transportInterrupted
            case .fileDoesNotExist, .resourceUnavailable:
                self = .resourceMissing
            case .noPermissionsToReadFile:
                self = .accessDenied
            case .cannotDecodeRawData, .cannotDecodeContentData:
                self = .invalidData
            default:
                return nil
            }
        case NSPOSIXErrorDomain:
            guard let code = POSIXErrorCode(rawValue: Int32(error.code)) else {
                return nil
            }
            switch code {
            case .ECONNRESET, .ECONNABORTED, .ENETDOWN, .ENETRESET,
                 .ENETUNREACH, .ENOTCONN, .ETIMEDOUT, .EHOSTDOWN,
                 .EHOSTUNREACH, .EPIPE:
                self = .transportInterrupted
            case .ENOENT, .ENOTDIR, .ESTALE:
                self = .resourceMissing
            case .EACCES, .EPERM:
                self = .accessDenied
            case .EBADMSG:
                self = .invalidData
            default:
                return nil
            }
        case NSCocoaErrorDomain:
            switch CocoaError.Code(rawValue: error.code) {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                self = .resourceMissing
            case .fileReadNoPermission:
                self = .accessDenied
            case .fileReadCorruptFile:
                self = .invalidData
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

public struct MediaSourceReadFailureObservation: Sendable, Equatable {
    public let sequence: UInt64
    public let failure: MediaSourceReadFailure

    public init(sequence: UInt64, failure: MediaSourceReadFailure) {
        self.sequence = sequence
        self.failure = failure
    }
}

private final class MediaSourceReadFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: MediaSourceReadFailureObservation?

    func record(_ failure: MediaSourceReadFailure) {
        lock.withLock {
            latest = MediaSourceReadFailureObservation(
                sequence: (latest?.sequence ?? 0) &+ 1,
                failure: failure
            )
        }
    }

    func snapshot() -> MediaSourceReadFailureObservation? {
        lock.withLock { latest }
    }
}

public struct MediaByteStreamAttributes: Sendable, Equatable {
    public let contentLength: Int64?
    public let supportsSeeking: Bool
    public let isLive: Bool

    public init(
        contentLength: Int64?,
        supportsSeeking: Bool,
        isLive: Bool
    ) {
        self.contentLength = contentLength
        self.supportsSeeking = supportsSeeking
        self.isLive = isLive
    }
}

public struct MediaByteRangeRead: Sendable, Equatable {
    public let data: Data
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
    public let preferredBufferDepth: MediaByteBufferDepth

    private var serverStorage: MediaByteStreamServer?
    private var retainCount = 1
    private var server: MediaByteStreamServer? { lock.withLock { serverStorage } }
    private let token: String
    private let readFailureState: MediaSourceReadFailureState
    private let lock = NSLock()

    fileprivate init(
        url: URL,
        preferredBufferDepth: MediaByteBufferDepth,
        token: String,
        readFailureState: MediaSourceReadFailureState,
        server: MediaByteStreamServer
    ) {
        self.url = url
        self.preferredBufferDepth = preferredBufferDepth
        self.token = token
        self.readFailureState = readFailureState
        self.serverStorage = server
    }

    public func latestReadFailure() -> MediaSourceReadFailureObservation? {
        readFailureState.snapshot()
    }

    public static func refreshing(
        _ handles: [MediaByteStreamHandle],
        restartingListeners: Bool
    ) async throws -> [MediaByteStreamHandle] {
        var restarted = Set<ObjectIdentifier>()
        var result: [MediaByteStreamHandle] = []
        for handle in handles {
            guard let server = handle.server else {
                throw MediaByteStreamServer.ServerError.listenerStopped
            }
            if restartingListeners, restarted.insert(ObjectIdentifier(server)).inserted {
                _ = server.stopTransfers(preservingRegistrations: true)
            }
            result.append(try await server.refreshedHandle(for: handle.token))
        }
        return result
    }

    public func measureLatency() async -> Double? {
        guard let server else { return nil }
        return await server.measureLatency(token: token)
    }

    public func measureCapacity(blocks: Int) async -> Double? {
        guard let server else { return nil }
        return await server.measureCapacity(token: token, blocks: blocks)
    }

    public func setSpeculativePrefetch(enabled: Bool) async {
        guard let server else { return }
        await server.setSpeculativePrefetch(token: token, enabled: enabled)
    }

    public func prefetchBlockSize() async -> Int64 {
        guard let server else { return 0 }
        return await server.prefetchBlockSize(token: token)
    }

    public func prewarm(byteCount: Int64) async throws {
        guard let server else { throw MediaByteStreamServer.ServerError.listenerStopped }
        try await server.prewarm(token: token, byteCount: byteCount)
    }

    public func useContainerIndex(for revision: ContentRevision?) {
        server?.configureContainerIndex(token: token, revision: revision)
    }

    public func finishContainerIndex() {
        server?.finishContainerIndex(token: token)
    }

    public func discardContainerIndex() {
        server?.discardContainerIndex(token: token)
    }

    #if DEBUG
        public func debugCounters() -> MediaByteStreamDebugCounters? {
            server?.debugCounters(token: token)
        }
    #endif

    public func retain() {
        lock.withLock {
            guard serverStorage != nil else { return }
            retainCount += 1
        }
    }

    public func release() {
        let owner: MediaByteStreamServer? = lock.withLock {
            retainCount -= 1
            guard retainCount <= 0 else { return nil }
            let owner = serverStorage
            serverStorage = nil
            return owner
        }
        owner?.unregister(token: token)
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

    #if DEBUG
        public init(debugRootURL: URL, fileManager: FileManager = .default) {
            rootURL = debugRootURL
            try? fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        }

        public func debugSnapshot(
            fileManager: FileManager = .default
        ) -> ContainerIndexDebugSnapshot {
            queue.sync { [rootURL] in
                let candidates = (try? fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                let entries: [ContainerIndexDebugEntry] = candidates.compactMap {
                    directoryURL -> ContainerIndexDebugEntry? in
                    let key = directoryURL.lastPathComponent
                    guard Self.isRevisionKey(key),
                          (try? directoryURL.resourceValues(
                            forKeys: [.isDirectoryKey]
                          ).isDirectory) == true else { return nil }
                    let resourceKeys: Set<URLResourceKey> = [
                        .isRegularFileKey,
                        .fileSizeKey
                    ]
                    let files = ((fileManager.enumerator(
                        at: directoryURL,
                        includingPropertiesForKeys: Array(resourceKeys),
                        options: [.skipsHiddenFiles]
                    )?.allObjects as? [URL]) ?? [])
                    .filter {
                        (try? $0.resourceValues(forKeys: resourceKeys)
                            .isRegularFile) == true
                    }
                    .sorted { $0.path < $1.path }
                    var hasher = SHA256()
                    var bytes: Int64 = 0
                    var contentLength: Int64?
                    var ranges: [ContainerIndexDebugRange] = []
                    var invalidFileCount = 0
                    for fileURL in files {
                        guard let data = try? Data(contentsOf: fileURL) else {
                            return nil
                        }
                        let relativePath = String(
                            fileURL.path.dropFirst(directoryURL.path.count + 1)
                        )
                        hasher.update(data: Data(relativePath.utf8))
                        hasher.update(data: Data([0]))
                        hasher.update(data: data)
                        hasher.update(data: Data([0]))
                        bytes += Int64(data.count)

                        if relativePath == "length.txt" {
                            if let text = String(bytes: data, encoding: .utf8),
                               let parsed = Int64(text),
                               parsed >= 0 {
                                contentLength = parsed
                            } else {
                                invalidFileCount += 1
                            }
                            continue
                        }
                        guard fileURL.pathExtension == "bin",
                              let range = Self.debugRange(
                                fileName: fileURL.deletingPathExtension().lastPathComponent,
                                actualBytes: data.count
                              ) else {
                            invalidFileCount += 1
                            continue
                        }
                        ranges.append(range)
                    }
                    ranges.sort {
                        ($0.lowerBound, $0.upperBoundExclusive)
                            < ($1.lowerBound, $1.upperBoundExclusive)
                    }
                    return ContainerIndexDebugEntry(
                        contentRevision: "sha256:\(key)",
                        digest: Self.digest(hasher.finalize()),
                        bytes: bytes,
                        contentLength: contentLength,
                        ranges: ranges,
                        invalidFileCount: invalidFileCount
                    )
                }
                .sorted { $0.contentRevision < $1.contentRevision }
                var snapshotHasher = SHA256()
                for entry in entries {
                    snapshotHasher.update(data: Data(entry.contentRevision.utf8))
                    snapshotHasher.update(data: Data([0]))
                    snapshotHasher.update(data: Data(entry.digest.utf8))
                    snapshotHasher.update(data: Data([0]))
                    snapshotHasher.update(data: Data(String(entry.bytes).utf8))
                    snapshotHasher.update(data: Data([10]))
                }
                return ContainerIndexDebugSnapshot(
                    cacheIdentity: Self.digest(
                        SHA256.hash(data: Data(rootURL.standardizedFileURL.path.utf8))
                    ),
                    digest: Self.digest(snapshotHasher.finalize()),
                    entries: entries
                )
            }
        }

        private static func debugRange(
            fileName: String,
            actualBytes: Int
        ) -> ContainerIndexDebugRange? {
            let parts = fileName.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let lowerBound = Int64(parts[0]),
                  let declaredBytes = Int64(parts[1]),
                  lowerBound >= 0,
                  declaredBytes > 0,
                  declaredBytes == Int64(actualBytes),
                  lowerBound <= Int64.max - declaredBytes else { return nil }
            return ContainerIndexDebugRange(
                lowerBound: lowerBound,
                upperBoundExclusive: lowerBound + declaredBytes,
                bytes: declaredBytes
            )
        }

        private static func isRevisionKey(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
        }

        private static func digest(_ digest: SHA256.Digest) -> String {
            "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        }
    #endif

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

    @discardableResult
    func record(_ data: Data, at offset: Int64, contentLength: Int64?) -> Bool {
        lock.withLock {
            guard recordsReads, data.isEmpty == false else { return false }
            pending[offset] = data
            if let contentLength { authoritativeContentLength = contentLength }
            return true
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

#if DEBUG
public final class DebugThrottle: @unchecked Sendable {
    public static let shared = DebugThrottle()
    private let lock = NSLock()
    private var rate: Double = 0

    public func set(_ bytesPerSecond: Double) {
        lock.withLock { rate = max(0, bytesPerSecond) }
    }

    public func current() -> Double {
        lock.withLock { rate }
    }
}
#endif

public final class MediaByteStreamServer: @unchecked Sendable {
    public enum ServerError: LocalizedError {
        case listenerFailed(String)
        case listenerStopped
        case unknownRegistration

        public var errorDescription: String? {
            switch self {
            case .listenerFailed(let message): "Unable to start the private media stream: \(message)"
            case .listenerStopped: "The private media stream stopped before it became ready."
            case .unknownRegistration: "The private media stream no longer holds the requested media."
            }
        }
    }

    #if DEBUG
        private static let debugStatisticsLock = NSLock()
        nonisolated(unsafe) private static var debugTotalBytes: Int64 = 0
        nonisolated(unsafe) private static var debugTotalRequests: Int = 0
        nonisolated(unsafe) private static var debugLastBlockSize: Int64 = 0

        private final class WeakPipeline {
            weak var value: MediaReadPipeline?

            init(_ value: MediaReadPipeline) {
                self.value = value
            }
        }

        nonisolated(unsafe) private static var debugPipelines: [WeakPipeline] = []

        fileprivate static func recordDebugPipeline(_ pipeline: MediaReadPipeline) {
            debugStatisticsLock.withLock {
                debugPipelines.removeAll { $0.value == nil }
                debugPipelines.append(WeakPipeline(pipeline))
            }
        }

        public static func debugProbeSamples() async -> [String] {
            let pipelines = debugStatisticsLock.withLock {
                debugPipelines.compactMap(\.value)
            }
            var rows: [String] = []
            for pipeline in pipelines {
                rows.append(contentsOf: await pipeline.debugProbeSamples())
            }
            return rows
        }

        public static func debugPipelineSnapshots() async -> [String] {
            let pipelines = debugStatisticsLock.withLock {
                debugPipelines.compactMap(\.value)
            }
            var rows: [String] = []
            for pipeline in pipelines {
                let snapshot = await pipeline.snapshot()
                rows.append(
                    "block=\(snapshot.blockSize) latency=\(snapshot.latencySeconds)"
                        + " throughput=\(snapshot.throughputBytesPerSecond)"
                        + " recent=\(snapshot.recentBytesPerSecond)"
                        + " burst=\(snapshot.burstBytesPerSecond)"
                        + " demand=\(snapshot.demandBytes)"
                        + " speculative=\(snapshot.prefetchBytes)"
                        + " prefetch=\(snapshot.prefetchBlocks) concurrency=\(snapshot.concurrency)"
                        + " cached=\(snapshot.cachedBytes) active=\(snapshot.activeReads)"
                )
            }
            return rows
        }

        public static func debugStatisticsSnapshot() -> (bytes: Int64, requests: Int, block: Int64) {
            debugStatisticsLock.withLock { (debugTotalBytes, debugTotalRequests, debugLastBlockSize) }
        }

        fileprivate static func recordDebugBytes(_ count: Int) {
            debugStatisticsLock.withLock { debugTotalBytes += Int64(count) }
        }

        fileprivate static func recordDebugRequest() {
            debugStatisticsLock.withLock { debugTotalRequests += 1 }
        }

        fileprivate static func recordDebugBlockSize(_ size: Int64) {
            debugStatisticsLock.withLock { debugLastBlockSize = size }
        }
    #endif

    public struct Statistics: Sendable, Equatable {
        public var acceptedConnectionCount = 0
        public var requestCount = 0
        public var bytesRead: Int64 = 0
        public var largestRequest: Int64 = 0
    }

    #if DEBUG
    final class SourceThrottle: @unchecked Sendable {
        private let lock = NSLock()
        private var rate: Double = 0
        private var capacity: Double = 0
        private var tokens: Double = 0
        private var last = Date().timeIntervalSinceReferenceDate

        func configure(bytesPerSecond: Double) {
            lock.withLock {
                rate = max(0, bytesPerSecond)
                capacity = max(rate, 1)
                tokens = capacity
                last = Date().timeIntervalSinceReferenceDate
            }
        }

        var isActive: Bool {
            lock.withLock { rate > 0 }
        }

        func configureIfNeeded(_ bytesPerSecond: Double) {
            let differs = lock.withLock { abs(rate - bytesPerSecond) > 0.5 }
            if differs {
                configure(bytesPerSecond: bytesPerSecond)
            }
        }

        func consume(_ bytes: Int) async {
            guard bytes > 0 else { return }
            while true {
                let wait: Double? = lock.withLock {
                    let live = DebugThrottle.shared.current()
                    guard live > 0 else { return nil }
                    let now = Date().timeIntervalSinceReferenceDate
                    let cap = Double(max(bytes, Int(live)))
                    tokens = min(cap, tokens + (now - last) * live)
                    last = now
                    if tokens >= Double(bytes) {
                        tokens -= Double(bytes)
                        return nil
                    }
                    return (Double(bytes) - tokens) / live
                }
                guard let wait else { return }
                let slice = min(max(wait, 0.001), 0.05)
                try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
            }
        }
    }

    #endif

    private final class Registration: @unchecked Sendable {
        let source: any MediaByteRangeSource
        let filename: String
        let token: String
        let preferredBufferDepth: MediaByteBufferDepth
        var readChunkSize: Int64
        var pipeline: MediaReadPipeline?
        let readFailureState = MediaSourceReadFailureState()
        #if DEBUG
        let throttle = SourceThrottle()
        #endif
        let lock = NSLock()
        var indexSession: ContainerIndexSession?
        private var failureStreak = 0
        private var breakerOpenUntil: UInt64 = 0
        var authoritativeContentLength: Int64?
        var degradedReadMode = false
        #if DEBUG
            var containerIndexDebugState: MediaByteStreamContainerIndexDebugState
        #endif

        private static let breakerThreshold = 3

        func breakerAllows(now: UInt64) -> Bool {
            lock.withLock { breakerOpenUntil <= now }
        }

        func breakerSucceeded() {
            lock.withLock {
                failureStreak = 0
                breakerOpenUntil = 0
            }
        }

        func breakerFailed(cooldown: Double) {
            lock.withLock {
                failureStreak += 1
                guard failureStreak >= Self.breakerThreshold else { return }
                let nanos = UInt64(max(cooldown, 0.01) * 1_000_000_000)
                breakerOpenUntil = DispatchTime.now().uptimeNanoseconds + nanos
                failureStreak = 0
            }
        }

        init(
            source: any MediaByteRangeSource,
            filename: String,
            token: String,
            preferredBufferDepth: MediaByteBufferDepth,
            readChunkSize: Int64
        ) {
            self.source = source
            self.filename = filename
            self.token = token
            self.preferredBufferDepth = preferredBufferDepth
            self.readChunkSize = max(1, readChunkSize)
            #if DEBUG
                containerIndexDebugState = MediaByteStreamContainerIndexDebugState(
                    scope: "media-byte-stream:\(token.lowercased())"
                )
            #endif
        }
    }

    private struct ListenerTeardown {
        let waiters: [CheckedContinuation<NWEndpoint.Port, any Error>]
        let connections: [NWConnection]
        let transfers: [Task<Void, Never>]
    }

    private enum ByteRangeRequest {
        case entireRepresentation
        case bounded(start: Int64, end: Int64)
        case openEnded(start: Int64)
        case suffix(length: Int64)
        case rejected

        init(header: String?) {
            guard let header else {
                self = .entireRepresentation
                return
            }
            guard header.contains(",") == false,
                  let separator = header.firstIndex(of: "="),
                  header[..<separator].caseInsensitiveCompare("bytes") == .orderedSame else {
                self = .rejected
                return
            }
            let bounds = header[header.index(after: separator)...]
                .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard bounds.count == 2 else {
                self = .rejected
                return
            }
            if bounds[0].isEmpty {
                guard let length = Int64(bounds[1]), length > 0 else {
                    self = .rejected
                    return
                }
                self = .suffix(length: length)
                return
            }
            guard let start = Int64(bounds[0]), start >= 0 else {
                self = .rejected
                return
            }
            if bounds[1].isEmpty {
                self = .openEnded(start: start)
                return
            }
            guard let end = Int64(bounds[1]), end >= start else {
                self = .rejected
                return
            }
            self = .bounded(start: start, end: end)
        }

        var isPartial: Bool {
            if case .entireRepresentation = self { false } else { true }
        }

        var canUseSequentialTransfer: Bool {
            switch self {
            case .entireRepresentation, .openEnded(start: 0), .bounded(start: 0, end: _): true
            default: false
            }
        }

        func discoveryRange(chunkSize: Int64, lengthHint: Int64?) -> Range<Int64>? {
            switch self {
            case .entireRepresentation:
                return 0..<min(chunkSize, Self.positive(lengthHint) ?? chunkSize)
            case .suffix(let length):
                guard let hint = Self.positive(lengthHint) else { return 0..<chunkSize }
                let start = max(0, hint - length)
                guard let chunkEnd = Self.addingWithoutOverflow(start, chunkSize) else { return nil }
                return start..<min(hint, chunkEnd)
            case .bounded(let start, let end):
                guard let chunkEnd = Self.addingWithoutOverflow(start, chunkSize) else { return nil }
                let requestedEnd = Self.addingWithoutOverflow(end, 1) ?? Int64.max
                let hintedEnd = Self.positive(lengthHint).flatMap { $0 > start ? $0 : nil }
                    ?? Int64.max
                return start..<min(chunkEnd, requestedEnd, hintedEnd)
            case .openEnded(let start):
                guard let end = Self.addingWithoutOverflow(start, chunkSize) else { return nil }
                let hintedEnd = Self.positive(lengthHint).flatMap { $0 > start ? $0 : nil }
                    ?? Int64.max
                return start..<min(end, hintedEnd)
            case .rejected:
                return nil
            }
        }

        func resolvedRange(contentLength: Int64) -> Range<Int64>? {
            guard contentLength >= 0 else { return nil }
            switch self {
            case .entireRepresentation:
                return 0..<contentLength
            case .bounded(let start, let end):
                guard start < contentLength else { return nil }
                return start..<(min(end, contentLength - 1) + 1)
            case .openEnded(let start):
                guard start < contentLength else { return nil }
                return start..<contentLength
            case .suffix(let length):
                guard contentLength > 0 else { return nil }
                return max(0, contentLength - length)..<contentLength
            case .rejected:
                return nil
            }
        }

        private static func addingWithoutOverflow(_ value: Int64, _ addition: Int64) -> Int64? {
            let result = value.addingReportingOverflow(addition)
            return result.overflow ? nil : result.partialValue
        }

        private static func positive(_ value: Int64?) -> Int64? {
            value.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    private let readChunkSize: Int64
    private let silentReadTimeout: Duration
    private let silentReadRetryLimit: Int
    private let degradedReadTimeout: Duration
    private let containerIndexCache: ContainerIndexCache
    private let queue = DispatchQueue(label: "app.enchron.media-byte-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startupWaiters: [CheckedContinuation<NWEndpoint.Port, any Error>] = []
    private var registrations: [String: Registration] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var transferTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var transferTokens: [ObjectIdentifier: String] = [:]
    private var statistics = Statistics()
    #if DEBUG
        private let debugCounterState = OSAllocatedUnfairLock(
            uncheckedState: MediaByteStreamDebugCounterState()
        )
    #endif

    public init(
        readChunkSize: Int64 = 1_048_576,
        silentReadTimeout: Duration = .seconds(30),
        silentReadRetryLimit: Int = 1,
        degradedReadTimeout: Duration = .seconds(10)
    ) {
        self.readChunkSize = max(1, readChunkSize)
        self.silentReadTimeout = silentReadTimeout
        self.silentReadRetryLimit = max(0, silentReadRetryLimit)
        self.degradedReadTimeout = degradedReadTimeout
        self.containerIndexCache = .shared
    }

    #if DEBUG
        init(
            readChunkSize: Int64 = 1_048_576,
            silentReadTimeout: Duration = .seconds(30),
            silentReadRetryLimit: Int = 1,
            degradedReadTimeout: Duration = .seconds(10),
            debugContainerIndexCache: ContainerIndexCache
        ) {
            self.readChunkSize = max(1, readChunkSize)
            self.silentReadTimeout = silentReadTimeout
            self.silentReadRetryLimit = max(0, silentReadRetryLimit)
            self.degradedReadTimeout = degradedReadTimeout
            self.containerIndexCache = debugContainerIndexCache
        }
    #endif

    deinit {
        listener?.cancel()
        connections.values.forEach { $0.cancel() }
        transferTasks.values.forEach { $0.cancel() }
    }

    public func register(
        source: any MediaByteRangeSource,
        filename: String,
        preferredBufferDepth: MediaByteBufferDepth = .none
    ) async throws -> MediaByteStreamHandle {
        try Task.checkCancellation()
        try MediaSourcePreparationResources.current?.hold(self)
        let port = try await ensureStarted()
        try Task.checkCancellation()
        #if DEBUG
            let listenerState = lock.withLock {
                listener.map { String(describing: $0.state) } ?? "none"
            }
            MediaSourceDebugTrace.event(
                "bytestream.register.endpoint port=\(port.rawValue) listener=\(listenerState)"
            )
        #endif
        let token = UUID().uuidString
        let registration = Registration(
            source: source,
            filename: filename,
            token: token,
            preferredBufferDepth: preferredBufferDepth,
            readChunkSize: readChunkSize
        )
        attachPipeline(to: registration)
        lock.withLock { registrations[token] = registration }
        await registration.pipeline?.setSpeculativePrefetch(enabled: false)
        await registration.pipeline?.primeProbe()
        if let pipeline = registration.pipeline {
            let block = await pipeline.snapshot().blockSize
            if block > 0 {
                registration.readChunkSize = block
            }
        }
        #if DEBUG
        if let pipeline = registration.pipeline {
            MediaByteStreamServer.recordDebugPipeline(pipeline)
        }
        #endif
        MediaSourceDebugTrace.event("bytestream.register token=\(token.prefix(8)) name=\(filename)")
        let escapedName = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "media"
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/\(escapedName)") else {
            unregister(token: token)
            throw ServerError.listenerFailed("Invalid loopback URL.")
        }
        let handle = MediaByteStreamHandle(
            url: url,
            preferredBufferDepth: preferredBufferDepth,
            token: token,
            readFailureState: registration.readFailureState,
            server: self
        )
        try MediaSourcePreparationResources.current?.hold(handle)
        return handle
    }

    public func measureLatency(token: String) async -> Double? {
        let registration = lock.withLock { registrations[token] }
        guard let pipeline = registration?.pipeline else { return nil }
        return await pipeline.measureLatency()
    }

    public func measureCapacity(token: String, blocks: Int) async -> Double? {
        let registration = lock.withLock { registrations[token] }
        guard let pipeline = registration?.pipeline else { return nil }
        return await pipeline.measureCapacity(blocks: blocks)
    }

    #if DEBUG
    public static func debugMeasureLatency() async -> Double? {
        let pipelines = debugStatisticsLock.withLock { debugPipelines.compactMap(\.value) }
        guard let pipeline = pipelines.last else { return nil }
        return await pipeline.measureLatency()
    }

    public static func debugMeasureCapacity(blocks: Int) async -> Double? {
        let pipelines = debugStatisticsLock.withLock { debugPipelines.compactMap(\.value) }
        guard let pipeline = pipelines.last else { return nil }
        return await pipeline.measureCapacity(blocks: blocks)
    }
    #endif

    public func setSpeculativePrefetch(token: String, enabled: Bool) async {
        let registration = lock.withLock { registrations[token] }
        await registration?.pipeline?.setSpeculativePrefetch(enabled: enabled)
    }

    public func prefetchBlockSize(token: String) async -> Int64 {
        let registration = lock.withLock { registrations[token] }
        guard let pipeline = registration?.pipeline else { return 0 }
        return await pipeline.snapshot().blockSize
    }

    public func prewarm(token: String, byteCount: Int64) async throws {
        let registration = lock.withLock { registrations[token] }
        guard let registration, let pipeline = registration.pipeline else {
            throw ServerError.unknownRegistration
        }
        let length = registration.source.byteStreamAttributes.contentLength ?? byteCount
        let end = min(max(0, byteCount), length)
        guard end > 0 else { return }
        await pipeline.preload(0..<end)
    }

    private func attachPipeline(to registration: Registration) {
        registration.pipeline = MediaReadPipeline(
            contentLength: registration.source.byteStreamAttributes.contentLength,
            backendRead: { [weak self, weak registration] range in
                guard let self, let registration else {
                    throw ServerError.unknownRegistration
                }
                return try await self.read(range, registration: registration)
            }
        )
    }

    private func pipelineRead(
        _ range: Range<Int64>,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        guard let pipeline = registration.pipeline else {
            throw ServerError.unknownRegistration
        }
        return try await pipeline.read(range)
    }

    public func snapshot() -> Statistics {
        lock.withLock { statistics }
    }

    public func refreshedHandle(for token: String) async throws -> MediaByteStreamHandle {
        let port = try await ensureStarted()
        try Task.checkCancellation()
        let registration = lock.withLock { registrations[token] }
        guard let registration else { throw ServerError.unknownRegistration }
        let refreshedToken = UUID().uuidString
        let refreshed = Registration(
            source: registration.source,
            filename: registration.filename,
            token: refreshedToken,
            preferredBufferDepth: registration.preferredBufferDepth,
            readChunkSize: registration.readChunkSize
        )
        attachPipeline(to: refreshed)
        lock.withLock { registrations[refreshedToken] = refreshed }
        MediaSourceDebugTrace.event(
            "bytestream.register refreshed token=\(refreshedToken.prefix(8))"
                + " name=\(registration.filename) port=\(port.rawValue)"
        )
        let escapedName = registration.filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? "media"
        guard let url = URL(
            string: "http://127.0.0.1:\(port.rawValue)/\(refreshedToken)/\(escapedName)"
        ) else {
            _ = lock.withLock { registrations.removeValue(forKey: refreshedToken) }
            throw ServerError.listenerFailed("Invalid loopback URL.")
        }
        return MediaByteStreamHandle(
            url: url,
            preferredBufferDepth: refreshed.preferredBufferDepth,
            token: refreshedToken,
            readFailureState: refreshed.readFailureState,
            server: self
        )
    }

    #if DEBUG
        fileprivate func debugCounters(token: String) -> MediaByteStreamDebugCounters {
            let containerIndexOpen = lock.withLock { registrations[token] }
                .flatMap { registration in
                    registration.lock.withLock {
                        registration.containerIndexDebugState.snapshot()
                    }
                }
            return debugCounterState.withLock { counters in
                MediaByteStreamDebugCounters(
                    scope: UInt64(UInt(bitPattern: ObjectIdentifier(self))),
                    acceptedConnectionCount: counters.acceptedConnectionCount,
                    requestCount: counters.requestCount,
                    containerIndexOpen: containerIndexOpen
                )
            }
        }
    #endif

    public func stop() {
        _ = stopTransfers()
    }

    public func stopAndWait() async {
        for task in stopTransfers() { await task.value }
    }

    fileprivate func stopTransfers(preservingRegistrations: Bool = false) -> [Task<Void, Never>] {
        MediaSourceDebugTrace.event(
            "bytestream.stopTransfers preservingRegistrations=\(preservingRegistrations)"
        )
        let work = lock.withLock { () -> (NWListener?, ListenerTeardown) in
            let work = (
                listener,
                ListenerTeardown(
                    waiters: startupWaiters,
                    connections: Array(connections.values),
                    transfers: Array(transferTasks.values)
                )
            )
            listener = nil
            port = nil
            startupWaiters.removeAll()
            if !preservingRegistrations { registrations.removeAll() }
            connections.removeAll()
            transferTasks.removeAll()
            transferTokens.removeAll()
            return work
        }
        work.0?.cancel()
        work.1.connections.forEach { $0.cancel() }
        work.1.transfers.forEach { $0.cancel() }
        work.1.waiters.forEach { $0.resume(throwing: ServerError.listenerStopped) }
        MediaSourceDebugTrace.event("bytestream.stopped listenerReleased=true")
        return work.1.transfers
    }

    #if DEBUG
        public func debugCancelListener() async {
            guard let target = lock.withLock({ listener }) else { return }
            target.cancel()
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if lock.withLock({ listener == nil }) { return }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    #endif

    fileprivate func configureContainerIndex(token: String, revision: ContentRevision?) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        registration.lock.withLock {
            registration.indexSession = revision.map { containerIndexCache.session(for: $0) }
            #if DEBUG
                registration.containerIndexDebugState.configure(revision: revision)
            #endif
        }
    }

    fileprivate func finishContainerIndex(token: String) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        guard let session = registration.lock.withLock({ registration.indexSession }) else {
            return
        }
        session.finish()
        #if DEBUG
            registration.lock.withLock {
                guard registration.indexSession === session else { return }
                registration.containerIndexDebugState.containerIndexFinished = true
            }
        #endif
    }

    fileprivate func discardContainerIndex(token: String) {
        guard let registration = lock.withLock({ registrations[token] }) else { return }
        guard let session = registration.lock.withLock({ registration.indexSession }) else {
            return
        }
        session.discard()
        #if DEBUG
            registration.lock.withLock {
                guard registration.indexSession === session else { return }
                registration.containerIndexDebugState.containerIndexFinished = false
            }
        #endif
    }

    #if DEBUG
        private static let debugSourceReadDelayLock = NSLock()
        nonisolated(unsafe) private static var debugSourceReadDelayStorage: Int?

        public static func setDebugSourceReadDelay(milliseconds: Int?) {
            debugSourceReadDelayLock.withLock { debugSourceReadDelayStorage = milliseconds }
            MediaSourceDebugTrace.event(
                "bytestream.readDelay ms=\(milliseconds.map(String.init) ?? "none")"
            )
        }

        public static func debugSourceReadDelayMilliseconds() -> Int? {
            debugSourceReadDelayLock.withLock { debugSourceReadDelayStorage }
        }
    #endif

    fileprivate func unregister(token: String) {
        let removed = lock.withLock { registrations.removeValue(forKey: token) }
        if let pipeline = removed?.pipeline {
            Task { await pipeline.cancelAll() }
        }
        let orphans = lock.withLock { () -> [(Task<Void, Never>?, NWConnection?)] in
            let ids = transferTokens.filter { $0.value == token }.map(\.key)
            return ids.map { id in
                transferTokens.removeValue(forKey: id)
                return (transferTasks.removeValue(forKey: id), connections.removeValue(forKey: id))
            }
        }
        for (task, connection) in orphans {
            task?.cancel()
            connection?.cancel()
        }
        let live = lock.withLock { (registrations.count, transferTasks.count, connections.count) }
        MediaSourceDebugTrace.event(
            "bytestream.unregister token=\(token.prefix(8)) registrations=\(live.0)"
                + " transfers=\(live.1) connections=\(live.2)"
        )
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
                    MediaSourceDebugTrace.event("bytestream.listener.failed error=\(error)")
                    waiters.forEach { $0.resume(throwing: error) }
                    return false
                }
            }
            guard startsListener, let listener = lock.withLock({ self.listener }) else { return }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }
                self.listenerStateChanged(state, of: listener)
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)
        }
    }

    private func listenerStateChanged(_ state: NWListener.State, of listener: NWListener) {
        switch state {
        case .ready:
            guard let readyPort = listener.port else { return }
            let waiters = lock.withLock {
                () -> [CheckedContinuation<NWEndpoint.Port, any Error>] in
                guard self.listener === listener else { return [] }
                port = readyPort
                let values = startupWaiters
                startupWaiters.removeAll()
                return values
            }
            traceListenerState("ready", port: readyPort)
            waiters.forEach { $0.resume(returning: readyPort) }
        case .waiting(let error):
            lock.withLock {
                guard self.listener === listener else { return }
                port = nil
            }
            traceListenerState("waiting:\(error)", port: listener.port)
        case .failed(let error):
            traceListenerState("failed:\(error)", port: listener.port)
            failStartup(error, of: listener)
        case .cancelled:
            traceListenerState("cancelled", port: listener.port)
            failStartup(ServerError.listenerStopped, of: listener)
        default:
            break
        }
    }

    private func traceListenerState(_ state: String, port: NWEndpoint.Port?) {
        MediaSourceDebugTrace.event(
            "bytestream.listener.state=\(state)"
                + " port=\(port.map { String($0.rawValue) } ?? "none")"
        )
    }

    private func failStartup(_ error: any Error, of listener: NWListener) {
        let teardown = lock.withLock { () -> ListenerTeardown? in
            guard self.listener === listener else { return nil }
            let teardown = ListenerTeardown(
                waiters: startupWaiters,
                connections: Array(connections.values),
                transfers: Array(transferTasks.values)
            )
            startupWaiters.removeAll()
            self.listener = nil
            port = nil
            connections.removeAll()
            transferTasks.removeAll()
            transferTokens.removeAll()
            return teardown
        }
        guard let teardown else { return }
        listener.cancel()
        teardown.waiters.forEach { $0.resume(throwing: error) }
        teardown.connections.forEach { $0.cancel() }
        teardown.transfers.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.withLock {
            connections[id] = connection
            statistics.acceptedConnectionCount += 1
        }
        #if DEBUG
            debugCounterState.withLock { counters in
                counters.acceptedConnectionCount &+= 1
            }
        #endif
        MediaSourceDebugTrace.event("bytestream.connection.accepted connection=\(id.hashValue)")
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
            transferTokens.removeValue(forKey: id)
            return transferTasks.removeValue(forKey: id)
        }
        MediaSourceDebugTrace.event(
            "bytestream.connection.end connection=\(id.hashValue) hadTransfer=\(task != nil)"
        )
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
        guard method == "GET" || method == "HEAD",
              let token,
              let registration = lock.withLock({ registrations[token] }) else {
            sendError(404, message: "Not Found", on: connection)
            return
        }
        let header = Self.headers(from: request)["range"]
        let id = ObjectIdentifier(connection)
        MediaSourceDebugTrace.event(
            "bytestream.request token=\(token.prefix(8)) method=\(method) range=\(header ?? "none")"
                + " connection=\(id.hashValue)"
        )
        let task = Task { [weak self, connection] in
            guard let self else { return }
            defer {
                self.lock.withLock {
                    self.transferTasks.removeValue(forKey: id)
                    self.transferTokens.removeValue(forKey: id)
                }
                MediaSourceDebugTrace.event(
                    "bytestream.transfer.end token=\(token.prefix(8)) connection=\(id.hashValue)"
                )
            }
            await self.respond(method: method, rangeHeader: header, registration: registration, on: connection)
        }
        lock.withLock {
            transferTasks[id] = task
            transferTokens[id] = token
        }
    }

    private func respond(
        method: String,
        rangeHeader: String?,
        registration: Registration,
        on connection: NWConnection
    ) async {
        let attributes = registration.source.byteStreamAttributes
        let knownLength = registration.lock.withLock {
            registration.authoritativeContentLength
        }
        if method == "HEAD" {
            let length = knownLength
            var response = "HTTP/1.1 200 OK\r\n"
            response += "Accept-Ranges: \(attributes.supportsSeeking ? "bytes" : "none")\r\n"
            response += "Content-Type: application/octet-stream\r\n"
            if let length { response += "Content-Length: \(length)\r\n" }
            response += "\r\n"
            try? await send(Data(response.utf8), on: connection)
            receiveRequest(on: connection, accumulated: Data())
            return
        }

        let byteRangeRequest = ByteRangeRequest(header: rangeHeader)
        if case .rejected = byteRangeRequest {
            sendRangeNotSatisfiable(length: knownLength, on: connection)
            return
        }
        await respond(
            to: byteRangeRequest,
            knownLength: knownLength,
            attributes: attributes,
            registration: registration,
            on: connection
        )
    }

    private func respond(
        to request: ByteRangeRequest,
        knownLength: Int64?,
        attributes: MediaByteStreamAttributes,
        registration: Registration,
        on connection: NWConnection
    ) async {
        guard attributes.supportsSeeking else {
            guard request.canUseSequentialTransfer else {
                sendRangeNotSatisfiable(length: nil, on: connection)
                return
            }
            await sendChunked(registration: registration, on: connection)
            return
        }

        let initialRange: Range<Int64>
        if let knownLength {
            guard let requestedRange = request.resolvedRange(contentLength: knownLength) else {
                sendRangeNotSatisfiable(length: knownLength, on: connection)
                return
            }
            let initialChunk = min(Int64(requestedRange.count), 2_097_152)
            initialRange = requestedRange.lowerBound..<min(
                requestedRange.upperBound,
                requestedRange.lowerBound + initialChunk
            )
        } else {
            guard let discoveryRange = request.discoveryRange(
                chunkSize: registration.readChunkSize,
                lengthHint: attributes.contentLength
            ) else {
                sendRangeNotSatisfiable(length: nil, on: connection)
                return
            }
            initialRange = discoveryRange
        }

        let first: MediaByteRangeRead
        do {
            first = try await pipelineRead(initialRange, registration: registration)
        } catch {
            sendError(502, message: "Bad Gateway", on: connection)
            return
        }
        do {
            guard let actualLength = first.contentLength ?? knownLength,
                  actualLength >= 0 else {
                guard request.canUseSequentialTransfer, initialRange.lowerBound == 0 else {
                    sendRangeNotSatisfiable(length: nil, on: connection)
                    return
                }
                await sendChunked(registration: registration, initial: first, on: connection)
                return
            }
            guard first.supportsSeeking else {
                guard request.canUseSequentialTransfer, initialRange.lowerBound == 0 else {
                    sendRangeNotSatisfiable(length: actualLength, on: connection)
                    return
                }
                await sendChunked(registration: registration, initial: first, on: connection)
                return
            }
            guard let requestedRange = request.resolvedRange(contentLength: actualLength) else {
                sendRangeNotSatisfiable(length: actualLength, on: connection)
                return
            }
            let responseLength = Int64(requestedRange.count)
            lock.withLock {
                statistics.requestCount += 1
                #if DEBUG
                    Self.recordDebugRequest()
                #endif
                statistics.largestRequest = max(statistics.largestRequest, responseLength)
            }
            #if DEBUG
                debugCounterState.withLock { counters in
                    counters.requestCount &+= 1
                }
            #endif
            let snapshot = await registration.pipeline?.snapshot()
            let readAhead = max(
                262_144,
                min(16_777_216, Int64(snapshot?.prefetchBlocks ?? 4) * (snapshot?.blockSize ?? 262_144))
            )
            var response = "HTTP/1.1 \(request.isPartial ? "206 Partial Content" : "200 OK")\r\n"
            response += "Accept-Ranges: bytes\r\nContent-Type: application/octet-stream\r\n"
            response += "X-Enchron-Read-Ahead: \(readAhead)\r\n"
            response += "Content-Length: \(responseLength)\r\n"
            if request.isPartial {
                response += "Content-Range: bytes \(requestedRange.lowerBound)-\(requestedRange.upperBound - 1)/\(actualLength)\r\n"
            }
            response += "\r\n"
            try await send(Data(response.utf8), on: connection)
            var offset = requestedRange.lowerBound
            if initialRange.lowerBound == requestedRange.lowerBound,
               first.data.isEmpty == false {
                let payload = first.data.prefix(Int(min(Int64(first.data.count), requestedRange.upperBound - offset)))
                try await send(Data(payload), on: connection)
                offset += Int64(payload.count)
                lock.withLock { statistics.bytesRead += Int64(payload.count) }
                #if DEBUG
                    Self.recordDebugBytes(payload.count)
                #endif
            }
            #if DEBUG
                Self.recordDebugBlockSize(registration.readChunkSize)
            #endif
            do {
                while offset < requestedRange.upperBound {
                    try Task.checkCancellation()
                    let chunkEnd = min(offset + registration.readChunkSize, requestedRange.upperBound)
                    let readStartedAt = Date()
                    let result = try await pipelineRead(
                        offset..<chunkEnd,
                        registration: registration
                    )
                    MediaSourceDebugTrace.event(
                        "bytestream.read token=\(registration.token.prefix(8)) offset=\(offset)"
                            + " bytes=\(result.data.count)"
                            + " ms=\(Int(Date().timeIntervalSince(readStartedAt) * 1000))"
                    )
                    guard result.data.isEmpty == false,
                          result.supportsSeeking,
                          result.contentLength == nil || result.contentLength == actualLength else {
                        connection.cancel()
                        return
                    }
                    let payload = result.data.prefix(
                        Int(min(Int64(result.data.count), requestedRange.upperBound - offset))
                    )
                    try await send(Data(payload), on: connection)
                    offset += Int64(payload.count)
                    lock.withLock { statistics.bytesRead += Int64(payload.count) }
                    #if DEBUG
                        Self.recordDebugBytes(payload.count)
                    #endif
                }
            } catch {
                connection.cancel()
                return
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
            #if DEBUG
                registration.lock.withLock {
                    guard registration.indexSession === session else { return }
                    registration.containerIndexDebugState.recordCacheHit(
                        offset: range.lowerBound,
                        byteCount: cached.data.count
                    )
                }
            #endif
            return MediaByteRangeRead(
                data: cached.data,
                contentLength: cached.contentLength
                    ?? registration.lock.withLock { registration.authoritativeContentLength },
                supportsSeeking: true
            )
        }
        let result: MediaByteRangeRead
        do {
            #if DEBUG
                if let delay = Self.debugSourceReadDelayMilliseconds() {
                    try await Task.sleep(for: .milliseconds(delay))
                }
            #endif
            #if DEBUG
            let debugRate = DebugThrottle.shared.current()
            registration.throttle.configureIfNeeded(debugRate)
            if debugRate > 0 {
                await registration.throttle.consume(range.count)
            }
            #endif
            result = try await readSourceWithTransientRetry(range, registration: registration)
        } catch {
            if let failure = MediaSourceReadFailure(classifying: error) {
                registration.readFailureState.record(failure)
            }
            throw error
        }
        if let contentLength = result.contentLength, contentLength >= 0 {
            registration.lock.withLock {
                registration.authoritativeContentLength = contentLength
            }
        }
        #if DEBUG
            if let session {
                registration.lock.withLock {
                    guard registration.indexSession === session else { return }
                    registration.containerIndexDebugState.recordSourceRead(
                        offset: range.lowerBound,
                        byteCount: result.data.count
                    )
                }
            }
        #endif
        #if DEBUG
            let recorded = session?.record(
                result.data,
                at: range.lowerBound,
                contentLength: result.contentLength
            ) ?? false
            if recorded, let session {
                registration.lock.withLock {
                    guard registration.indexSession === session else { return }
                    registration.containerIndexDebugState.recordIndexWrite(
                        offset: range.lowerBound,
                        byteCount: result.data.count
                    )
                }
            }
        #else
            session?.record(
                result.data,
                at: range.lowerBound,
                contentLength: result.contentLength
            )
        #endif
        return result
    }

    private struct SourceReadSilenceTimeout: Error {}

    private final class SourceReadRace: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var storedResult: Result<MediaByteRangeRead, any Error>?
        private var continuation:
            CheckedContinuation<MediaByteRangeRead, any Error>?

        func finish(with result: Result<MediaByteRangeRead, any Error>) {
            let pending = lock.withLock {
                () -> CheckedContinuation<MediaByteRangeRead, any Error>? in
                guard !finished else { return nil }
                finished = true
                if let continuation {
                    self.continuation = nil
                    return continuation
                }
                storedResult = result
                return nil
            }
            pending?.resume(with: result)
        }

        func attach(
            _ continuation: CheckedContinuation<MediaByteRangeRead, any Error>
        ) {
            let result = lock.withLock { () -> Result<MediaByteRangeRead, any Error>? in
                if finished {
                    let stored = storedResult
                    storedResult = nil
                    return stored
                }
                self.continuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
    }

    private struct SilenceReadExhausted: Error {}

    private func readSourceWithTransientRetry(
        _ range: Range<Int64>,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        let now = DispatchTime.now().uptimeNanoseconds
        guard registration.breakerAllows(now: now) else {
            throw MediaSourceReadFailure.transportInterrupted
        }
        var attempt = 0
        while true {
            do {
                let result = try await readSourceWithHedge(range, registration: registration)
                registration.breakerSucceeded()
                return result
            } catch is SilenceReadExhausted {
                registration.breakerFailed(cooldown: await cooldownSeconds(registration: registration))
                throw MediaSourceReadFailure.transportInterrupted
            } catch {
                guard MediaSourceReadFailure(classifying: error) == .transportInterrupted else {
                    throw error
                }
                registration.breakerFailed(cooldown: await cooldownSeconds(registration: registration))
                guard attempt < 2 else { throw error }
                attempt += 1
                let latency = await registration.pipeline?.snapshot().latencySeconds ?? 0.1
                let backoff = min(latency * pow(2, Double(attempt - 1)), 5)
                try await Task.sleep(
                    nanoseconds: UInt64(max(backoff, 0.001) * 1_000_000_000)
                )
            }
        }
    }

    private func cooldownSeconds(registration: Registration) async -> Double {
        let latency = await registration.pipeline?.snapshot().latencySeconds ?? 0.1
        return max(0.25, latency * 10)
    }

    private func readSourceWithHedge(
        _ range: Range<Int64>,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        let degraded = registration.lock.withLock { registration.degradedReadMode }
        if degraded {
            return try await readSourceWithSilenceRetry(range, registration: registration)
        }
        guard await registration.pipeline?.hasMeasuredLatency() == true else {
            return try await readSourceWithSilenceRetry(range, registration: registration)
        }
        let latency = await registration.pipeline?.snapshot().latencySeconds ?? 0.1
        let hedgeDelay = max(latency * 2, 0.001)
        return try await withThrowingTaskGroup(of: MediaByteRangeRead.self) { group in
            group.addTask {
                try await self.readSourceWithSilenceRetry(range, registration: registration)
            }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(hedgeDelay * 1_000_000_000)
                )
                return try await self.readSourceWithSilenceRetry(
                    range,
                    registration: registration
                )
            }
            defer { group.cancelAll() }
            var lastError: Error = MediaSourceReadFailure.transportInterrupted
            while true {
                do {
                    guard let value = try await group.next() else { break }
                    return value
                } catch is SilenceReadExhausted {
                    lastError = MediaSourceReadFailure.transportInterrupted
                } catch is CancellationError {
                    continue
                } catch {
                    if MediaSourceReadFailure(classifying: error) != .transportInterrupted {
                        throw error
                    }
                    lastError = error
                }
            }
            throw lastError
        }
    }

    private func readSourceWithSilenceRetry(
        _ range: Range<Int64>,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        let degraded = registration.lock.withLock { registration.degradedReadMode }
        let timeout: Duration
        if degraded {
            timeout = degradedReadTimeout
        } else {
            let components = silentReadTimeout.components
            let base = Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
            let latency = await registration.pipeline?.snapshot().latencySeconds ?? base
            timeout = .seconds(max(base, latency * 3))
        }
        let retryLimit = degraded ? 0 : silentReadRetryLimit
        var attempt = 0
        while true {
            do {
                let result = try await readSourceWithTimeout(
                    range,
                    timeout: timeout,
                    registration: registration
                )
                registration.lock.withLock { registration.degradedReadMode = false }
                return result
            } catch is SourceReadSilenceTimeout {
                attempt += 1
                if attempt > retryLimit {
                    registration.lock.withLock {
                        registration.degradedReadMode = true
                    }
                    MediaSourceDebugTrace.event(
                        "bytestream.read.exhausted"
                            + " token=\(registration.token.prefix(8))"
                            + " offset=\(range.lowerBound)"
                    )
                    throw SilenceReadExhausted()
                }
                MediaSourceDebugTrace.event(
                    "bytestream.read.retry"
                        + " token=\(registration.token.prefix(8))"
                        + " offset=\(range.lowerBound) attempt=\(attempt + 1)"
                )
            }
        }
    }

    private func readSourceWithTimeout(
        _ range: Range<Int64>,
        timeout: Duration,
        registration: Registration
    ) async throws -> MediaByteRangeRead {
        let race = SourceReadRace()
        let readTask = Task {
            let result: Result<MediaByteRangeRead, any Error>
            do {
                result = .success(try await registration.source.read(in: range))
            } catch {
                result = .failure(error)
            }
            race.finish(with: result)
        }
        let timerTask = Task {
            try? await Task.sleep(for: timeout)
            race.finish(with: .failure(SourceReadSilenceTimeout()))
        }
        defer {
            readTask.cancel()
            timerTask.cancel()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.attach(continuation)
            }
        } onCancel: {
            race.finish(with: .failure(CancellationError()))
            readTask.cancel()
            timerTask.cancel()
        }
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
                let result = try await pipelineRead(
                    offset..<(offset + registration.readChunkSize),
                    registration: registration
                )
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
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
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

}

extension Range where Bound == Int64 {
    fileprivate func prefix(upToCount count: Int64) -> Range<Int64> {
        let candidate = lowerBound.addingReportingOverflow(count)
        let end = candidate.overflow ? upperBound : Swift.min(upperBound, candidate.partialValue)
        return lowerBound..<end
    }
}

public actor MediaReadPipeline {
    public struct Configuration: Sendable {
        public var blockSize: Int64
        public var maxConcurrentReads: Int
        public var maxPrefetchBlocks: Int
        public var prefetchTargetSeconds: Double
        public var cacheCapacityBytes: Int
        public var initialThroughputBytesPerSecond: Double

        public init(
            blockSize: Int64 = 262_144,
            maxConcurrentReads: Int = 8,
            maxPrefetchBlocks: Int = 16,
            prefetchTargetSeconds: Double = 1.0,
            cacheCapacityBytes: Int = 64 * 1_024 * 1_024,
            initialThroughputBytesPerSecond: Double = 10_000_000
        ) {
            self.blockSize = max(1, blockSize)
            self.maxConcurrentReads = max(1, maxConcurrentReads)
            self.maxPrefetchBlocks = max(1, maxPrefetchBlocks)
            self.prefetchTargetSeconds = max(0.05, prefetchTargetSeconds)
            self.cacheCapacityBytes = max(Int(self.blockSize), cacheCapacityBytes)
            self.initialThroughputBytesPerSecond = max(1, initialThroughputBytesPerSecond)
        }
    }

    public struct Snapshot: Sendable {
        public let blockSize: Int64
        public let cachedBlocks: Int
        public let cachedBytes: Int
        public let activeReads: Int
        public let latencySeconds: Double
        public let throughputBytesPerSecond: Double
        public let recentBytesPerSecond: Double
        public let burstBytesPerSecond: Double
        public let demandBytes: Int64
        public let prefetchBytes: Int64
        public let prefetchBlocks: Int
        public let concurrency: Int
    }

    public typealias BackendRead = @Sendable (Range<Int64>) async throws -> MediaByteRangeRead

    struct SourceProbe: Sendable {
        struct Sample: Sendable {
            let bytes: Double
            let seconds: Double
            let start: Double
            let end: Double
        }

        struct Estimate: Sendable {
            let latencySeconds: Double
            let throughputBytesPerSecond: Double
            let jitterSeconds: Double
            let errorRate: Double
            let sampleCount: Int
        }

        private var samples: [Sample] = []
        private var attempts = 0
        private var failures = 0
        private let capacity = 64

        mutating func record(bytes: Int, seconds: Double) {
            let end = Date().timeIntervalSinceReferenceDate
            record(bytes: bytes, start: end - seconds, end: end)
        }

        mutating func record(bytes: Int, start: Double, end: Double) {
            attempts += 1
            guard bytes > 0, end > start else { return }
            samples.append(
                Sample(bytes: Double(bytes), seconds: end - start, start: start, end: end)
            )
            if samples.count > capacity {
                samples.removeFirst(samples.count - capacity)
            }
        }

        mutating func recordFailure() {
            attempts += 1
            failures += 1
        }

        #if DEBUG
        var debugSamples: [String] {
            let intervals = samples.map { ($0.start, $0.end) }
            return samples.map { sample in
                let concurrency = intervals.filter { $0.0 < sample.end && sample.start < $0.1 }.count
                return "bytes=\(Int(sample.bytes)) seconds=\(sample.seconds)"
                    + " start=\(sample.start) end=\(sample.end) concurrency=\(concurrency)"
            }
        }
        #endif

        func ratePercentile(window: Double, percentile: Double, now: Double) -> Double? {
            guard let anchor = samples.map(\.end).max() else { return nil }
            guard now - anchor <= window * 2 else { return nil }
            let cutoff = anchor - window
            let rates = samples
                .filter { $0.end > cutoff && $0.seconds > 0 }
                .map { $0.bytes / $0.seconds }
                .sorted()
            guard rates.isEmpty == false else { return nil }
            let clamped = min(max(percentile, 0), 1)
            let index = Int((Double(rates.count - 1) * clamped).rounded())
            return rates[index]
        }

        func recentRate(window: Double, now: Double) -> Double? {
            guard let anchor = samples.map(\.end).max() else { return nil }
            guard now - anchor <= window * 2 else { return nil }
            let cutoff = anchor - window
            let recent = samples.filter { $0.end > cutoff }
            guard recent.isEmpty == false else { return nil }
            let starts = recent.map(\.start).min() ?? 0
            let ends = recent.map(\.end).max() ?? 0
            let span = ends - starts
            guard span > 0 else { return nil }
            return recent.reduce(0) { $0 + $1.bytes } / span
        }

        var estimate: Estimate? {
            guard samples.count >= 2 else { return nil }
            let points = samples.map {
                (bytes: $0.bytes, seconds: $0.seconds, start: $0.start, end: $0.end)
            }
            let concurrency = points.map { point in
                points.filter { $0.start < point.end && point.start < $0.end }.count
            }
            let xs = points.enumerated().map { index, point in
                point.bytes * Double(max(concurrency[index], 1))
            }
            let ys = points.map(\.seconds)
            let count = Double(points.count)
            let maxX = xs.max() ?? 0
            var slopes: [Double] = []
            for left in points.indices {
                for right in points.indices where right > left {
                    let deltaX = xs[right] - xs[left]
                    guard abs(deltaX) >= maxX * 0.5 else { continue }
                    let deltaY = ys[right] - ys[left]
                    guard deltaX != 0 else { continue }
                    let slope = deltaY / deltaX
                    if slope > 0 {
                        slopes.append(slope)
                    }
                }
            }
            let sortedSlopes = slopes.sorted()
            let middleSlope = sortedSlopes.isEmpty ? 0 : sortedSlopes[sortedSlopes.count / 2]
            let throughput: Double
            let latency: Double
            if middleSlope > 0 {
                throughput = 1 / middleSlope
                let latencies = zip(xs, ys).map { max(0, $1 - middleSlope * $0) }.sorted()
                latency = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
            } else {
                let mergedBytes = points.reduce(0) { $0 + $1.bytes }
                let starts = points.map(\.start).min() ?? 0
                let ends = points.map(\.end).max() ?? 0
                guard ends > starts else { return nil }
                throughput = mergedBytes / (ends - starts)
                latency = 0
            }
            let residuals = zip(xs, ys).map { x, y in y - (latency + x / throughput) }
            let meanResidual = residuals.reduce(0) { $0 + $1 * $1 } / count
            let relativeError = meanResidual.squareRoot() / max(ys.reduce(0, +) / count, 1e-9)
            guard relativeError <= 0.2 else { return nil }
            let mean = residuals.reduce(0, +) / count
            let variance = residuals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
            let errorRate = attempts > 0 ? Double(failures) / Double(attempts) : 0
            return Estimate(
                latencySeconds: latency,
                throughputBytesPerSecond: throughput,
                jitterSeconds: variance.squareRoot(),
                errorRate: errorRate,
                sampleCount: points.count
            )
        }
    }

    private let clock: @Sendable () -> Double
    private let backendRead: BackendRead
    private let configuration: Configuration
    private var effectiveBlockSize: Int64
    private let cachesBlocks: Bool
    private var cache: [Int64: Data] = [:]
    private var recency: [Int64] = []
    private var cachedBytes = 0
    private var speculativePrefetchEnabled = true
    private var demandReadDurations: [Double] = []

    private func recordDemandDuration(_ seconds: Double) {
        demandReadDurations.append(seconds)
        if demandReadDurations.count > 8 {
            demandReadDurations.removeFirst(demandReadDurations.count - 8)
        }
    }

    private var sourceCongested: Bool {
        let samples = demandReadDurations.suffix(4)
        guard samples.count >= 2 else { return false }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        guard let latency = measuredLatency, latency > 0 else { return false }
        return median > latency * 4
    }
    private var demandBytes: Int64 = 0
    private var prefetchBytes: Int64 = 0
    private var inFlight: [Int64: Task<MediaByteRangeRead, any Error>] = [:]
    private var prefetchTasks: [Int64: Task<Void, Never>] = [:]
    private var activeReads = 0
    private var observedContentLength: Int64?
    private var streaming = false
    private var probe = SourceProbe()

    public init(
        configuration: Configuration = Configuration(),
        contentLength: Int64? = nil,
        clock: @escaping @Sendable () -> Double = {
            Date().timeIntervalSinceReferenceDate
        },
        backendRead: @escaping BackendRead
    ) {
        self.configuration = configuration
        self.clock = clock
        self.backendRead = backendRead
        if let contentLength, contentLength > 0 {
            let chosen: Int64 = contentLength >= 32 * 1_024 * 1_024
                ? 4 * 1_024 * 1_024
                : configuration.blockSize
            effectiveBlockSize = min(chosen, contentLength)
            cachesBlocks = true
            observedContentLength = contentLength
        } else {
            effectiveBlockSize = configuration.blockSize
            cachesBlocks = false
        }
    }

    public func read(_ range: Range<Int64>) async throws -> MediaByteRangeRead {
        guard range.isEmpty == false else {
            return MediaByteRangeRead(
                data: Data(),
                contentLength: observedContentLength,
                supportsSeeking: true
            )
        }
        if cachesBlocks == false {
            let read = try await backendRead(range)
            return MediaByteRangeRead(
                data: read.data,
                contentLength: read.contentLength,
                supportsSeeking: true
            )
        }
        if observedContentLength == nil, Int64(range.count) < effectiveBlockSize {
            let read = try await backendRead(range)
            if let length = read.contentLength, length >= 0 {
                observedContentLength = length
            }
            return MediaByteRangeRead(
                data: read.data,
                contentLength: observedContentLength,
                supportsSeeking: true
            )
        }
        if Int64(range.count) >= 1_048_576 {
            streaming = true
        }
        var result = Data()
        var block = blockIndex(for: range.lowerBound)
        let lastBlock = blockIndex(for: range.upperBound - 1)
        while block <= lastBlock {
            let read = try await fetch(block, demand: true)
            if let length = read.contentLength, length >= 0 {
                if let known = observedContentLength, known != length {
                    invalidateCache()
                }
                observedContentLength = length
            }
            let blockStart = block * effectiveBlockSize
            let start = max(range.lowerBound, blockStart) - blockStart
            let end = min(range.upperBound, blockStart + Int64(read.data.count)) - blockStart
            if start < end, let slice = read.data.nonEmptySlice(from: start, to: end) {
                result.append(slice)
            }
            if read.data.count < effectiveBlockSize { break }
            block += 1
        }
        return MediaByteRangeRead(
            data: result,
            contentLength: observedContentLength,
            supportsSeeking: true
        )
    }

    public func preload(_ range: Range<Int64>) async {
        guard cachesBlocks, range.isEmpty == false else { return }
        var blocks: [Int64] = []
        var block = blockIndex(for: range.lowerBound)
        let last = blockIndex(for: range.upperBound - 1)
        while block <= last {
            blocks.append(block)
            block += 1
        }
        await withTaskGroup(of: Void.self) { group in
            for block in blocks {
                group.addTask { [weak self] in
                    _ = try? await self?.fetch(block, demand: false)
                }
            }
        }
    }

    public func contentLength() -> Int64? {
        observedContentLength
    }

    #if DEBUG
    #if DEBUG
    public func debugRecentRate(window: Double) -> Double? {
        probe.recentRate(window: window, now: Date().timeIntervalSinceReferenceDate)
    }
    #endif

    public func debugProbeSamples() -> [String] {
        probe.debugSamples
    }
    #endif

    private var measuredLatency: Double?
    private var measuredThroughput: Double?
    private var capacityFloor: Double?
    private var capacityCeiling: Double?
    private var capacityLatest: Double?
    private var lastCapacityProbeAt: Double = -.infinity

    public func hasMeasuredLatency() -> Bool {
        measuredLatency != nil
    }

    public func primeProbe() async {
        guard cachesBlocks, cache.isEmpty else { return }
        guard let length = observedContentLength, length > 32 * 1_024 * 1_024 else { return }
        guard measuredLatency == nil else { return }
        _ = await measureLatency()
    }

    public func measureLatency() async -> Double? {
        let offset = (observedContentLength ?? 0) / 2
        let range = offset..<(offset + 4_096)
        let startedAt = clock()
        _ = try? await backendRead(range)
        let seconds = clock() - startedAt
        guard seconds > 0 else { return nil }
        measuredLatency = seconds
        refreshBlockSize()
        return seconds
    }

    public func measureCapacity(blocks: Int) async -> Double? {
        guard cachesBlocks else { return nil }
        guard activeReads == 0, inFlight.isEmpty else { return nil }
        let count = max(1, min(blocks, configuration.maxConcurrentReads))
        var rates: [Double] = []
        for _ in 0 ..< 2 {
            let base = max(0, (cache.keys.max() ?? 0) + 1)
            let startedAt = clock()
            var bytes = 0
            await withTaskGroup(of: Int.self) { group in
                for index in 0..<count {
                    group.addTask { [weak self] in
                        guard let self else { return 0 }
                        guard let read = try? await self.fetch(base + Int64(index), demand: false) else {
                            return 0
                        }
                        return read.data.count
                    }
                }
                for await value in group {
                    bytes += value
                }
            }
            let seconds = clock() - startedAt
            guard seconds > 0, bytes > 0 else { return nil }
            rates.append(Double(bytes) / seconds)
        }
        guard let rate = rates.min() else { return nil }
        lastCapacityProbeAt = Date().timeIntervalSinceReferenceDate
        measuredThroughput = rate
        capacityLatest = rate
        capacityFloor = min(capacityFloor ?? rate, rate)
        capacityCeiling = max(capacityCeiling ?? rate, rate)
        refreshBlockSize()
        return rate
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            blockSize: effectiveBlockSize,
            cachedBlocks: cache.count,
            cachedBytes: cachedBytes,
            activeReads: activeReads,
            latencySeconds: measuredLatency ?? probe.estimate?.latencySeconds ?? 0.1,
            throughputBytesPerSecond: probeThroughput,
            recentBytesPerSecond: probe.recentRate(
                window: 5,
                now: Date().timeIntervalSinceReferenceDate
            ) ?? 0,
            burstBytesPerSecond: probe.recentRate(
                window: 1,
                now: Date().timeIntervalSinceReferenceDate
            ) ?? 0,
            demandBytes: demandBytes,
            prefetchBytes: prefetchBytes,
            prefetchBlocks: prefetchBlockCount,
            concurrency: concurrencyLimit
        )
    }

    public func cancelAll() {
        for task in inFlight.values {
            task.cancel()
        }
        for task in prefetchTasks.values {
            task.cancel()
        }
        inFlight.removeAll()
        prefetchTasks.removeAll()
    }

    private func invalidateCache() {
        cache.removeAll()
        recency.removeAll()
        cachedBytes = 0
    }

    private func refreshBlockSize() {
        guard cachesBlocks, cache.isEmpty, inFlight.isEmpty else { return }
        guard let latency = measuredLatency, latency > 0 else { return }
        let observed = probeThroughput
        let bandwidth = observed > 0 ? observed : configuration.initialThroughputBytesPerSecond
        guard bandwidth > 0 else { return }
        let upper = Double(configuration.cacheCapacityBytes) / 8
        let target = min(max(bandwidth * latency, 64 * 1_024), upper)
        let length = observedContentLength ?? Int64(target)
        effectiveBlockSize = max(1, min(Int64(target), length))
    }

    private var probeThroughput: Double {
        let now = Date().timeIntervalSinceReferenceDate
        let planned = capacityLatest ?? capacityFloor ?? measuredThroughput
            ?? probe.ratePercentile(window: 30, percentile: 0.25, now: now)
            ?? probe.recentRate(window: 5, now: now)
            ?? probe.estimate?.throughputBytesPerSecond ?? 0
        guard now - lastCapacityProbeAt > 5 else { return planned }
        guard planned > 0,
              let recent = probe.recentRate(window: 5, now: now),
              recent > 0,
              abs(recent - planned) / planned > 0.2 else {
            return planned
        }
        return recent
    }

    private var probeLatency: Double {
        measuredLatency ?? probe.estimate?.latencySeconds ?? 0.1
    }

    private func ceiling(_ value: Double) -> Int {
        let rounded = value.rounded()
        if abs(value - rounded) < 1e-6 {
            return Int(rounded)
        }
        return Int(value.rounded(.up))
    }

    private var prefetchBlockCount: Int {
        let throughput = probeThroughput
        guard throughput > 0 else {
            return min(4, configuration.maxPrefetchBlocks)
        }
        let blockSeconds = Double(effectiveBlockSize) / throughput
        let targetSeconds = max(probeLatency, blockSeconds) * configuration.prefetchTargetSeconds
        let blocks = throughput * targetSeconds / Double(effectiveBlockSize)
        let cacheBound = max(1, Int(configuration.cacheCapacityBytes) / Int(effectiveBlockSize))
        let limit = min(configuration.maxPrefetchBlocks, cacheBound)
        let floor = concurrencyLimit + 1
        return min(max(ceiling(blocks), floor), max(limit, floor))
    }

    private var concurrencyLimit: Int {
        let throughput = probeThroughput
        let latency = probeLatency
        guard throughput > 0 else {
            return min(4, configuration.maxConcurrentReads)
        }
        let blockSeconds = Double(effectiveBlockSize) / throughput
        let required = 1 + latency / max(blockSeconds, 0.001)
        return min(max(ceiling(required), 2), configuration.maxConcurrentReads)
    }

    private func blockIndex(for offset: Int64) -> Int64 {
        offset / effectiveBlockSize
    }

    private func blockRange(_ index: Int64) -> Range<Int64> {
        let start = index * effectiveBlockSize
        return start..<(start + effectiveBlockSize)
    }

    private func fetch(_ block: Int64, demand: Bool) async throws -> MediaByteRangeRead {
        if let cached = cache[block] {
            touch(block)
            return MediaByteRangeRead(
                data: cached,
                contentLength: observedContentLength,
                supportsSeeking: true
            )
        }
        if let pending = inFlight[block] {
            return try await pending.value
        }
        if demand == false, activeReads >= configuration.maxConcurrentReads {
            throw CancellationError()
        }
        let range = blockRange(block)
        activeReads += 1
        let startedAt = Date()
        let task = Task { [backendRead] in
            try await backendRead(range)
        }
        inFlight[block] = task
        defer {
            activeReads = max(0, activeReads - 1)
            inFlight[block] = nil
        }
        do {
            let read = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if let length = read.contentLength, length >= 0 {
                if let known = observedContentLength, known != length {
                    invalidateCache()
                }
                observedContentLength = length
            }
            probe.record(
                bytes: read.data.count,
                start: startedAt.timeIntervalSinceReferenceDate,
                end: Date().timeIntervalSinceReferenceDate
            )
            if demand {
                demandBytes += Int64(read.data.count)
                recordDemandDuration(Date().timeIntervalSince(startedAt))
            } else {
                prefetchBytes += Int64(read.data.count)
            }
            store(read.data, at: block)
            if demand {
                schedulePrefetch(after: block)
            }
            return read
        } catch {
            activeReads = max(0, activeReads - 1)
            inFlight[block] = nil
            probe.recordFailure()
            throw error
        }
    }

    private func store(_ data: Data, at block: Int64) {
        guard data.isEmpty == false else { return }
        cache[block] = data
        cachedBytes += data.count
        touch(block)
        while cachedBytes > configuration.cacheCapacityBytes, let oldest = recency.first {
            recency.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                cachedBytes -= evicted.count
            }
        }
    }

    private func touch(_ block: Int64) {
        if let index = recency.firstIndex(of: block) {
            recency.remove(at: index)
        }
        recency.append(block)
    }

    public func setSpeculativePrefetch(enabled: Bool) {
        speculativePrefetchEnabled = enabled
    }

    private func schedulePrefetch(after block: Int64) {
        guard speculativePrefetchEnabled, sourceCongested == false else { return }
        guard speculativePrefetchEnabled else { return }
        guard let length = observedContentLength, length > 1_048_576 else { return }
        let count = prefetchBlockCount
        guard count > 0 else { return }
        for offset in 1...count {
            let next = block + Int64(offset)
            if let length = observedContentLength, next * effectiveBlockSize >= length {
                break
            }
            if cache[next] != nil || inFlight[next] != nil || prefetchTasks[next] != nil {
                continue
            }
            prefetchTasks[next] = Task { [weak self] in
                await self?.runPrefetch(next)
            }
        }
    }

    private func runPrefetch(_ block: Int64) async {
        defer { prefetchTasks[block] = nil }
        guard cache[block] == nil, inFlight[block] == nil else { return }
        guard activeReads < configuration.maxConcurrentReads else { return }
        _ = try? await fetch(block, demand: false)
    }
}

extension Data {
    fileprivate func nonEmptySlice(from start: Int64, to end: Int64) -> Data? {
        guard start >= 0, end > start, end <= Int64(count) else { return nil }
        return self[Int(start)..<Int(end)]
    }
}
