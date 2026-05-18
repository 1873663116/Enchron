import Foundation

extension SpatialSceneDomain {
    public enum ScreenGeometry: Sendable, Equatable, Codable {
        case flat(width: Float, height: Float)
        case curved(radius: Float, height: Float)

        public var height: Float {
            switch self {
            case .flat(_, let h), .curved(_, let h): return h
            }
        }
    }
}
