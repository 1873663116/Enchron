import CoreGraphics
import Foundation
@preconcurrency import Metal
@preconcurrency import QuartzCore

enum HDRProbeError: LocalizedError {
    case noDrawable
    case noProbeDrawable
    case missingDevice
    case unsupportedPixelFormat(MTLPixelFormat)
    case allocationFailed
    case commandQueueFailed
    case commandBufferFailed
    case blitEncoderFailed
    case commandBufferTimedOut
    case readbackTimedOut
    case simulatorDrawableReadbackUnavailable
    case simulatorFullFrameReadbackUnavailable
    case commandBufferExecutionFailed(String)
    case sampleTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .noDrawable:
            return "No MPV drawable has been vended yet."
        case .noProbeDrawable:
            return "No prior MPV drawable is available for probe readback yet."
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
        case .blitEncoderFailed:
            return "Failed to create Metal blit encoder for probe readback."
        case .commandBufferTimedOut:
            return "Probe readback command buffer timed out."
        case .readbackTimedOut:
            return "Probe readback timed out before producing a sample."
        case .simulatorDrawableReadbackUnavailable:
            return "MPV drawable readback is disabled on Simulator."
        case .simulatorFullFrameReadbackUnavailable:
            return "Full-frame drawable readback is disabled on Simulator."
        case .commandBufferExecutionFailed(let message):
            return "Probe readback command buffer failed: \(message)."
        case .sampleTooLarge(let byteCount):
            return "Probe sample is too large for CPU readback (\(byteCount) bytes)."
        }
    }
}

final class HDRProbeController {
    static let extendedLinearDisplayP3Contract = "extended-linear Display P3"

    enum ReadbackMode {
        case centeredROI
        case fullFrame
    }

    private let maxReadbackBytes: Int
    private let maxProbeDimension: Int

    init(maxReadbackBytes: Int = 192 * 1024 * 1024, maxProbeDimension: Int = 640) {
        self.maxReadbackBytes = maxReadbackBytes
        self.maxProbeDimension = maxProbeDimension
    }

    func sampleSyntheticStats(hdrOutputEnabled: Bool?) -> PlaybackCoreDomain.HDRProbeSample {
        let pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = [
            .init(red: 0.5, green: 0.5, blue: 0.5),
            .init(red: 1.0, green: 1.0, blue: 1.0),
            .init(red: 2.0, green: 2.0, blue: 2.0),
            .init(red: 4.0, green: 4.0, blue: 4.0)
        ]
        return PlaybackCoreDomain.HDRProbeSample(
            source: .syntheticStats,
            hdrOutputEnabled: hdrOutputEnabled,
            pixelFormat: MTLPixelFormat.rgba16Float.hdrProbeName,
            colorspace: "n/a",
            width: pixels.count,
            height: 1,
            statistics: PlaybackCoreDomain.HDRProbeCalculator.statistics(for: pixels),
            videoTime: nil,
            contract: PlaybackCoreDomain.HDRProbeContract.calculatorOnly.rawValue,
            renderer: "calculator",
            probeRegion: "cpu synthetic"
        )
    }

