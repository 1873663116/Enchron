import SwiftUI
import MetalKit
import CoreVideo

public struct WindowVideoView: UIViewRepresentable {
    @Bindable var viewModel: WindowVideoViewModel
    
    public init(viewModel: WindowVideoViewModel) {
        self.viewModel = viewModel
    }

    public func makeUIView(context: Context) -> UIView {
        if viewModel.usesNativeGPUOutput {
            let view = MPVNativeMetalLayerView()
            view.isUserInteractionEnabled = false
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

            if let layer = mtkView.layer as? CAMetalLayer {
                layer.wantsExtendedDynamicRangeContent = true
            }

            return mtkView
        }
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if viewModel.usesNativeGPUOutput, let nativeView = uiView as? MPVNativeMetalLayerView {
            viewModel.attachVideoLayer(nativeView.metalLayer)
        }
    }
}
