import Foundation
import MediaSource
import Testing

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamLifecycleTests {
    @Test("retiring one playback stream leaves other streams readable")
    func independentStreamsSurviveRetirement() async throws {
        let source = LifecycleByteRangeSource()
        let first = try await MediaByteStreamServer(readChunkSize: 4)
            .register(source: source, filename: "first.bin")
        let second = try await MediaByteStreamServer(readChunkSize: 4)
            .register(source: source, filename: "second.bin")
        #expect(try await fetchRange("bytes=2-6", from: first.url).body == Data("23456".utf8))
        first.release()
        #expect(try await fetchRange("bytes=2-6", from: second.url).body == Data("23456".utf8))
        second.release()
    }

    @MainActor
    @Test("cancelling preparation releases its streams without touching unrelated content")
    func preparationRetiresOnlyOwnedStreams() async throws {
        let source = LifecycleByteRangeSource()
        let unrelatedServer = MediaByteStreamServer(readChunkSize: 4)
        let unrelated = try await unrelatedServer.register(source: source, filename: "image.bin")
        let preparation = MediaSourcePreparation()
        let playbackServer = MediaByteStreamServer(readChunkSize: 4)
        var resume: CheckedContinuation<Void, Never>?
        var retiredURLs: [URL] = []
        let old = Task {
            try await preparation.resolve {
                let video = try await playbackServer.register(source: source, filename: "video.bin")
                let subtitle = try await playbackServer.register(source: source, filename: "subtitle.bin")
                retiredURLs = [video.url, subtitle.url]
                await withCheckedContinuation { resume = $0 }
                return [video, subtitle]
            }
        }
        while resume == nil { await Task.yield() }
        preparation.cancel()
        resume?.resume()
        do {
            _ = try await old.value
            Issue.record("A retired preparation returned its streams")
        } catch { #expect(error is CancellationError) }
        for url in retiredURLs {
            do {
                _ = try await fetchRange("bytes=2-6", from: url)
                Issue.record("The retired playback listener still accepts requests")
            } catch {
                #expect((error as? URLError)?.code == .cannotConnectToHost)
            }
        }
        #expect(try await fetchRange("bytes=2-6", from: unrelated.url).body == Data("23456".utf8))
        unrelated.release()
        await playbackServer.stopAndWait()
        await unrelatedServer.stopAndWait()
    }

    @Test("background teardown permits immediate reopen before old handles release")
    func backgroundTeardownPermitsImmediateReopen() async throws {
        let source = LifecycleByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let before = try await server.register(source: source, filename: "before.bin")
        let initial = try await fetchRange("bytes=2-6", from: before.url)
        #expect(initial.body == Data("23456".utf8))

        server.stop()
        server.stop()

        let after = try await server.register(source: source, filename: "after.bin")
        before.release()
        for _ in 0..<3 {
            let served = try await fetchRange("bytes=2-6", from: after.url)
            #expect(served.statusCode == 206)
            #expect(served.body == Data("23456".utf8))
        }
        after.release()
        await server.stopAndWait()
    }

    @Test("an active playback endpoint bundle moves to one fresh listener generation")
    func activeEndpointBundleRefreshesTogether() async throws {
        let source = LifecycleByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let video = try await server.register(source: source, filename: "video.bin")
        let subtitle = try await server.register(source: source, filename: "subtitle.vtt")

        let refreshed = try await MediaByteStreamHandle.refreshing(
            [video, subtitle],
            restartingListeners: true
        )
        #expect(refreshed.count == 2)
        #expect(refreshed[0].url != video.url)
        #expect(refreshed[1].url != subtitle.url)

        video.release()
        subtitle.release()

        #expect(
            try await fetchRange("bytes=2-6", from: refreshed[0].url).body
                == Data("23456".utf8)
        )
        #expect(
            try await fetchRange("bytes=2-6", from: refreshed[1].url).body
                == Data("23456".utf8)
        )

        refreshed.forEach { $0.release() }
        await server.stopAndWait()
    }

}

private final class LifecycleByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: 10,
        supportsSeeking: true,
        isLive: false
    )

    private let payload = Data("0123456789".utf8)

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let count = Int64(payload.count)
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        return MediaByteRangeRead(
            data: Data(payload[Int(lower)..<Int(upper)]),
            contentLength: count,
            supportsSeeking: true
        )
    }
}

private struct LifecycleObservation: Sendable {
    let statusCode: Int
    let body: Data
}

private func fetchRange(_ value: String, from url: URL) async throws -> LifecycleObservation {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3
    configuration.timeoutIntervalForResource = 3
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    request.setValue(value, forHTTPHeaderField: "Range")
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    return LifecycleObservation(statusCode: http.statusCode, body: body)
}
#endif
