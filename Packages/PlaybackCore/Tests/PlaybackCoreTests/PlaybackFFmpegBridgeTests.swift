import AudioToolbox
import CoreMedia
import Foundation
import PlaybackFFmpegBridge
import Testing

@Test func embeddedSubRipTracksExposeStableMetadata() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )

    let count = fixture.path.withCString(PBFFmpegSubtitleTrackCount)
    #expect(count == 2)

    var streamIndex: Int32 = -1
    var codec = [CChar](repeating: 0, count: 64)
    var language = [CChar](repeating: 0, count: 64)
    var title = [CChar](repeating: 0, count: 256)
    let copied = fixture.path.withCString { path in
        PBFFmpegSubtitleTrackCopyInfo(
            path,
            0,
            &streamIndex,
            &codec,
            codec.count,
            &language,
            language.count,
            &title,
            title.count
        )
    }

    #expect(copied)
    #expect(streamIndex == 1)
    #expect(cString(codec) == "subrip")
    #expect(cString(language) == "zho")
    #expect(cString(title) == "简体中文")
}

@Test func embeddedSubRipCuesPreserveTimingUTF8AndLineBreaks() throws {
    silenceFFmpegDiagnostics()
    let fixture = try #require(
        Bundle.module.url(
            forResource: "subtitle-subrip",
            withExtension: "mkv",
            subdirectory: "Fixtures"
        )
    )
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegSubtitleReaderCreate(path, 1, &error, error.count)
    }
    let activeReader = try #require(reader, Comment(rawValue: cString(error)))
    defer { PBFFmpegSubtitleReaderDestroy(activeReader) }

    var startSeconds = 0.0
    var durationSeconds = 0.0
    var text: Unmanaged<CFString>?
    let result = PBFFmpegSubtitleReaderCopyNextCue(
        activeReader,
        &startSeconds,
        &durationSeconds,
        &text,
        &error,
        error.count
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: cString(error)))
    let cueText = try #require(text?.takeRetainedValue()) as String

    #expect(abs(startSeconds - 0.5) < 0.001)
    #expect(abs(durationSeconds - 1.5) < 0.001)
    #expect(cueText == "第一行\n第二行")
}

@Test func delayedAudioParametersAreDiscovered() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream()
    defer { try? FileManager.default.removeItem(at: fixture) }

    let trackCount = fixture.path.withCString(PBFFmpegAudioTrackCount)

    #expect(trackCount == 1)
}

@Test func declaredAudioWithoutParametersIsNotReportedAsNoAudio() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream(includeAudioPackets: false)
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)

    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }

    #expect(reader == nil)
    let message = String(
        decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
    #expect(message == "Audio stream parameters are unavailable after extended probe")
}

@Test func delayedAudioParametersProduceCompressedAACSample() throws {
    silenceFFmpegDiagnostics()
    let fixture = try delayedAACTransportStream()
    defer { try? FileManager.default.removeItem(at: fixture) }
    var error = [CChar](repeating: 0, count: 512)
    let reader = fixture.path.withCString { path in
        PBFFmpegAudioReaderCreate(path, 0, -1, &error, error.count)
    }
    let activeReader = try #require(reader)
    defer { PBFFmpegAudioReaderDestroy(activeReader) }
    var sample: Unmanaged<CMSampleBuffer>?

    let result = PBFFmpegAudioReaderCopyNextSample(
        activeReader,
        &sample,
        &error,
        error.count
    )
    let message = String(
        decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
    #expect(result == PBFFmpegReadResultSample, Comment(rawValue: message))
    let buffer = try #require(sample?.takeRetainedValue())

    #expect(PBFFmpegAudioReaderGetSampleRate(activeReader) == 48_000)
    #expect(PBFFmpegAudioReaderGetChannelCount(activeReader) == 1)
    #expect(CMSampleBufferGetNumSamples(buffer) > 0)
    let format = try #require(CMSampleBufferGetFormatDescription(buffer))
    let streamDescription = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format))
    #expect(streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
    #expect(streamDescription.pointee.mFormatID != kAudioFormatLinearPCM)
}

private func delayedAACTransportStream(includeAudioPackets: Bool = true) throws -> URL {
    let encoded = "R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAQAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABAAArAXAAHBAADhAPAAAuEA8AAP4QHwAJdXh9D/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAMAdQAAB7DH4AAAAB4AAAgMAKMQAH79ERAAfYYQAAAbMoAWg1///gGAAAAbUUigABAAAAAAG4AAgAQAAAAQAAD//4AAABtY//80GAAAABARP5wTEAC4A0AHQFAE4BfhnJobiEhgCssNJpNLJqSgwmEwhEIaGhob2UgMK6W37Nv5wCsAIAA4ADkEQAQAPwA4GAhf6AFYAdkslAB4AHTAB6AVuCIAKBgljAlhi7ogDsMJpCBBAlALwG4AdHAQARAFAHQIP9QFA0Ax5SA0MANCGAZhnIQDAmk0rqJQBazpLYmbti057qcCgCEEH9kEH+IAOQQgDgQwDgQf5ACwoAqADkEEBMANgA7ALHGAFQAcqAyCGAUNCAMtcAIAFgIAGoBkAIgDTlEwB38G8CmALSGQgzAOgA/DQExYaGFEL4oov8hhucNzhoaXiWoM5/vriw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"
    guard let base = Data(base64Encoded: encoded) else {
        throw FixtureError.invalidBase
    }
    let packetSize = 188
    let tablePacketCount = 3
    let videoPacketCount = 34
    let audioPacketCount = 3
    let tableBytes = packetSize * tablePacketCount
    let videoBytes = packetSize * videoPacketCount
    let audioBytes = packetSize * audioPacketCount
    let videoPackets = base[tableBytes..<(tableBytes + videoBytes)]
    let audioPackets = base.suffix(audioBytes)
    var fixture = Data(base.prefix(tableBytes))
    while fixture.count < 5_600_000 {
        fixture.append(videoPackets)
    }
    if includeAudioPackets {
        fixture.append(audioPackets)
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("playbackcore-delayed-audio-\(UUID().uuidString).ts")
    try fixture.write(to: url, options: .atomic)
    return url
}

private enum FixtureError: Error {
    case invalidBase
}

@_silgen_name("av_log_set_level")
private func avLogSetLevel(_ level: Int32)

private func silenceFFmpegDiagnostics() {
    avLogSetLevel(-8)
}

private func cString(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}
