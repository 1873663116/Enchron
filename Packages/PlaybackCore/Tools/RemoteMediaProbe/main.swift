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
    case session
}

func errorMessage(_ buffer: [CChar]) -> String {
    String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
        as: UTF8.self
    )
}

func enumerateTracks(source: String, monitor: OpaquePointer) throws -> String {
    var error = [CChar](repeating: 0, count: 512)
    let information = source.withCString {
        PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
            $0,
            monitor,
            &error,
            error.count
        )
    }
    guard let information else {
        throw ProbeFailure.operation(
            "media source information failed: \(errorMessage(error))"
        )
    }
    defer { PBFFmpegMediaSourceInformationDestroy(information) }
    let streamCount = PBFFmpegMediaSourceInformationGetStreamCount(information)
    var videoCount = 0
    var audioCount = 0
    var subtitleCount = 0
    for ordinal in 0..<streamCount {
        var stream = PBFFmpegMediaStreamInfo()
        let copied = PBFFmpegMediaSourceInformationCopyStream(
            information,
            ordinal,
            &stream,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0,
            nil, 0
        )
        guard copied else {
            throw ProbeFailure.operation("stream info failed at ordinal \(ordinal)")
        }
        switch stream.category {
        case PBFFmpegMediaStreamCategoryVideo:
            videoCount += 1
        case PBFFmpegMediaStreamCategoryAudio:
            guard stream.sampleRate > 0, stream.channelCount > 0 else {
                throw ProbeFailure.operation("audio stream parameters are unavailable")
            }
            audioCount += 1
        case PBFFmpegMediaStreamCategorySubtitle:
            subtitleCount += 1
        default:
            break
        }
    }
    return "video_tracks=\(videoCount) audio_tracks=\(audioCount) subtitle_tracks=\(subtitleCount)"
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
    let duration = PBFFmpegReaderGetDurationSeconds(reader)
    guard duration.isFinite, duration > 0 else {
        PBFFmpegReaderDestroy(reader)
        throw ProbeFailure.operation("video stream duration is unavailable")
    }
    PBFFmpegReaderDestroy(reader)
    return "video_stream=\(streamIndex) duration_seconds=\(duration)"
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
            "usage: PlaybackCoreRemoteMediaProbe --stage tracks|video-reader|audio-reader|session --url URL"
        )
    }
    guard let monitor = PBFFmpegSourceReadMonitorCreate() else {
        throw ProbeFailure.operation("source read monitor allocation failed")
    }
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let stages: [ProbeStage] = stage == .session
        ? [.tracks, .videoReader, .audioReader]
        : [stage]
    var previousBytes: UInt64 = 0
    for currentStage in stages {
        let detail = switch currentStage {
        case .tracks:
            try enumerateTracks(source: arguments[3], monitor: monitor)
        case .videoReader:
            try openVideoReader(source: arguments[3], monitor: monitor)
        case .audioReader:
            try openAudioReader(source: arguments[3], monitor: monitor)
        case .session:
            throw ProbeFailure.operation("nested session stage")
        }
        let cumulativeBytes = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
        let bytes = cumulativeBytes - previousBytes
        previousBytes = cumulativeBytes
        FileHandle.standardOutput.write(
            Data(
                "stage=\(currentStage.rawValue) bytes_read=\(bytes) \(detail)\n".utf8
            )
        )
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
