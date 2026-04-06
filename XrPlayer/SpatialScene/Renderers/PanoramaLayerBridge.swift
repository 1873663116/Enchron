import Foundation
import Metal
import Observation
import QuartzCore
import RealityKit
import UIKit

/// Bridges libmpv's native CAMetalLayer output to a RealityKit
/// `LowLevelTexture` for panorama / immersive rendering.
///
/// Instead of calling `nextDrawable()` (which returns a blank drawable),
/// the bridge reads from `MPVNativeMetalLayer.lastVendedDrawable` — the
/// drawable that libmpv most recently acquired and rendered into.
@MainActor
@Observable
public final class PanoramaLayerBridge {
    public struct SurfaceSnapshot: Sendable, Equatable {
        public let pixelFormat: String
        public let framebufferOnly: Bool
        public let wantsExtendedDynamicRangeContent: Bool
        public let colorspaceName: String?
        public let drawableWidth: Int
        public let drawableHeight: Int
    }

    public private(set) weak var videoLayer: CAMetalLayer?
    public private(set) var textureResource: TextureResource?
    public private(set) var attachedSurface: SurfaceSnapshot?
    public private(set) var layerAttachmentCount: Int = 0
    public private(set) var copyTickCount: Int = 0
    public private(set) var lastCopyTickReason: String?
    public private(set) var lastCopyFailure: String?

    /// When set to a non-mono layout, the bridge crops the source frame to the
    /// left-eye region before copying to the `LowLevelTexture`. This supports
    /// SBS and TopBottom stereo 3D video by extracting a single eye's content
    /// (MVP: left eye). `.mono` is treated as no-crop (same as nil).
    public var stereoCropMode: PlaybackCoreDomain.StereoLayout?

    /// When set, the bridge applies a fisheye-to-equirectangular remap
    /// via a Metal compute shader before copying to the `LowLevelTexture`.
    /// Fisheye remap takes precedence over stereo crop.
    public var fisheyeRemapConfig: SpatialSceneDomain.FisheyeRemapConfiguration?

    private var displayLink: CADisplayLink?
    private var commandQueue: MTLCommandQueue?
    private var lowLevelTexture: LowLevelTexture?
    private var textureDescriptor: TextureDescriptor?

    /// Track the last drawable ID we copied to avoid re-copying the same frame.
    private var lastCopiedDrawableID: Int = -1
    private var fisheyeComputePipeline: MTLComputePipelineState?

    public init() {}

    public func attachVideoLayer(_ layer: CAMetalLayer?) {
        videoLayer = layer
        stopDisplayLinkIfNeeded()
        lastCopiedDrawableID = -1

        guard let layer else {
            attachedSurface = nil
            lowLevelTexture = nil
            textureResource = nil
            textureDescriptor = nil
            lastCopyFailure = nil
            print("[PanoramaBridge] layer_detached")
            return
        }

        layerAttachmentCount += 1
        attachedSurface = SurfaceSnapshot(
            pixelFormat: String(describing: layer.pixelFormat),
            framebufferOnly: layer.framebufferOnly,
            wantsExtendedDynamicRangeContent: layer.wantsExtendedDynamicRangeContent,
            colorspaceName: layer.colorspace?.name as String?,
            drawableWidth: Int(layer.drawableSize.width),
            drawableHeight: Int(layer.drawableSize.height)
        )
        commandQueue = layer.device?.makeCommandQueue()
        lastCopyFailure = nil
        print(
            "[PanoramaBridge] layer_attached count=\(layerAttachmentCount)"
            + " size=\(Int(layer.drawableSize.width))x\(Int(layer.drawableSize.height))"
            + " format=\(layer.pixelFormat) framebufferOnly=\(layer.framebufferOnly)"
        )
        startDisplayLink()
    }

    public func noteCopyTick(reason: String) {
        copyTickCount += 1
        lastCopyTickReason = reason
        if copyTickCount == 1 || copyTickCount.isMultiple(of: 60) {
            print("[PanoramaBridge] copy_tick count=\(copyTickCount) reason=\(reason)")
        }
    }
}

