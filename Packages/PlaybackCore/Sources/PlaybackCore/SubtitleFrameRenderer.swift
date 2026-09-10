import CoreMedia
import Foundation
import PlaybackFFmpegBridge

public enum PlaybackSubtitleFrameKind: String, Sendable, Equatable {
    case libass
    case bitmap
    case coreText
}

public struct PlaybackSubtitleFrame: Sendable, Equatable {
    public let kind: PlaybackSubtitleFrameKind
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let contentX: Int
    public let contentY: Int
    public let contentWidth: Int
    public let contentHeight: Int
    public let bytesPerRow: Int
    public let premultipliedBGRA: Data
    public let changeIdentifier: UInt64

    public init(
        kind: PlaybackSubtitleFrameKind,
        canvasWidth: Int,
        canvasHeight: Int,
        contentX: Int,
        contentY: Int,
        contentWidth: Int,
        contentHeight: Int,
        bytesPerRow: Int,
        premultipliedBGRA: Data,
        changeIdentifier: UInt64
    ) {
        self.kind = kind
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.contentX = contentX
        self.contentY = contentY
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.bytesPerRow = bytesPerRow
        self.premultipliedBGRA = premultipliedBGRA
        self.changeIdentifier = changeIdentifier
    }
}

protocol SubtitleFrameRendering: AnyObject, Sendable {
    func frame(at time: CMTime, viewportWidth: Int, viewportHeight: Int) throws -> PlaybackSubtitleFrame?
    func ingestPendingCues(for track: PlaybackSubtitleTrack) throws -> [PlaybackSubtitleCue]
    // What the renderer is holding, for telling apart the ways a bitmap track
    // can come up empty. Empty for renderers that hold nothing of the kind.
    var stateDescription: String { get }
    // True while packets have been decoded and none of them produced a display
    // set: a track that is present, arriving and unreadable.
    var holdsUndecodablePackets: Bool { get }
}

extension SubtitleFrameRendering {
    func ingestPendingCues(for track: PlaybackSubtitleTrack) throws -> [PlaybackSubtitleCue] { [] }
    var stateDescription: String { "" }
    var holdsUndecodablePackets: Bool { false }
}

final class FFmpegSubtitleFrameRenderer: SubtitleFrameRendering, @unchecked Sendable {
    private let renderer: OpaquePointer
    private let lock = NSLock()
    private let demuxSession: FFmpegDemuxSession?
    private var exportedTextCueCount = 0

