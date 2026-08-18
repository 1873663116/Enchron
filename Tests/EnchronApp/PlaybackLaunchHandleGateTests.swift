import Foundation
import MediaSource
import PlaybackFeature
import Testing

struct PlaybackLaunchHandleGateTests {
    @Test("playback launch accepts local and routed handles issued by MediaSource")
    func issuedHandleKinds() async throws {
        let localURL = URL(fileURLWithPath: "/tmp/local-feature.mkv")
        let localHandle = MediaByteStreamHandle.localFile(url: localURL)
        let localRequest = PlaybackLaunchRequest(
            source: localHandle,
            displayName: "local-feature.mkv"
        )

        let remoteHandle = try await MediaByteStreamEndpoint.shared.resolve(
            HandleGateByteSource(),
            filename: "remote-feature.mkv"
        )
        let lease = try #require(remoteHandle.accessLease)
        defer { lease.release() }
        let remoteRequest = PlaybackLaunchRequest(
            source: remoteHandle,
            displayName: "remote-feature.mkv"
        )

        #expect(localRequest.source.issuance == .localFile)
        #expect(localRequest.url == localURL)
        #expect(remoteRequest.source.issuance == .loopbackRoute)
        #expect(remoteRequest.url.scheme == "http")
        #expect(remoteRequest.url.host == "127.0.0.1")
    }
}

private final class HandleGateByteSource: MediaByteSource, Sendable {
    let totalLength: Int64? = 4
    let seekability = MediaByteSourceSeekability.randomAccess
    let liveness = MediaByteSourceLiveness.finite
    let suggestedBufferDepth = MediaByteBufferDepth.none

    func read(in range: Range<Int64>) async throws -> Data {
        Data("test".utf8).subdata(
            in: Int(range.lowerBound)..<Int(range.upperBound)
        )
    }
}
