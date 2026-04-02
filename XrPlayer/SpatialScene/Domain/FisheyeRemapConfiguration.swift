import Foundation

extension SpatialSceneDomain {
    public struct FisheyeRemapConfiguration: Sendable, Equatable {
        public let fovRadiusRadians: Float

        /// Stub: default FOV = 0 instead of π/2 → FOV test FAIL.
        public init(fovRadiusRadians: Float = 0) {
            self.fovRadiusRadians = fovRadiusRadians
        }

        /// Map output UV to input UV using fisheye → equirectangular transform.
        /// Returns nil if the sample point is outside the FOV.
        /// Stub: always returns nil → center mapping test FAIL.
        public func sampleCoordinate(outputU: Float, outputV: Float) -> (u: Float, v: Float)? {
            nil
        }
    }
}
