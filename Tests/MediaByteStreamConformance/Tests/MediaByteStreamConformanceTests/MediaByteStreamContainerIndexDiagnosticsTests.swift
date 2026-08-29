import Foundation
import Testing
@testable import MediaSource

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamContainerIndexDiagnosticsTests {
    @Test("container-index diagnostics distinguish first-open writes from second-open hits")
    func distinguishesFirstAndSecondOpenRanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = ContainerIndexCache(debugRootURL: root)
        let server = MediaByteStreamServer(
            readChunkSize: 4,
            debugContainerIndexCache: cache
        )
        defer { Task { await server.stopAndWait() } }

        let revision = ContentRevision.remote(
            entityTag: "diagnostic-revision",
            sizeInBytes: 12
        )
        let expectedRevision = "sha256:\(revision.storageKey)"
        let expectedRanges = [
            ContainerIndexDebugRange(lowerBound: 0, upperBoundExclusive: 4, bytes: 4),
            ContainerIndexDebugRange(lowerBound: 4, upperBoundExclusive: 8, bytes: 4)
        ]

        let firstSource = DiagnosticByteRangeSource(payload: "0123456789ab")
        let firstHandle = try await server.register(
            source: firstSource,
            filename: "first.mkv"
        )
        firstHandle.useContainerIndex(for: revision)
        try await request("bytes=4-7", from: firstHandle.url)
        try await request("bytes=0-3", from: firstHandle.url)
        let collecting = try #require(firstHandle.debugCounters()?.containerIndexOpen)
        #expect(collecting.contentRevision == expectedRevision)
        #expect(collecting.containerIndexFinished == false)
        firstHandle.finishContainerIndex()
        let first = try #require(firstHandle.debugCounters()?.containerIndexOpen)
        firstHandle.release()

        #expect(first.scope == collecting.scope)
        #expect(first.contentRevision == expectedRevision)
        #expect(first.containerIndexFinished)
        #expect(first.cacheHitRanges.isEmpty)
        #expect(first.sourceReadRanges == expectedRanges)
        #expect(first.recordedRanges == expectedRanges)

        let secondSource = DiagnosticByteRangeSource(payload: "abcdefghijkl")
        let secondHandle = try await server.register(
            source: secondSource,
            filename: "second.mkv"
        )
        defer { secondHandle.release() }
        secondHandle.useContainerIndex(for: revision)
        try await request("bytes=4-7", from: secondHandle.url)
        try await request("bytes=0-3", from: secondHandle.url)
        secondHandle.finishContainerIndex()
        let second = try #require(secondHandle.debugCounters()?.containerIndexOpen)

        #expect(second.scope != first.scope)
        #expect(second.contentRevision == expectedRevision)
        #expect(second.containerIndexFinished)
        #expect(second.cacheHitRanges == expectedRanges)
        #expect(second.sourceReadRanges.isEmpty)
        #expect(second.recordedRanges.isEmpty)
        #expect(firstSource.requestedRanges == [4..<8, 0..<4])
        #expect(secondSource.requestedRanges.isEmpty)
        await server.stopAndWait()
    }

    private func request(_ range: String, from url: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 206)
        #expect(data.count == 4)
    }
}

private final class DiagnosticByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes

    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(payload: String) {
        data = Data(payload.utf8)
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: Int64(data.count),
            supportsSeeking: true,
            isLive: false
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        let lowerBound = min(Int(range.lowerBound), data.count)
        let upperBound = min(Int(range.upperBound), data.count)
        return MediaByteRangeRead(
            data: data[lowerBound..<upperBound],
            contentLength: Int64(data.count),
            supportsSeeking: true
        )
    }
}
#endif
