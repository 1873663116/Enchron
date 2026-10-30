import CoreMedia
import Foundation
import Testing
@testable import PlaybackCore

private func fixtureClipURL() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["ENCHRON_MEDIA_FIXTURE"] else {
        return nil
    }
    return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
}

private struct SubtitleHarness {
    let session: FFmpegDemuxSession
    let provider: FFmpegSubtitleProvider
    let url: URL
    let track: PlaybackSubtitleTrack

    static func make(url: URL) async throws -> SubtitleHarness {
        let meter = PlaybackSourceReadMeter()
        let session = FFmpegDemuxSession(sourceReadMeter: meter)
        try await session.configureSource(transport: .localFile)
        let argument = FFmpegSourceLocator.argument(for: url)
        try session.withSource(argument: argument) { _ in () }
        let provider = FFmpegSubtitleProvider(sourceReadMeter: meter, demuxSession: session)
        let tracks = try await provider.tracks(in: url, asset: nil)
        let track = try #require(tracks.first { $0.codecName.contains("pgs") } ?? tracks.first)
        return SubtitleHarness(session: session, provider: provider, url: url, track: track)
    }

    func makeRenderer() async throws -> FFmpegSubtitleFrameRenderer {
        _ = try await provider.cues(in: url, asset: nil, track: track)
        let renderer = try #require(
            try await provider.frameRenderer(in: url, asset: nil, track: track)
        )
        return try #require(renderer as? FFmpegSubtitleFrameRenderer)
    }

    func driveAudio(seconds: Double) async throws {
        let meter = PlaybackSourceReadMeter()
        let audio = FFmpegAudioSampleProvider(sourceReadMeter: meter, demuxSession: session)
        try await audio.prepare(url: url, asset: nil, startTime: .zero, streamIndex: 2)
        let deadline = Date().addingTimeInterval(seconds)
        var read = 0
        while Date() < deadline, read < 900, try await audio.copyNextSample() != nil {
            read += 1
        }
        audio.cancel()
    }
}

@Test func subtitleSubscribedAfterPlaybackStartedIngests() async throws {
    guard let url = fixtureClipURL() else { return }
    let harness = try await SubtitleHarness.make(url: url)
    try await harness.driveAudio(seconds: 6)
    let renderer = try await harness.makeRenderer()
    var processed = 0
    var second = 60.0
    while processed == 0, second < 200 {
        _ = try renderer.ingestPendingCues(for: harness.track)
        _ = try renderer.frame(
            at: CMTime(seconds: second, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        )
        processed = Int(renderer.decodedPacketCount)
        second += 0.5
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    print("LATE STATE:", renderer.stateDescription)
    #expect(processed > 0, "renderer ingested no packet after a late subscription")
}

@Test func subtitleSubscribedBeforePlaybackIngests() async throws {
    guard let url = fixtureClipURL() else { return }
    let harness = try await SubtitleHarness.make(url: url)
    let renderer = try await harness.makeRenderer()
    let driver = Task { try await harness.driveAudio(seconds: 6) }
    var processed = 0
    var second = 60.0
    while processed == 0, second < 200 {
        _ = try renderer.ingestPendingCues(for: harness.track)
        _ = try renderer.frame(
            at: CMTime(seconds: second, preferredTimescale: 600),
            viewportWidth: 1_920,
            viewportHeight: 1_080
        )
        processed = Int(renderer.decodedPacketCount)
        second += 0.5
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    try await driver.value
    #expect(processed > 0, "renderer ingested no packet after an early subscription")
}
