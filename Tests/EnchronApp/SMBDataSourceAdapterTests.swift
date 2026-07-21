import Foundation
import Testing
@testable import Enchron

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

    @Test("SMB share selection keeps one host-scoped credential identity")
    func credentialIdentitySurvivesShareSelection() throws {
        let host = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20",
            username: "viewer"
        )
        let selectedShare = host.withSMBShare("Media")

        #expect(host.credentialSourceID == selectedShare.credentialSourceID)
        #expect(host.credentialSourceID == "smb:192.168.1.20:0")
        #expect(selectedShare.rootPath == "/Media")

        let dataSource = FileBrowsingDomain.DataSource(
            name: "Living Room NAS",
            sourceType: .smb,
            connectionInfo: selectedShare
        )
        let persistedRecord = String(decoding: try JSONEncoder().encode(dataSource), as: UTF8.self)
        #expect(!persistedRecord.localizedCaseInsensitiveContains("password"))
    }

    @Test("SMB playback bridge serves only the requested byte range")
    func requestedByteRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = HTTPRangeStreamingServer(source: source, filename: "feature.mp4")
        let url = try await server.start()
        defer { server.stop() }

        var request = URLRequest(url: url)
        request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 3-6/10")
        #expect(data == Data("3456".utf8))
        #expect(source.requestedRanges == [3..<7])
    }

    @Test("SMB playback bridge applies backpressure-sized source reads")
    func boundedReads() async throws {
        let source = RecordingByteRangeSource(data: Data(repeating: 0x2a, count: 11))
        let server = HTTPRangeStreamingServer(
            source: source,
            filename: "feature.mkv",
            readChunkSize: 4
        )
        let url = try await server.start()
        defer { server.stop() }

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(data.count == 11)
        #expect(source.requestedRanges == [0..<4, 4..<8, 8..<11])
    }

    @Test("playback bridge supports open-ended seek ranges")
    func openEndedRange() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = HTTPRangeStreamingServer(source: source, filename: "feature.mp4")
        let url = try await server.start()
        defer { server.stop() }

        var request = URLRequest(url: url)
        request.setValue("bytes=7-", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 7-9/10")
        #expect(data == Data("789".utf8))
        #expect(source.requestedRanges == [7..<10])
    }

    @Test("HEAD reports range capability without reading SMB bytes")
    func headDoesNotReadSource() async throws {
        let source = RecordingByteRangeSource(data: Data("0123456789".utf8))
        let server = HTTPRangeStreamingServer(source: source, filename: "feature.mp4")
        let url = try await server.start()
        defer { server.stop() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Length") == "10")
        #expect(source.requestedRanges.isEmpty)
    }

    @Test("stopping the playback bridge cancels accepted connections and in-flight reads")
    func stopCancelsInFlightRead() async throws {
        let source = CancellationAwareByteRangeSource()
        let server = HTTPRangeStreamingServer(source: source, filename: "feature.mkv")
        let url = try await server.start()
        let request = Task {
            try await URLSession.shared.data(from: url)
        }

        #expect(source.waitUntilReadStarts())
        await server.stopAndWait()
        _ = try? await request.value

        #expect(source.wasCancelled)
    }
}

private final class RecordingByteRangeSource: ByteRangeStreamingSource, @unchecked Sendable {
    let contentLength: Int64
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(data: Data) {
        self.data = data
        contentLength = Int64(data.count)
    }

    func read(in range: Range<Int64>) async throws -> Data {
        lock.withLock { ranges.append(range) }
        return data[Int(range.lowerBound)..<Int(range.upperBound)]
    }
}

private final class CancellationAwareByteRangeSource: ByteRangeStreamingSource, @unchecked Sendable {
    let contentLength: Int64 = 1_024
    private let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var cancellationObserved = false

    var wasCancelled: Bool {
        lock.withLock { cancellationObserved }
    }

    func waitUntilReadStarts() -> Bool {
        started.wait(timeout: .now() + 2) == .success
    }

    func read(in range: Range<Int64>) async throws -> Data {
        started.signal()
        do {
            try await Task.sleep(for: .seconds(30))
            return Data(repeating: 0, count: range.count)
        } catch {
            lock.withLock { cancellationObserved = true }
            throw error
        }
    }
}
