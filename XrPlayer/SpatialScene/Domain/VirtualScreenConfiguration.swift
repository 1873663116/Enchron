import Foundation

extension SpatialSceneDomain {
    public struct VirtualScreenConfiguration: Sendable, Equatable {
        public var geometry: ScreenGeometry

        /// Stub: no clamping on init → width clamping tests FAIL.
        public init(geometry: ScreenGeometry = .flat(width: 0, height: 0)) {
            self.geometry = geometry
        }

        /// Stub: always returns 0 → aspect ratio test FAIL.
        public var aspectRatio: Float { 0 }

        /// Switch to curved shape, preserving height from current geometry.
        /// Stub: does NOT preserve height → shape switch test FAIL.
        public func switchToCurved(radius: Float) -> VirtualScreenConfiguration {
            VirtualScreenConfiguration(geometry: .curved(radius: radius, height: 0))
        }
    }
}
