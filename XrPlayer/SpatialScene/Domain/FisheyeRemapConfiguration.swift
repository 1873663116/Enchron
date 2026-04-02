import Foundation

extension SpatialSceneDomain {
    public struct FisheyeRemapConfiguration: Sendable, Equatable {
        public let fovRadiusRadians: Float

        public init(fovRadiusRadians: Float = Float.pi / 2) {
            self.fovRadiusRadians = fovRadiusRadians
        }

        /// Map output equirectangular UV to input fisheye UV.
        /// Returns nil if the sample point is outside the FOV.
        ///
        /// Algorithm: output UV → spherical (lon, lat) → 3D direction → equidistant fisheye projection.
        public func sampleCoordinate(outputU: Float, outputV: Float) -> (u: Float, v: Float)? {
            let longitude = (outputU - 0.5) * 2.0 * Float.pi
            let latitude = (0.5 - outputV) * Float.pi

            let cosLat = cos(latitude)
            let x = cosLat * sin(longitude)
            let y = sin(latitude)
            let z = cosLat * cos(longitude)

            // Angle from optical axis (+Z)
            let theta = acos(min(max(z, -1.0), 1.0))

            guard theta <= fovRadiusRadians else { return nil }

            guard theta > 1e-7 else {
                return (u: 0.5, v: 0.5)
            }

            // Equidistant projection: radial distance proportional to angle
            let r = (theta / fovRadiusRadians) * 0.5
            let phi = atan2(y, x)

            let fishU = 0.5 + r * cos(phi)
            let fishV = 0.5 + r * sin(phi)

            return (u: fishU, v: fishV)
        }
    }
}
