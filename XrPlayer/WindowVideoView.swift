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

    public init(viewModel: WindowVideoViewModel) {
        self.viewModel = viewModel
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
            // UIViewRepresentable may not always trigger layoutSubviews on geometry changes.
            nativeView.setNeedsLayout()
        }
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.viewModel?.attachVideoLayer(nil)
    }
}
