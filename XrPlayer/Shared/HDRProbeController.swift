import CoreGraphics
import Foundation
import Metal
import QuartzCore

enum HDRProbeError: LocalizedError {
    case noDrawable
    case missingDevice
    case unsupportedPixelFormat(MTLPixelFormat)
    case allocationFailed
    case commandQueueFailed
    case commandBufferFailed
    case sampleTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .noDrawable:
            return "No MPV drawable has been vended yet."
        case .missingDevice:
            return "The Metal layer has no device."
        case .unsupportedPixelFormat(let format):
            return "Unsupported probe pixel format: \(format.hdrProbeName)."
        case .allocationFailed:
            return "Failed to allocate probe readback buffer."
        case .commandQueueFailed:
            return "Failed to create Metal command queue for probe readback."
        case .commandBufferFailed:
            return "Failed to create Metal command buffer for probe readback."
        case .sampleTooLarge(let byteCount):
            return "Probe sample is too large for CPU readback (\(byteCount) bytes)."
        }
    }
}

final class HDRProbeController {
    static let extendedLinearDisplayP3Contract = "extended-linear Display P3"

    private let maxReadbackBytes: Int

    init(maxReadbackBytes: Int = 160 * 1024 * 1024) {
        self.maxReadbackBytes = maxReadbackBytes
    }

    func sampleSyntheticEDR(hdrOutputEnabled: Bool?) -> PlaybackCoreDomain.HDRProbeSample {
        let pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = [
            .init(red: 0.5, green: 0.5, blue: 0.5),
            .init(red: 1.0, green: 1.0, blue: 1.0),
            .init(red: 2.0, green: 2.0, blue: 2.0),
            .init(red: 4.0, green: 4.0, blue: 4.0)
        ]
        return PlaybackCoreDomain.HDRProbeSample(
            source: .syntheticEDR,
            hdrOutputEnabled: hdrOutputEnabled,
            pixelFormat: MTLPixelFormat.rgba16Float.hdrProbeName,
            colorspace: CGColorSpace.extendedLinearDisplayP3Name,
            width: pixels.count,
            height: 1,
            statistics: PlaybackCoreDomain.HDRProbeCalculator.statistics(for: pixels),
            videoTime: nil,
            contract: Self.extendedLinearDisplayP3Contract
        )
    }

    func sampleMPVDrawable(
        from layer: CAMetalLayer?,
        hdrOutputEnabled: Bool,
        videoTime: Double?
    ) throws -> PlaybackCoreDomain.HDRProbeSample {
        guard let layer else { throw HDRProbeError.noDrawable }
        guard let nativeLayer = layer as? MPVNativeMetalLayer,
              let drawable = nativeLayer.lastVendedDrawable else {
            throw HDRProbeError.noDrawable
        }

        let texture = drawable.texture
        guard let device = layer.device ?? texture.device as MTLDevice? else {
            throw HDRProbeError.missingDevice
        }
        guard let layout = TextureReadbackLayout(pixelFormat: texture.pixelFormat) else {
            throw HDRProbeError.unsupportedPixelFormat(texture.pixelFormat)
        }

        let readback = try copyTextureToSharedBuffer(texture, layout: layout, device: device)
        let width = texture.width
        let height = texture.height
        let pixels = layout.pixels(readback.buffer.contents(), width, height, readback.bytesPerRow)
        return PlaybackCoreDomain.HDRProbeSample(
            source: .mpvDrawable,
            hdrOutputEnabled: hdrOutputEnabled,
            pixelFormat: texture.pixelFormat.hdrProbeName,
            colorspace: layer.hdrProbeColorspaceName,
            width: width,
            height: height,
            statistics: PlaybackCoreDomain.HDRProbeCalculator.statistics(for: pixels),
            videoTime: videoTime,
            contract: Self.extendedLinearDisplayP3Contract
        )
    }

