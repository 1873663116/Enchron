import Foundation
import PlaybackFFmpegBridge

final class FFmpegDemuxSession: @unchecked Sendable {
    private let operationLock = NSLock()
    private let sourceLock = NSLock()
    private let sourceReadMeter: PlaybackSourceReadMeter
    private var source: OpaquePointer?
    private var sourceArgument: String?
    private var sourceTransport: PlaybackSourceTransport = .localFile
    private var bufferConfiguration = PBFFmpegDemuxBufferConfigurationMake(
        PBFFmpegDemuxBufferModeNone,
        0
    )

    init(sourceReadMeter: PlaybackSourceReadMeter) {
        self.sourceReadMeter = sourceReadMeter
    }

    func configureSource(transport: PlaybackSourceTransport) throws {
        try operationLock.withLock {
            guard source == nil else {
                if sourceTransport != transport {
                    throw FFmpegDemuxSessionError.sourceChanged
                }
                return
            }
            sourceTransport = transport
            bufferConfiguration = try .playbackConfiguration(
                for: transport.bufferPreference
            )
        }
    }

    deinit {
        let source = sourceLock.withLock {
            defer {
                self.source = nil
            }
            return self.source
        }
        guard let source else { return }
        PlaybackTrace.event("demux.destroy.begin")
        PBFFmpegDemuxSourceDestroy(source)
        PlaybackTrace.event("demux.destroy.end")
    }

    func withSource<T>(
        argument: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try operationLock.withLock {
            if let source = sourceLock.withLock({ source }) {
                guard sourceArgument == argument else {
                    throw FFmpegDemuxSessionError.sourceChanged
                }
                return try body(source)
            }
            var error = [CChar](repeating: 0, count: 512)
            PlaybackTrace.event("demux.open.begin remote=\(sourceTransport.isRemote)")
            let opened = argument.withCString {
                PBFFmpegDemuxSourceCreate(
                    $0,
                    sourceTransport.isRemote,
                    bufferConfiguration,
                    sourceReadMeter.bridgeMonitor,
                    &error,
                    error.count
                )
            }
            PlaybackTrace.event("demux.open.end ok=\(opened != nil)")
            guard let opened else {
                let message = ffmpegErrorMessage(error)
                PlaybackTrace.event("demux.open.failed error=\(message)")
                throw FFmpegDemuxSessionError.open(message)
            }
            sourceLock.withLock { source = opened }
            sourceArgument = argument
            return try body(opened)
        }
    }

    func seek(to seconds: Double) throws {
        try operationLock.withLock {
            guard let source = sourceLock.withLock({ source }) else {
                throw FFmpegDemuxSessionError.notOpen
            }
            var error = [CChar](repeating: 0, count: 512)
            PlaybackTrace.event("demux.seek.begin seconds=\(seconds)")
            let sought = PBFFmpegDemuxSourceSeek(
                source,
                seconds,
                &error,
                error.count
            )
            PlaybackTrace.event("demux.seek.end ok=\(sought)")
            guard sought else {
                throw FFmpegDemuxSessionError.seek(ffmpegErrorMessage(error))
            }
        }
    }

    func interrupt() {
        guard let source = sourceLock.withLock({ source }) else { return }
        PlaybackTrace.event("demux.interrupt")
        PBFFmpegDemuxSourceInterrupt(source)
    }

    func isOpen(for argument: String) -> Bool {
        operationLock.withLock {
            sourceLock.withLock { source != nil } && sourceArgument == argument
        }
    }

    func bufferDiagnostics() -> PlaybackDemuxBufferDiagnostics? {
        guard let source = sourceLock.withLock({ source }) else { return nil }
        let mode = switch PBFFmpegDemuxSourceGetBufferMode(source) {
        case PBFFmpegDemuxBufferModeAutomatic:
            PlaybackDemuxBufferDiagnostics.Mode.automatic
        case PBFFmpegDemuxBufferModeBytes:
            PlaybackDemuxBufferDiagnostics.Mode.bytes
        default:
            PlaybackDemuxBufferDiagnostics.Mode.none
        }
        return PlaybackDemuxBufferDiagnostics(
            mode: mode,
            bufferedDurationSeconds: PBFFmpegDemuxSourceGetBufferedDurationSeconds(source),
            targetDurationSeconds: PBFFmpegDemuxSourceGetBufferTargetDurationSeconds(source),
            forwardBufferedBytes: PBFFmpegDemuxSourceGetForwardBufferedByteCount(source),
            forwardLimitBytes: PBFFmpegDemuxSourceGetForwardBufferByteLimit(source),
            auxiliaryBufferedBytes:
                PBFFmpegDemuxSourceGetAuxiliaryBufferedByteCount(source),
            backwardBufferedBytes: PBFFmpegDemuxSourceGetRetainedByteCount(source),
            backwardLimitBytes: PBFFmpegDemuxSourceGetBackwardBufferByteLimit(source),
            reconnectAttemptCount: PBFFmpegDemuxSourceGetReconnectAttemptCount(source),
            readFrameCount: PBFFmpegDemuxSourceGetReadFrameCount(source)
        )
    }
}

enum FFmpegDemuxSessionError: LocalizedError, Sendable {
    case notOpen
    case sourceChanged
    case open(String)
    case seek(String)

    var errorDescription: String? {
        switch self {
        case .notOpen: "The shared FFmpeg source is not open"
        case .sourceChanged: "The shared FFmpeg source cannot change while readers are attached"
        case .open(let message): "Open shared FFmpeg source: \(message)"
        case .seek(let message): "Seek shared FFmpeg source: \(message)"
        }
    }
}
