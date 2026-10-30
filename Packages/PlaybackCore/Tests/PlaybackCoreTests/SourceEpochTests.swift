import CoreMedia
import Foundation
import Testing
@testable import PlaybackCore

private func fixtureMediaURL() throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
}

@Test func aDemuxSessionExposesOneEpochPerOpenSource() async throws {
    let url = try fixtureMediaURL()
    let session = FFmpegDemuxSession(sourceReadMeter: PlaybackSourceReadMeter())
    #expect(session.currentEpoch() == nil)
    try await session.configureSource(transport: .localFile)
    let argument = FFmpegSourceLocator.argument(for: url)
    let opened = try session.withSource(argument: argument) { _ in
        session.currentEpoch()
    }
    #expect(opened != nil)
    session.rotateEpochForTesting()
    #expect(session.currentEpoch() != opened)
}

@Test func anAudioReaderRefusesToReadFromAMovedEpoch() async throws {
    guard let path = ProcessInfo.processInfo.environment["ENCHRON_MEDIA_FIXTURE"] else {
        return
    }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let meter = PlaybackSourceReadMeter()
    let session = FFmpegDemuxSession(sourceReadMeter: meter)
    try await session.configureSource(transport: .localFile)
    let provider = FFmpegAudioSampleProvider(sourceReadMeter: meter, demuxSession: session)
    try await provider.prepare(url: url, asset: nil, startTime: .zero, streamIndex: nil)
    _ = try? await provider.copyNextSample()
    session.rotateEpochForTesting()
    await #expect(throws: AudioSampleProviderError.self) {
        _ = try await provider.copyNextSample()
    }
    provider.cancel()
}

@Test func aVideoReaderRefusesToReadFromAMovedEpoch() async throws {
    let url = try fixtureMediaURL()
    let meter = PlaybackSourceReadMeter()
    let session = FFmpegDemuxSession(sourceReadMeter: meter)
    try await session.configureSource(transport: .localFile)
    let provider = FFmpegSampleProvider(sourceReadMeter: meter, demuxSession: session)
    try await provider.prepare(
        url: url,
        asset: nil,
        sourceInformation: nil,
        startTime: .zero
    )
    session.rotateEpochForTesting()
    await #expect(throws: PlaybackProviderError.self) {
        _ = try await provider.nextEvent()
    }
    provider.cancel()
}

@Test func aSubtitleRendererRefusesToIngestFromAMovedEpoch() async throws {
    let url = try fixtureMediaURL()
    let meter = PlaybackSourceReadMeter()
    let session = FFmpegDemuxSession(sourceReadMeter: meter)
    try await session.configureSource(transport: .localFile)
    let source = FFmpegSourceLocator.argument(for: url)
    let provider = FFmpegSubtitleProvider(sourceReadMeter: meter, demuxSession: session)
    let tracks = try await provider.tracks(in: url, asset: nil)
    let track = try #require(tracks.first)
    let renderer = try FFmpegSubtitleFrameRenderer(
        demuxSession: session,
        source: source,
        track: track
    )
    session.rotateEpochForTesting()
    #expect(throws: SubtitleProviderError.self) {
        _ = try renderer.ingestPendingCues(for: track)
    }
}
