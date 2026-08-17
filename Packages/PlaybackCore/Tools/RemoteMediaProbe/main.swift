import Foundation
import CoreMedia
import VideoToolbox
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
    case playback
    case session
    case decode
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

func openSharedSession(source: String, monitor: OpaquePointer) throws -> String {
    var error = [CChar](repeating: 0, count: 512)
    let demuxSource = source.withCString {
        PBFFmpegDemuxSourceCreate($0, false, monitor, &error, error.count)
    }
    guard let demuxSource else {
        throw ProbeFailure.operation(
            "demux source open failed: \(errorMessage(error))"
        )
    }
    defer { PBFFmpegDemuxSourceDestroy(demuxSource) }
    guard let information = PBFFmpegDemuxSourceCopyInformation(
        demuxSource,
        &error,
        error.count
    ) else {
        throw ProbeFailure.operation(
            "demux source information failed: \(errorMessage(error))"
        )
    }
    defer { PBFFmpegMediaSourceInformationDestroy(information) }
    guard let videoReader = PBFFmpegReaderAllocate(),
          let audioReader = PBFFmpegAudioReaderAllocate() else {
        throw ProbeFailure.operation("shared reader allocation failed")
    }
    defer {
        PBFFmpegReaderDestroy(videoReader)
        PBFFmpegAudioReaderDestroy(audioReader)
    }
    guard PBFFmpegReaderOpenWithDemuxSource(
        videoReader,
        demuxSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    ) else {
        throw ProbeFailure.operation(
            "shared video reader open failed: \(errorMessage(error))"
        )
    }
    guard PBFFmpegAudioReaderOpenWithDemuxSource(
        audioReader,
        demuxSource,
        -1,
        &error,
        error.count
    ) else {
        throw ProbeFailure.operation(
            "shared audio reader open failed: \(errorMessage(error))"
        )
    }
    return "streams=\(PBFFmpegMediaSourceInformationGetStreamCount(information)) "
        + "video_stream=\(PBFFmpegReaderGetVideoStreamIndex(videoReader)) "
        + "audio_stream=\(PBFFmpegAudioReaderGetStreamIndex(audioReader))"
}

final class DecodeTally: @unchecked Sendable {
    private let lock = NSLock()
    private var decoded = 0
    private var failed = 0
    private var firstFailure: OSStatus = noErr

    func record(status: OSStatus, hasImage: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if status == noErr && hasImage {
            decoded += 1
        } else {
            failed += 1
            if firstFailure == noErr { firstFailure = status }
        }
    }

    var decodedFrames: Int { lock.withLock { decoded } }
    var failedFrames: Int { lock.withLock { failed } }
    var firstFailureStatus: OSStatus { lock.withLock { firstFailure } }
}

