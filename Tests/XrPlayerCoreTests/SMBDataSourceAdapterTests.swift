import Foundation
import Testing
@testable import XrPlayerCore

struct SMBDataSourceAdapterTests {
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
