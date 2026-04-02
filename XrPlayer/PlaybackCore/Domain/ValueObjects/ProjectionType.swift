import Foundation

extension PlaybackCoreDomain {
    public enum ProjectionType: String, Sendable, CaseIterable, Codable {
        case flat
        case stereoscopicSBS
        case stereoscopicOU
        case panorama360
        case panorama180
        case fisheye

        public var isPanoramic: Bool {
            switch self {
            case .panorama360, .panorama180, .fisheye:
                return true
            case .flat, .stereoscopicSBS, .stereoscopicOU:
                return false
            }
        }

        public var isStereo3D: Bool {
            switch self {
            case .stereoscopicSBS, .stereoscopicOU: true
            default: false
            }
        }

        public var requiresHemisphereMesh: Bool {
            self == .panorama180
        }

        public var requiresFisheyeRemap: Bool {
            self == .fisheye
        }
    }
}
