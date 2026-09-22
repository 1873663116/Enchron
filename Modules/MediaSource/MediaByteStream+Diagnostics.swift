#if DEBUG
import Foundation

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

struct MediaByteStreamContainerIndexDebugState: Sendable {
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
