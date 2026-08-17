import Foundation
import MediaSource
import Testing
@testable import MediaLibrary

@Suite(.serialized)
struct SMBDataSourceAdapterTests {
    @Test("SMB paths remove only the connected share prefix")
    func shareRelativePaths() {
        #expect(
            SMBDataSourceAdapter.shareRelativePath(
                for: "/Media/Movies/Feature.mkv",
                rootPath: "/Media/Movies"
            ) == "/Movies/Feature.mkv"
        )
        #expect(
            SMBDataSourceAdapter.shareRelativePath(
                for: "/Media",
                rootPath: "/Media"
            ) == "/"
        )
        #expect(
            SMBDataSourceAdapter.shareRelativePath(
                for: "Other/Feature.mkv/",
                rootPath: "/Media"
            ) == "/Other/Feature.mkv"
        )
        #expect(SMBDataSourceAdapter.childPath(named: "Season 1", in: "/Media/") == "/Media/Season 1")
    }

    @Test("SMB credentials are scoped to one server and account")
    func credentialIdentityUsesServerAndAccount() throws {
        let host = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20",
            username: "viewer"
        )
        #expect(host.credentialSourceID == "smb:192.168.1.20:0:viewer")
        #expect(host.rootPath == "/")

        let otherAccount = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20",
            username: "other-viewer"
        )
        #expect(host.credentialSourceID != otherAccount.credentialSourceID)

        let dataSource = FileBrowsingDomain.DataSource(
            name: "Living Room NAS",
            sourceType: .smb,
            connectionInfo: host
        )
        let persistedRecord = String(decoding: try JSONEncoder().encode(dataSource), as: UTF8.self)
        #expect(!persistedRecord.localizedCaseInsensitiveContains("password"))
    }

    @Test("SMB accepts a server host name and treats its shares as root folders")
    func serverRootAddressAndSharePaths() throws {
        let server = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "smb://nas.local:445",
            username: "viewer"
        )
        #expect(server.host == "nas.local")
        #expect(server.port == 445)
        #expect(server.rootPath == "/")
        #expect(
            SMBDataSourceAdapter.shareAndRelativePath(
                for: "/Media/Movies/Feature.mkv"
            )?.share == "Media"
        )
        #expect(
            SMBDataSourceAdapter.shareAndRelativePath(
                for: "/Media/Movies/Feature.mkv"
            )?.relativePath == "/Movies/Feature.mkv"
        )
    }

    @Test("SMB playback bridge serves only the requested byte range")
    func requestedByteRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer()
        let handle = try await server.register(source: source, filename: "feature.mp4")
        let url = handle.url
        defer { handle.release() }

        var request = URLRequest(url: url)
        request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 3-6/10")
        #expect(data == Data("3456".utf8))

        var suffixRequest = URLRequest(url: handle.url)
        suffixRequest.setValue("bytes=-2", forHTTPHeaderField: "Range")
        let (suffixData, suffixResponse) = try await URLSession.shared.data(for: suffixRequest)
        let suffixHTTPResponse = try #require(suffixResponse as? HTTPURLResponse)

        #expect(suffixHTTPResponse.statusCode == 206)
        #expect(suffixHTTPResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 8-9/10")
        #expect(suffixData == Data("89".utf8))
        #expect(source.requestedRanges == [3..<7, 8..<10])
    }

    @Test("SMB playback bridge applies backpressure-sized source reads")
    func boundedReads() async throws {
        let source = RecordingByteRangeSource(data: Data(repeating: 0x2a, count: 11))
        let server = MediaByteStreamServer(readChunkSize: 4)
        let handle = try await server.register(source: source, filename: "feature.mkv")
        let url = handle.url
        defer { handle.release() }

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(data.count == 11)
        #expect(source.requestedRanges == [0..<4, 4..<8, 8..<11])
    }

    @Test("playback bridge supports open-ended seek ranges")
    func openEndedRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer()
        let handle = try await server.register(source: source, filename: "feature.mp4")
        let url = handle.url
        defer { handle.release() }

        var request = URLRequest(url: url)
        request.setValue("bytes=7-", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 7-9/10")
        #expect(data == Data("789".utf8))
        #expect(source.requestedRanges == [7..<10])
    }

    @Test("HEAD does not publish a directory length before reading source bytes")
    func headDoesNotReadSource() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer()
        let handle = try await server.register(source: source, filename: "feature.mp4")
        let url = handle.url
        defer { handle.release() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == nil)
        #expect(source.requestedRanges.isEmpty)
    }

    @Test("successive requests reuse one loopback connection")
    func successiveRequestsReuseConnection() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer()
        let handle = try await server.register(source: source, filename: "feature.mp4")
        let session = URLSession(configuration: .ephemeral)
        defer {
            session.invalidateAndCancel()
            handle.release()
        }

        for bounds in ["bytes=0-1", "bytes=2-3"] {
            var request = URLRequest(url: handle.url)
            request.setValue(bounds, forHTTPHeaderField: "Range")
            let (_, response) = try await session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 206)
        }

        let statistics = server.snapshot()
        #expect(statistics.requestCount == 2)
        #expect(statistics.acceptedConnectionCount == 1)
    }

    @Test("unknown source length uses chunked transfer and disables seeking")
    func unknownLengthUsesChunkedTransfer() async throws {
        let source = UnknownLengthByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer(readChunkSize: 4)
        let handle = try await server.register(source: source, filename: "live.mkv")
        defer { handle.release() }

        let (data, response) = try await URLSession.shared.data(from: handle.url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "none")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == nil)
        #expect(data == Data("0123456789".utf8))
        #expect(source.requestedRanges == [0..<4, 4..<8, 8..<12, 10..<14])
    }

    @Test("a seekable source can discover its length from the first range read")
    func seekableSourceDiscoversLength() async throws {
        let source = UnknownLengthSeekableByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer(readChunkSize: 4)
        let handle = try await server.register(source: source, filename: "feature.mkv")
        defer { handle.release() }

        var request = URLRequest(url: handle.url)
        request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 3-6/10")
        #expect(data == Data("3456".utf8))
        #expect(source.requestedRanges == [3..<7])
    }

    @Test("a zero-based range can fall back to a non-seekable source")
    func zeroBasedRangeFallsBackToSequentialTransfer() async throws {
        let source = UnknownLengthByteRangeSource(data: Data("0123456789".utf8))
        let server = MediaByteStreamServer(readChunkSize: 4)
        let handle = try await server.register(source: source, filename: "live.mkv")
        defer { handle.release() }

        var request = URLRequest(url: handle.url)
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "none")
        #expect(data == Data("0123456789".utf8))
    }

    @Test("container index cache reuses bytes for the same content revision")
    func containerIndexCacheReusesRevisionBytes() async throws {
        let revision = ContentRevision.remote(
            entityTag: UUID().uuidString,
            sizeInBytes: 10
        )
        let firstSource = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let firstServer = MediaByteStreamServer(readChunkSize: 4)
        let firstHandle = try await firstServer.register(source: firstSource, filename: "feature.mkv")
        firstHandle.useContainerIndex(for: revision)

        var firstRequest = URLRequest(url: firstHandle.url)
        firstRequest.setValue("bytes=0-3", forHTTPHeaderField: "Range")
        let (firstData, _) = try await URLSession.shared.data(for: firstRequest)
        firstHandle.finishContainerIndex()
        firstHandle.release()

        let secondSource = RecordingByteRangeSource(data: Data("abcdefghij".utf8))
        let secondServer = MediaByteStreamServer(readChunkSize: 4)
        let secondHandle = try await secondServer.register(source: secondSource, filename: "feature.mkv")
        defer { secondHandle.release() }
        secondHandle.useContainerIndex(for: revision)

        var secondRequest = URLRequest(url: secondHandle.url)
        secondRequest.setValue("bytes=0-3", forHTTPHeaderField: "Range")
        let (secondData, _) = try await URLSession.shared.data(for: secondRequest)

        #expect(firstData == Data("0123".utf8))
        #expect(secondData == firstData)
        #expect(firstSource.requestedRanges == [0..<4])
        #expect(secondSource.requestedRanges.isEmpty)
    }

    @Test("stopping the playback bridge cancels accepted connections and in-flight reads")
    func stopCancelsInFlightRead() async throws {
        let source = CancellationAwareByteRangeSource()
        let server = MediaByteStreamServer()
        let handle = try await server.register(source: source, filename: "feature.mkv")
        let url = handle.url
        let request = Task {
            try await URLSession.shared.data(from: url)
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while source.hasStarted == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(source.hasStarted)
        await server.stopAndWait()
        _ = try? await request.value

        #expect(source.wasCancelled)
    }
}

