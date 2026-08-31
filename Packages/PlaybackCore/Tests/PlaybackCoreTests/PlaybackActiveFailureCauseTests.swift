import CoreMedia
import Foundation
import PlaybackFFmpegBridge
import Testing
@testable import PlaybackCore

private let activeFailureTestMedia = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TestMedia")

@Test("Core consumes every typed FFmpeg read cause without a fallback")
func coreConsumesEveryTypedFFmpegReadCause() throws {
    let expectations: [(PBFFmpegActiveFailureCause, PlaybackCoreActiveFailureCause)] = [
        (PBFFmpegActiveFailureCauseConnectionInterrupted, .connectionInterrupted),
        (PBFFmpegActiveFailureCauseSourceFileMissing, .sourceFileMissing),
        (PBFFmpegActiveFailureCauseSourceAccessDenied, .sourceAccessDenied),
        (PBFFmpegActiveFailureCauseMediaDataCorrupt, .mediaDataCorrupt)
    ]

    for (bridgeCause, expected) in expectations {
        let error = try #require(
            PlaybackProviderError(bridgeCause: bridgeCause, message: "diagnostic")
        )
        #expect(error.activeFailureCause == expected)
    }
    #expect(
        PlaybackProviderError(
            bridgeCause: PBFFmpegActiveFailureCauseNone,
            message: "diagnostic"
        ) == nil
    )
}

@Test("FFmpeg decoder failure records corrupt media without changing read result semantics")
func decoderFailureRecordsCorruptMedia() throws {
    let fixture = activeFailureTestMedia.appendingPathComponent(
        "TestVectors/Upstream/Fraunhofer/Audio/xHE-AAC/Sintel_24kbps_rap5s.mp4"
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString {
        PBFFmpegAudioReaderCreate($0, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader)
    defer { PBFFmpegAudioReaderDestroy(activeReader) }

    var sample: Unmanaged<CMSampleBuffer>?
    var metadata = PBFFmpegAudioSampleMetadata()
    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &metadata,
        &error,
        error.count
    )

    #expect(result == PBFFmpegReadResultError)
    #expect(
        PBFFmpegAudioReaderGetLastActiveFailureCause(activeReader)
            == PBFFmpegActiveFailureCauseMediaDataCorrupt,
        Comment(
            rawValue: String(
                bytes: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                encoding: .utf8
            ) ?? "non-UTF-8 FFmpeg diagnostic"
        )
    )
}

@Test("MPEG-4 Part 2 opening reports its structured codec name")
func mpeg4Part2OpeningReportsStructuredCodec() throws {
    let fixture = activeFailureTestMedia.appendingPathComponent(
        "TestVectors/Upstream/FATE/MPEG4-Part2/mpeg4_sstp_dpcm.m4v"
    )
    let operations = SystemFFmpegVideoReaderOperations()
    let reader = try #require(operations.allocate())
    defer { operations.destroy(reader) }

    do {
        _ = try operations.open(reader, source: fixture.path, startSeconds: 0)
        Issue.record("MPEG-4 Part 2 unexpectedly opened")
    } catch let error as PlaybackControlError {
        guard case .unsupportedVideoCodec(let codecName) = error else {
            Issue.record("Unexpected PlaybackControlError: \(error)")
            return
        }
        #expect(codecName == "mpeg4")
    }
}
