import CoreMedia
import Foundation
import PlaybackFFmpegBridge

public struct PlaybackSubtitleTrack: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let streamIndex: Int
    public let codecName: String
    public let language: String?
    public let title: String?

    public init(
        id: String,
        streamIndex: Int,
        codecName: String,
        language: String?,
        title: String?
    ) {
        self.id = id
        self.streamIndex = streamIndex
        self.codecName = codecName
        self.language = language
        self.title = title
    }

    public var label: String {
        title ?? language ?? "Subtitle \(streamIndex)"
    }
}

public struct PlaybackSubtitleCue: Identifiable, Sendable, Equatable {
    public let id: String
    public let trackID: PlaybackSubtitleTrack.ID
    public let timeRange: CMTimeRange
    public let text: String

    public init(
        id: String,
        trackID: PlaybackSubtitleTrack.ID,
        timeRange: CMTimeRange,
        text: String
    ) {
        self.id = id
        self.trackID = trackID
        self.timeRange = timeRange
        self.text = text
    }
}

protocol SubtitleProvider: AnyObject {
    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack]
    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue]
    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering?
    func cancel()
}

extension SubtitleProvider {
    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? { nil }
}

final class NoSubtitleProvider: SubtitleProvider {
    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] { [] }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] { [] }

    func cancel() {}
}

final class FFmpegSubtitleProvider: SubtitleProvider {
    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] {
        let argument = FFmpegSourceLocator.argument(for: url)
        return argument.withCString { path in
            let count = max(0, Int(PBFFmpegSubtitleTrackCount(path)))
            return (0..<count).compactMap { ordinal in
                var streamIndex: Int32 = -1
                var codec = [CChar](repeating: 0, count: 64)
                var language = [CChar](repeating: 0, count: 64)
                var title = [CChar](repeating: 0, count: 256)
                guard PBFFmpegSubtitleTrackCopyInfo(
                    path,
                    Int32(ordinal),
                    &streamIndex,
                    &codec,
                    codec.count,
                    &language,
                    language.count,
                    &title,
                    title.count
                ) else { return nil }
                let index = Int(streamIndex)
                return PlaybackSubtitleTrack(
                    id: "ffmpeg.subtitle.\(index)",
                    streamIndex: index,
                    codecName: Self.string(codec) ?? "unknown",
                    language: Self.string(language),
                    title: Self.string(title)
                )
            }
        }
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        var error = [CChar](repeating: 0, count: 512)
        let reader = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBFFmpegSubtitleReaderCreate(
                path,
                Int32(track.streamIndex),
                &error,
                error.count
            )
        }
        guard let reader else {
            throw SubtitleProviderError.open(Self.errorMessage(error))
        }
        defer { PBFFmpegSubtitleReaderDestroy(reader) }

        var cues: [PlaybackSubtitleCue] = []
        while true {
            try Task.checkCancellation()
            var startSeconds = 0.0
            var durationSeconds = 0.0
            var cueText: Unmanaged<CFString>?
            let result = PBFFmpegSubtitleReaderCopyNextCue(
                reader,
                &startSeconds,
                &durationSeconds,
                &cueText,
                &error,
                error.count
            )
            switch result {
            case PBFFmpegReadResultSample:
                guard let cueText else {
                    throw SubtitleProviderError.read("SubRip cue text is unavailable")
                }
                let text = (cueText.takeRetainedValue() as String)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                let start = CMTime(seconds: startSeconds, preferredTimescale: 60_000)
                let duration = CMTime(seconds: durationSeconds, preferredTimescale: 60_000)
                cues.append(PlaybackSubtitleCue(
                    id: "\(track.id).cue.\(cues.count)",
                    trackID: track.id,
                    timeRange: CMTimeRange(start: start, duration: duration),
                    text: text
                ))
            case PBFFmpegReadResultEnd:
                return cues
            default:
                throw SubtitleProviderError.read(Self.errorMessage(error))
            }
        }
    }

    func cancel() {}

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? {
        try FFmpegSubtitleFrameRenderer(url: url, track: track)
    }

    private static func string(_ buffer: [CChar]) -> String? {
        let value = errorMessage(buffer)
        return value.isEmpty ? nil : value
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}

enum SubtitleProviderError: LocalizedError, Sendable {
    case open(String)
    case read(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Open subtitle provider: \(message)"
        case .read(let message): "Read subtitle provider: \(message)"
        }
    }
}
