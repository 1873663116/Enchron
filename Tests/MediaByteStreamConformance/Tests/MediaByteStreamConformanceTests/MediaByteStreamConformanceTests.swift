import Foundation
import MediaSource
import Testing

/// The executable media byte-range contract.
///
/// `MediaByteStreamAttributes.contentLength` is a pre-open hint. Directory metadata,
/// including zero and stale sizes, cannot decide whether an HTTP range is satisfiable.
/// Only `MediaByteRangeRead.contentLength`, returned by the byte source itself, can
/// establish the representation length and its end. The server must apply that answer
/// before it emits a status, `Content-Range`, `Content-Length`, or body byte.
///
/// Every request shape runs against every source shape through the public loopback HTTP
/// endpoint. Named regressions retain the three historical failure shapes: a false zero
/// length, an open range stopped at the first response body, and a source that pads reads
/// past the representation end. A truncated range is also retained as a permanent bad
/// upstream sample.
@Suite(.serialized)
struct MediaByteStreamConformanceTests {
    @Test(
        "request and source shapes satisfy the byte-range contract",
        arguments: RequestShape.allCases,
        SourceShape.allCases
    )
    func requestSourceMatrix(request: RequestShape, source: SourceShape) async throws {
        let scriptedSource = ScriptedByteRangeSource(shape: source)
        let response = try await observe(
            source: scriptedSource,
            request: request,
            readChunkSize: 3
        )
        let expected = ExpectedHTTPResponse.for(request: request, source: source)

        #expect(response.statusCode == expected.statusCode)
        #expect(response.contentRange == expected.contentRange)
        #expect(response.contentLength == expected.contentLength)
        #expect(response.body == expected.body)
    }

    @Test("zero directory length cannot reject a nonzero range")
    func zeroLengthHintRemainsNonAuthoritative() async throws {
        let source = ScriptedByteRangeSource(shape: .zeroLengthHint)
        let response = try await observe(source: source, request: .openEnded, readChunkSize: 3)

        #expect(response.statusCode == 206)
        #expect(response.contentRange == "bytes 4-9/10")
        #expect(response.body == Data("456789".utf8))
        #expect(source.requestedRanges.first?.lowerBound == 4)
    }

    @Test("open range continues after the first bounded source response")
    func openRangeDoesNotStopAtFirstResponseBody() async throws {
        let source = ScriptedByteRangeSource(
            shape: .unknownLengthSeekable,
            behavior: .limitEveryRead(to: 2)
        )
        let response = try await observe(source: source, request: .openEnded, readChunkSize: 4)

        #expect(response.statusCode == 206)
        #expect(response.contentRange == "bytes 4-9/10")
        #expect(response.body == Data("456789".utf8))
        #expect(source.requestedRanges.count >= 3)
        #expect(source.requestedRanges.allSatisfy { $0.upperBound - $0.lowerBound <= 4 })
    }

    @Test("padded out-of-bounds bytes cannot make a range satisfiable")
    func paddedOutOfBoundsReadIsRejected() async throws {
        let source = ScriptedByteRangeSource(
            shape: .largeLengthHint,
            behavior: .padPastEnd(with: 0)
        )
        let response = try await observe(source: source, request: .startsAtLength, readChunkSize: 4)

        #expect(source.requestedRanges == [10..<14])
        #expect(response.statusCode == 416)
        #expect(response.contentRange == "bytes */10")
        #expect(response.body.isEmpty)
    }

    @Test("a source truncation cannot become a successful short response")
    func truncatedRangeFailsTheTransfer() async throws {
        let source = ScriptedByteRangeSource(
            shape: .unknownLengthSeekable,
            behavior: .truncateAndFail(at: 6)
        )

        do {
            _ = try await observe(source: source, request: .closed, readChunkSize: 3)
            Issue.record("the server completed a response after the source truncated its range")
        } catch {
            #expect(source.requestedRanges == [2..<5, 5..<7, 6..<7])
        }
    }

