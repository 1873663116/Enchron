import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import QuartzCore
import RealityKit
import SwiftUI

@MainActor
final class PlaybackChromeBackdrop {
    static let sampleWidth = 160
    static let blurRadius: Double = 6
    static let refreshInterval: TimeInterval = 1.0 / 24
    static let planeLift: Float = 0.01

    let entity: Entity = {
        let entity = Entity()
        entity.name = "Enchron.ChromeBackdrop"
        return entity
    }()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private var texture: TextureResource?
    private var textureSize = SIMD2<Int>(repeating: 0)
    private var lastSampledBuffer: CVPixelBuffer?
    private var lastSampledAt: TimeInterval = 0
    private var planeSize: SIMD2<Float>?
    private var subscription: EventSubscription?

    func observe<Content: RealityViewContentProtocol>(
        in content: Content,
        refresh: @escaping @MainActor () -> Void
    ) {
        guard subscription == nil else { return }
        subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
            Task { @MainActor in refresh() }
        }
    }

    func update(
        on videoEntity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        screenSize: SIMD2<Float>,
        bandFraction: Float,
        usesMainWindow: Bool
    ) {
        guard bandFraction > 0, screenSize.x > 0, screenSize.y > 0 else {
            entity.isEnabled = false
            return
        }
        let size = SIMD2<Float>(screenSize.x, screenSize.y * bandFraction)
        if entity.parent !== videoEntity {
            videoEntity.addChild(entity)
        }
        entity.position = [0, screenSize.y / 2 - size.y / 2, Self.planeLift]
        if usesMainWindow {
            entity.components.set(
                ModelSortGroupComponent(
                    group: .planarUIInline,
                    order: WindowPlaybackSurfaceGeometry.chromeBackdropSortOrder
                )
            )
        } else {
            entity.components.remove(ModelSortGroupComponent.self)
        }
        let now = CACurrentMediaTime()
        if now - lastSampledAt >= Self.refreshInterval,
           let buffer = renderer.displayedPixelBuffer(),
           buffer !== lastSampledBuffer {
            lastSampledAt = now
            if let image = Self.blurredBand(of: buffer, bandFraction: bandFraction),
               replaceTexture(with: image) {
                lastSampledBuffer = buffer
            }
        }
        guard let texture else {
            entity.isEnabled = false
            return
        }
        if planeSize != size || entity.components[ModelComponent.self] == nil {
            var material = UnlitMaterial(texture: texture)
            material.blending = .transparent(opacity: .init(scale: 1))
            material.writesDepth = false
            entity.components.set(ModelComponent(
                mesh: .generatePlane(width: size.x, height: size.y),
                materials: [material]
            ))
            planeSize = size
        }
        entity.isEnabled = true
    }

    func remove() {
        subscription?.cancel()
        subscription = nil
        entity.removeFromParent()
        entity.components.remove(ModelComponent.self)
        entity.components.remove(ModelSortGroupComponent.self)
        entity.isEnabled = false
        texture = nil
        textureSize = .zero
        planeSize = nil
        lastSampledBuffer = nil
        lastSampledAt = 0
    }

    private func replaceTexture(with image: CGImage) -> Bool {
        let nextSize = SIMD2(image.width, image.height)
        do {
            if let texture, textureSize == nextSize {
                try texture.replace(withImage: image, options: .init(semantic: .color))
            } else {
                texture = try TextureResource(image: image, options: .init(semantic: .color))
                textureSize = nextSize
                planeSize = nil
            }
            return true
        } catch {
            return false
        }
    }

    // The band samples the top of the displayed frame, shrinks it to a
    // thumbnail, blurs it, and bakes the eased fade into its alpha so the
    // plane dissolves into the sharp video below it.
    private static func blurredBand(
        of buffer: CVPixelBuffer,
        bandFraction: Float
    ) -> CGImage? {
        let source = CIImage(cvPixelBuffer: buffer)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let bandHeight = extent.height * CGFloat(bandFraction)
        let band = CGRect(
            x: extent.minX,
            y: extent.maxY - bandHeight,
            width: extent.width,
            height: bandHeight
        )
        let scale = CGFloat(sampleWidth) / extent.width
        let scaled = source
            .cropped(to: band)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let target = CGRect(
            x: 0,
            y: 0,
            width: (band.width * scale).rounded(),
            height: max((band.height * scale).rounded(), 1)
        )
        let placed = scaled.transformed(
            by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY)
        )
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = placed.clampedToExtent()
        blur.radius = Float(blurRadius)
        guard let blurred = blur.outputImage?.cropped(to: target) else { return nil }

        let hold = CGFloat(DesignTokens.PlaybackEdge.holdFraction)
        let gradient = CIFilter.smoothLinearGradient()
        gradient.point0 = CGPoint(x: 0, y: 0)
        gradient.point1 = CGPoint(x: 0, y: target.height * (1 - hold))
        gradient.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let mask = gradient.outputImage?.cropped(to: target) else { return nil }

        let masked = CIFilter.blendWithAlphaMask()
        masked.inputImage = blurred
        masked.backgroundImage = CIImage(color: .clear).cropped(to: target)
        masked.maskImage = mask
        guard let output = masked.outputImage?.cropped(to: target) else { return nil }
        return CIContext.shared.createCGImage(
            output,
            from: target,
            format: .BGRA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }
}

private extension CIContext {
    nonisolated(unsafe) static let shared = CIContext(options: [.cacheIntermediates: false])
}
