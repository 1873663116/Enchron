import Foundation

nonisolated extension PlaybackCoreDomain {
    public enum StereoLayout: String, Sendable, CaseIterable, Codable {
        case mono
        case sideBySide
        case topBottom

        public struct UVRect: Sendable, Equatable {
            public let originX: Float
            public let originY: Float
            public let width: Float
            public let height: Float

            public init(originX: Float, originY: Float, width: Float, height: Float) {
                self.originX = originX
                self.originY = originY
                self.width = width
                self.height = height
            }
        }

        public var leftEyeUVRect: UVRect {
            switch self {
            case .mono:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 0.5)
            }
        }

        public var rightEyeUVRect: UVRect {
            switch self {
            case .mono:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 1.0)
            case .sideBySide:
                UVRect(originX: 0.5, originY: 0, width: 0.5, height: 1.0)
            case .topBottom:
                UVRect(originX: 0, originY: 0.5, width: 1.0, height: 0.5)
            }
        }

        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            switch self {
            case .mono:
                (inputWidth, inputHeight)
            case .sideBySide:
                (inputWidth / 2, inputHeight)
            case .topBottom:
                (inputWidth, inputHeight / 2)
            }
        }
    }
}
