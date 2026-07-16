import Foundation

public enum PlaybackRoute: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleCompressed
    case ffmpegCompressed

    public var id: Self { self }

    public var label: String {
        switch self {
        case .appleCompressed: "Apple Compressed"
        case .ffmpegCompressed: "FFmpeg Compressed"
        }
    }

    public var rendererInputKind: RendererInputKind {
        switch self {
        case .appleCompressed, .ffmpegCompressed: .compressed
        }
    }

}

public enum RendererInputKind: String, Codable, Sendable {
    case compressed
}
