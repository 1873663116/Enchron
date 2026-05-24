import CoreVideo
import Foundation

public nonisolated enum VideoToolboxBridgeError: Error, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case poolCreationFailed(OSStatus)
    case pixelBufferCreationFailed(OSStatus)
    case unsupportedPacketLayout
}

public nonisolated final class VideoToolboxBridge: @unchecked Sendable {
    public static let hwdecOptionValue = "videotoolbox"
    public static let hwdecCodecs = "all"

    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    private let pixelFormat: OSType

    public init(pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        self.pixelFormat = pixelFormat
    }

    public func makePixelBuffer(from packet: Data) throws -> CVPixelBuffer {
        guard packet.isEmpty == false else {
            return try makePlaceholderPixelBuffer(width: 1, height: 1)
        }

        // In production this should parse/convert decoded frame bytes (from libmpv render callback)
        // to CVPixelBuffer plane memory. Packet-only conversion is not reliable without metadata.
        throw VideoToolboxBridgeError.unsupportedPacketLayout
    }

    public func makePlaceholderPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        guard width > 0, height > 0 else {
            throw VideoToolboxBridgeError.invalidDimensions(width: width, height: height)
        }

        try ensurePool(width: width, height: height)

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool!, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw VideoToolboxBridgeError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(buffer))
        }

        return buffer
    }

    private func ensurePool(width: Int, height: Int) throws {
        if let pixelBufferPool, poolWidth == width, poolHeight == height {
            _ = pixelBufferPool
            return
        }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
        guard status == kCVReturnSuccess, let newPool else {
            throw VideoToolboxBridgeError.poolCreationFailed(status)
        }

        pixelBufferPool = newPool
        poolWidth = width
        poolHeight = height
    }
}
