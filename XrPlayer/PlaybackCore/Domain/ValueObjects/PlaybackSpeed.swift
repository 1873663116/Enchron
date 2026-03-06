import Foundation

extension PlaybackCoreDomain {
    public struct PlaybackSpeed: Sendable, Equatable, Hashable {
        public let value: Double

        public init(_ value: Double) {
            self.value = min(max(value, 0.25), 5.0)
        }

        public static let `default` = PlaybackSpeed(1.0)
        public static let speed0_5 = PlaybackSpeed(0.5)
        public static let speed0_75 = PlaybackSpeed(0.75)
        public static let speed1_0 = PlaybackSpeed(1.0)
        public static let speed1_25 = PlaybackSpeed(1.25)
        public static let speed1_5 = PlaybackSpeed(1.5)
        public static let speed2_0 = PlaybackSpeed(2.0)
        
        public static let allCases: [PlaybackSpeed] = [
            .speed0_5, .speed0_75, .speed1_0, .speed1_25, .speed1_5, .speed2_0
        ]
    }
}
