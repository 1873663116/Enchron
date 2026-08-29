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
        case 408, 502, 503, 504:
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

    private weak var server: MediaByteStreamServer?
    private let token: String
    private let readFailureState: MediaSourceReadFailureState
    private let lock = NSLock()
    private var isReleased = false

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
        self.server = server
    }

    public func latestReadFailure() -> MediaSourceReadFailureObservation? {
        readFailureState.snapshot()
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

#if DEBUG
public struct ContainerIndexDebugRange: Codable, Sendable, Equatable {
    public let lowerBound: Int64
    public let upperBoundExclusive: Int64
    public let bytes: Int64

    public init(lowerBound: Int64, upperBoundExclusive: Int64, bytes: Int64) {
        self.lowerBound = lowerBound
        self.upperBoundExclusive = upperBoundExclusive
        self.bytes = bytes
    }
}

public struct ContainerIndexDebugEntry: Codable, Sendable, Equatable {
    public let contentRevision: String
    public let digest: String
    public let bytes: Int64
    public let contentLength: Int64?
    public let ranges: [ContainerIndexDebugRange]
    public let invalidFileCount: Int

    public init(
        contentRevision: String,
        digest: String,
        bytes: Int64,
        contentLength: Int64?,
        ranges: [ContainerIndexDebugRange],
        invalidFileCount: Int
    ) {
        self.contentRevision = contentRevision
        self.digest = digest
        self.bytes = bytes
        self.contentLength = contentLength
        self.ranges = ranges
        self.invalidFileCount = invalidFileCount
    }
}

public struct ContainerIndexDebugSnapshot: Codable, Sendable, Equatable {
    public static let schemaValue = "enchron.regression.container-index-state@1"

    public let schema: String
    public let cacheIdentity: String
    public let digest: String
    public let entryCount: Int
    public let entries: [ContainerIndexDebugEntry]
    public let totalBytes: Int64

    public init(
        cacheIdentity: String,
        digest: String,
        entries: [ContainerIndexDebugEntry]
    ) {
        self.schema = Self.schemaValue
        self.cacheIdentity = cacheIdentity
        self.digest = digest
        self.entryCount = entries.count
        self.entries = entries
        self.totalBytes = entries.reduce(0) { $0 + $1.bytes }
    }
}

public struct MediaByteStreamContainerIndexDebugSnapshot: Codable, Sendable, Equatable {
    public static let schemaValue =
        "enchron.regression.media-byte-stream-container-index-open@1"

    public let schema: String
    public let scope: String
    public let contentRevision: String
    public let containerIndexFinished: Bool
    public let cacheHitRanges: [ContainerIndexDebugRange]
    public let sourceReadRanges: [ContainerIndexDebugRange]
    public let recordedRanges: [ContainerIndexDebugRange]

    public init(
        scope: String,
        contentRevision: String,
        containerIndexFinished: Bool,
        cacheHitRanges: [ContainerIndexDebugRange],
        sourceReadRanges: [ContainerIndexDebugRange],
        recordedRanges: [ContainerIndexDebugRange]
    ) {
        self.schema = Self.schemaValue
        self.scope = scope
        self.contentRevision = contentRevision
        self.containerIndexFinished = containerIndexFinished
        self.cacheHitRanges = Self.sorted(cacheHitRanges)
        self.sourceReadRanges = Self.sorted(sourceReadRanges)
        self.recordedRanges = Self.sorted(recordedRanges)
    }

    private static func sorted(
        _ ranges: [ContainerIndexDebugRange]
    ) -> [ContainerIndexDebugRange] {
        ranges.sorted {
            ($0.lowerBound, $0.upperBoundExclusive, $0.bytes)
                < ($1.lowerBound, $1.upperBoundExclusive, $1.bytes)
        }
    }
}

private struct MediaByteStreamContainerIndexDebugState: Sendable {
    let scope: String
    var contentRevision: String?
    var containerIndexFinished = false
    var cacheHitRanges: [ContainerIndexDebugRange] = []
    var sourceReadRanges: [ContainerIndexDebugRange] = []
    var recordedRanges: [ContainerIndexDebugRange] = []

    mutating func configure(revision: ContentRevision?) {
        contentRevision = revision.map { "sha256:\($0.storageKey)" }
        containerIndexFinished = false
        cacheHitRanges.removeAll(keepingCapacity: true)
        sourceReadRanges.removeAll(keepingCapacity: true)
        recordedRanges.removeAll(keepingCapacity: true)
    }

    mutating func recordCacheHit(offset: Int64, byteCount: Int) {
        if let range = Self.range(offset: offset, byteCount: byteCount) {
            cacheHitRanges.append(range)
        }
    }

    mutating func recordSourceRead(offset: Int64, byteCount: Int) {
        if let range = Self.range(offset: offset, byteCount: byteCount) {
            sourceReadRanges.append(range)
        }
    }

    mutating func recordIndexWrite(offset: Int64, byteCount: Int) {
        if let range = Self.range(offset: offset, byteCount: byteCount) {
            recordedRanges.append(range)
        }
    }

    func snapshot() -> MediaByteStreamContainerIndexDebugSnapshot? {
        guard let contentRevision else { return nil }
        return MediaByteStreamContainerIndexDebugSnapshot(
            scope: scope,
            contentRevision: contentRevision,
            containerIndexFinished: containerIndexFinished,
            cacheHitRanges: cacheHitRanges,
            sourceReadRanges: sourceReadRanges,
            recordedRanges: recordedRanges
        )
    }

    private static func range(
        offset: Int64,
        byteCount: Int
    ) -> ContainerIndexDebugRange? {
        guard offset >= 0, byteCount > 0 else { return nil }
        let bytes = Int64(byteCount)
        let upperBound = offset.addingReportingOverflow(bytes)
        guard upperBound.overflow == false else { return nil }
        return ContainerIndexDebugRange(
            lowerBound: offset,
            upperBoundExclusive: upperBound.partialValue,
            bytes: bytes
        )
    }
}
#endif

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
        let readFailureState = MediaSourceReadFailureState()
        let lock = NSLock()
        var indexSession: ContainerIndexSession?
        var authoritativeContentLength: Int64?
        #if DEBUG
            var containerIndexDebugState: MediaByteStreamContainerIndexDebugState
        #endif

        init(source: any MediaByteRangeSource, filename: String, token: String) {
            self.source = source
            self.filename = filename
            #if DEBUG
                containerIndexDebugState = MediaByteStreamContainerIndexDebugState(
                    scope: "media-byte-stream:\(token.lowercased())"
                )
            #endif
        }
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

    public static let shared = MediaByteStreamServer()

    private let readChunkSize: Int64
    private let containerIndexCache: ContainerIndexCache
    private let queue = DispatchQueue(label: "app.enchron.media-byte-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startupWaiters: [CheckedContinuation<NWEndpoint.Port, any Error>] = []
    private var registrations: [String: Registration] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var transferTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var statistics = Statistics()
    #if DEBUG
        private let debugCounterState = OSAllocatedUnfairLock(
            uncheckedState: MediaByteStreamDebugCounterState()
        )
    #endif

    public init(readChunkSize: Int64 = 1_048_576) {
        self.readChunkSize = max(1, readChunkSize)
        self.containerIndexCache = .shared
    }

    #if DEBUG
        init(
            readChunkSize: Int64 = 1_048_576,
            debugContainerIndexCache: ContainerIndexCache
        ) {
            self.readChunkSize = max(1, readChunkSize)
            self.containerIndexCache = debugContainerIndexCache
        }
    #endif

    public func register(
        source: any MediaByteRangeSource,
        filename: String,
        preferredBufferDepth: MediaByteBufferDepth = .none
    ) async throws -> MediaByteStreamHandle {
        let port = try await ensureStarted()
        let token = UUID().uuidString
        let registration = Registration(source: source, filename: filename, token: token)
        lock.withLock { registrations[token] = registration }
        let escapedName = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "media"
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/\(escapedName)") else {
            unregister(token: token)
            throw ServerError.listenerFailed("Invalid loopback URL.")
        }
        return MediaByteStreamHandle(
            url: url,
            preferredBufferDepth: preferredBufferDepth,
            token: token,
            readFailureState: registration.readFailureState,
            server: self
        )
    }

    public func snapshot() -> Statistics {
        lock.withLock { statistics }
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
        #if DEBUG
            debugCounterState.withLock { counters in
                counters.acceptedConnectionCount &+= 1
            }
        #endif
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
        guard method == "GET" || method == "HEAD",
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
            initialRange = requestedRange.prefix(upToCount: readChunkSize)
        } else {
            guard let discoveryRange = request.discoveryRange(
                chunkSize: readChunkSize,
                lengthHint: attributes.contentLength
            ) else {
                sendRangeNotSatisfiable(length: nil, on: connection)
                return
            }
            initialRange = discoveryRange
        }

        let first: MediaByteRangeRead
        do {
            first = try await read(initialRange, registration: registration)
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
                statistics.largestRequest = max(statistics.largestRequest, responseLength)
            }
            #if DEBUG
                debugCounterState.withLock { counters in
                    counters.requestCount &+= 1
                }
            #endif
            var response = "HTTP/1.1 \(request.isPartial ? "206 Partial Content" : "200 OK")\r\n"
            response += "Accept-Ranges: bytes\r\nContent-Type: application/octet-stream\r\n"
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
            }
            while offset < requestedRange.upperBound {
                let end = min(offset + readChunkSize, requestedRange.upperBound)
                let result = try await read(offset..<end, registration: registration)
                guard result.data.isEmpty == false,
                      result.supportsSeeking,
                      result.contentLength == nil || result.contentLength == actualLength else {
                    connection.cancel()
                    return
                }
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
            result = try await registration.source.read(in: range)
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
                let result = try await read(
                    offset..<(offset + readChunkSize),
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
