import Foundation

nonisolated extension PersistenceDomain {
    public struct ProgressPosition: Sendable, Equatable {
        public let seconds: Double

        public init(seconds: Double) {
            self.seconds = max(0, seconds)
        }
    }
}
