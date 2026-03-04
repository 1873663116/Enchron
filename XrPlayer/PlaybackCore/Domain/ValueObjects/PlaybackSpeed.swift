import Foundation

extension PlaybackCoreDomain {
    public struct PlaybackSpeed: Sendable, Equatable, Hashable {
        public let value: Double

        public init(_ value: Double) {
            self.value = min(max(value, 0.25), 5.0)
        }

        public static let `default` = PlaybackSpeed(1.0)
    }
}