/// Decodes the compressed samples PlaybackCore would hand its renderer. The bridge
/// only produces compressed samples, so whether VideoToolbox accepts a format is not
/// observable anywhere else in this package.
func decodeSamples(
    source: String,
    monitor: OpaquePointer,
    limitSeconds: Double?
) throws -> String {
    var error = [CChar](repeating: 0, count: 512)
    guard let videoReader = PBFFmpegReaderAllocate() else {
        throw ProbeFailure.operation("reader allocation failed")
    }
    defer { PBFFmpegReaderDestroy(videoReader) }
    PBFFmpegReaderSetSourceReadMonitor(videoReader, monitor)
    let opened = source.withCString {
        PBFFmpegReaderOpen(videoReader, $0, PBFFmpegModeCompressed, 0, &error, error.count)
    }
    guard opened else {
        throw ProbeFailure.operation("video reader open failed: \(errorMessage(error))")
    }
    var formatOut: Unmanaged<CMVideoFormatDescription>?
    let formatStatus = PBFFmpegVideoFormatDescriptionCreate(
        videoReader,
        nil,
        nil,
        nil,
        &formatOut
    )
    guard formatStatus == noErr, let format = formatOut?.takeRetainedValue() else {
        throw ProbeFailure.operation("compressed format description unavailable")
    }
    let subType = CMFormatDescriptionGetMediaSubType(format)
    let codec = String(
        bytes: [24, 16, 8, 0].map { UInt8((subType >> $0) & 0xff) },
        encoding: .ascii
    ) ?? "????"
    let colorFacts = formatColorFacts(format)

    var session: VTDecompressionSession?
    let sessionStatus = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: format,
        decoderSpecification: nil,
        imageBufferAttributes: nil,
        outputCallback: nil,
        decompressionSessionOut: &session
    )
    guard sessionStatus == noErr, let session else {
        return "codec=\(codec) session_status=\(sessionStatus) decoded_frames=0 "
            + "sample_bytes=0 \(colorFacts) decode=session_rejected"
    }
    defer { VTDecompressionSessionInvalidate(session) }

    let tally = DecodeTally()
    var firstDecodeStatus: OSStatus = noErr
    var failedFrames = 0
    var sampleBytes = 0
    var sampleCount = 0
    // Sources whose first sample carries a non-zero presentation time, such as the
    // Apple projected-media examples starting near ten seconds, would satisfy an
    // absolute bound before delivering a second frame.
    var firstSeconds: Double?
    var elapsedSeconds = 0.0
    while true {
        if let limitSeconds, elapsedSeconds >= limitSeconds { break }
        var sample: Unmanaged<CMSampleBuffer>?
        let result = PBFFmpegReaderCopyNextSample(videoReader, &sample, &error, error.count)
        if result == PBFFmpegReadResultEnd { break }
        guard result == PBFFmpegReadResultSample, let sample else {
            throw ProbeFailure.operation("sample read failed: \(errorMessage(error))")
        }
        let buffer = sample.takeRetainedValue()
        sampleCount += 1
        sampleBytes += CMSampleBufferGetTotalSampleSize(buffer)
        let presentation = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        if presentation.isFinite {
            let origin = firstSeconds ?? presentation
            firstSeconds = origin
            elapsedSeconds = max(elapsedSeconds, presentation - origin)
        }
        var flagsOut = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: buffer,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flagsOut,
            outputHandler: { status, _, image, _, _ in
                tally.record(status: status, hasImage: image != nil)
            }
        )
        if status != noErr {
            failedFrames += 1
            if firstDecodeStatus == noErr { firstDecodeStatus = status }
        }
    }
    VTDecompressionSessionWaitForAsynchronousFrames(session)
    let decodedFrames = tally.decodedFrames
    let callbackFailures = tally.failedFrames
    let firstCallbackStatus = tally.firstFailureStatus
    let verdict = decodedFrames > 0 && failedFrames == 0 && callbackFailures == 0
        ? "ok"
        : (decodedFrames > 0 ? "partial" : "no_frames")
    return "codec=\(codec) session_status=0 samples=\(sampleCount) "
        + "sample_bytes=\(sampleBytes) decoded_frames=\(decodedFrames) "
        + "submit_failures=\(failedFrames) callback_failures=\(callbackFailures) "
        + "first_decode_status=\(firstDecodeStatus == noErr ? firstCallbackStatus : firstDecodeStatus) "
        + "\(colorFacts) decode=\(verdict)"
}

// The color interpretation the renderer will receive, read back from the one
// format description PlaybackCore constructs. `none` means the extension is
// absent, which the decoder resolves by guessing.
func formatColorFacts(_ format: CMVideoFormatDescription) -> String {
    let extensions = (CMFormatDescriptionGetExtensions(format) as? [String: Any]) ?? [:]
    func value(_ key: CFString) -> String {
        guard let raw = extensions[key as String] else { return "none" }
        return String(describing: raw).replacingOccurrences(of: " ", with: "_")
    }
    let atoms = extensions[
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
    ] as? [String: Any]
    let atomKeys = atoms?.keys.sorted().joined(separator: "+") ?? "none"
    let mastering = extensions[
        kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String
    ] != nil
    let lightLevel = extensions[
        kCMFormatDescriptionExtension_ContentLightLevelInfo as String
    ] != nil
    return "color_primaries=\(value(kCMFormatDescriptionExtension_ColorPrimaries)) "
        + "transfer=\(value(kCMFormatDescriptionExtension_TransferFunction)) "
        + "matrix=\(value(kCMFormatDescriptionExtension_YCbCrMatrix)) "
        + "full_range=\(value(kCMFormatDescriptionExtension_FullRangeVideo)) "
        + "atoms=\(atomKeys) mastering=\(mastering ? 1 : 0) light_level=\(lightLevel ? 1 : 0)"
}

