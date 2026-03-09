---
name: metal-gpu
description: >
  Write, explain, and debug Metal GPU code including shaders (vertex, fragment, compute),
  render pipelines, compute pipelines, buffer/texture management, and Metal 4 APIs.
  Use this skill whenever the user mentions Metal, GPU programming, shaders, MSL (Metal Shading Language),
  render passes, compute kernels, MTLDevice, MTLCommandBuffer, MTLRenderPipelineState,
  or any Apple GPU/graphics programming topic. Also trigger when the user wants to do
  parallel computation on Apple devices, write GPU-accelerated code, or work with
  Metal Performance Shaders, MetalFX, MetalKit, or Compositor Services.
  Covers iOS, macOS, iPadOS, tvOS, and visionOS.
---

# Metal GPU Code Skill

Write production-quality Metal code with correct patterns, optimal performance, and clear explanations.

## When to Read References

For detailed API topology, Metal 4 specifics, and Apple Silicon optimization patterns, read:
```
/mnt/skills/user/metal-gpu/references/metal-api-guide.md
```

## Core Principles

1. **Always start with the device**: `MTLCreateSystemDefaultDevice()` — every Metal workflow begins here
2. **Command pattern**: Device → Command Queue → Command Buffer → Command Encoder → Commit
3. **Shaders are MSL (Metal Shading Language)**: C++14-based, with Metal-specific types and attributes
4. **Resource management matters**: Use appropriate storage modes, avoid unnecessary copies
5. **Triple buffering** for render loops to keep CPU and GPU in parallel

## Quick Reference: Metal Command Pipeline

```
MTLDevice
  └─ makeCommandQueue() → MTLCommandQueue
       └─ makeCommandBuffer() → MTLCommandBuffer
            ├─ makeRenderCommandEncoder(descriptor:) → MTLRenderCommandEncoder
            ├─ makeComputeCommandEncoder() → MTLComputeCommandEncoder
            └─ makeBlitCommandEncoder() → MTLBlitCommandEncoder
```

## Writing Shaders (MSL)

Use Metal Shading Language. Always include:
- `#include <metal_stdlib>` and `using namespace metal;`
- Correct attribute qualifiers: `[[vertex_id]]`, `[[position]]`, `[[stage_in]]`, `[[buffer(n)]]`, `[[texture(n)]]`
- Proper address space qualifiers: `device`, `constant`, `threadgroup`, `thread`

### Vertex Shader Pattern
```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 texCoord;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant float4x4 &mvp [[buffer(1)]]) {
    VertexOut out;
    out.position = mvp * float4(in.position, 1.0);
    out.normal = in.normal;
    out.texCoord = in.texCoord;
    return out;
}
```

### Fragment Shader Pattern
```metal
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> albedo [[texture(0)]],
                              sampler texSampler [[sampler(0)]]) {
    float4 color = albedo.sample(texSampler, in.texCoord);
    return color;
}
```

### Compute Kernel Pattern
```metal
kernel void compute_main(device float *input  [[buffer(0)]],
                         device float *output [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    output[id] = input[id] * 2.0;
}
```

## Swift-Side Setup Patterns

### Render Pipeline Setup
```swift
let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!

// Load shaders
let library = device.makeDefaultLibrary()!
let vertexFunction = library.makeFunction(name: "vertex_main")
let fragmentFunction = library.makeFunction(name: "fragment_main")

// Pipeline descriptor
let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = vertexFunction
pipelineDescriptor.fragmentFunction = fragmentFunction
pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

// Vertex descriptor
let vertexDescriptor = MTLVertexDescriptor()
vertexDescriptor.attributes[0].format = .float3  // position
vertexDescriptor.attributes[0].offset = 0
vertexDescriptor.attributes[0].bufferIndex = 0
vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
pipelineDescriptor.vertexDescriptor = vertexDescriptor

let pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
```

### Compute Pipeline Setup
```swift
let computeFunction = library.makeFunction(name: "compute_main")!
let computePipeline = try! device.makeComputePipelineState(function: computeFunction)

let commandBuffer = commandQueue.makeCommandBuffer()!
let encoder = commandBuffer.makeComputeCommandEncoder()!
encoder.setComputePipelineState(computePipeline)
encoder.setBuffer(inputBuffer, offset: 0, index: 0)
encoder.setBuffer(outputBuffer, offset: 0, index: 1)

let gridSize = MTLSize(width: elementCount, height: 1, depth: 1)
let threadGroupSize = MTLSize(
    width: min(computePipeline.maxTotalThreadsPerThreadgroup, elementCount),
    height: 1, depth: 1
)
encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
encoder.endEncoding()
commandBuffer.commit()
```

### MetalKit View Rendering
```swift
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        encoder.setRenderPipelineState(pipelineState)
        // Set buffers, draw primitives...
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

## Performance Best Practices

1. **Storage modes**: Use `.shared` on Apple Silicon (unified memory), `.private` for GPU-only data, `.managed` on Intel Macs
2. **Triple buffering**: Rotate 3 buffers with a semaphore to avoid CPU/GPU stalls
3. **Avoid per-frame allocations**: Reuse buffers and command encoders
4. **Use `dispatchThreads` over `dispatchThreadgroups`** when possible (Apple Silicon)
5. **Prefer tile-based deferred rendering** patterns on Apple GPUs — use imageblocks and tile shaders
6. **Compile pipelines ahead of time**: Pipeline creation is expensive, do it at load time
7. **Use Metal GPU frame capture** in Xcode to profile and debug

## Common Mistakes to Avoid

- Forgetting `encoder.endEncoding()` before committing
- Mismatched buffer indices between Swift and MSL
- Using wrong pixel format for render targets
- Not handling `nil` from optional Metal API calls
- Blocking the main thread waiting for GPU completion — use `addCompletedHandler` instead
- Forgetting to set the vertex descriptor when using `[[stage_in]]`

## Metal 4 Notes

Metal 4 introduces a modernized core API. Key changes:
- New compilation API for finer shader compilation control
- Updated command encoding patterns
- See `references/metal-api-guide.md` for the full Metal 4 API topology

## Frameworks Ecosystem

| Framework | Purpose |
|-----------|---------|
| **Metal** | Direct GPU access, shaders, pipelines |
| **MetalKit** | View management, texture loading, model I/O |
| **MetalFX** | Upscaling (temporal/spatial) for performance |
| **Metal Performance Shaders** | Optimized compute & image processing kernels |
| **Compositor Services** | Stereoscopic rendering for visionOS |
| **RealityKit** | High-level 3D rendering (uses Metal underneath) |
