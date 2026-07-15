import Foundation

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
