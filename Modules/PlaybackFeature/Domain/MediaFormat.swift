import Foundation
import MediaSource

public enum MediaProjection: String, CaseIterable, Codable, Sendable {
    case flat
    case equirectangular180
    case equirectangular360
    case fisheye

    public var isPanoramic: Bool { self != .flat }
}

public enum MediaStereoLayout: String, CaseIterable, Codable, Sendable {
    case mono
    case sideBySide
    case topBottom
}

public struct MediaFormat: Codable, Equatable, Sendable {
    public var projection: MediaProjection
    public var stereoLayout: MediaStereoLayout

    public init(projection: MediaProjection, stereoLayout: MediaStereoLayout) {
        self.projection = projection
        self.stereoLayout = stereoLayout
    }

    public static let standard = Self(projection: .flat, stereoLayout: .mono)
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

public enum MediaFormatValidationError: Error, Equatable, Sendable {
    case fisheyeRequiresAIME
}

public enum MediaFormatPolicy {
    public static func validate(_ format: MediaFormat, hasAIME: Bool) throws {
        if format.projection == .fisheye, hasAIME == false {
            throw MediaFormatValidationError.fisheyeRequiresAIME
        }
    }
}
