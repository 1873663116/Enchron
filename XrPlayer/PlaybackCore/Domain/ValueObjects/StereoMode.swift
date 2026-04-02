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

        /// Stub: returns zero rect → left eye UV tests FAIL.
        public var leftEyeUVRect: UVRect {
            UVRect(originX: 0, originY: 0, width: 0, height: 0)
        }

        /// Stub: returns zero rect → right eye UV tests FAIL.
        public var rightEyeUVRect: UVRect {
            UVRect(originX: 0, originY: 0, width: 0, height: 0)
        }

        /// Stub: returns (0, 0) → output dimensions tests FAIL.
        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            (0, 0)
        }
    }
}