    @Test("HEAD publishes only a length learned from a source response")
    func headUsesOnlyPreviouslyObservedSourceLength() async throws {
        let source = ScriptedByteRangeSource(shape: .largeLengthHint)
        let server = MediaByteStreamServer(readChunkSize: 3)
        let handle = try await server.register(source: source, filename: "contract.bin")
        defer { handle.release() }

        do {
            let firstHead = try await send(request: .head, to: handle.url)
            #expect(firstHead.statusCode == 200)
            #expect(firstHead.contentLength == nil)
            #expect(source.requestedRanges.isEmpty)

            let range = try await send(request: .range("bytes=2-5"), to: handle.url)
            #expect(range.contentRange == "bytes 2-5/10")

            let learnedHead = try await send(request: .head, to: handle.url)
            #expect(learnedHead.statusCode == 200)
            #expect(learnedHead.contentLength == 10)
            await server.stopAndWait()
        } catch {
            await server.stopAndWait()
            throw error
        }
    }

    @Test(
        "registration preserves every demux buffer declaration",
        arguments: [
            MediaByteBufferDepth.none,
            MediaByteBufferDepth.automatic,
            MediaByteBufferDepth.bytes(64 * 1_024)
        ]
    )
    func registrationPreservesBufferDepth(_ depth: MediaByteBufferDepth) async throws {
        let source = BufferDepthByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let handle = try await server.register(
            source: source,
            filename: "policy.bin",
            preferredBufferDepth: depth
        )
        defer { handle.release() }

        #expect(handle.preferredBufferDepth == depth)
        await server.stopAndWait()
    }
}

private final class BufferDepthByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes

    init() {
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: 1,
            supportsSeeking: true,
            isLive: false
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        MediaByteRangeRead(
            data: range.lowerBound == 0 ? Data([0]) : Data(),
            contentLength: 1,
            supportsSeeking: true
        )
    }
}

enum RequestShape: String, CaseIterable, Sendable, CustomStringConvertible {
    case noRange
    case closed
    case openEnded
    case zeroBasedOpenEnded
    case suffix
    case lastByte
    case endPastLength
    case startsAtLength
    case beyondLength
    case multipleRanges

    var description: String { rawValue }

    fileprivate var request: HTTPRequestShape {
        switch self {
        case .noRange: .get
        case .closed: .range("bytes=2-6")
        case .openEnded: .range("bytes=4-")
        case .zeroBasedOpenEnded: .range("bytes=0-")
        case .suffix: .range("bytes=-3")
        case .lastByte: .range("bytes=9-9")
        case .endPastLength: .range("bytes=8-14")
        case .startsAtLength: .range("bytes=10-")
        case .beyondLength: .range("bytes=12-14")
        case .multipleRanges: .range("bytes=0-1,4-5")
        }
    }
}

enum SourceShape: String, CaseIterable, Sendable, CustomStringConvertible {
    case knownLength
    case unknownLengthSeekable
    case zeroLengthHint
    case smallLengthHint
    case largeLengthHint
    case sequential

    var description: String { rawValue }

    var attributes: MediaByteStreamAttributes {
        let hintedLength: Int64? = switch self {
        case .knownLength: 10
        case .unknownLengthSeekable, .sequential: nil
        case .zeroLengthHint: 0
        case .smallLengthHint: 6
        case .largeLengthHint: 14
        }
        return MediaByteStreamAttributes(
            contentLength: hintedLength,
            supportsSeeking: self != .sequential,
            isLive: self == .sequential
        )
    }
}

private struct ExpectedHTTPResponse: Sendable {
    let statusCode: Int
    let contentRange: String?
    let contentLength: Int?
    let body: Data

    static func `for`(request: RequestShape, source: SourceShape) -> Self {
        if source == .sequential {
            switch request {
            case .noRange, .zeroBasedOpenEnded:
                return Self(
                    statusCode: 200,
                    contentRange: nil,
                    contentLength: nil,
                    body: "0123456789"
                )
            default:
                return Self(statusCode: 416, contentRange: nil, body: "")
            }
        }
        switch request {
        case .noRange:
            return Self(statusCode: 200, contentRange: nil, body: "0123456789")
        case .closed:
            return Self(statusCode: 206, contentRange: "bytes 2-6/10", body: "23456")
        case .openEnded:
            return Self(statusCode: 206, contentRange: "bytes 4-9/10", body: "456789")
        case .zeroBasedOpenEnded:
            return Self(statusCode: 206, contentRange: "bytes 0-9/10", body: "0123456789")
        case .suffix:
            return Self(statusCode: 206, contentRange: "bytes 7-9/10", body: "789")
        case .lastByte:
            return Self(statusCode: 206, contentRange: "bytes 9-9/10", body: "9")
        case .endPastLength:
            return Self(statusCode: 206, contentRange: "bytes 8-9/10", body: "89")
        case .startsAtLength, .beyondLength:
            return Self(statusCode: 416, contentRange: "bytes */10", body: "")
        case .multipleRanges:
            return Self(statusCode: 416, contentRange: nil, body: "")
        }
    }

