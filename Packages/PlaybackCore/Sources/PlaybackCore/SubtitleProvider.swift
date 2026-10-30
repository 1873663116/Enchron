import CoreMedia
import Foundation
import OSLog
import PlaybackFFmpegBridge

private let logger = Logger(
    subsystem: "com.xiongzhipeng.PlaybackCore",
    category: "Playback"
)

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
        title
            ?? language.flatMap(PlaybackLanguageName.display)
            ?? "Subtitle \(streamIndex)"
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

struct PreparedSubtitleTrack: Sendable {
    let track: PlaybackSubtitleTrack
    let cues: [PlaybackSubtitleCue]
    let renderer: SubtitleFrameRendering?
}

struct PreparedExternalSubtitleSource: Sendable {
    let source: PlaybackExternalSubtitleSource
    let tracks: [PreparedSubtitleTrack]
}

extension PlaybackSubtitleTrack {
    func externalTrack(in source: PlaybackExternalSubtitleSource) -> PlaybackSubtitleTrack {
        PlaybackSubtitleTrack(
            id: "external.subtitle.\(source.id).\(streamIndex)",
            streamIndex: streamIndex,
            codecName: codecName,
            language: language,
            title: title ?? source.displayName
        )
    }
}

protocol SubtitleProvider: AnyObject {
    func prepareExternalSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> PreparedExternalSubtitleSource
    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack]
    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
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
    func discardFrameRenderer(trackID: String)
    func cancel()
}

extension SubtitleProvider {
    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack,
        startSeconds: Double
    ) async throws -> [PlaybackSubtitleCue] {
        try await cues(in: url, asset: asset, track: track)
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack,
        startSeconds: Double
    ) async throws -> SubtitleFrameRendering? {
        try await frameRenderer(in: url, asset: asset, track: track)
    }

    func discardFrameRenderer(trackID: String) {}

    func prepareExternalSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> PreparedExternalSubtitleSource {
        let tracks = try await probeTracks(in: source.url, asset: nil)
        guard !tracks.isEmpty else {
            throw PlaybackControlError.externalSubtitleHasNoSupportedTracks(source.displayName)
        }
        var prepared: [PreparedSubtitleTrack] = []
        for track in tracks {
            try Task.checkCancellation()
            let externalTrack = track.externalTrack(in: source)
            let cues = try await cues(
                in: source.url,
                asset: nil,
                track: externalTrack,
                startSeconds: 0
            )
            let renderer = try await frameRenderer(
                in: source.url,
                asset: nil,
                track: externalTrack,
                startSeconds: 0
            )
            prepared.append(PreparedSubtitleTrack(track: externalTrack, cues: cues, renderer: renderer))
        }
        try Task.checkCancellation()
        return PreparedExternalSubtitleSource(source: source, tracks: prepared)
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
    ) async throws -> [PlaybackSubtitleTrack] {
        try await probeTracks(in: url, asset: asset)
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? { nil }
}

