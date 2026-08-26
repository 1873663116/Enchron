import DesignSystem
import MetalKit
import PlaybackCore
import SwiftUI
import UIKit

public struct AudioSpectrumSurface: View {
    let frame: AudioSpectrumFrame

    public init(frame: AudioSpectrumFrame) {
        self.frame = frame
    }

    public var body: some View {
        AudioSpectrumMetalView(bands: frame.bands)
            .padding(.horizontal, DesignTokens.AudioSpectrum.horizontalInset)
            .padding(.vertical, DesignTokens.AudioSpectrum.verticalInset)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("PlayerUI-audio-spectrum")
            .accessibilityLabel("Audio spectrum")
            .accessibilityValue(frame.bands.contains(where: { $0 > 0.01 }) ? "Active" : "Quiet")
    }
}

private struct AudioSpectrumMetalView: UIViewRepresentable {
    let bands: [Float]

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.delegate = context.coordinator
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(bands: bands)
        view.setNeedsDisplay()
    }

    final class Renderer: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var bands = Array(repeating: Float.zero, count: 24)
        private let lock = NSLock()

        func configure(_ view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            do {
                let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "audioSpectrumVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "audioSpectrumFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                pipeline = nil
            }
        }

        func update(bands: [Float]) {
            lock.withLock {
                self.bands = bands.isEmpty
                    ? Array(repeating: 0, count: 24)
                    : bands.map { min(1, max(0, $0)) }
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pass = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass),
                  let pipeline else { return }
            let currentBands = lock.withLock { bands }
            let vertices = Self.vertices(for: currentBands)
            let color = UIColor(DesignTokens.AudioSpectrum.barColor)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            var rgba = SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(
                vertices,
                length: vertices.count * MemoryLayout<SIMD2<Float>>.stride,
                index: 0
            )
            encoder.setFragmentBytes(
                &rgba,
                length: MemoryLayout<SIMD4<Float>>.stride,
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private static func vertices(for bands: [Float]) -> [SIMD2<Float>] {
            let count = max(1, bands.count)
            let slotWidth = 2 / Float(count)
            let gap = min(slotWidth * 0.45, Float(DesignTokens.AudioSpectrum.barSpacing) / 100)
            return bands.enumerated().flatMap { index, magnitude in
                let left = -1 + Float(index) * slotWidth + gap
                let right = -1 + Float(index + 1) * slotWidth - gap
                let bottom: Float = -0.92
                let top = bottom + max(0.025, magnitude) * 1.84
                return [
                    SIMD2(left, bottom), SIMD2(right, bottom), SIMD2(left, top),
                    SIMD2(right, bottom), SIMD2(right, top), SIMD2(left, top)
                ]
            }
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        vertex float4 audioSpectrumVertex(
            const device float2 *positions [[buffer(0)]],
            uint vertexID [[vertex_id]]
        ) {
            return float4(positions[vertexID], 0, 1);
        }

        fragment float4 audioSpectrumFragment(
            constant float4 &color [[buffer(0)]]
        ) {
            return color;
        }
        """
    }
}