    init(
        url: URL,
        track: PlaybackSubtitleTrack,
        sourceReadMeter: PlaybackSourceReadMeter,
        cancellation: FFmpegReadCancellation
    ) throws {
        var error = [CChar](repeating: 0, count: 512)
        let renderer = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBSubtitleFrameRendererCreate(
                path,
                Int32(track.streamIndex),
                sourceReadMeter.bridgeMonitor,
                cancellation.handle,
                &error,
                error.count
            )
        }
        guard let renderer else {
            throw SubtitleProviderError.open(Self.errorMessage(error))
        }
        self.renderer = renderer
        demuxSession = nil
    }

    init(
        demuxSession: FFmpegDemuxSession,
        source: String,
        track: PlaybackSubtitleTrack
    ) throws {
        var error = [CChar](repeating: 0, count: 512)
        let renderer = try demuxSession.withSource(argument: source) {
            PBSubtitleFrameRendererCreateWithDemuxSource(
                $0,
                Int32(track.streamIndex),
                &error,
                error.count
            )
        }
        guard let renderer else {
            throw SubtitleProviderError.open(Self.errorMessage(error))
        }
        self.renderer = renderer
        self.demuxSession = demuxSession
    }

    deinit {
        PBSubtitleFrameRendererDestroy(renderer)
    }

    func frame(
        at time: CMTime,
        viewportWidth: Int = 1_920,
        viewportHeight: Int = 1_080
    ) throws -> PlaybackSubtitleFrame? {
        guard time.isNumeric else { return nil }
        return try lock.withLock {
            var data: Unmanaged<CFData>?
            var info = PBSubtitleFrameInfo()
            var error = [CChar](repeating: 0, count: 512)
            let result = PBSubtitleFrameRendererCopyFrame(
                renderer,
                time.seconds,
                Int32(viewportWidth),
                Int32(viewportHeight),
                &data,
                &info,
                &error,
                error.count
            )
            switch result {
            case PBSubtitleFrameResultFrame:
                guard let data else {
                    throw SubtitleProviderError.read("Subtitle frame data is unavailable")
                }
                let bytes = data.takeRetainedValue() as Data
                return PlaybackSubtitleFrame(
                    kind: info.kind == PBSubtitleFrameKindBitmap ? .bitmap : .libass,
                    canvasWidth: Int(info.canvasWidth),
                    canvasHeight: Int(info.canvasHeight),
                    contentX: Int(info.contentX),
                    contentY: Int(info.contentY),
                    contentWidth: Int(info.contentWidth),
                    contentHeight: Int(info.contentHeight),
                    bytesPerRow: Int(info.bytesPerRow),
                    premultipliedBGRA: bytes,
                    changeIdentifier: info.changeIdentifier
                )
            case PBSubtitleFrameResultEmpty:
                return nil
            default:
                throw SubtitleProviderError.read(Self.errorMessage(error))
            }
        }
    }

    // Packets this renderer has put through the subtitle decoder, for tests and
    // diagnostics that need to tell a lookup apart from a decode.
    var decodedPacketCount: UInt64 {
        lock.withLock { PBSubtitleFrameRendererGetDecodedPacketCount(renderer) }
    }

    var holdsUndecodablePackets: Bool {
        let state = lock.withLock { PBSubtitleFrameRendererCopyState(renderer) }
        return state.decodedPacketCount > 0 && state.displaySetCount == 0
    }

    var stateDescription: String {
        let state = lock.withLock { PBSubtitleFrameRendererCopyState(renderer) }
        func seconds(_ value: Double) -> String {
            value.isFinite ? String(format: "%.3f", value) : "none"
        }
        return "ingested=\(state.ingestedPacketCount)"
            + " held=\(state.heldPacketCount)"
            + " decoded=\(state.decodedPacketCount)"
            + " displaySets=\(state.displaySetCount)"
            + " cursor=\(state.decodeCursor)"
            + " packetSpan=\(seconds(state.firstPacketSeconds))..\(seconds(state.lastPacketSeconds))"
            + " covered=\(seconds(state.coveredStartSeconds))..\(seconds(state.coveredEndSeconds))"
            + " lastPacket=size:\(state.lastPacketSize)"
            + ",pts:\(state.lastPacketHasPresentationTime != 0)"
            + ",segment:\(state.lastPacketSegmentType)/\(state.lastPacketSegmentLength)"
            + " lastDecode=result:\(state.lastDecodeResult)"
            + ",produced:\(state.lastDecodeProduced)"
            + ",rects:\(state.lastSubtitleRectCount)"
            + ",format:\(state.lastSubtitleFormat)"
            + ",display:\(state.lastSubtitleStartDisplayTime)..\(state.lastSubtitleEndDisplayTime)"
    }

    func textCues(for track: PlaybackSubtitleTrack) throws -> [PlaybackSubtitleCue] {
        try lock.withLock {
            let count = Int(PBSubtitleFrameRendererGetTextCueCount(renderer))
            exportedTextCueCount = count
            return try textCues(for: track, in: 0..<count)
        }
    }

    func ingestPendingCues(for track: PlaybackSubtitleTrack) throws -> [PlaybackSubtitleCue] {
        guard demuxSession != nil else { return [] }
        return try lock.withLock {
            var error = [CChar](repeating: 0, count: 512)
            guard PBSubtitleFrameRendererIngestAvailablePackets(
                renderer,
                &error,
                error.count
            ) >= 0 else {
                throw SubtitleProviderError.read(Self.errorMessage(error))
            }
            let count = Int(PBSubtitleFrameRendererGetTextCueCount(renderer))
            guard count > exportedTextCueCount else { return [] }
            defer { exportedTextCueCount = count }
            return try textCues(for: track, in: exportedTextCueCount..<count)
        }
    }

    private func textCues(
        for track: PlaybackSubtitleTrack,
        in indices: Range<Int>
    ) throws -> [PlaybackSubtitleCue] {
        try indices.map { index in
                var startSeconds = 0.0
                var durationSeconds = 0.0
                var text: Unmanaged<CFString>?
                guard PBSubtitleFrameRendererCopyTextCue(
                    renderer,
                    Int32(index),
                    &startSeconds,
                    &durationSeconds,
                    &text
                ), let text else {
                    throw SubtitleProviderError.read(
                        "Subtitle cue \(index) is unavailable"
                    )
                }
                let start = CMTime(seconds: startSeconds, preferredTimescale: 60_000)
                let duration = CMTime(seconds: durationSeconds, preferredTimescale: 60_000)
                return PlaybackSubtitleCue(
                    id: "\(track.id).cue.\(index)",
                    trackID: track.id,
                    timeRange: CMTimeRange(start: start, duration: duration),
                    text: (text.takeRetainedValue() as String)
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                )
        }
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}
