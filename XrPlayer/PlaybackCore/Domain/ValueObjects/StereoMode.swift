import Foundation

extension PlaybackCoreDomain {
    public enum StereoMode: String, Sendable, CaseIterable, Codable {
        case sideBySide
        case overUnder

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
            case .sideBySide:
                UVRect(originX: 0, originY: 0, width: 0.5, height: 1.0)
            case .overUnder:
                UVRect(originX: 0, originY: 0, width: 1.0, height: 0.5)
            }
        }

        public var rightEyeUVRect: UVRect {
            switch self {
            case .sideBySide:
                UVRect(originX: 0.5, originY: 0, width: 0.5, height: 1.0)
            case .overUnder:
                UVRect(originX: 0, originY: 0.5, width: 1.0, height: 0.5)
            }
        }

        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            switch self {
            case .sideBySide:
                (inputWidth / 2, inputHeight)
            case .overUnder:
                (inputWidth, inputHeight / 2)
            }
        }
    }
}
