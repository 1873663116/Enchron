import Foundation

public nonisolated enum PlaybackModel {}


nonisolated extension PlaybackModel {
    /// Describes the immutable presentation metadata discovered in the source.
    /// User projection overrides deliberately remain a separate type.
    public enum SourceVideoContentKind: String, Sendable, Equatable, Codable {
        case rectilinear
        case spatialVideo
        case halfEquirectangular
        case equirectangular
        case parametricImmersive
        case appleImmersiveVideo

        public var isPanoramic: Bool {
            switch self {
            case .halfEquirectangular, .equirectangular, .parametricImmersive,
                    .appleImmersiveVideo:
                true
            case .rectilinear, .spatialVideo:
                false
            }
        }

        public var displayName: String {
            switch self {
            case .rectilinear: "Flat"
            case .spatialVideo: "Spatial Video"
            case .halfEquirectangular: "180°"
            case .equirectangular: "360°"
            case .parametricImmersive: "Wide FOV"
            case .appleImmersiveVideo: "Apple Immersive Video"
            }
        }
    }
}


nonisolated extension PlaybackModel {
    public enum HDRType: String, Sendable, CaseIterable, Codable {
        case sdr
        case hdr10
        case hdr10Plus
        case dolbyVision
        case hlg
    }
}


nonisolated extension PlaybackModel {
    /// The Dolby Vision a source claims, alongside the picture it actually produced.
    ///
    /// `HDRType` cannot carry this on its own. It names one dynamic range, and a
    /// Profile 7 source has two answers at once: it is Dolby Vision, and what reaches
    /// the wearer is its base layer. The profile is stored separately from the layers
    /// because the layers are what decide the fallback, while the profile number is
    /// only a name.
    public struct DolbyVision: Sendable, Equatable, Codable {
        public let profile: Int
        public let level: Int
        /// The picture delivered in place of Dolby Vision, set only when the source
        /// stores its picture across two layers and just the base layer arrives.
        public let fallbackTo: HDRType?

        public init(profile: Int, level: Int, fallbackTo: HDRType? = nil) {
            self.profile = profile
            self.level = level
            self.fallbackTo = fallbackTo
        }

        /// Reads the way the rest of the dynamic range labels do, so a title that fell
        /// back sits in the same sentence as one that did not.
        public var label: String {
            let name = "Dolby Vision Profile \(profile).\(level)"
            guard let fallbackTo else { return name }
            return "\(name) Fallback to \(fallbackTo.label)"
        }
    }
}


nonisolated extension PlaybackModel.HDRType {
    public var label: String {
        switch self {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }
}


nonisolated extension PlaybackModel {
    public enum ProjectionType: String, Sendable, CaseIterable, Codable {
        case flat
        case equirectangular360
        case equirectangular180
        case customAngle

        public var isPanoramic: Bool {
            switch self {
            case .equirectangular360, .equirectangular180, .customAngle:
                return true
            case .flat:
                return false
            }
        }

        public var requiresHemisphereMesh: Bool {
            self == .equirectangular180
        }

        public var usesCustomPanoramaAngle: Bool { self == .customAngle }
    }
}


nonisolated extension PlaybackModel {
    public enum StereoLayout: String, Sendable, CaseIterable, Codable {
        case mono
        case multiview
        case sideBySide
        case topBottom

        public static let userSelectableCases: [Self] = [
            .mono,
            .sideBySide,
            .topBottom,
        ]

        public struct UVRect: Sendable, Equatable {
            public let originX: Float
            public let originY: Float
            public let width: Float
            public let height: Float

            public init(originX: Float, originY: Float, width: Float, height: Float) {
                self.originX = originX
                self.originY = originY
                self.width = width
                self.height = height
            }
        }

        public var leftEyeUVRect: UVRect {
            switch self {
            case .mono, .multiview:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 0.5)
            }
        }

        public var rightEyeUVRect: UVRect {
            switch self {
            case .mono, .multiview:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0.5, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0.5, width: 1.0, height: 0.5)
            }
        }

        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            switch self {
            case .mono, .multiview:
                (inputWidth, inputHeight)
            case .sideBySide:
                (inputWidth / 2, inputHeight)
            case .topBottom:
                (inputWidth, inputHeight / 2)
            }
        }

        public func outputDisplayDimensions(
            inputWidth: Int,
            inputHeight: Int,
            pixelAspectRatio: MediaProfile.PixelAspectRatio
        ) -> MediaProfile.DisplayDimensions {
            let pixelDimensions = outputDimensions(
                inputWidth: inputWidth,
                inputHeight: inputHeight
            )
            return MediaProfile.DisplayDimensions(
                width: Double(pixelDimensions.width)
                    * Double(pixelAspectRatio.horizontalSpacing)
                    / Double(pixelAspectRatio.verticalSpacing),
                height: Double(pixelDimensions.height)
            )
        }
    }
}


