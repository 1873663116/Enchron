import Foundation
import MediaSource

enum EmbyMediaByteSourceError: LocalizedError, Equatable {
    case invalidRange
    case invalidResponse
    case httpStatus(Int)
    case unsatisfiableRange(totalLength: Int64?)
    case mismatchedRange
    case shortRead(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "The requested Emby byte range is invalid."
        case .invalidResponse:
            "The Emby server returned an invalid byte response."
        case .httpStatus(let status):
            "The Emby server returned HTTP status \(status) while reading video data."
        case .unsatisfiableRange:
            "The Emby server could not satisfy the requested byte range."
        case .mismatchedRange:
            "The Emby server returned a different byte range than requested."
        case .shortRead(let expected, let actual):
            "The Emby server returned \(actual) bytes when \(expected) were requested."
        }
    }
}

nonisolated final class EmbyMediaByteSource: MediaByteRangeSource, @unchecked Sendable {
    private struct ContentRange {
        let start: Int64
        let end: Int64
        let totalLength: Int64
    }

    let byteStreamAttributes: MediaByteStreamAttributes

    private let streamURL: URL
    private let accessToken: String
    let session: URLSession
    private let lock = NSLock()
    private var serverLength: Int64?

    var currentContentLength: Int64? {
        lock.withLock { serverLength }
    }

    init(
        streamURL: URL,
        accessToken: String,
        contentLength: Int64?,
        session: URLSession = MediaSourceNetwork.shared.session
    ) {
        self.streamURL = Self.authenticatedURL(streamURL, accessToken: accessToken)
        self.accessToken = accessToken
        self.session = session
        serverLength = contentLength
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: contentLength,
            supportsSeeking: true,
            isLive: false
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        guard range.lowerBound >= 0,
              range.upperBound > range.lowerBound else {
            throw MediaSourceReadFailure.invalidData
        }

        var request = URLRequest(url: streamURL)
        request.setValue(
            "bytes=\(range.lowerBound)-\(range.upperBound - 1)",
            forHTTPHeaderField: "Range"
        )
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let failure = MediaSourceReadFailure(classifying: error) {
                throw failure
            }
            throw error
        }
        guard let response = response as? HTTPURLResponse else {
            throw MediaSourceReadFailure.invalidData
        }
        if response.statusCode == 416 {
            let length = Self.unsatisfiedLength(
                response.value(forHTTPHeaderField: "Content-Range")
            )
            if let length {
                updateServerLength(length)
                return MediaByteRangeRead(
                    data: Data(),
                    contentLength: length,
                    supportsSeeking: true
                )
            }
            throw MediaSourceReadFailure.invalidData
        }
        guard response.statusCode == 206 else {
            if let failure = MediaSourceReadFailure(
                httpStatusCode: response.statusCode
            ) {
                throw failure
            }
            throw EmbyMediaByteSourceError.httpStatus(response.statusCode)
        }
        guard let contentRange = Self.contentRange(
            response.value(forHTTPHeaderField: "Content-Range")
        ) else {
            throw MediaSourceReadFailure.invalidData
        }

        updateServerLength(contentRange.totalLength)
        guard contentRange.start == range.lowerBound,
              contentRange.end == min(range.upperBound - 1, contentRange.totalLength - 1),
              contentRange.end < contentRange.totalLength else {
            throw MediaSourceReadFailure.invalidData
        }
        let expectedCount = Int(contentRange.end - contentRange.start + 1)
        guard data.count == expectedCount else {
            throw MediaSourceReadFailure.invalidData
        }
        return MediaByteRangeRead(
            data: data,
            contentLength: contentRange.totalLength,
            supportsSeeking: true
        )
    }

    private func updateServerLength(_ length: Int64) {
        lock.withLock { serverLength = length }
    }

    private static func authenticatedURL(_ url: URL, accessToken: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }
        queryItems.append(URLQueryItem(name: "api_key", value: accessToken))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private static func contentRange(
        _ value: String?
    ) -> ContentRange? {
        guard let value else { return nil }
        let fields = value.split(whereSeparator: \Character.isWhitespace)
        guard fields.count == 2,
              fields[0].caseInsensitiveCompare("bytes") == .orderedSame else {
            return nil
        }
        let rangeAndLength = fields[1].split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard rangeAndLength.count == 2,
              let totalLength = Int64(rangeAndLength[1]),
              totalLength >= 0 else {
            return nil
        }
        let bounds = rangeAndLength[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              start >= 0,
              end >= start else {
            return nil
        }
        return ContentRange(
            start: start,
            end: end,
            totalLength: totalLength
        )
    }

    private static func unsatisfiedLength(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let fields = value.split(whereSeparator: \Character.isWhitespace)
        guard fields.count == 2,
              fields[0].caseInsensitiveCompare("bytes") == .orderedSame else {
            return nil
        }
        let rangeAndLength = fields[1].split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard rangeAndLength.count == 2,
              rangeAndLength[0] == "*",
              let totalLength = Int64(rangeAndLength[1]),
              totalLength >= 0 else {
            return nil
        }
        return totalLength
    }
}
