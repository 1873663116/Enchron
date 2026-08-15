import Foundation
import PlaybackFFmpegBridge

public enum MediaSourceStreamCategory: String, Codable, Sendable {
    case video
    case audio
    case subtitle
    case other
}

public struct MediaSourceVideoInformation: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let nominalFrameRate: Double
    public let colorPrimaries: String
    public let transferFunction: String
    public let yCbCrMatrix: String
    public let colorRange: String
    public let projectionKind: String

    public init(
        width: Int,
        height: Int,
        nominalFrameRate: Double,
        colorPrimaries: String,
        transferFunction: String,
        yCbCrMatrix: String,
        colorRange: String,
        projectionKind: String
    ) {
        self.width = width
        self.height = height
        self.nominalFrameRate = nominalFrameRate
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.colorRange = colorRange
        self.projectionKind = projectionKind
    }
}

public struct MediaSourceAudioInformation: Codable, Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int

    public init(sampleRate: Int, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct MediaSourceStreamInformation: Codable, Equatable, Identifiable, Sendable {
    public let streamIndex: Int
    public let category: MediaSourceStreamCategory
    public let codecID: Int32
    public let codecName: String
    public let codecTag: UInt32
    public let language: String?
    public let title: String?
    public let disposition: Int32
    public let video: MediaSourceVideoInformation?
    public let audio: MediaSourceAudioInformation?

    public var id: Int { streamIndex }

    public init(
        streamIndex: Int,
        category: MediaSourceStreamCategory,
        codecID: Int32,
        codecName: String,
        codecTag: UInt32,
        language: String?,
        title: String?,
        disposition: Int32,
        video: MediaSourceVideoInformation?,
        audio: MediaSourceAudioInformation?
    ) {
        self.streamIndex = streamIndex
        self.category = category
        self.codecID = codecID
        self.codecName = codecName
        self.codecTag = codecTag
        self.language = language
        self.title = title
        self.disposition = disposition
        self.video = video
        self.audio = audio
    }

    public var codecTagString: String {
        let bytes = (0..<4).map { shift in
            UInt8(truncatingIfNeeded: codecTag >> UInt32(shift * 8))
        }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

public struct MediaSourceInformation: Codable, Equatable, Sendable {
    public let containerFormat: String
    public let durationSeconds: Double
    public let streams: [MediaSourceStreamInformation]

    public init(
        containerFormat: String,
        durationSeconds: Double,
        streams: [MediaSourceStreamInformation]
    ) {
        self.containerFormat = containerFormat
        self.durationSeconds = durationSeconds
        self.streams = streams
    }
}

protocol MediaSourceInformationLoading: Sendable {
    func load(from url: URL) async throws -> MediaSourceInformation
}

struct SystemMediaSourceInformationLoader: MediaSourceInformationLoading {
    private let sourceReadMeter: PlaybackSourceReadMeter
    private let demuxSession: FFmpegDemuxSession?
    private let queue = DispatchQueue(
        label: "com.enchron.playbackcore.ffmpeg-media-source-information"
    )

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
    }

    func load(from url: URL) async throws -> MediaSourceInformation {
        let source = FFmpegSourceLocator.argument(for: url)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [sourceReadMeter, demuxSession] in
                var error = [CChar](repeating: 0, count: 512)
                let handle: OpaquePointer?
                do {
                    handle = if let demuxSession {
                        try demuxSession.withSource(argument: source) {
                            PBFFmpegDemuxSourceCopyInformation(
                                $0,
                                &error,
                                error.count
                            )
                        }
                    } else {
                        source.withCString {
                            PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
                                $0,
                                sourceReadMeter.bridgeMonitor,
                                &error,
                                error.count
                            )
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                guard let handle else {
                    continuation.resume(
                        throwing: MediaSourceInformationError.open(
                            ffmpegErrorMessage(error)
                        )
                    )
                    return
                }
                defer { PBFFmpegMediaSourceInformationDestroy(handle) }
                do {
                    continuation.resume(returning: try Self.copy(handle))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func copy(
        _ handle: OpaquePointer
    ) throws -> MediaSourceInformation {
        let streamCount = Int(PBFFmpegMediaSourceInformationGetStreamCount(handle))
        var streams: [MediaSourceStreamInformation] = []
        streams.reserveCapacity(streamCount)
        for ordinal in 0..<streamCount {
            var raw = PBFFmpegMediaStreamInfo()
            var codecName = [CChar](repeating: 0, count: 64)
            var language = [CChar](repeating: 0, count: 64)
            var title = [CChar](repeating: 0, count: 256)
            var colorPrimaries = [CChar](repeating: 0, count: 64)
            var transferFunction = [CChar](repeating: 0, count: 64)
            var yCbCrMatrix = [CChar](repeating: 0, count: 64)
            var colorRange = [CChar](repeating: 0, count: 64)
            var projectionKind = [CChar](repeating: 0, count: 64)
            guard PBFFmpegMediaSourceInformationCopyStream(
                handle,
                Int32(ordinal),
                &raw,
                &codecName,
                codecName.count,
                &language,
                language.count,
                &title,
                title.count,
                &colorPrimaries,
                colorPrimaries.count,
                &transferFunction,
                transferFunction.count,
                &yCbCrMatrix,
                yCbCrMatrix.count,
                &colorRange,
                colorRange.count,
                &projectionKind,
                projectionKind.count
            ) else {
                throw MediaSourceInformationError.copyStream(ordinal)
            }
            let category = streamCategory(raw.category)
            let video = category == .video
                ? MediaSourceVideoInformation(
                    width: Int(raw.width),
                    height: Int(raw.height),
                    nominalFrameRate: raw.nominalFrameRate,
                    colorPrimaries: string(colorPrimaries) ?? "unknown",
                    transferFunction: string(transferFunction) ?? "unknown",
                    yCbCrMatrix: string(yCbCrMatrix) ?? "unknown",
                    colorRange: string(colorRange) ?? "unknown",
                    projectionKind: string(projectionKind) ?? "unknown"
                )
                : nil
            let audio = category == .audio
                ? MediaSourceAudioInformation(
                    sampleRate: Int(raw.sampleRate),
                    channelCount: Int(raw.channelCount)
                )
                : nil
            streams.append(MediaSourceStreamInformation(
                streamIndex: Int(raw.streamIndex),
                category: category,
                codecID: Int32(raw.codecID),
                codecName: string(codecName) ?? "unknown",
                codecTag: raw.codecTag,
                language: string(language),
                title: string(title),
                disposition: Int32(raw.disposition),
                video: video,
                audio: audio
            ))
        }
        return MediaSourceInformation(
            containerFormat: String(
                cString: PBFFmpegMediaSourceInformationGetContainerFormat(handle)
            ),
            durationSeconds: PBFFmpegMediaSourceInformationGetDurationSeconds(handle),
            streams: streams
        )
    }

    private static func streamCategory(
        _ value: PBFFmpegMediaStreamCategory
    ) -> MediaSourceStreamCategory {
        switch value {
        case PBFFmpegMediaStreamCategoryVideo: .video
        case PBFFmpegMediaStreamCategoryAudio: .audio
        case PBFFmpegMediaStreamCategorySubtitle: .subtitle
        default: .other
        }
    }

    private static func string(_ buffer: [CChar]) -> String? {
        let value = String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        return value.isEmpty ? nil : value
    }
}

enum MediaSourceInformationError: LocalizedError, Sendable {
    case open(String)
    case copyStream(Int)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Open media source information: \(message)"
        case .copyStream(let ordinal): "Copy media stream information: ordinal \(ordinal)"
        }
    }
}

extension MediaSourceInformation {
    var playbackAudioTracks: [PlaybackAudioTrack] {
        streams.compactMap { stream in
            guard stream.category == .audio,
                  stream.supportsPlaybackAudio,
                  let audio = stream.audio else { return nil }
            return PlaybackAudioTrack(
                streamIndex: stream.streamIndex,
                codecName: stream.codecName,
                sampleRate: audio.sampleRate,
                channelCount: audio.channelCount,
                language: stream.language,
                title: stream.title
            )
        }
    }

    var playbackSubtitleTracks: [PlaybackSubtitleTrack] {
        streams.compactMap { stream in
            guard stream.category == .subtitle,
                  stream.supportsPlaybackSubtitle else { return nil }
            return PlaybackSubtitleTrack(
                id: "ffmpeg.subtitle.\(stream.streamIndex)",
                streamIndex: stream.streamIndex,
                codecName: stream.codecName,
                language: stream.language,
                title: stream.title
            )
        }
    }
}

private extension MediaSourceStreamInformation {
    var supportsPlaybackAudio: Bool {
        guard let audio, audio.sampleRate > 0, audio.channelCount > 0 else { return false }
        return [
            "aac", "ac3", "eac3", "mp2", "mp3", "alac", "opus", "flac", "apac",
        ].contains(codecName) || codecName.hasPrefix("pcm_")
    }

    var supportsPlaybackSubtitle: Bool {
        [
            "ass", "ssa", "subrip", "webvtt", "mov_text", "hdmv_pgs_subtitle",
            "dvd_subtitle", "dvb_subtitle",
        ].contains(codecName)
    }
}
