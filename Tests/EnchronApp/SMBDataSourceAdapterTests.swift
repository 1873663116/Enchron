import Foundation
import MediaSource
import Testing
@testable import MediaLibrary
@testable import Enchron

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

    @Test("Media byte stream serves only the requested byte range")
    func requestedByteRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mp4"
        )
        let lease = try #require(resolvedSource.accessLease)
        defer { lease.release() }

        var request = URLRequest(url: resolvedSource.url)
        request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 3-6/10")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == "4")
        #expect(data == Data("3456".utf8))
        #expect(source.requestedRanges == [3..<7])
    }

    @Test("Media byte stream applies the source's suggested buffer depth")
    func boundedReads() async throws {
        let source = RecordingByteRangeSource(
            data: Data(repeating: 0x2a, count: 11),
            suggestedBufferDepth: .bytes(4)
        )
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mkv"
        )
        let lease = try #require(resolvedSource.accessLease)
        defer { lease.release() }

        let (data, response) = try await URLSession.shared.data(from: resolvedSource.url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(data.count == 11)
        #expect(source.requestedRanges == [0..<4, 4..<8, 8..<11])
    }

    @Test("Media byte stream supports open-ended seek ranges")
    func openEndedRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mp4"
        )
        let lease = try #require(resolvedSource.accessLease)
        defer { lease.release() }

        var request = URLRequest(url: resolvedSource.url)
        request.setValue("bytes=7-", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 7-9/10")
        #expect(data == Data("789".utf8))
        #expect(source.requestedRanges == [7..<10])
    }

    @Test("Media byte stream supports suffix ranges")
    func suffixRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mp4"
        )
        let lease = try #require(resolvedSource.accessLease)
        defer { lease.release() }

        var request = URLRequest(url: resolvedSource.url)
        request.setValue("bytes=-3", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 7-9/10")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == "3")
        #expect(data == Data("789".utf8))
        #expect(source.requestedRanges == [7..<10])
    }

    @Test("HEAD reports range capability without reading source bytes")
    func headDoesNotReadSource() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mp4"
        )
        let lease = try #require(resolvedSource.accessLease)
        defer { lease.release() }

        var request = URLRequest(url: resolvedSource.url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == "10")
        #expect(source.requestedRanges.isEmpty)
    }

    @Test("Releasing a byte stream route cancels its in-flight reads")
    func stopCancelsInFlightRead() async throws {
        let source = CancellationAwareByteRangeSource()
        let resolvedSource = try await MediaByteStreamEndpoint.shared.resolve(
            source,
            filename: "feature.mkv"
        )
        let lease = try #require(resolvedSource.accessLease)
        let request = Task {
            try await URLSession.shared.data(from: resolvedSource.url)
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while source.hasStarted == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(source.hasStarted)
        lease.release()

        while source.wasCancelled == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try? await request.value

        #expect(source.wasCancelled)
    }

    @Test("Media byte stream endpoint is shared across sources")
    func sharedEndpoint() async throws {
        #expect(MediaByteStreamEndpoint.shared === MediaByteStreamEndpoint.shared)

        let first = try await MediaByteStreamEndpoint.shared.resolve(
            RecordingByteRangeSource(data: Data("first".utf8)),
            filename: "first.mp4"
        )
        let second = try await MediaByteStreamEndpoint.shared.resolve(
            RecordingByteRangeSource(data: Data("second".utf8)),
            filename: "second.mkv"
        )
        let firstLease = try #require(first.accessLease)
        let secondLease = try #require(second.accessLease)
        defer {
            firstLease.release()
            secondLease.release()
        }

        #expect(first.url.port != nil)
        #expect(first.url.port == second.url.port)
    }
}

private final class RecordingByteRangeSource: MediaByteSource, @unchecked Sendable {
    let totalLength: Int64?
    let seekability = MediaByteSourceSeekability.randomAccess
    let liveness = MediaByteSourceLiveness.finite
    let suggestedBufferDepth: MediaByteBufferDepth
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(
        data: Data,
        suggestedBufferDepth: MediaByteBufferDepth = .bytes(1_024 * 1_024)
    ) {
        self.data = data
        totalLength = Int64(data.count)
        self.suggestedBufferDepth = suggestedBufferDepth
    }

    func read(in range: Range<Int64>) async throws -> Data {
        lock.withLock { ranges.append(range) }
        return data[Int(range.lowerBound)..<Int(range.upperBound)]
    }
}

private final class CancellationAwareByteRangeSource: MediaByteSource, @unchecked Sendable {
    let totalLength: Int64? = 1_024
    let seekability = MediaByteSourceSeekability.randomAccess
    let liveness = MediaByteSourceLiveness.finite
    let suggestedBufferDepth = MediaByteBufferDepth.bytes(1_024 * 1_024)
    private let lock = NSLock()
    private var readStarted = false
    private var cancellationObserved = false

    var hasStarted: Bool {
        lock.withLock { readStarted }
    }

    var wasCancelled: Bool {
        lock.withLock { cancellationObserved }
    }

    func read(in range: Range<Int64>) async throws -> Data {
        lock.withLock { readStarted = true }
        do {
            try await Task.sleep(for: .seconds(30))
            return Data(repeating: 0, count: range.count)
        } catch {
            lock.withLock { cancellationObserved = true }
            throw error
        }
    }
}