    private func copyTextureToSharedBuffer(
        _ texture: MTLTexture,
        layout: TextureReadbackLayout,
        device: MTLDevice
    ) throws -> TextureReadbackResult {
        let bytesPerRow = Self.alignedBytesPerRow(width: texture.width, bytesPerPixel: layout.bytesPerPixel)
        let byteCount = bytesPerRow * texture.height
        guard byteCount <= maxReadbackBytes else {
            throw HDRProbeError.sampleTooLarge(byteCount)
        }
        guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw HDRProbeError.allocationFailed
        }
        guard let queue = device.makeCommandQueue() else {
            throw HDRProbeError.commandQueueFailed
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HDRProbeError.commandBufferFailed
        }

        let blit = commandBuffer.makeBlitCommandEncoder()
        blit?.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * texture.height
        )
        blit?.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return TextureReadbackResult(buffer: buffer, bytesPerRow: bytesPerRow)
    }

    private static func alignedBytesPerRow(width: Int, bytesPerPixel: Int) -> Int {
        let raw = width * bytesPerPixel
        let alignment = 256
        return ((raw + alignment - 1) / alignment) * alignment
    }
}

private struct TextureReadbackResult {
    let buffer: MTLBuffer
    let bytesPerRow: Int
}

private struct TextureReadbackLayout {
    let bytesPerPixel: Int
    let pixels: (UnsafeMutableRawPointer, Int, Int, Int) -> [PlaybackCoreDomain.HDRProbeCalculator.Pixel]

    init?(pixelFormat: MTLPixelFormat) {
        switch pixelFormat {
        case .rgba16Float:
            bytesPerPixel = 8
            pixels = { pointer, width, height, bytesPerRow in
                Self.readRGBA16Float(pointer, width: width, height: height, bytesPerRow: bytesPerRow)
            }
        case .bgra8Unorm, .bgra8Unorm_srgb:
            bytesPerPixel = 4
            pixels = { pointer, width, height, bytesPerRow in
                Self.readBGRA8(pointer, width: width, height: height, bytesPerRow: bytesPerRow)
            }
        default:
            return nil
        }
    }

    private static func readRGBA16Float(
        _ pointer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> [PlaybackCoreDomain.HDRProbeCalculator.Pixel] {
        let bytes = pointer.assumingMemoryBound(to: UInt8.self)
        var pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let offset = rowOffset + x * 8
                let red = halfFloat(at: bytes, offset: offset)
                let green = halfFloat(at: bytes, offset: offset + 2)
                let blue = halfFloat(at: bytes, offset: offset + 4)
                pixels.append(.init(red: red, green: green, blue: blue))
            }
        }
        return pixels
    }

    private static func readBGRA8(
        _ pointer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> [PlaybackCoreDomain.HDRProbeCalculator.Pixel] {
        let bytes = pointer.assumingMemoryBound(to: UInt8.self)
        var pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let offset = rowOffset + x * 4
                let blue = Double(bytes[offset]) / 255.0
                let green = Double(bytes[offset + 1]) / 255.0
                let red = Double(bytes[offset + 2]) / 255.0
                pixels.append(.init(red: red, green: green, blue: blue))
            }
        }
        return pixels
    }

    private static func halfFloat(at bytes: UnsafePointer<UInt8>, offset: Int) -> Double {
        let bitPattern = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        return Double(Float(Float16(bitPattern: bitPattern)))
    }
}

extension MTLPixelFormat {
    var hdrProbeName: String {
        switch self {
        case .rgba16Float: return "rgba16Float"
        case .rgba32Float: return "rgba32Float"
        case .bgra8Unorm: return "bgra8Unorm"
        case .bgra8Unorm_srgb: return "bgra8Unorm_srgb"
        default: return "\(rawValue)"
        }
    }
}

extension CAMetalLayer {
    var hdrProbeColorspaceName: String {
        guard let name = colorspace?.name else { return "missing" }
        return name as String
    }
}

extension CGColorSpace {
    static let extendedLinearDisplayP3Name = "kCGColorSpaceExtendedLinearDisplayP3"
}
