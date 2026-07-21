import Foundation

public nonisolated enum PlaybackModel {}


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
    public enum ProjectionType: String, Sendable, CaseIterable, Codable {
        case flat
        case equirectangular360
        case equirectangular180
        case fisheye

        public var isPanoramic: Bool {
            switch self {
            case .equirectangular360, .equirectangular180, .fisheye:
                return true
            case .flat:
                return false
            }
        }

        public var requiresHemisphereMesh: Bool {
            self == .equirectangular180
        }

        public var requiresFisheyeRemap: Bool {
            self == .fisheye
        }
    }
}


nonisolated extension PlaybackModel {
    public enum StereoLayout: String, Sendable, CaseIterable, Codable {
        case mono
        case sideBySide
        case topBottom

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
            case .mono:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 0.5)
            }
        }

        public var rightEyeUVRect: UVRect {
            switch self {
            case .mono:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0.5, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0.5, width: 1.0, height: 0.5)
            }
        }

        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            switch self {
            case .mono:
                (inputWidth, inputHeight)
            case .sideBySide:
                (inputWidth / 2, inputHeight)
            case .topBottom:
                (inputWidth, inputHeight / 2)
            }
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
    public struct MediaFile: Sendable, Equatable {
        public let url: URL
        public let containerFormat: String
        public let audioTracks: [AudioTrack]
        public let subtitleTracks: [SubtitleTrack]

        public init(
            url: URL,
            containerFormat: String,
            audioTracks: [AudioTrack] = [],
            subtitleTracks: [SubtitleTrack] = []
        ) {
            self.url = url
            self.containerFormat = containerFormat
            self.audioTracks = audioTracks
            self.subtitleTracks = subtitleTracks
        }
    }
}


nonisolated extension PlaybackModel {
    public struct MediaProfile: Sendable, Equatable, Codable {
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
        public let hdrType: HDRType
        public let resolution: Resolution
        public let frameRate: Double
        public let videoCodec: String?
        public let durationSeconds: Double?
        public let hasCoverArt: Bool

        public init(
            projectionType: ProjectionType,
            stereoLayout: StereoLayout = .mono,
            hdrType: HDRType,
            resolution: Resolution,
            frameRate: Double = 0,
            videoCodec: String? = nil,
            durationSeconds: Double? = nil,
            hasCoverArt: Bool = false
        ) {
            self.projectionType = projectionType
            self.stereoLayout = stereoLayout
            self.hdrType = hdrType
            self.resolution = resolution
            self.frameRate = max(0, frameRate)
            self.videoCodec = videoCodec
            self.durationSeconds = durationSeconds
            self.hasCoverArt = hasCoverArt
        }
    }
}


public nonisolated protocol MediaProfileDetecting: AnyObject {
    func didDetectMediaProfile(_ profile: PlaybackModel.MediaProfile)
}