final class NoSubtitleProvider: SubtitleProvider {
    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] { [] }

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

    func prepareExternalSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> PreparedExternalSubtitleSource {
        let tracks = try await probeTracks(in: source.url, asset: nil)
        try Task.checkCancellation()
        guard !tracks.isEmpty else {
            throw PlaybackControlError.externalSubtitleHasNoSupportedTracks(source.displayName)
        }
        var prepared: [PreparedSubtitleTrack] = []
        for track in tracks {
            let externalTrack = track.externalTrack(in: source)
            let cancellation = FFmpegReadCancellation()
            let ready = try await withTaskCancellationHandler {
                let prepared = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<PreparedSubtitleTrack, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async { [sourceReadMeter] in
                        do {
                            let renderer = try FFmpegSubtitleFrameRenderer(
                                url: source.url,
                                track: externalTrack,
                                sourceReadMeter: sourceReadMeter,
                                cancellation: cancellation
                            )
                            let cues = try renderer.textCues(for: externalTrack)
                            let frameRenderer: SubtitleFrameRendering =
                                if CoreTextSubtitleFrameRenderer.rendersTextTrack(codecName: externalTrack.codecName) {
                                    try CoreTextSubtitleFrameRenderer(source: renderer, track: externalTrack)
                                } else {
                                    renderer
                                }
                            continuation.resume(returning: PreparedSubtitleTrack(
                                track: externalTrack,
                                cues: cues,
                                renderer: frameRenderer
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                try Task.checkCancellation()
                return prepared
            } onCancel: {
                cancellation.cancel()
            }
            prepared.append(ready)
        }
        try Task.checkCancellation()
        return PreparedExternalSubtitleSource(source: source, tracks: prepared)
    }

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
        informationLoader = SystemMediaSourceInformationLoader(
            sourceReadMeter: sourceReadMeter
        )
    }

    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackSubtitleTrack] {
        (try? await informationLoader.load(from: url))?.playbackSubtitleTracks ?? []
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
    ) async throws -> [PlaybackSubtitleTrack] {
        if let description { return description.subtitleTracks }
        return try await probeTracks(in: url, asset: asset)
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> [PlaybackSubtitleCue] {
        try await cues(in: url, asset: asset, track: track, startSeconds: 0)
    }

    func cues(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack,
        startSeconds: Double
    ) async throws -> [PlaybackSubtitleCue] {
        let source = FFmpegSourceLocator.argument(for: url)
        if let demuxSession, demuxSession.isOpen(for: source) {
            let existing = rendererLock.withLock { sharedRenderers[track.id] }
            let renderer = try existing ?? FFmpegSubtitleFrameRenderer(
                demuxSession: demuxSession,
                source: source,
                track: track,
                startSeconds: startSeconds
            )
            rendererLock.withLock {
                sharedRenderers[track.id] = renderer
            }
            return try renderer.textCues(for: track)
        }
        let cancellation = FFmpegReadCancellation()
        return try await withTaskCancellationHandler {
            try self.documentCues(source: source, track: track, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func documentCues(
        source: String,
        track: PlaybackSubtitleTrack,
        cancellation: FFmpegReadCancellation
    ) throws -> [PlaybackSubtitleCue] {
        var error = [CChar](repeating: 0, count: 512)
        let reader: OpaquePointer? = source.withCString { path in
            PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
                path,
                Int32(track.streamIndex),
                &error,
                error.count,
                sourceReadMeter.bridgeMonitor,
                cancellation.handle
            )
        }
        guard let reader else {
            try Task.checkCancellation()
            throw SubtitleProviderError.open(Self.errorMessage(error))
        }
        defer { PBFFmpegSubtitleReaderDestroy(reader) }
        let subtitleStart = PBFFmpegSubtitleReaderGetStartTimestampSeconds(reader)
        let openSummary = "subtitle.reader.open track=\(track.id) stream=\(track.streamIndex)"
            + " start=\(String(format: "%.3f", subtitleStart))"
        logger.info("\(openSummary, privacy: .public)")

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
                if let first = cues.first {
                    let start = String(format: "%.3f", first.timeRange.start.seconds)
                    let end = String(format: "%.3f", first.timeRange.end.seconds)
                    let summary = "subtitle.cues.first track=\(track.id) count=\(cues.count)"
                        + " start=\(start) end=\(end)"
                    logger.info("\(summary, privacy: .public)")
                }
                return cues
            default:
                try Task.checkCancellation()
                throw SubtitleProviderError.read(Self.errorMessage(error))
            }
        }
    }

    func discardFrameRenderer(trackID: String) {
        rendererLock.withLock { sharedRenderers[trackID] = nil }
    }

    func cancel() {
        rendererLock.withLock { sharedRenderers.removeAll() }
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack
    ) async throws -> SubtitleFrameRendering? {
        try await frameRenderer(in: url, asset: asset, track: track, startSeconds: 0)
    }

    func frameRenderer(
        in url: URL,
        asset: PlaybackAsset?,
        track: PlaybackSubtitleTrack,
        startSeconds: Double
    ) async throws -> SubtitleFrameRendering? {
        let source = FFmpegSourceLocator.argument(for: url)
        let renderer: FFmpegSubtitleFrameRenderer?
        if let demuxSession, demuxSession.isOpen(for: source) {
            let existing = rendererLock.withLock { sharedRenderers[track.id] }
            if let existing {
                renderer = existing
            } else {
                let created = try FFmpegSubtitleFrameRenderer(
                    demuxSession: demuxSession,
                    source: source,
                    track: track,
                    startSeconds: startSeconds
                )
                rendererLock.withLock { sharedRenderers[track.id] = created }
                renderer = created
            }
        } else {
            let cancellation = FFmpegReadCancellation()
            renderer = try await withTaskCancellationHandler {
                try FFmpegSubtitleFrameRenderer(
                    url: url,
                    track: track,
                    sourceReadMeter: self.sourceReadMeter,
                    cancellation: cancellation
                )
            } onCancel: {
                cancellation.cancel()
            }
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

enum SubtitleProviderError: LocalizedError, Sendable, Equatable {
    case open(String)
    case read(String)
    case preparationTimedOut

    var errorDescription: String? {
        switch self {
        case .open(let message): "Open subtitle provider: \(message)"
        case .read(let message): "Read subtitle provider: \(message)"
        case .preparationTimedOut: "Subtitle preparation timed out."
        }
    }
}
