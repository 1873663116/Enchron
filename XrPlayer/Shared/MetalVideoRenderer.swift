import Metal
import MetalKit
import CoreVideo
import Foundation
import simd

public final class MetalVideoRenderer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var renderPipelineState: MTLRenderPipelineState?
    private var renderPipelineStateNV12: MTLRenderPipelineState?
    
    private let frameSemaphore = DispatchSemaphore(value: 1)
    private var currentPixelBuffer: CVPixelBuffer?
    
    // Color conversion matrices
    private let bt709Matrix = simd_float3x3(
        simd_float3(1.164,  1.164,  1.164),
        simd_float3(0.000, -0.213,  2.112),
        simd_float3(1.793, -0.533,  0.000)
    )
    
    private let bt2020Matrix = simd_float3x3(
        simd_float3(1.164,  1.164,  1.164),
        simd_float3(0.000, -0.187,  2.142),
        simd_float3(1.678, -0.650,  0.000)
    )
    
    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache
        
        super.init()
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        let vertexFunction = library.makeFunction(name: "video_vertex")
        let fragmentFunction = library.makeFunction(name: "video_fragment")
        let fragmentFunctionBGRA = library.makeFunction(name: "video_fragment_bgra")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunctionBGRA
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            pipelineDescriptor.fragmentFunction = fragmentFunction
            renderPipelineStateNV12 = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    public func enqueueFrame(_ pixelBuffer: CVPixelBuffer) {
        frameSemaphore.wait()
        self.currentPixelBuffer = pixelBuffer
        frameSemaphore.signal()
    }
    
    public func render(in view: MTKView) {
        frameSemaphore.wait()
        let pixelBuffer = self.currentPixelBuffer
        frameSemaphore.signal()
        
        guard let pixelBuffer = pixelBuffer,
              let textureCache = textureCache,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Update pixel format if changed (e.g. for HDR)
        // For visionOS, we might want to use .bgra10_xr for HDR content
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || 
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            renderNV12(pixelBuffer, textureCache: textureCache, commandBuffer: commandBuffer, descriptor: renderPassDescriptor, drawable: drawable)
        } else {
            renderBGRA(pixelBuffer, textureCache: textureCache, commandBuffer: commandBuffer, descriptor: renderPassDescriptor, drawable: drawable)
        }
    }
    
    private func renderNV12(_ pixelBuffer: CVPixelBuffer, textureCache: CVMetalTextureCache, commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, drawable: CAMetalDrawable) {
        guard let pipelineState = renderPipelineStateNV12 else { return }
        
        do {
            let is10Bit = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            let pixelFormatY: MTLPixelFormat = is10Bit ? .r16Uint : .r8Unorm
            let pixelFormatUV: MTLPixelFormat = is10Bit ? .rg16Uint : .rg8Unorm
            
            let textureY = try pixelBuffer.makeMetalTexture(cache: textureCache, pixelFormat: pixelFormatY, planeIndex: 0)
            let textureUV = try pixelBuffer.makeMetalTexture(cache: textureCache, pixelFormat: pixelFormatUV, planeIndex: 1)
            
            // Choose color matrix
            var colorMatrix = bt709Matrix
            if let colorPrimaries = CVBufferGetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, nil) {
                if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                    colorMatrix = bt2020Matrix
                }
            }
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            renderEncoder?.setRenderPipelineState(pipelineState)
            renderEncoder?.setFragmentTexture(textureY, index: 0)
            renderEncoder?.setFragmentTexture(textureUV, index: 1)
            
            // Set uniforms
            var matrix = colorMatrix
            renderEncoder?.setFragmentBytes(&matrix, length: MemoryLayout<simd_float3x3>.size, index: 0)
            
            renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder?.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            print("NV12 Rendering error: \(error)")
        }
    }
    
    private func renderBGRA(_ pixelBuffer: CVPixelBuffer, textureCache: CVMetalTextureCache, commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, drawable: CAMetalDrawable) {
        guard let pipelineState = renderPipelineState else { return }
        
        do {
            let texture = try pixelBuffer.makeMetalTexture(cache: textureCache, pixelFormat: .bgra8Unorm)
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            renderEncoder?.setRenderPipelineState(pipelineState)
            renderEncoder?.setFragmentTexture(texture, index: 0)
            renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder?.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            print("BGRA Rendering error: \(error)")
        }
    }
}

extension MetalVideoRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        render(in: view)
    }
}
