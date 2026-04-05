import SwiftUI
import MetalKit
import CoreVideo

public struct WindowVideoView: UIViewRepresentable {
    public final class Coordinator {
        weak var viewModel: WindowVideoViewModel?

        init(viewModel: WindowVideoViewModel) {
            self.viewModel = viewModel
        }
    }

    @Bindable var viewModel: WindowVideoViewModel

    /// Container size from GeometryReader. When the window resizes, this value
    /// changes and SwiftUI calls `updateUIView`, ensuring the Metal layer /
    /// MTKView drawable size stays in sync.
    var containerSize: CGSize

    public init(viewModel: WindowVideoViewModel, containerSize: CGSize = .zero) {
        self.viewModel = viewModel
        self.containerSize = containerSize
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeUIView(context: Context) -> UIView {
        if viewModel.usesNativeGPUOutput {
            let view = MPVNativeMetalLayerView()
            view.isUserInteractionEnabled = false
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.contentMode = .scaleToFill
            viewModel.attachVideoLayer(view.metalLayer)
            return view
        } else {
            let mtkView = MTKView()
            mtkView.device = MTLCreateSystemDefaultDevice()
            mtkView.delegate = viewModel.renderer
            mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            mtkView.framebufferOnly = false
            mtkView.enableSetNeedsDisplay = false
            mtkView.isPaused = false
            mtkView.isUserInteractionEnabled = false
            mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            if let layer = mtkView.layer as? CAMetalLayer {
                layer.wantsExtendedDynamicRangeContent = true
            }

            return mtkView
        }
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if viewModel.usesNativeGPUOutput, let nativeView = uiView as? MPVNativeMetalLayerView {
            viewModel.attachVideoLayer(nativeView.metalLayer)
            // Force layout update when SwiftUI resizes the container (e.g., window resize).
            // containerSize dependency ensures this fires on geometry changes.
            nativeView.setNeedsLayout()
        } else if let mtkView = uiView as? MTKView {
            // MTKView path: update drawableSize to match the new container size.
            let scale = mtkView.contentScaleFactor
            let newDrawableSize = CGSize(
                width: containerSize.width * scale,
                height: containerSize.height * scale
            )
            if newDrawableSize.width > 1, newDrawableSize.height > 1 {
                mtkView.drawableSize = newDrawableSize
            }
        }
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.viewModel?.attachVideoLayer(nil)
    }
}
