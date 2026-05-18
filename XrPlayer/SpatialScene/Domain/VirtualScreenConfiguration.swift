import Foundation

extension SpatialSceneDomain {
    public struct VirtualScreenConfiguration: Sendable, Equatable {
        public var geometry: ScreenGeometry

        public init(geometry: ScreenGeometry = .flat(width: 2.4, height: 1.35)) {
            switch geometry {
            case .flat(let w, let h):
                let clampedWidth = min(max(w, 1.0), 10.0)
                self.geometry = .flat(width: clampedWidth, height: h)
            case .curved:
                self.geometry = geometry
            }
        }

        public var aspectRatio: Float {
            switch geometry {
            case .flat(let w, let h):
                guard h > 0 else { return 0 }
                return w / h
            case .curved(let r, let h):
                guard h > 0 else { return 0 }
                let arcWidth = r * (2 * Float.pi / 3)
                return arcWidth / h
            }
        }

        public func switchToCurved(radius: Float) -> VirtualScreenConfiguration {
            VirtualScreenConfiguration(geometry: .curved(radius: radius, height: geometry.height))
        }
    }
}