    private init(statusCode: Int, contentRange: String?, body: String) {
        self.init(
            statusCode: statusCode,
            contentRange: contentRange,
            contentLength: body.utf8.count,
            body: body
        )
    }

    private init(
        statusCode: Int,
        contentRange: String?,
        contentLength: Int?,
        body: String
    ) {
        self.statusCode = statusCode
        self.contentRange = contentRange
        self.contentLength = contentLength
        self.body = Data(body.utf8)
    }
}

private enum ScriptedSourceBehavior: Sendable {
    case normal
    case limitEveryRead(to: Int)
    case padPastEnd(with: UInt8)
    case truncateAndFail(at: Int64)
}

private enum ScriptedSourceError: Error {
    case upstreamTruncated
}

private final class ScriptedByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes

    private let payload = Data("0123456789".utf8)
    private let shape: SourceShape
    private let behavior: ScriptedSourceBehavior
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    var requestedRanges: [Range<Int64>] {
        lock.withLock { ranges }
    }

    init(shape: SourceShape, behavior: ScriptedSourceBehavior = .normal) {
        self.shape = shape
        self.behavior = behavior
        byteStreamAttributes = shape.attributes
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        if case .truncateAndFail(let breakpoint) = behavior,
           range.lowerBound >= breakpoint {
            throw ScriptedSourceError.upstreamTruncated
        }

        let actualUpperBound = Int64(payload.count)
        let readableUpperBound: Int64 = if case .truncateAndFail(let breakpoint) = behavior {
            min(actualUpperBound, breakpoint)
        } else {
            actualUpperBound
        }
        let lower = min(max(0, range.lowerBound), readableUpperBound)
        var upper = min(max(lower, range.upperBound), readableUpperBound)
        if case .limitEveryRead(let limit) = behavior {
            upper = min(upper, lower + Int64(limit))
        }
        var data = Data(payload[Int(lower)..<Int(upper)])
        if case .padPastEnd(let byte) = behavior, data.count < range.count {
            data.append(Data(repeating: byte, count: range.count - data.count))
        }

        return MediaByteRangeRead(
            data: data,
            contentLength: shape == .sequential ? nil : actualUpperBound,
            supportsSeeking: shape != .sequential
        )
    }
}

private struct HTTPObservation: Sendable {
    let statusCode: Int
    let contentRange: String?
    let contentLength: Int?
    let body: Data
}

private enum HTTPRequestShape: Sendable {
    case get
    case head
    case range(String)
}

private func observe(
    source: ScriptedByteRangeSource,
    request: RequestShape,
    readChunkSize: Int64
) async throws -> HTTPObservation {
    let server = MediaByteStreamServer(readChunkSize: readChunkSize)
    let handle = try await server.register(source: source, filename: "contract.bin")
    defer { handle.release() }
    do {
        let response = try await send(request: request.request, to: handle.url)
        await server.stopAndWait()
        return response
    } catch {
        await server.stopAndWait()
        throw error
    }
}

private func send(request shape: HTTPRequestShape, to url: URL) async throws -> HTTPObservation {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3
    configuration.timeoutIntervalForResource = 3
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    switch shape {
    case .get:
        break
    case .head:
        request.httpMethod = "HEAD"
    case .range(let value):
        request.setValue(value, forHTTPHeaderField: "Range")
    }
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    return HTTPObservation(
        statusCode: http.statusCode,
        contentRange: http.value(forHTTPHeaderField: "Content-Range"),
        contentLength: http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
        body: body
    )
}