func demuxSourceHasAudio(_ demuxSource: OpaquePointer) throws -> Bool {
    var error = [CChar](repeating: 0, count: 512)
    guard let information = PBFFmpegDemuxSourceCopyInformation(
        demuxSource,
        &error,
        error.count
    ) else {
        throw ProbeFailure.operation(
            "demux source information failed: \(errorMessage(error))"
        )
    }
    defer { PBFFmpegMediaSourceInformationDestroy(information) }
    for ordinal in 0..<PBFFmpegMediaSourceInformationGetStreamCount(information) {
        var stream = PBFFmpegMediaStreamInfo()
        guard PBFFmpegMediaSourceInformationCopyStream(
            information, ordinal, &stream,
            nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0, nil, 0
        ) else {
            throw ProbeFailure.operation("stream info failed at ordinal \(ordinal)")
        }
        if stream.category == PBFFmpegMediaStreamCategoryAudio { return true }
    }
    return false
}

func measurePlayback(
    source: String,
    monitor: OpaquePointer,
    limitSeconds: Double?
) throws -> String {
    guard let videoReader = PBFFmpegReaderAllocate(),
          let audioReader = PBFFmpegAudioReaderAllocate() else {
        throw ProbeFailure.operation("reader allocation failed")
    }
    var error = [CChar](repeating: 0, count: 512)
    let demuxSource = source.withCString {
        PBFFmpegDemuxSourceCreate($0, false, monitor, &error, error.count)
    }
    guard let demuxSource else {
        throw ProbeFailure.operation(
            "demux source open failed: \(errorMessage(error))"
        )
    }
    defer {
        PBFFmpegReaderDestroy(videoReader)
        PBFFmpegAudioReaderDestroy(audioReader)
        PBFFmpegDemuxSourceDestroy(demuxSource)
    }
    let videoOpened = PBFFmpegReaderOpenWithDemuxSource(
        videoReader,
        demuxSource,
        PBFFmpegModeCompressed,
        &error,
        error.count
    )
    guard videoOpened else {
        throw ProbeFailure.operation(
            "video reader open failed: \(errorMessage(error))"
        )
    }
    let hasAudio = try demuxSourceHasAudio(demuxSource)
    if hasAudio {
        let audioOpened = PBFFmpegAudioReaderOpenWithDemuxSource(
            audioReader,
            demuxSource,
            -1,
            &error,
            error.count
        )
        guard audioOpened else {
            throw ProbeFailure.operation(
                "audio reader open failed: \(errorMessage(error))"
            )
        }
    }

    let bytesAtPlaybackStart = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
    var videoEndSeconds = 0.0
    var audioEndSeconds = 0.0
    var videoEnded = false
    var audioEnded = !hasAudio
    var videoSampleCount = 0
    var audioSampleCount = 0
    var videoReachedLimit = false
    var audioReachedLimit = !hasAudio
    // Measured from the first presentation time, not from zero, so a source that
    // starts at a non-zero timestamp still delivers the requested span.
    var originSeconds: Double?
    while !videoEnded || !audioEnded {
        if let limitSeconds, let origin = originSeconds {
            if videoEndSeconds - origin >= limitSeconds { videoEnded = true; videoReachedLimit = true }
            if audioEndSeconds - origin >= limitSeconds { audioEnded = true; audioReachedLimit = true }
            if videoEnded && audioEnded { break }
        }
        let readVideo = !videoEnded && (audioEnded || videoEndSeconds <= audioEndSeconds)
        if readVideo {
            var sample: Unmanaged<CMSampleBuffer>?
            let result = PBFFmpegReaderCopyNextSample(
                videoReader,
                &sample,
                &error,
                error.count
            )
            switch result {
            case PBFFmpegReadResultSample:
                guard let sample else {
                    throw ProbeFailure.operation("video sample was unavailable")
                }
                let buffer = sample.takeRetainedValue()
                let presentation = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                if originSeconds == nil, presentation.isFinite { originSeconds = presentation }
                videoEndSeconds = max(
                    videoEndSeconds,
                    presentation + max(0, CMSampleBufferGetDuration(buffer).seconds)
                )
                videoSampleCount += 1
            case PBFFmpegReadResultEnd:
                videoEnded = true
            default:
                throw ProbeFailure.operation(
                    "video sample read failed: \(errorMessage(error))"
                )
            }
        } else {
            var sample: Unmanaged<CMSampleBuffer>?
            var metadata = PBFFmpegAudioSampleMetadata()
            let result = PBFFmpegAudioReaderCopyNextSample(
                audioReader,
                &sample,
                &metadata,
                &error,
                error.count
            )
            switch result {
            case PBFFmpegReadResultSample:
                guard let sample else {
                    throw ProbeFailure.operation("audio sample was unavailable")
                }
                let buffer = sample.takeRetainedValue()
                audioEndSeconds = max(
                    audioEndSeconds,
                    CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                        + max(0, CMSampleBufferGetDuration(buffer).seconds)
                )
                audioSampleCount += 1
            case PBFFmpegReadResultEnd:
                audioEnded = true
            default:
                throw ProbeFailure.operation(
                    "audio sample read failed: \(errorMessage(error))"
                )
            }
        }
    }
    let playbackBytes = PBFFmpegSourceReadMonitorGetTotalBytesRead(monitor)
        - bytesAtPlaybackStart
    let deliveredSeconds = max(videoEndSeconds, audioEndSeconds) - (originSeconds ?? 0)
    guard deliveredSeconds > 0 else {
        throw ProbeFailure.operation("playback produced no timed samples")
    }
    let bytesPerSecond = Double(playbackBytes) / deliveredSeconds
    let completion = limitSeconds == nil
        ? "end_of_stream"
        : (videoReachedLimit && audioReachedLimit ? "limit" : "end_of_stream")
    return "playback_bytes=\(playbackBytes) delivered_seconds=\(deliveredSeconds) "
        + "bytes_per_second=\(bytesPerSecond) video_samples=\(videoSampleCount) "
        + "audio_samples=\(audioSampleCount) has_audio=\(hasAudio) "
        + "completion=\(completion)"
}

