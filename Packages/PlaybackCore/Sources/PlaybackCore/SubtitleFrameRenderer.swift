import CoreMedia
import Foundation
import PlaybackFFmpegBridge

public enum PlaybackSubtitleFrameKind: String, Sendable, Equatable {
    case libass
    case bitmap
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
}

final class FFmpegSubtitleFrameRenderer: SubtitleFrameRendering, @unchecked Sendable {
    private let renderer: OpaquePointer
    private let lock = NSLock()

    init(url: URL, track: PlaybackSubtitleTrack) throws {
        var error = [CChar](repeating: 0, count: 512)
        let renderer = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBSubtitleFrameRendererCreate(
                path,
                Int32(track.streamIndex),
                &error,
                error.count
            )
        }
        guard let renderer else {
            throw SubtitleProviderError.open(Self.errorMessage(error))
        }
        self.renderer = renderer
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

    private static func errorMessage(_ buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}
