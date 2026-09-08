import Foundation
import MediaSource
import Testing

@Suite(.serialized)
struct MediaByteStreamReleaseTests {
    @Test("releasing the handle cancels a read the source has not answered")
    func releasingTheHandleCancelsAnUnansweredRead() async throws {
        let source = HangingByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 1_048_576)
        let handle = try await server.register(source: source, filename: "hang.bin")
        let client = Task { try await fetch(handle.url) }
        #expect(await source.waitForReadStart(timeout: .seconds(3)))
        handle.release()
        let outcome = await source.waitForOutcome(timeout: .seconds(2))
        #expect(outcome == .cancelled, "the source read outlived the released handle: \(String(describing: outcome))")
        client.cancel()
        _ = try? await client.value
        await server.stopAndWait()
    }
}

private enum HangingReadOutcome: Equatable {
    case cancelled
    case completed
}

private final class HangingByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: 4_194_304,
        supportsSeeking: true,
        isLive: false
    )

    private let lock = NSLock()
    private var readStarted = false
    private var outcome: HangingReadOutcome?

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { readStarted = true }
        do {
            try await Task.sleep(for: .seconds(30))
            lock.withLock { outcome = .completed }
        } catch {
            lock.withLock { outcome = .cancelled }
            throw error
        }
        return MediaByteRangeRead(
            data: Data(count: range.count),
            contentLength: byteStreamAttributes.contentLength,
            supportsSeeking: true
        )
    }

    func waitForReadStart(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if lock.withLock({ readStarted }) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func waitForOutcome(timeout: Duration) async -> HangingReadOutcome? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let outcome = lock.withLock({ outcome }) { return outcome }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}

private func fetch(_ url: URL) async throws -> Int {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 10
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.setValue("bytes=0-", forHTTPHeaderField: "Range")
    let (body, _) = try await session.data(for: request)
    return body.count
}
