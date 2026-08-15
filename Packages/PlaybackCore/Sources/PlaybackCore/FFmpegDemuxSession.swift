import Foundation
import PlaybackFFmpegBridge

final class FFmpegDemuxSession: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceReadMeter: PlaybackSourceReadMeter
    private var source: OpaquePointer?
    private var sourceArgument: String?

    init(sourceReadMeter: PlaybackSourceReadMeter) {
        self.sourceReadMeter = sourceReadMeter
    }

    deinit {
        let source = lock.withLock {
            defer {
                self.source = nil
                sourceArgument = nil
            }
            return self.source
        }
        if let source { PBFFmpegDemuxSourceDestroy(source) }
    }

    func withSource<T>(
        argument: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try lock.withLock {
            if let source {
                guard sourceArgument == argument else {
                    throw FFmpegDemuxSessionError.sourceChanged
                }
                return try body(source)
            }
            var error = [CChar](repeating: 0, count: 512)
            let opened = argument.withCString {
                PBFFmpegDemuxSourceCreate(
                    $0,
                    sourceReadMeter.bridgeMonitor,
                    &error,
                    error.count
                )
            }
            guard let opened else {
                throw FFmpegDemuxSessionError.open(ffmpegErrorMessage(error))
            }
            source = opened
            sourceArgument = argument
            return try body(opened)
        }
    }

    func seek(to seconds: Double) throws {
        try lock.withLock {
            guard let source else { throw FFmpegDemuxSessionError.notOpen }
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

    func isOpen(for argument: String) -> Bool {
        lock.withLock { source != nil && sourceArgument == argument }
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
