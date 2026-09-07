import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import QuartzCore
import RealityKit
import SwiftUI

@MainActor
final class PlaybackChromeBackdropSampler {
    static let sampleWidth = 160
    static let blurRadius: Double = 6
    static let refreshInterval: TimeInterval = 1.0 / 24

    private var lastSampledBuffer: CVPixelBuffer?
    private var lastSampledAt: TimeInterval = 0
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

    // Returns a new band only when the displayed frame changed and the
    // refresh interval elapsed; nil means "keep what you have".
    func sample(renderer: AVSampleBufferVideoRenderer, bandFraction: Float) -> CGImage? {
        guard bandFraction > 0 else { return nil }
        let now = CACurrentMediaTime()
        guard now - lastSampledAt >= Self.refreshInterval,
              let buffer = renderer.displayedPixelBuffer(),
              buffer !== lastSampledBuffer else {
            return nil
        }
        lastSampledAt = now
        guard let image = Self.blurredBand(of: buffer, bandFraction: bandFraction) else {
            return nil
        }
        lastSampledBuffer = buffer
        return image
    }

    func reset() {
        subscription?.cancel()
        subscription = nil
        lastSampledBuffer = nil
        lastSampledAt = 0
    }

    // The band samples the top of the displayed frame, shrinks it to a
    // thumbnail, blurs it, and bakes the eased fade into its alpha so the
    // image dissolves into the sharp video below it.
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
        let peak = DesignTokens.PlaybackEdge.peakOpacity
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: peak)
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

// The window-shaped edge only exists in SwiftUI: a full-window overlay
// clipped by the container shape inherits the window's corners with no
// inset to infer, and the coincident z offset keeps it over the video mesh.
public struct PlaybackChromeBackdropView: View {
    @Environment(PlaybackSessionModel.self) private var appModel

    public init() {}

    public var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                if let image = appModel.windowChromeBackdropImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.PlaybackEdge.depth)
                        .clipped()
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
