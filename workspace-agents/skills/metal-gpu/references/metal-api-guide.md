# Metal API Reference Guide

Detailed reference for Metal API patterns, Metal 4, and Apple Silicon optimization.

## Table of Contents
1. [Metal 4 Core API](#metal-4-core-api)
2. [Command Encoding Deep Dive](#command-encoding)
3. [Resource Management](#resource-management)
4. [Shader Compilation & Libraries](#shader-compilation)
5. [Apple Silicon Optimization](#apple-silicon)
6. [Presentation & Display](#presentation)
7. [Ray Tracing](#ray-tracing)
8. [Debugging & Profiling](#debugging)

---

## Metal 4 Core API

Metal 4 modernizes the foundational APIs. Key documentation entry points:

- **Understanding the Metal 4 core API**: Discover features and functionality in Metal 4 foundational APIs
- **Drawing a triangle with Metal 4**: Render a colorful, rotating 2D triangle with draw commands
- **New compilation API**: Finer control over when and how shaders compile

When writing Metal 4 code, prefer the updated patterns documented at:
https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api

---

## Command Encoding

Metal uses a command-based architecture. The hierarchy:

### GPU Device
```swift
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal not supported on this device")
}
```

On macOS with multiple GPUs, use `MTLCopyAllDevices()` to enumerate.

### Command Queue
One queue per app is typical. Thread-safe — can create command buffers from any thread.
```swift
let commandQueue = device.makeCommandQueue()!
```

### Command Buffer
Transient — create per frame, don't reuse. Contains encoded commands.
```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
// Encode commands...
commandBuffer.commit()
commandBuffer.waitUntilCompleted() // Only if you need synchronous execution
```

### Encoder Types

| Encoder | Purpose | Key Methods |
|---------|---------|-------------|
| `MTLRenderCommandEncoder` | Drawing geometry | `setVertexBuffer`, `drawPrimitives`, `drawIndexedPrimitives` |
| `MTLComputeCommandEncoder` | Parallel computation | `setBuffer`, `dispatchThreads`, `dispatchThreadgroups` |
| `MTLBlitCommandEncoder` | Data transfer/copy | `copy(from:to:)`, `generateMipmaps`, `fill` |

### Indirect Command Buffers
Store draw/compute commands in Metal buffers for GPU-driven rendering:
```swift
let icbDescriptor = MTLIndirectCommandBufferDescriptor()
icbDescriptor.commandTypes = [.draw, .drawIndexed]
icbDescriptor.maxVertexBufferBindCount = 10
icbDescriptor.maxFragmentBufferBindCount = 10
let icb = device.makeIndirectCommandBuffer(descriptor: icbDescriptor, maxCommandCount: 1000)!
```

---

## Resource Management

### Buffers
```swift
// Shared memory (CPU + GPU access, Apple Silicon preferred)
let buffer = device.makeBuffer(bytes: data, length: byteLength, options: .storageModeShared)!

// Private memory (GPU only, fastest for GPU-exclusive data)
let privateBuffer = device.makeBuffer(length: byteLength, options: .storageModePrivate)!
```

### Textures
```swift
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba8Unorm,
    width: 512, height: 512,
    mipmapped: true
)
descriptor.usage = [.shaderRead, .renderTarget]
let texture = device.makeTexture(descriptor: descriptor)!
```

### Heaps (Manual Memory Management)
For advanced memory control — allocate a large heap, then suballocate:
```swift
let heapDescriptor = MTLHeapDescriptor()
heapDescriptor.size = 256 * 1024 * 1024 // 256 MB
heapDescriptor.storageMode = .private
let heap = device.makeHeap(descriptor: heapDescriptor)!
let textureFromHeap = heap.makeTexture(descriptor: textureDescriptor)!
```

### Synchronization
- **MTLFence**: Synchronize within a command buffer between encoders
- **MTLEvent**: Synchronize across command buffers
- **MTLSharedEvent**: Synchronize between CPU and GPU, or across devices

```swift
let event = device.makeEvent()!
// Encoder A signals
encoderA.updateFence(fence, after: .fragment)
// Encoder B waits
encoderB.waitForFence(fence, before: .vertex)
```

---

## Shader Compilation

### Runtime Compilation
```swift
let library = try device.makeLibrary(source: mslSource, options: nil)
```

### Precompiled Libraries (Preferred)
Add `.metal` files to Xcode target. Access at runtime:
```swift
let library = device.makeDefaultLibrary()!
let function = library.makeFunction(name: "my_shader")!
```

### Function Specialization
Create pipeline variants from a common shader with function constants:
```metal
constant bool useTexture [[function_constant(0)]];

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    if (useTexture) {
        // textured path
    } else {
        // color-only path
    }
}
```

```swift
let constants = MTLFunctionConstantValues()
var useTexture = true
constants.setConstantValue(&useTexture, type: .bool, index: 0)
let function = try library.makeFunction(name: "fragment_main", constantValues: constants)
```

### Metal 4 Compilation API
Metal 4 provides finer-grained control over shader compilation timing and caching.
See: https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api

---

## Apple Silicon Optimization

Apple Silicon GPUs use **tile-based deferred rendering (TBDR)**. This changes optimization strategies significantly.

### Key Features
- **Unified memory**: CPU and GPU share the same memory — use `.storageModeShared`
- **Tile memory (imageblocks)**: On-chip memory for tile shaders — no bandwidth cost
- **Raster order groups**: Guaranteed order for overlapping fragment operations
- **SIMD-group functions**: Efficient cross-lane operations in shader code

### Tile Shaders
Access tile memory directly in fragment shaders for deferred rendering:
```metal
struct GBufferData {
    half4 albedo   [[color(0)]];
    half4 normal   [[color(1)]];
    float depth    [[color(2)]];
};

kernel void lighting_tile(imageblock<GBufferData> imageBlock,
                          ushort2 tid [[thread_position_in_threadgroup]]) {
    GBufferData gBuffer = imageBlock.read(tid);
    // Perform lighting calculation using tile data
}
```

### Porting from Intel Mac
- Replace `.storageModeManaged` with `.storageModeShared` (no synchronize needed)
- Remove `didModifyRange:` calls
- Use `dispatchThreads` instead of `dispatchThreadgroups` when possible
- Leverage TBDR: Avoid unnecessary load/store actions on render targets
- Set `storeAction = .dontCare` for transient attachments (depth/stencil)

---

## Presentation

### MetalKit View (Recommended)
```swift
let mtkView = MTKView(frame: frame, device: device)
mtkView.colorPixelFormat = .bgra8Unorm
mtkView.depthStencilPixelFormat = .depth32Float
mtkView.delegate = renderer
```

### CAMetalLayer (Manual)
```swift
let metalLayer = CAMetalLayer()
metalLayer.device = device
metalLayer.pixelFormat = .bgra8Unorm
metalLayer.framebufferOnly = true

// In render loop:
guard let drawable = metalLayer.nextDrawable() else { return }
// Render to drawable.texture, then:
commandBuffer.present(drawable)
```

### HDR Content
Use `.rgba16Float` pixel format and set EDR metadata for high dynamic range.

### visionOS
Use Compositor Services for fully immersive stereoscopic content:
- Render separate views for each eye
- Configure with `CompositorLayerConfiguration`

---

## Ray Tracing

Build acceleration structures for ray-scene intersection:

```swift
// Geometry descriptor
let geometryDescriptor = MTLAccelerationStructureTriangleGeometryDescriptor()
geometryDescriptor.vertexBuffer = vertexBuffer
geometryDescriptor.triangleCount = triangleCount

// Build
let accelDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
accelDescriptor.geometryDescriptors = [geometryDescriptor]

let sizes = device.accelerationStructureSizes(descriptor: accelDescriptor)
let accelStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
let scratchBuffer = device.makeBuffer(length: sizes.buildScratchBufferSize)!

let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
encoder.build(accelerationStructure: accelStructure, descriptor: accelDescriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
encoder.endEncoding()
```

In MSL, use the `intersector` and `intersection_result` types for ray queries.

---

## Debugging & Profiling

### GPU Frame Capture (Xcode)
```swift
let captureManager = MTLCaptureManager.shared()
let captureDescriptor = MTLCaptureDescriptor()
captureDescriptor.captureObject = device
try captureManager.startCapture(with: captureDescriptor)
// ... render frame ...
captureManager.stopCapture()
```

### Shader Logging
```metal
#include <metal_logging>
os_log_default.log("Value: %f", myValue);
```

### Simulator Support
Metal in Simulator requires alternative render paths. Check with:
```swift
#if targetEnvironment(simulator)
// Use simplified rendering or software fallback
#endif
```

### Metal Debugger
Use Xcode's Metal Debugger for:
- GPU trace analysis
- Shader profiling
- Memory inspection
- Dependency viewer
- Pipeline statistics

---

## Common Data Type Mappings (Swift ↔ MSL)

| Swift | MSL | Size |
|-------|-----|------|
| `SIMD2<Float>` | `float2` | 8 bytes |
| `SIMD3<Float>` | `float3` | 16 bytes (padded!) |
| `SIMD4<Float>` | `float4` | 16 bytes |
| `float4x4` | `float4x4` | 64 bytes |
| `UInt32` | `uint` | 4 bytes |
| `Float` | `float` | 4 bytes |
| `simd_half4` | `half4` | 8 bytes |

**Important**: `SIMD3<Float>` / `float3` is padded to 16 bytes. Account for this in buffer layouts or use packed types (`packed_float3` in MSL).
