import Foundation
import VideoToolbox

public enum StreamResolution: String, Sendable, Codable, CaseIterable {
    case r1920x1080
    case r2560x1440
    case r3840x2160
    case r2560x1600

    /// The display spelling of a resolution, e.g. `2560x1440`.
    public var displayValue: String {
        "\(width)x\(height)"
    }

    /// Reads a resolution from either its case name or its display spelling.
    public static func parsed(_ raw: String) -> StreamResolution? {
        if let value = StreamResolution(rawValue: raw) {
            return value
        }
        return allCases.first { $0.displayValue == raw }
    }

    public var width: Int {
        switch self {
        case .r1920x1080: 1920
        case .r2560x1440: 2560
        case .r3840x2160: 3840
        case .r2560x1600: 2560
        }
    }

    public var height: Int {
        switch self {
        case .r1920x1080: 1080
        case .r2560x1440: 1440
        case .r3840x2160: 2160
        case .r2560x1600: 1600
        }
    }

    public var label: String {
        "\(width) × \(height)"
    }
}

public enum StreamCodecPreference: String, Sendable, Codable, CaseIterable {
    case auto
    case hevc
    case h264
    case av1

    public var label: String {
        switch self {
        case .auto: "自动"
        case .hevc: "HEVC"
        case .h264: "H.264"
        case .av1: "AV1"
        }
    }
}

public struct StreamOptions: Sendable, Equatable, Codable {
    public var resolution: StreamResolution
    public var frameRate: Int
    public var bitrateKbps: Int
    public var codec: StreamCodecPreference
    public var hdrEnabled: Bool
    public var framePacing: Bool

    public static let defaultFrameRates = [60, 90, 120]
    public static let bitrateRangeMbps = 10...100

    public init(
        resolution: StreamResolution = .r2560x1440,
        frameRate: Int = 90,
        bitrateKbps: Int = 40_000,
        codec: StreamCodecPreference = .hevc,
        hdrEnabled: Bool = true,
        framePacing: Bool = true
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.codec = codec
        self.hdrEnabled = hdrEnabled
        self.framePacing = framePacing
    }

    public var readableValue: String {
        var parts: [String] = []
        parts.append("resolution=\(resolution.displayValue)")
        parts.append("fps=\(frameRate)")
        parts.append("bitrate=\(bitrateKbps)")
        parts.append("codec=\(codec.rawValue)")
        parts.append("hdr=\(hdrEnabled)")
        parts.append("framePacing=\(framePacing)")
        return parts.joined(separator: ";")
    }
}

public enum StreamCodecAvailability {
    public static var av1DecodeSupported: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }
}

extension StreamOptions {
    /// The codec this device can actually play back.
    ///
    /// A stored preference can name a codec the current device cannot decode,
    /// and a session built from it connects and then never presents a frame.
    /// Resolving on the way in keeps a stale preference from disabling streaming
    /// with no visible cause.
    public mutating func resolveCodecAvailability() {
        if codec == .av1, StreamCodecAvailability.av1DecodeSupported == false {
            codec = .hevc
        }
    }
}

public final class StreamSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "enchron.streaming.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> StreamOptions {
        guard
            let data = defaults.data(forKey: key),
            var options = try? JSONDecoder().decode(StreamOptions.self, from: data)
        else {
            return StreamOptions()
        }
        options.resolveCodecAvailability()
        return options
    }

    public func save(_ options: StreamOptions) {
        guard let data = try? JSONEncoder().encode(options) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
