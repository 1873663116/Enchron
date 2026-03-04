import Foundation

extension PersistenceDomain {
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
            self.distanceMeters = distanceMeters
            self.verticalOffsetMeters = verticalOffsetMeters
            self.viewAngleDegrees = viewAngleDegrees
        }
    }
}