nonisolated extension PlaybackModel {
    public struct AudioTrack: Sendable, Equatable, Identifiable {
        public let id: String
        public let languageCode: String?
        public let displayName: String
        public let isDefault: Bool

        public init(id: String, languageCode: String?, displayName: String, isDefault: Bool = false) {
            self.id = id
            self.languageCode = languageCode
            self.displayName = displayName
            self.isDefault = isDefault
        }
    }
}


nonisolated extension PlaybackModel {
    public struct SubtitleTrack: Sendable, Equatable, Identifiable {
        public let id: String
        public let languageCode: String?
        public let displayName: String
        public let isDefault: Bool

        public init(id: String, languageCode: String?, displayName: String, isDefault: Bool = false) {
            self.id = id
            self.languageCode = languageCode
            self.displayName = displayName
            self.isDefault = isDefault
        }
    }
}


nonisolated extension PlaybackModel {
    public struct MediaProfile: Sendable, Equatable, Codable {
        public struct PixelAspectRatio: Sendable, Equatable, Codable {
            public static let square = PixelAspectRatio(
                horizontalSpacing: 1,
                verticalSpacing: 1
            )

            public let horizontalSpacing: Int
            public let verticalSpacing: Int

            public init(horizontalSpacing: Int, verticalSpacing: Int) {
                if horizontalSpacing > 0, verticalSpacing > 0 {
                    self.horizontalSpacing = horizontalSpacing
                    self.verticalSpacing = verticalSpacing
                } else {
                    self = .square
                }
            }
        }

        public struct DisplayDimensions: Sendable, Equatable {
            public let width: Double
            public let height: Double

            public init(width: Double, height: Double) {
                self.width = max(0, width)
                self.height = max(0, height)
            }
        }

        public struct Resolution: Sendable, Equatable, Codable {
            public let width: Int
            public let height: Int

            public init(width: Int, height: Int) {
                self.width = max(0, width)
                self.height = max(0, height)
            }
        }

        public let projectionType: ProjectionType
        public let stereoLayout: StereoLayout
        /// The dynamic range of the picture that reaches the wearer. A Profile 7
        /// source reports the base layer here and its Dolby Vision claim in
        /// `dolbyVision`.
        public let hdrType: HDRType
        public let dolbyVision: DolbyVision?
        public let resolution: Resolution
        private let sampleAspectRatio: PixelAspectRatio?
        public let frameRate: Double
        public let videoCodec: String?
        public let durationSeconds: Double?
        public let hasCoverArt: Bool

        public init(
            projectionType: ProjectionType,
            stereoLayout: StereoLayout = .mono,
            hdrType: HDRType,
            dolbyVision: DolbyVision? = nil,
            resolution: Resolution,
            pixelAspectRatio: PixelAspectRatio = .square,
            frameRate: Double = 0,
            videoCodec: String? = nil,
            durationSeconds: Double? = nil,
            hasCoverArt: Bool = false
        ) {
            self.projectionType = projectionType
            self.stereoLayout = stereoLayout
            self.hdrType = hdrType
            self.dolbyVision = dolbyVision
            self.resolution = resolution
            sampleAspectRatio = pixelAspectRatio == .square ? nil : pixelAspectRatio
            self.frameRate = max(0, frameRate)
            self.videoCodec = videoCodec
            self.durationSeconds = durationSeconds
            self.hasCoverArt = hasCoverArt
        }

        public var pixelAspectRatio: PixelAspectRatio {
            sampleAspectRatio ?? .square
        }

        public func displayDimensions(for stereoLayout: StereoLayout) -> DisplayDimensions {
            stereoLayout.outputDisplayDimensions(
                inputWidth: resolution.width,
                inputHeight: resolution.height,
                pixelAspectRatio: pixelAspectRatio
            )
        }
    }
}


public nonisolated protocol MediaProfileDetecting: AnyObject {
    func didDetectMediaProfile(_ profile: PlaybackModel.MediaProfile)
}
