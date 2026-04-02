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

        /// Front hemisphere UV range: U spans [0.25, 0.75] of equirectangular texture.
        public var uRange: ClosedRange<Float> { 0.25...0.75 }

        /// Front hemisphere longitude: -π/2 to π/2.
        public var longitudeRange: ClosedRange<Float> { (-Float.pi / 2)...(Float.pi / 2) }

        public var vertexCount: Int { (stacks + 1) * (slices + 1) }

        /// Full latitude range: V spans [0.0, 1.0] (pole to pole).
        public var vRange: ClosedRange<Float> { 0.0...1.0 }
    }
}
