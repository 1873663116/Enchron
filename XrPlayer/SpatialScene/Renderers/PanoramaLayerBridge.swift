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

    private var displayLink: CADisplayLink?
    private var commandQueue: MTLCommandQueue?
    private var lowLevelTexture: LowLevelTexture?
    private var textureDescriptor: TextureDescriptor?

    /// Track the last drawable ID we copied to avoid re-copying the same frame.
    private var lastCopiedDrawableID: Int = -1

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

        let descriptor = TextureDescriptor(
            width: sourceTexture.width,
            height: sourceTexture.height,
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
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                recordCopyFailure("missing_blit_encoder")
                return
            }

            blitEncoder.copy(
                from: sourceTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(
                    width: sourceTexture.width,
                    height: sourceTexture.height,
                    depth: 1
                ),
                to: destinationTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: .init(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
            commandBuffer.commit()

            lastCopiedDrawableID = drawableID
            lastCopyFailure = nil
            noteCopyTick(reason: "display_link")
        } catch {
            recordCopyFailure("copy_error=\(error.localizedDescription)")
        }
    }

    func configureLowLevelTexture(_ descriptor: TextureDescriptor) throws {
        let lowLevelDescriptor = LowLevelTexture.Descriptor(
            textureType: .type2D,
            pixelFormat: descriptor.pixelFormat,
            width: descriptor.width,
            height: descriptor.height,
            depth: 1,
            mipmapLevelCount: 1,
            textureUsage: [.shaderRead]
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
}