    func sampleMPVDrawable(
        from layer: CAMetalLayer?,
        hdrOutputEnabled: Bool,
        videoTime: Double?,
        mediaFingerprint: String?,
        sampleSequence: Int,
        readbackMode: ReadbackMode = .centeredROI
    ) throws -> PlaybackCoreDomain.HDRProbeSample {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["XRPLAYER_ALLOW_SIMULATOR_DRAWABLE_READBACK"] == "1" else {
            throw HDRProbeError.simulatorDrawableReadbackUnavailable
        }
        if readbackMode == .fullFrame {
            throw HDRProbeError.simulatorFullFrameReadbackUnavailable
        }
        #endif

        guard let layer else { throw HDRProbeError.noDrawable }
        guard let nativeLayer = layer as? MPVNativeMetalLayer,
              let drawable = nativeLayer.lastProbeDrawable else {
            throw HDRProbeError.noProbeDrawable
        }

        let texture = drawable.texture
        guard let device = layer.device ?? texture.device as MTLDevice? else {
            throw HDRProbeError.missingDevice
        }
        guard let layout = TextureReadbackLayout(pixelFormat: texture.pixelFormat) else {
            throw HDRProbeError.unsupportedPixelFormat(texture.pixelFormat)
        }

        let region = ProbeReadbackRegion(in: texture, mode: readbackMode, maxDimension: maxProbeDimension)
        let readback = try copyTextureToSharedBuffer(texture, region: region, layout: layout, device: device)
        let width = region.width
        let height = region.height
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
            contract: Self.probeContract(for: texture, layer: layer),
            mediaFingerprint: mediaFingerprint,
            renderer: "mpv",
            probeRegion: region.description,
            sampleSequence: sampleSequence
        )
    }

    func sampleMPVDrawableAsync(
        from layer: CAMetalLayer?,
        hdrOutputEnabled: Bool,
        videoTime: Double?,
        mediaFingerprint: String?,
        sampleSequence: Int,
        readbackMode: ReadbackMode = .centeredROI,
        timeout: TimeInterval = 3
    ) async throws -> PlaybackCoreDomain.HDRProbeSample {
        try await withCheckedThrowingContinuation { continuation in
            let completion = ProbeContinuation(continuation)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    let sample = try self.sampleMPVDrawable(
                        from: layer,
                        hdrOutputEnabled: hdrOutputEnabled,
                        videoTime: videoTime,
                        mediaFingerprint: mediaFingerprint,
                        sampleSequence: sampleSequence,
                        readbackMode: readbackMode
                    )
                    completion.resume(with: .success(sample))
                } catch {
                    completion.resume(with: .failure(error))
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                completion.resume(with: .failure(HDRProbeError.readbackTimedOut))
            }
        }
    }

    private func copyTextureToSharedBuffer(
        _ texture: MTLTexture,
        region: ProbeReadbackRegion,
        layout: TextureReadbackLayout,
        device: MTLDevice
    ) throws -> TextureReadbackResult {
        let bytesPerRow = Self.alignedBytesPerRow(width: region.width, bytesPerPixel: layout.bytesPerPixel)
        let byteCount = bytesPerRow * region.height
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

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw HDRProbeError.blitEncoderFailed
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: region.x, y: region.y, z: 0),
            sourceSize: MTLSize(width: region.width, height: region.height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * region.height
        )
        blit.endEncoding()
        let completion = DispatchSemaphore(value: 0)
        commandBuffer.addCompletedHandler { _ in
            completion.signal()
        }
        commandBuffer.commit()
        guard completion.wait(timeout: .now() + .seconds(2)) == .success else {
            throw HDRProbeError.commandBufferTimedOut
        }
        if commandBuffer.status == .error {
            throw HDRProbeError.commandBufferExecutionFailed(
                commandBuffer.error?.localizedDescription ?? "unknown error"
            )
        }

        return TextureReadbackResult(buffer: buffer, bytesPerRow: bytesPerRow)
    }

    private static func probeContract(for texture: MTLTexture, layer: CAMetalLayer) -> String {
        guard texture.pixelFormat == .rgba16Float else {
            return PlaybackCoreDomain.HDRProbeContract.mismatch.rawValue
        }
        guard layer.hdrProbeColorspaceName == CGColorSpace.extendedLinearDisplayP3Name else {
            return PlaybackCoreDomain.HDRProbeContract.mismatch.rawValue
        }
        return PlaybackCoreDomain.HDRProbeContract.extendedLinearDisplayP3.rawValue
    }

    private static func alignedBytesPerRow(width: Int, bytesPerPixel: Int) -> Int {
        let raw = width * bytesPerPixel
        let alignment = 256
        return ((raw + alignment - 1) / alignment) * alignment
    }
}

private final class ProbeContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PlaybackCoreDomain.HDRProbeSample, Error>?

    init(_ continuation: CheckedContinuation<PlaybackCoreDomain.HDRProbeSample, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<PlaybackCoreDomain.HDRProbeSample, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }

        switch result {
        case .success(let sample):
            pending.resume(returning: sample)
        case .failure(let error):
            pending.resume(throwing: error)
        }
    }
}

private struct TextureReadbackResult {
    let buffer: MTLBuffer
    let bytesPerRow: Int
}

private struct ProbeReadbackRegion {
    enum Kind: String {
        case centeredROI = "center ROI"
        case fullFrame = "full frame"
    }

    let kind: Kind
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var description: String {
        "\(kind.rawValue) \(width)x\(height) @ \(x),\(y)"
    }

    init(in texture: MTLTexture, mode: HDRProbeController.ReadbackMode, maxDimension: Int) {
        switch mode {
        case .centeredROI:
            let width = min(texture.width, maxDimension)
            let height = min(texture.height, maxDimension)
            self.kind = .centeredROI
            self.x = max((texture.width - width) / 2, 0)
            self.y = max((texture.height - height) / 2, 0)
            self.width = width
            self.height = height
        case .fullFrame:
            self.kind = .fullFrame
            self.x = 0
            self.y = 0
            self.width = texture.width
            self.height = texture.height
        }
    }
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
        case .rgb10a2Unorm:
            bytesPerPixel = 4
            pixels = { pointer, width, height, bytesPerRow in
                Self.readRGB10A2(pointer, width: width, height: height, bytesPerRow: bytesPerRow)
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

    private static func readRGB10A2(
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
                let packed = UInt32(bytes[offset])
                    | (UInt32(bytes[offset + 1]) << 8)
                    | (UInt32(bytes[offset + 2]) << 16)
                    | (UInt32(bytes[offset + 3]) << 24)
                let red = Double(packed & 0x3FF) / 1023.0
                let green = Double((packed >> 10) & 0x3FF) / 1023.0
                let blue = Double((packed >> 20) & 0x3FF) / 1023.0
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
        case .rgb10a2Unorm: return "rgb10a2Unorm"
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
