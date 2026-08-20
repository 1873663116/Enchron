import Foundation
import PlaybackFFmpegBridge

final class FFmpegDemuxSession: @unchecked Sendable {
    private let operationLock = NSLock()
    private let sourceLock = NSLock()
    private let sourceReadMeter: PlaybackSourceReadMeter
    private var source: OpaquePointer?
    private var sourceArgument: String?
    private var sourceIsRemote = false

    init(sourceReadMeter: PlaybackSourceReadMeter) {
        self.sourceReadMeter = sourceReadMeter
    }

    func configureSource(isRemote: Bool) throws {
        try lock.withLock {
            guard source == nil else {
                if sourceIsRemote != isRemote {
                    throw FFmpegDemuxSessionError.sourceChanged
                }
                return
            }
            sourceIsRemote = isRemote
        }
    }

    deinit {
        let source = sourceLock.withLock {
            defer {
                self.source = nil
            }
            return self.source
        }
        if let source { PBFFmpegDemuxSourceDestroy(source) }
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
            let opened = argument.withCString {
                PBFFmpegDemuxSourceCreate(
                    $0,
                    sourceIsRemote,
                    sourceReadMeter.bridgeMonitor,
                    &error,
                    error.count
                )
            }
            guard let opened else {
                throw FFmpegDemuxSessionError.open(ffmpegErrorMessage(error))
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
            guard PBFFmpegDemuxSourceSeek(
                source,
                seconds,
                &error,
                error.count
            ) else {
                throw FFmpegDemuxSessionError.seek(ffmpegErrorMessage(error))
            }
        }
    }

    func interrupt() {
        guard let source = sourceLock.withLock({ source }) else { return }
        PBFFmpegDemuxSourceInterrupt(source)
    }

    func isOpen(for argument: String) -> Bool {
        operationLock.withLock {
            sourceLock.withLock { source != nil } && sourceArgument == argument
        }
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
