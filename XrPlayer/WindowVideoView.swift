import SwiftUI
import MetalKit
import CoreVideo

public struct WindowVideoView: UIViewRepresentable {
    @Bindable var viewModel: WindowVideoViewModel
    
    public init(viewModel: WindowVideoViewModel) {
        self.viewModel = viewModel
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = viewModel.renderer
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true // We want to trigger redraw on new frames
        
        // visionOS specific: enable HDR/EDR if possible
        if let layer = mtkView.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
        }
        
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        // This will be called whenever viewModel.frameCount changes
        _ = viewModel.frameCount // Access it to ensure observation
        uiView.setNeedsDisplay()
    }
}
