import Foundation
import VideoToolbox

public enum StreamResolution: String, Sendable, Codable, CaseIterable {
    case r1280x720
    case r1920x1080
    case r2560x1440
    case r3360x1440
    case r5120x1440
    case r3840x2160
    case custom

    public static let customWidthRange = 320...7680
    public static let customHeightRange = 240...4320

    public static let maximumPixelCount = 7680 * 4320

    /// The display spelling of a resolution, e.g. `2560x1440`.
    public var displayValue: String {
        "\(width)x\(height)"
    }

    /// Reads a resolution from either its case name or its display spelling.
    public static func parsed(_ raw: String) -> StreamResolution? {
        if let value = StreamResolution(rawValue: raw) {
            return value
        }
        if let match = allCases.first(where: { $0 != .custom && $0.displayValue == raw }) {
            return match
        }
        let parts = raw.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else { return nil }
        return .custom
    }

    public var width: Int {
        switch self {
        case .r1280x720: 1280
        case .r1920x1080: 1920
        case .r2560x1440: 2560
        case .r3360x1440: 3360
        case .r5120x1440: 5120
        case .r3840x2160: 3840
        case .custom: 2560
        }
    }

    public var height: Int {
        switch self {
        case .r1280x720: 720
        case .r1920x1080: 1080
        case .r2560x1440: 1440
        case .r3360x1440: 1440
        case .r5120x1440: 1440
        case .r3840x2160: 2160
        case .custom: 1440
        }
    }

    public var label: String {
        if self == .custom {
            return "自定义"
        }
        return "\(width) × \(height)"
    }

    public var pixelCount: Int {
        width * height
    }

    public static func isCustomDimensionsValid(width: Int, height: Int) -> Bool {
        guard customWidthRange.contains(width), customHeightRange.contains(height) else {
            return false
        }
        return width * height <= maximumPixelCount
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
    public var customWidth: Int
    public var customHeight: Int
    public var frameRate: Int
    public var bitrateKbps: Int
    public var codec: StreamCodecPreference
    public var hdrEnabled: Bool
    public var framePacing: Bool
    public var customBitrateEnabled: Bool

    public static let defaultFrameRates = [30, 60, 90, 120]

    /// Non-uniform so the low end stays fine grained where bandwidth is tight,
    /// matching how Moonlight lays out its bitrate ladder.
    public static let bitrateLadderMbps: [Int] = [
        5, 8, 10, 12, 15, 18, 20, 25, 30, 35, 40, 50, 60, 70, 80, 100, 120, 150, 200
    ]

    public static let bitrateRangeMbps = 5...200

    public static let customBitrateKbpsRange = 1_000...500_000

    public init(
        resolution: StreamResolution = .r2560x1440,
        customWidth: Int = 2560,
        customHeight: Int = 1440,
        frameRate: Int = 90,
        bitrateKbps: Int = 40_000,
        codec: StreamCodecPreference = .auto,
        hdrEnabled: Bool = false,
        framePacing: Bool = true,
        customBitrateEnabled: Bool = false
    ) {
        self.resolution = resolution
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.codec = codec
        self.hdrEnabled = hdrEnabled
        self.framePacing = framePacing
        self.customBitrateEnabled = customBitrateEnabled
    }

    public var streamWidth: Int {
        resolution == .custom ? customWidth : resolution.width
    }

    public var streamHeight: Int {
        resolution == .custom ? customHeight : resolution.height
    }

    private enum CodingKeys: String, CodingKey {
        case resolution, customWidth, customHeight, frameRate, bitrateKbps
        case codec, hdrEnabled, framePacing, customBitrateEnabled
    }

    /// Older stored settings predate custom resolutions, so a missing pair
    /// decodes to the default size instead of failing the whole record.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = (try? container.decodeIfPresent(StreamResolution.self, forKey: .resolution)) ?? .r2560x1440
        customWidth = try container.decodeIfPresent(Int.self, forKey: .customWidth) ?? 2560
        customHeight = try container.decodeIfPresent(Int.self, forKey: .customHeight) ?? 1440
        frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? 90
        bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? 40_000
        codec = try container.decodeIfPresent(StreamCodecPreference.self, forKey: .codec) ?? .auto
        hdrEnabled = try container.decodeIfPresent(Bool.self, forKey: .hdrEnabled) ?? false
        framePacing = try container.decodeIfPresent(Bool.self, forKey: .framePacing) ?? true
        customBitrateEnabled = try container.decodeIfPresent(Bool.self, forKey: .customBitrateEnabled) ?? false
    }

