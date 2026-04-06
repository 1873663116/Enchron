import Foundation

extension PlaybackCoreDomain {
    public enum ProjectionType: String, Sendable, CaseIterable, Codable {
        case flat
        case equirectangular360
        case equirectangular180
        case fisheye

        public var isPanoramic: Bool {
            switch self {
            case .equirectangular360, .equirectangular180, .fisheye:
                return true
            case .flat:
                return false
            }
        }

        public var requiresHemisphereMesh: Bool {
            self == .equirectangular180
        }

        public var requiresFisheyeRemap: Bool {
            self == .fisheye
        }
    }
}