@MainActor
private extension PanoramaLayerBridge {
    struct TextureDescriptor: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }

    func startDisplayLink() {
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stopDisplayLinkIfNeeded() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc func handleDisplayLink() {
        guard let layer = videoLayer as? MPVNativeMetalLayer else {
            recordCopyFailure("not_mpv_native_layer")
            return
        }
        guard let commandQueue else {
            recordCopyFailure("missing_command_queue")
            return
        }

        // Read the drawable that libmpv most recently rendered into.
        guard let drawable = layer.lastVendedDrawable else {
            recordCopyFailure("no_drawable_yet")
            return
        }

        let sourceTexture = drawable.texture

        // Skip if we already copied this exact drawable (same frame).
        let drawableID = sourceTexture.hash
        guard drawableID != lastCopiedDrawableID else {
            return
        }

        // Determine output dimensions
        let outputWidth: Int
        let outputHeight: Int

        if fisheyeRemapConfig != nil {
            // Fisheye remap outputs to equirectangular at source dimensions
            outputWidth = sourceTexture.width
            outputHeight = sourceTexture.height
        } else if let stereoCropMode, stereoCropMode != .mono {
            let uvRect = stereoCropMode.leftEyeUVRect
            outputWidth = Int(Float(sourceTexture.width) * uvRect.width)
            outputHeight = Int(Float(sourceTexture.height) * uvRect.height)
        } else {
            outputWidth = sourceTexture.width
            outputHeight = sourceTexture.height
        }

        let descriptor = TextureDescriptor(
            width: outputWidth,
            height: outputHeight,
            pixelFormat: sourceTexture.pixelFormat
        )

        do {
            if textureDescriptor != descriptor {
                try configureLowLevelTexture(descriptor)
            }

            guard let lowLevelTexture,
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else {
                recordCopyFailure("missing_llt_or_cb")
                return
            }

            let destinationTexture = lowLevelTexture.replace(using: commandBuffer)

            if let fisheyeRemapConfig {
                try encodeFisheyeRemap(
                    commandBuffer: commandBuffer,
                    source: sourceTexture,
                    destination: destinationTexture,
                    config: fisheyeRemapConfig,
                    outputWidth: outputWidth,
                    outputHeight: outputHeight
                )
            } else {
                encodeBlitCopy(
                    commandBuffer: commandBuffer,
                    source: sourceTexture,
                    destination: destinationTexture
                )
            }

            commandBuffer.commit()
            lastCopiedDrawableID = drawableID
            lastCopyFailure = nil
            noteCopyTick(reason: fisheyeRemapConfig != nil ? "fisheye_remap" : "display_link")
        } catch {
            recordCopyFailure("copy_error=\(error.localizedDescription)")
        }
    }

    func encodeFisheyeRemap(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture,
        config: SpatialSceneDomain.FisheyeRemapConfiguration,
        outputWidth: Int,
        outputHeight: Int
    ) throws {
        let pipeline = try getOrCreateFisheyeComputePipeline()
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            recordCopyFailure("missing_compute_encoder")
            return
        }
        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(source, index: 0)
        computeEncoder.setTexture(destination, index: 1)
        var uniforms = FisheyeRemapUniforms(fovRadiusRadians: config.fovRadiusRadians)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<FisheyeRemapUniforms>.size, index: 0)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (outputWidth + 15) / 16,
            height: (outputHeight + 15) / 16,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
    }

    func encodeBlitCopy(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let sourceOrigin: MTLOrigin
        let copyWidth: Int
        let copyHeight: Int

        if let stereoCropMode, stereoCropMode != .mono {
            let uvRect = stereoCropMode.leftEyeUVRect
            sourceOrigin = MTLOrigin(
                x: Int(Float(source.width) * uvRect.originX),
                y: Int(Float(source.height) * uvRect.originY),
                z: 0
            )
            copyWidth = Int(Float(source.width) * uvRect.width)
            copyHeight = Int(Float(source.height) * uvRect.height)
        } else {
            sourceOrigin = MTLOrigin(x: 0, y: 0, z: 0)
            copyWidth = source.width
            copyHeight = source.height
        }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            recordCopyFailure("missing_blit_encoder")
            return
        }
        blitEncoder.copy(
            from: source, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: sourceOrigin,
            sourceSize: .init(width: copyWidth, height: copyHeight, depth: 1),
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
    }

    func configureLowLevelTexture(_ descriptor: TextureDescriptor) throws {
        let lowLevelDescriptor = LowLevelTexture.Descriptor(
            textureType: .type2D,
            pixelFormat: descriptor.pixelFormat,
            width: descriptor.width,
            height: descriptor.height,
            depth: 1,
            mipmapLevelCount: 1,
            textureUsage: [.shaderRead, .shaderWrite]
        )
        let texture = try LowLevelTexture(descriptor: lowLevelDescriptor)
        lowLevelTexture = texture
        textureResource = try TextureResource(from: texture)
        textureDescriptor = descriptor
        print(
            "[PanoramaBridge] low_level_texture_ready"
            + " size=\(descriptor.width)x\(descriptor.height)"
            + " format=\(descriptor.pixelFormat)"
        )
    }

    func recordCopyFailure(_ reason: String) {
        guard lastCopyFailure != reason else { return }
        lastCopyFailure = reason
        print("[PanoramaBridge] \(reason)")
    }

    struct FisheyeRemapUniforms {
        var fovRadiusRadians: Float
    }

    func getOrCreateFisheyeComputePipeline() throws -> MTLComputePipelineState {
        if let pipeline = fisheyeComputePipeline { return pipeline }
        guard let device = videoLayer?.device,
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "fisheye_remap")
        else {
            throw NSError(domain: "PanoramaBridge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "fisheye_remap kernel not found"
            ])
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        fisheyeComputePipeline = pipeline
        print("[PanoramaBridge] fisheye_compute_pipeline_ready")
        return pipeline
    }
}
