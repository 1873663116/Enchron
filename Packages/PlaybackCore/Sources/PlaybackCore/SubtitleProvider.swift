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

public struct PlaybackExternalSubtitleSource: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let displayName: String

    public init(id: String, url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
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
    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) async throws -> [PlaybackSubtitleTrack]
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
    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) async throws -> [PlaybackSubtitleTrack] {
        try await tracks(in: url, asset: asset)
    }

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
    private let sourceReadMeter: PlaybackSourceReadMeter
    private let demuxSession: FFmpegDemuxSession?
    private let informationLoader: SystemMediaSourceInformationLoader
    private let rendererLock = NSLock()
    private var sharedRenderers: [PlaybackSubtitleTrack.ID: FFmpegSubtitleFrameRenderer] = [:]

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
        informationLoader = SystemMediaSourceInformationLoader(
            sourceReadMeter: sourceReadMeter,
            demuxSession: demuxSession
        )
    }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] {
        (try? await informationLoader.load(from: url))?.playbackSubtitleTracks ?? []
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        sourceInformation: MediaSourceInformation?
    ) async throws -> [PlaybackSubtitleTrack] {
        if let sourceInformation { return sourceInformation.playbackSubtitleTracks }
        return try await tracks(in: url, asset: asset)
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        var error = [CChar](repeating: 0, count: 512)
        let source = FFmpegSourceLocator.argument(for: url)
        if let demuxSession, demuxSession.isOpen(for: source) {
            let existing = rendererLock.withLock { sharedRenderers[track.id] }
            let renderer = try existing ?? FFmpegSubtitleFrameRenderer(
                demuxSession: demuxSession,
                source: source,
                track: track
            )
            rendererLock.withLock {
                sharedRenderers[track.id] = renderer
            }
            return try renderer.textCues(for: track)
        }
        let reader: OpaquePointer?
        reader = source.withCString { path in
            PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
                path,
                Int32(track.streamIndex),
                &error,
                error.count,
                sourceReadMeter.bridgeMonitor
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

    func cancel() {
        rendererLock.withLock { sharedRenderers.removeAll() }
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? {
        let source = FFmpegSourceLocator.argument(for: url)
        let renderer: FFmpegSubtitleFrameRenderer?
        if let demuxSession, demuxSession.isOpen(for: source) {
            renderer = rendererLock.withLock { sharedRenderers[track.id] }
        } else {
            renderer = try FFmpegSubtitleFrameRenderer(url: url, track: track)
        }
        guard let renderer else { return nil }
        if CoreTextSubtitleFrameRenderer.rendersTextTrack(codecName: track.codecName) {
            return try CoreTextSubtitleFrameRenderer(source: renderer, track: track)
        }
        return renderer
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
