---
name: metal-graphics
description: Metal GPU graphics for games - render pipeline, shaders, MTKView, MetalFX upscaling. Triggers on Metal, GPU, graphics, shaders, render pipeline, MTKView, game rendering, 3D graphics.
---

# Metal Graphics

## MTKView Setup

```swift
// UIKit
class GameViewController: UIViewController {
    var metalView: MTKView!
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        metalView = MTKView(frame: view.bounds, device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        view.addSubview(metalView)
        renderer = Renderer(metalView: metalView)
        metalView.delegate = renderer
    }
}

// SwiftUI
struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView()
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        context.coordinator.renderer = Renderer(metalView: view)
        view.delegate = context.coordinator.renderer
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var renderer: Renderer? }
}
```

## Renderer

```swift
class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!

    init(metalView: MTKView) {
        device = metalView.device!
        commandQueue = device.makeCommandQueue()!
        super.init()

        let library = device.makeDefaultLibrary()!
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertex_main")
        desc.fragmentFunction = library.makeFunction(name: "fragment_main")
        desc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        desc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let desc = view.currentRenderPassDescriptor else { return }
        let cmd = commandQueue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: desc)!
        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)
        // Draw calls here
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
```

## Shaders (Metal Shading Language)

```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    VertexOut out;
    out.position = u.projectionMatrix * u.viewMatrix * u.modelMatrix * float4(in.position, 1.0);
    out.color = in.color;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
    return tex.sample(s, in.texCoord) * in.color;
}
```

## Vertex Data

```swift
struct Vertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var texCoord: SIMD2<Float>
}

func buildVertexDescriptor() -> MTLVertexDescriptor {
    let d = MTLVertexDescriptor()
    d.attributes[0].format = .float3; d.attributes[0].offset = 0; d.attributes[0].bufferIndex = 0
    d.attributes[1].format = .float4; d.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride; d.attributes[1].bufferIndex = 0
    d.attributes[2].format = .float2; d.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride; d.attributes[2].bufferIndex = 0
    d.layouts[0].stride = MemoryLayout<Vertex>.stride
    return d
}

// Use .stride not .size for buffer lengths (alignment)
let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .storageModeShared)!
```

## Uniforms & Matrices

```swift
struct Uniforms { var modelMatrix, viewMatrix, projectionMatrix: float4x4 }
encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

extension float4x4 {
    static var identity: float4x4 { matrix_identity_float4x4 }
    init(translation t: SIMD3<Float>) { self = float4x4([[1,0,0,0],[0,1,0,0],[0,0,1,0],[t.x,t.y,t.z,1]]) }
    init(rotationY a: Float) { let c=cos(a),s=sin(a); self = float4x4([[c,0,-s,0],[0,1,0,0],[s,0,c,0],[0,0,0,1]]) }
    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let y=1/tan(fov*0.5), x=y/aspect, z=far/(near-far)
        return float4x4([[x,0,0,0],[0,y,0,0],[0,0,z,-1],[0,0,z*near,0]])
    }
}
```

## Textures

```swift
func loadTexture(_ name: String) -> MTLTexture? {
    try? MTKTextureLoader(device: device).newTexture(name: name, scaleFactor: 1, bundle: nil, options: [.generateMipmaps: true])
}

func samplerState() -> MTLSamplerState {
    let d = MTLSamplerDescriptor()
    d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear
    return device.makeSamplerState(descriptor: d)!
}

encoder.setFragmentTexture(texture, index: 0)
encoder.setFragmentSamplerState(sampler, index: 0)
```

## Draw Commands

```swift
encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: 100)
```

## MetalFX Upscaling

```swift
import MetalFX

// Spatial (simpler, no motion vectors)
let desc = MTLFXSpatialScalerDescriptor()
desc.inputWidth = 1920; desc.inputHeight = 1080
desc.outputWidth = 3840; desc.outputHeight = 2160
desc.colorTextureFormat = .bgra8Unorm; desc.outputTextureFormat = .bgra8Unorm
let upscaler = desc.makeSpatialScaler(device: device)!
upscaler.colorTexture = inputTex; upscaler.outputTexture = outputTex
upscaler.encode(commandBuffer: cmd)

// Temporal (better quality, needs motion vectors + depth)
let tdesc = MTLFXTemporalScalerDescriptor()
tdesc.inputWidth = 1920; tdesc.inputHeight = 1080
tdesc.outputWidth = 3840; tdesc.outputHeight = 2160
tdesc.colorTextureFormat = .bgra8Unorm; tdesc.depthTextureFormat = .depth32Float
tdesc.motionTextureFormat = .rg16Float; tdesc.outputTextureFormat = .bgra8Unorm
let temporal = tdesc.makeTemporalScaler(device: device)!
temporal.colorTexture = color; temporal.depthTexture = depth; temporal.motionTexture = motion
temporal.outputTexture = output; temporal.jitterOffsetX = jx; temporal.jitterOffsetY = jy
temporal.encode(commandBuffer: cmd)
```

## Frame Timing

```swift
var lastTime: CFTimeInterval = 0
func draw(in view: MTKView) {
    let now = CACurrentMediaTime()
    let dt = Float(now - lastTime); lastTime = now
    update(deltaTime: dt)
    render(in: view)
}

metalView.preferredFramesPerSecond = 60 // or 30 for demanding games
```

## Storage Modes

- `.storageModeShared` - CPU writes, GPU reads
- `.storageModePrivate` - GPU only (faster)
- Triple-buffer with shared for streaming data

## MCP Integration

**Context7**: `/websites/developer_apple` - Query "Metal tvOS", "MTKView", "MetalFX upscaling"

**Serena**: `find_symbol "MTKViewDelegate"` - Renderer setup; `search_for_pattern "makeRenderPipelineState"` - Pipeline config
