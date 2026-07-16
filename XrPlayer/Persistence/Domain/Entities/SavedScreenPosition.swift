import Foundation

nonisolated extension PersistenceDomain {
    public struct SavedScreenPosition: Sendable, Equatable {
        public let environmentID: String
        public let depthOffsetMeters: Double
        public let verticalOffsetMeters: Double
        public let viewAngleDegrees: Double
        public let screenScale: Double

        public init(
            environmentID: String,
            depthOffsetMeters: Double,
            verticalOffsetMeters: Double,
            viewAngleDegrees: Double,
            screenScale: Double
        ) {
            self.environmentID = environmentID
            self.depthOffsetMeters = min(max(depthOffsetMeters, -2.0), 2.0)
            self.verticalOffsetMeters = min(max(verticalOffsetMeters, -5.0), 5.0)
            self.viewAngleDegrees = min(max(viewAngleDegrees, -45.0), 45.0)
            self.screenScale = min(max(screenScale, 0.5), 2.5)
        }
    }
}
