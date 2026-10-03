import BluRayDiscBridge
import CoreMedia
import Foundation
import PlaybackFFmpegBridge
import Testing

private var discCorpus: URL {
    var location = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { location.deleteLastPathComponent() }
    return location.appendingPathComponent("TestMedia/Samples/DiscImages")
}

private func withDiscDemux<T>(
    _ relativePath: String, playlist: UInt32,
    body: (OpaquePointer) throws -> T
) throws -> T {
    var error = [CChar](repeating: 0, count: 512)
    let path = discCorpus.appendingPathComponent(relativePath).path
    let disc = try #require(path.withCString {
        PBBlurayOpen($0, playlist, &error, error.count)
    }, Comment(rawValue: String(decoding: error.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)))
    let source = try #require(path.withCString {
        PBFFmpegDemuxSourceCreateWithDisc(
            $0, disc, false,
            PBFFmpegDemuxBufferConfigurationMake(PBFFmpegDemuxBufferModeNone, 0),
            nil, &error, error.count
        )
    }, Comment(rawValue: String(decoding: error.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)))
    defer { PBFFmpegDemuxSourceDestroy(source) }
    return try body(source)
}

@Test(arguments: ["AVS-HD-709/HDMV-2d.iso", "AVS-HD-709/HDMV-2d", "AVS-HD-709/HDMV-2d/BDMV"])
func selectedDiscTitleUsesTheCompletePlaylistClock(_ path: String) throws {
    try withDiscDemux(path, playlist: 99) { source in
        var error = [CChar](repeating: 0, count: 512)
        let reader = try #require(PBFFmpegReaderAllocate())
        defer { PBFFmpegReaderDestroy(reader) }
        try #require(PBFFmpegReaderOpenWithDemuxSource(
            reader, source, PBFFmpegModeCompressed, &error, error.count
        ))
        #expect(abs(PBFFmpegReaderGetDurationSeconds(reader) - 30.03) < 0.000001)
        var times: [Double] = []
        while true {
            var reference: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(reader, &reference, &error, error.count)
            if result == PBFFmpegReadResultEnd { break }
            try #require(result == PBFFmpegReadResultSample)
            let sample = try #require(reference?.takeRetainedValue())
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        #expect(times.count == 720)
        let presented = times.sorted()
        #expect(abs(try #require(presented.first)) < 0.000001)
        #expect(abs(try #require(presented.last) - 719 * 1001.0 / 24000) < 0.00002)
        for clip in 0..<30 {
            #expect(abs(presented[clip * 24] - Double(clip) * 1.001) < 0.00002)
        }
    }
}

@Test(arguments: ["DolbyVision-Profile7-FEL/FEL_test_for_AVS.iso", "DolbyVision-Profile7-FEL/FEL_test_for_AVS"])
func discTitleProbeReportsPlaylistDurationInsteadOfRawClipDuration(_ path: String) throws {
    try withDiscDemux(path, playlist: 0) { source in
        var error = [CChar](repeating: 0, count: 512)
        let info = try #require(PBFFmpegDemuxSourceCopyInformation(source, &error, error.count))
        defer { PBFFmpegMediaSourceInformationDestroy(info) }
        #expect(abs(PBFFmpegMediaSourceInformationGetDurationSeconds(info) - 119.911444) < 0.000001)
        #expect(PBFFmpegMediaSourceInformationGetStreamCount(info) == 2)
        #expect(PBFFmpegMediaSourceInformationGetDolbyVisionProfile(info) == 0)
    }
}

@Test(arguments: ["AVS-HD-709/HDMV-2d.iso", "AVS-HD-709/HDMV-2d"])
func discSeekUsesWholeTitleTimeInBothDirections(_ path: String) throws {
    try withDiscDemux(path, playlist: 99) { source in
        var error = [CChar](repeating: 0, count: 512)
        for target in [12.012, 2.002, 28.028, 0.0] {
            try #require(PBFFmpegDemuxSourceSeek(source, target, &error, error.count))
            let reader = try #require(PBFFmpegReaderAllocate())
            defer { PBFFmpegReaderDestroy(reader) }
            try #require(PBFFmpegReaderOpenWithDemuxSource(
                reader, source, PBFFmpegModeCompressed, &error, error.count
            ))
            var reference: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(reader, &reference, &error, error.count)
            try #require(result == PBFFmpegReadResultSample)
            let sample = try #require(reference?.takeRetainedValue())
            let actual = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            #expect(actual >= target - 1.001)
            #expect(actual < target + 1.001)
        }
    }
}

@Test(arguments: ["AVS-HD-709/HDMV-2d.iso", "AVS-HD-709/HDMV-2d"])
func selectedDiscAudioUsesTheSameZeroBasedTitleClock(_ path: String) throws {
    try withDiscDemux(path, playlist: 41) { source in
        var error = [CChar](repeating: 0, count: 512)
        let reader = try #require(PBFFmpegAudioReaderAllocate())
        defer { PBFFmpegAudioReaderDestroy(reader) }
        try #require(PBFFmpegAudioReaderOpenWithDemuxSource(
            reader, source, -1, &error, error.count
        ))
        #expect(PBFFmpegAudioReaderGetSampleRate(reader) == 48_000)
        #expect(PBFFmpegAudioReaderGetChannelCount(reader) == 2)
        var reference: Unmanaged<CMSampleBuffer>?
        var metadata = PBFFmpegAudioSampleMetadata()
        let result = PBFFmpegAudioReaderCopyNextSample(
            reader, &reference, &metadata, &error, error.count
        )
        try #require(result == PBFFmpegReadResultSample)
        let sample = try #require(reference?.takeRetainedValue())
        #expect(CMSampleBufferGetNumSamples(sample) > 0)
        let firstTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        #expect(firstTime >= -0.1)
        #expect(firstTime < 0.1)
    }
}

@Test(arguments: ["Sintel-Editions/Sintel-Editions.iso", "Sintel-Editions/Sintel-Editions"])
func selectedDiscAudioDoesNotRepeatTheTimestampAtAClipBoundary(_ path: String) throws {
    try withDiscDemux(path, playlist: 1) { source in
        var error = [CChar](repeating: 0, count: 512)
        let reader = try #require(PBFFmpegAudioReaderAllocate())
        defer { PBFFmpegAudioReaderDestroy(reader) }
        try #require(PBFFmpegAudioReaderOpenWithDemuxSource(
            reader, source, -1, &error, error.count
        ))

        var times: [Double] = []
        while true {
            var reference: Unmanaged<CMSampleBuffer>?
            var metadata = PBFFmpegAudioSampleMetadata()
            let result = PBFFmpegAudioReaderCopyNextSample(
                reader, &reference, &metadata, &error, error.count
            )
            if result == PBFFmpegReadResultEnd { break }
            try #require(result == PBFFmpegReadResultSample)
            let sample = try #require(reference?.takeRetainedValue())
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }

        for (previous, current) in zip(times, times.dropFirst()) {
            #expect(
                current > previous,
                Comment(rawValue: "audio PTS repeated or moved backwards: \(previous) -> \(current)")
            )
        }

        let boundary = times.filter { $0 >= 64.9 && $0 <= 65.1 }
        let expectedBoundary = [64.904, 64.936, 64.968, 65.000, 65.032, 65.064, 65.096]
        #expect(boundary.count == expectedBoundary.count)
        for (actual, expected) in zip(boundary, expectedBoundary) {
            #expect(abs(actual - expected) < 0.000_001)
        }
        #expect(times.filter { abs($0 - 65.0) < 0.000_001 }.count == 1)
    }
}
