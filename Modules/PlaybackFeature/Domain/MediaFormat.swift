import Foundation
import MediaSource

public enum MediaFormatProvenance: String, Codable, Sendable, Equatable {
    case source
    case userOverride
}

public enum MediaProjection: String, CaseIterable, Codable, Sendable {
    case flat
    case equirectangular180
    case equirectangular360
    case customAngle

    public var isPanoramic: Bool { self != .flat }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = switch value {
        case Self.equirectangular180.rawValue: .equirectangular180
        case Self.equirectangular360.rawValue: .equirectangular360
        case Self.customAngle.rawValue: .customAngle
        // Older builds exposed an Apple-metadata-specific option that is no
        // longer a user-selectable projection. Preserve playback by opening it
        // as ordinary rectangular video.
        case "fisheye": .flat
        default: .flat
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum PanoramaHorizontalCoverage {
    public static let range = 180...360
    public static let step = 10
    public static let defaultCustomAngle = 200
    public static let selectableAngles = Array(
        stride(from: range.lowerBound, through: range.upperBound, by: step)
    )

    public static func normalized(_ degrees: Int) -> Int {
        let clamped = min(max(degrees, range.lowerBound), range.upperBound)
        let offset = clamped - range.lowerBound
        return range.lowerBound + Int((Double(offset) / Double(step)).rounded()) * step
    }
}

public enum MediaStereoLayout: String, CaseIterable, Codable, Sendable {
    case mono
    case sideBySide
    case topBottom
}

public struct MediaFormat: Codable, Equatable, Sendable {
    public var projection: MediaProjection
    public var horizontalFieldOfViewDegrees: Int?
    public var stereoLayout: MediaStereoLayout
    public var usesDolbyVisionFallback: Bool

    public init(
        projection: MediaProjection,
        horizontalFieldOfViewDegrees: Int? = nil,
        stereoLayout: MediaStereoLayout,
        usesDolbyVisionFallback: Bool = false
    ) {
        self.projection = projection
        self.horizontalFieldOfViewDegrees = switch projection {
        case .flat:
            nil
        case .equirectangular180:
            180
        case .equirectangular360:
            360
        case .customAngle:
            PanoramaHorizontalCoverage.normalized(
                horizontalFieldOfViewDegrees
                    ?? PanoramaHorizontalCoverage.defaultCustomAngle
            )
        }
        self.stereoLayout = stereoLayout
        self.usesDolbyVisionFallback = usesDolbyVisionFallback
    }

    private enum CodingKeys: String, CodingKey {
        case projection
        case horizontalFieldOfViewDegrees
        case stereoLayout
        case usesDolbyVisionFallback
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projection: try values.decode(MediaProjection.self, forKey: .projection),
            horizontalFieldOfViewDegrees: try values.decodeIfPresent(
                Int.self,
                forKey: .horizontalFieldOfViewDegrees
            ),
            stereoLayout: try values.decode(MediaStereoLayout.self, forKey: .stereoLayout),
            usesDolbyVisionFallback: try values.decodeIfPresent(
                Bool.self,
                forKey: .usesDolbyVisionFallback
            ) ?? false
        )
    }

    public static let standard = Self(projection: .flat, stereoLayout: .mono)
}

/// Immutable media-signaling facts captured when the current source opens.
/// User interpretation never mutates these values; Automatic resolves back to
/// this fact instead of manufacturing a flat fallback.
public struct SourceMediaFormatFact: Equatable, Sendable {
    public let contentKind: PlaybackModel.SourceVideoContentKind
    public let projection: PlaybackModel.ProjectionType
    public let horizontalFieldOfViewDegrees: Int?
    public let stereoLayout: PlaybackModel.StereoLayout

    public init(
        contentKind: PlaybackModel.SourceVideoContentKind,
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int? = nil,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        self.contentKind = contentKind
        self.projection = projection
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.stereoLayout = stereoLayout
    }
}

/// The single session-facing interpretation used by both source signaling and
/// a persisted user override. Presentation policy consumes this value without
/// re-reading mutable runtime fields.
public struct EffectiveMediaFormatInterpretation: Equatable, Sendable {
    public let source: SourceMediaFormatFact
    public let provenance: MediaFormatProvenance
    public let projection: PlaybackModel.ProjectionType
    public let horizontalFieldOfViewDegrees: Int?
    public let stereoLayout: PlaybackModel.StereoLayout
    public let usesDolbyVisionFallback: Bool

    public var isPanoramic: Bool {
        provenance == .source ? source.contentKind.isPanoramic : projection.isPanoramic
    }

    public var requestsSpatialVideoMode: Bool {
        provenance == .source && source.contentKind == .spatialVideo
    }

    public init(
        source: SourceMediaFormatFact,
        provenance: MediaFormatProvenance,
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int?,
        stereoLayout: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool = false
    ) {
        self.source = source
        self.provenance = provenance
        self.projection = projection
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.stereoLayout = stereoLayout
        self.usesDolbyVisionFallback = usesDolbyVisionFallback
    }
}

/// Resolves source facts and an optional user override through one pure rule.
/// Passing `nil` is the meaning of Automatic.
public enum MediaFormatInterpretationResolver {
    public static func resolve(
        source: SourceMediaFormatFact,
        `override` formatOverride: MediaFormat?
    ) -> EffectiveMediaFormatInterpretation {
        guard let formatOverride else {
            return EffectiveMediaFormatInterpretation(
                source: source,
                provenance: .source,
                projection: source.projection,
                horizontalFieldOfViewDegrees: source.horizontalFieldOfViewDegrees,
                stereoLayout: source.stereoLayout,
                usesDolbyVisionFallback: false
            )
        }

        return EffectiveMediaFormatInterpretation(
            source: source,
            provenance: .userOverride,
            projection: projection(from: formatOverride.projection),
            horizontalFieldOfViewDegrees: formatOverride.horizontalFieldOfViewDegrees,
            stereoLayout: stereoLayout(from: formatOverride.stereoLayout),
            usesDolbyVisionFallback: formatOverride.usesDolbyVisionFallback
        )
    }

    private static func projection(
        from projection: MediaProjection
    ) -> PlaybackModel.ProjectionType {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func stereoLayout(
        from stereoLayout: MediaStereoLayout
    ) -> PlaybackModel.StereoLayout {
        switch stereoLayout {
        case .mono: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }
}

public struct MediaFormatPreference: Codable, Equatable, Sendable {
    public let versionedIdentity: VersionedMediaIdentity
    public let format: MediaFormat
    public let updatedAt: Date

    public init(
        versionedIdentity: VersionedMediaIdentity,
        format: MediaFormat,
        updatedAt: Date = Date()
    ) {
        self.versionedIdentity = versionedIdentity
        self.format = format
        self.updatedAt = updatedAt
    }
}

public enum MediaFormatPolicy {
    public static func normalized(_ format: MediaFormat) -> MediaFormat {
        MediaFormat(
            projection: format.projection,
            horizontalFieldOfViewDegrees: format.horizontalFieldOfViewDegrees,
            stereoLayout: format.stereoLayout,
            usesDolbyVisionFallback: format.usesDolbyVisionFallback
        )
    }
}