private final class RecordingByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(data: Data) {
        self.data = data
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: Int64(data.count),
            supportsSeeking: true,
            isLive: false,
            preferredBufferDepth: .automatic
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        let lower = min(Int(range.lowerBound), data.count)
        let upper = min(Int(range.upperBound), data.count)
        return MediaByteRangeRead(
            data: data[lower..<upper],
            contentLength: Int64(data.count),
            supportsSeeking: true
        )
    }
}

private final class UnknownLengthByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: nil,
        supportsSeeking: false,
        isLive: true,
        preferredBufferDepth: .none
    )
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(data: Data) {
        self.data = data
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        let lower = min(Int(range.lowerBound), data.count)
        let upper = min(Int(range.upperBound), data.count)
        return MediaByteRangeRead(
            data: data[lower..<upper],
            contentLength: nil,
            supportsSeeking: false
        )
    }
}

private final class UnknownLengthSeekableByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: nil,
        supportsSeeking: true,
        isLive: false,
        preferredBufferDepth: .automatic
    )
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(data: Data) {
        self.data = data
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        let lower = min(Int(range.lowerBound), data.count)
        let upper = min(Int(range.upperBound), data.count)
        return MediaByteRangeRead(
            data: data[lower..<upper],
            contentLength: Int64(data.count),
            supportsSeeking: true
        )
    }
}

private final class CancellationAwareByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: 1_024,
        supportsSeeking: true,
        isLive: false,
        preferredBufferDepth: .automatic
    )
    private let lock = NSLock()
    private var readStarted = false
    private var cancellationObserved = false

    var hasStarted: Bool {
        lock.withLock { readStarted }
    }

    var wasCancelled: Bool {
        lock.withLock { cancellationObserved }
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { readStarted = true }
        do {
            try await Task.sleep(for: .seconds(30))
            return MediaByteRangeRead(
                data: Data(repeating: 0, count: range.count),
                contentLength: 1_024,
                supportsSeeking: true
            )
        } catch {
            lock.withLock { cancellationObserved = true }
            throw error
        }
    }
}