    public var readableValue: String {
        var parts: [String] = []
        parts.append("resolution=\(streamWidth)x\(streamHeight)")
        parts.append("fps=\(frameRate)")
        parts.append("bitrate=\(bitrateKbps)")
        parts.append("codec=\(codec.rawValue)")
        parts.append("hdr=\(hdrEnabled)")
        parts.append("framePacing=\(framePacing)")
        parts.append("customBitrate=\(customBitrateEnabled)")
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

    /// The host ignores HDR on an H.264 stream, so a stored combination of the
    /// two would show HDR as enabled on a picture that never carries it.
    public mutating func resolveHDRSupport() {
        if codec == .h264 {
            hdrEnabled = false
        }
    }

    public mutating func normalize() {
        resolveCodecAvailability()
        resolveHDRSupport()
        clampBitrate()
        clampCustomDimensions()
    }

    public mutating func clampCustomDimensions() {
        customWidth = min(max(customWidth, StreamResolution.customWidthRange.lowerBound),
                          StreamResolution.customWidthRange.upperBound)
        customHeight = min(max(customHeight, StreamResolution.customHeightRange.lowerBound),
                           StreamResolution.customHeightRange.upperBound)
        let maximum = StreamResolution.maximumPixelCount
        guard customWidth * customHeight > maximum else { return }
        customHeight = max(
            StreamResolution.customHeightRange.lowerBound,
            maximum / max(customWidth, 1)
        )
    }

    public mutating func clampBitrate() {
        guard customBitrateEnabled == false else {
            bitrateKbps = min(max(bitrateKbps, Self.customBitrateKbpsRange.lowerBound),
                               Self.customBitrateKbpsRange.upperBound)
            return
        }
        bitrateKbps = Self.nearestLadderMbps(bitrateKbps) * 1000
    }

    /// Moonlight's own suggestion, so the wearer does not have to guess which
    /// bitrate belongs to a resolution and frame rate.
    public func suggestedBitrateKbps() -> Int {
        let frameRateFactor = (frameRate <= 60 ? Double(frameRate) : (Double(frameRate) / 60).squareRoot() * 60) / 30
        let resolutionFactor = Self.resolutionFactor(pixels: streamWidth * streamHeight)
        return min(Int((resolutionFactor * frameRateFactor).rounded()) * 1000, 200_000)
    }

    private static func resolutionFactor(pixels: Int) -> Double {
        let table: [(pixels: Int, factor: Double)] = [
            (640 * 360, 1),
            (854 * 480, 2),
            (1280 * 720, 5),
            (1920 * 1080, 10),
            (2560 * 1440, 20),
            (3840 * 2160, 40)
        ]
        guard let first = table.first else { return 10 }
        if pixels <= first.pixels {
            return first.factor
        }
        for index in 1..<table.count where pixels < table[index].pixels {
            let low = table[index - 1]
            let high = table[index]
            let ratio = Double(pixels - low.pixels) / Double(high.pixels - low.pixels)
            return ratio * (high.factor - low.factor) + low.factor
        }
        return table[table.count - 1].factor
    }

    /// Snaps a bitrate onto the ladder entry a slider can actually reach.
    public static func nearestLadderMbps(_ kbps: Int) -> Int {
        let target = Double(kbps) / 1000
        return bitrateLadderMbps.min { abs(Double($0) - target) < abs(Double($1) - target) }
            ?? bitrateLadderMbps[1]
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
        options.normalize()
        save(options)
        return options
    }

    public func save(_ options: StreamOptions) {
        guard let data = try? JSONEncoder().encode(options) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
