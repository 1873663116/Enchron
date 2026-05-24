import Foundation

nonisolated extension PlaybackCoreDomain {
    public struct PlaybackPosition: Sendable, Equatable {
        public let seconds: Double
        public let duration: Double

        public init(seconds: Double, duration: Double) {
            self.seconds = max(0, seconds)
            self.duration = max(0, duration)
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(seconds / duration, 0), 1)
        }
    }
}