func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    var limitSeconds: Double?
    if let flag = arguments.firstIndex(of: "--seconds"), flag + 1 < arguments.count {
        guard let value = Double(arguments[flag + 1]), value > 0 else {
            throw ProbeFailure.usage("--seconds needs a positive number")
        }
        limitSeconds = value
        arguments.removeSubrange(flag...(flag + 1))
    }
    guard arguments.count == 4,
          arguments[0] == "--stage",
          let stage = ProbeStage(rawValue: arguments[1]),
          arguments[2] == "--url" else {
        throw ProbeFailure.usage(
            "usage: PlaybackCoreRemoteMediaProbe --stage tracks|video-reader|audio-reader|playback|session --url URL [--seconds N]"
        )
    }
    guard let monitor = PBFFmpegSourceReadMonitorCreate() else {
        throw ProbeFailure.operation("source read monitor allocation failed")
    }
    defer { PBFFmpegSourceReadMonitorDestroy(monitor) }
    let stages: [ProbeStage] = [stage]
    var previousBytes: UInt64 = 0
    for currentStage in stages {
        let detail = switch currentStage {
        case .tracks:
            try enumerateTracks(source: arguments[3], monitor: monitor)
        case .videoReader:
            try openVideoReader(source: arguments[3], monitor: monitor)
        case .audioReader:
            try openAudioReader(source: arguments[3], monitor: monitor)
        case .playback:
            try measurePlayback(
                source: arguments[3],
                monitor: monitor,
                limitSeconds: limitSeconds
            )
        case .session:
            try openSharedSession(source: arguments[3], monitor: monitor)
        case .decode:
            try decodeSamples(
                source: arguments[3],
                monitor: monitor,
                limitSeconds: limitSeconds
            )
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
