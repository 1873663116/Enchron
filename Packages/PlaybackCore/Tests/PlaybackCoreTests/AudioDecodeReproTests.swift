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

private func decodedSampleCount(streamIndex: Int, limit: Int = 64) async throws -> Int {
    guard let url = fixtureClipURL() else { return -1 }
    let provider = FFmpegAudioSampleProvider()
    try await provider.prepare(
        url: url,
        asset: nil,
        startTime: .zero,
        streamIndex: streamIndex
    )
    var count = 0
    while count < limit {
        guard let sample = try await provider.copyNextSample() else { break }
        count += 1
        _ = sample
    }
    provider.cancel()
    return count
}

@Test func dtsStreamDecodesSamples() async throws {
    let count = try await decodedSampleCount(streamIndex: 1)
    if count < 0 { return }
    #expect(count > 0, "decoded \(count) audio samples for the DTS stream")
}

@Test func ac3StreamDecodesSamples() async throws {
    let count = try await decodedSampleCount(streamIndex: 2)
    if count < 0 { return }
    #expect(count > 0, "decoded \(count) audio samples for the AC3 stream")
}

@Test func switchingFromAc3ToDtsKeepsDecoding() async throws {
    guard let url = fixtureClipURL() else { return }
    let provider = FFmpegAudioSampleProvider()
    try await provider.prepare(url: url, asset: nil, startTime: .zero, streamIndex: 2)
    var ac3Count = 0
    while ac3Count < 16 {
        guard try await provider.copyNextSample() != nil else { break }
        ac3Count += 1
    }
    let firstInfo = provider.info
    try await provider.prepare(
        url: url,
        asset: nil,
        startTime: CMTime(seconds: 5, preferredTimescale: 600),
        streamIndex: 1
    )
    let switchedInfo = provider.info
    var dtsCount = 0
    while dtsCount < 16 {
        guard try await provider.copyNextSample() != nil else { break }
        dtsCount += 1
    }
    provider.cancel()
    #expect(ac3Count > 0)
    #expect(firstInfo?.streamIndex == 2)
    #expect(switchedInfo?.streamIndex == 1)
    #expect(dtsCount > 0, "after switching to stream 1 only \(dtsCount) samples decoded")
}
