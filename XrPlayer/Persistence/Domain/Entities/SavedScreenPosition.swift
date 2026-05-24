import Foundation

nonisolated extension PersistenceDomain {
    public struct SavedScreenPosition: Sendable, Equatable {
        public let environmentID: String
        public let distanceMeters: Double
        public let verticalOffsetMeters: Double
        public let viewAngleDegrees: Double

        public init(
            environmentID: String,
            distanceMeters: Double,
            verticalOffsetMeters: Double,
            viewAngleDegrees: Double
        ) {
            self.environmentID = environmentID
            self.distanceMeters = min(max(distanceMeters, 2.0), 20.0)
            self.verticalOffsetMeters = min(max(verticalOffsetMeters, -5.0), 5.0)
            self.viewAngleDegrees = min(max(viewAngleDegrees, -45.0), 45.0)
        }
    }
}
