import Foundation

extension PlaybackCoreDomain {
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
        public let hdrType: HDRType
        public let resolution: Resolution
        public let frameRate: Double

        public init(
            projectionType: ProjectionType,
            hdrType: HDRType,
            resolution: Resolution,
            frameRate: Double = 0
        ) {
            self.projectionType = projectionType
            self.hdrType = hdrType
            self.resolution = resolution
            self.frameRate = max(0, frameRate)
        }
    }
}
