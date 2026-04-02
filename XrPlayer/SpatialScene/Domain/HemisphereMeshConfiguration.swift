import Foundation

extension SpatialSceneDomain {
    public struct HemisphereMeshConfiguration: Sendable, Equatable {
        public let stacks: Int
        public let slices: Int
        public let radius: Float

        public init(stacks: Int = 64, slices: Int = 64, radius: Float = 10.0) {
            self.stacks = stacks
            self.slices = slices
            self.radius = radius
        }

        /// Stub: returns 0...0 → U range test FAIL.
        public var uRange: ClosedRange<Float> { 0...0 }

        /// Stub: returns 0...0 → longitude range test FAIL.
        public var longitudeRange: ClosedRange<Float> { 0...0 }

        /// Stub: returns 0 → vertex count test FAIL.
        public var vertexCount: Int { 0 }

        /// Stub: returns 0...0 → V range test FAIL.
        public var vRange: ClosedRange<Float> { 0...0 }
    }
}
