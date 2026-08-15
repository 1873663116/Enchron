import Foundation
import PlaybackFFmpegBridge

enum ProbeFailure: Error, CustomStringConvertible {
    case usage(String)
    case operation(String)

    var description: String {
        switch self {
        case .usage(let message), .operation(let message): message
        }
    }
}

enum ProbeStage: String {
    case tracks
    case videoReader = "video-reader"
    case audioReader = "audio-reader"
}

func errorMessage(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

func enumerateTracks(source: String, monitor: OpaquePointer) throws -> String {
    let audioCount = source.withCString {
        PBFFmpegAudioTrackCountWithSourceReadMonitor($0, monitor)
    }
    guard audioCount >= 0 else { throw ProbeFailure.operation("audio track count failed") }
    for ordinal in 0..<audioCount {
        var streamIndex: Int32 = -1
        var sampleRate: Int32 = 0
        var channelCount: Int32 = 0
        var codec = [CChar](repeating: 0, count: 64)
        var language = [CChar](repeating: 0, count: 64)
        var title = [CChar](repeating: 0, count: 256)
        let copied = source.withCString {
            PBFFmpegAudioTrackCopyInfoWithSourceReadMonitor(
                $0,
                ordinal,
                &streamIndex,
                &sampleRate,
                &channelCount,
                &codec,
                codec.count,
                &language,
                language.count,
                &title,
                title.count,
                monitor
            )
        }
        guard copied else {
            throw ProbeFailure.operation("audio track info failed at ordinal \(ordinal)")
        }
    }

    let subtitleCount = source.withCString {
        PBFFmpegSubtitleTrackCountWithSourceReadMonitor($0, monitor)
    }
    guard subtitleCount >= 0 else {
        throw ProbeFailure.operation("subtitle track count failed")
    }
    for ordinal in 0..<subtitleCount {
        var streamIndex: Int32 = -1
        var codec = [CChar](repeating: 0, count: 64)
        var language = [CChar](repeating: 0, count: 64)
        var title = [CChar](repeating: 0, count: 256)
        let copied = source.withCString {
            PBFFmpegSubtitleTrackCopyInfoWithSourceReadMonitor(
                $0,
                ordinal,
                &streamIndex,
                &codec,
                codec.count,
                &language,
                language.count,
                &title,
                title.count,
                monitor
            )
        }
        guard copied else {
            throw ProbeFailure.operation("subtitle track info failed at ordinal \(ordinal)")
        }
    }
    return "audio_tracks=\(audioCount) subtitle_tracks=\(subtitleCount)"
}

func openVideoReader(source: String, monitor: OpaquePointer) throws -> String {
    guard let reader = PBFFmpegReaderAllocate() else {
        throw ProbeFailure.operation("video reader allocation failed")
    }
    PBFFmpegReaderSetSourceReadMonitor(reader, monitor)
    var error = [CChar](repeating: 0, count: 512)
    let opened = source.withCString {
        PBFFmpegReaderOpen(
            reader,
            $0,
            PBFFmpegModeCompressed,
            0,
            &error,
            error.count
        )
    }
    guard opened else {
        PBFFmpegReaderDestroy(reader)
        throw ProbeFailure.operation("video reader open failed: \(errorMessage(error))")
    }
    let streamIndex = PBFFmpegReaderGetVideoStreamIndex(reader)
    PBFFmpegReaderDestroy(reader)
    return "video_stream=\(streamIndex)"
}

func openAudioReader(source: String, monitor: OpaquePointer) throws -> String {
    guard let reader = PBFFmpegAudioReaderAllocate() else {
        throw ProbeFailure.operation("audio reader allocation failed")
    }
    PBFFmpegAudioReaderSetSourceReadMonitor(reader, monitor)
    var error = [CChar](repeating: 0, count: 512)
    let opened = source.withCString {
        PBFFmpegAudioReaderOpen(reader, $0, 0, -1, &error, error.count)
    }
    guard opened else {
        PBFFmpegAudioReaderDestroy(reader)
        throw ProbeFailure.operation("audio reader open failed: \(errorMessage(error))")
    }
    let streamIndex = PBFFmpegAudioReaderGetStreamIndex(reader)
    PBFFmpegAudioReaderDestroy(reader)
    return "audio_stream=\(streamIndex)"
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 4,
          arguments[0] == "--stage",
          let stage = ProbeStage(rawValue: arguments[1]),
          arguments[2] == "--url" else {
        throw ProbeFailure.usage(
            "usage: PlaybackCoreRemoteMediaProbe --stage tracks|video-reader|audio-reader --url URL"
        )
    }
    guard let monitor = PBFFmpegSourceReadMonitorCreate() else {
        throw ProbeFailure.operation("source read monitor allocation failed")
    }
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let detail = switch stage {
    case .tracks:
        try enumerateTracks(source: arguments[3], monitor: monitor)
    case .videoReader:
        try openVideoReader(source: arguments[3], monitor: monitor)
    case .audioReader:
        try openAudioReader(source: arguments[3], monitor: monitor)
    }
    let bytes = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    print("stage=\(stage.rawValue) bytes_read=\(bytes) \(detail)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
