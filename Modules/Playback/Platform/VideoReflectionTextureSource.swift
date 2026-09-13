import AVFoundation
import CoreVideo
import Metal
import RealityKit
import VideoToolbox

@MainActor
final class VideoReflectionTextureSource {
    nonisolated static let width = 128
    nonisolated static let height = 72
    nonisolated static let mipmapLevelCount = 8
    nonisolated static let linearCeiling: Float = 16

    enum Event {
        case frameEncoded
        case failed(String)
    }

    private(set) var textureResource: TextureResource?
    private var lowLevelTexture: LowLevelTexture?
    private(set) var failure: String?
    private(set) var frameCount: UInt64 = 0
    private(set) var preparation: Preparation?
    private(set) var lastFormat: OSType?
    private(set) var lastPlaneCount = 0

    var onEvent: (@MainActor (Event) -> Void)?

    private var engine: Engine?
    private var pendingEncode: Engine.PendingEncode?

    struct Preparation: Equatable {
        var width: Int
        var height: Int
        var mipmapLevelCount: Int
        var pixelFormat: MTLPixelFormat
    }

    /// Per-update entry point. Returns immediately; the pixel transfer and
    /// Metal encoding run on the engine's serial queue so the update loop
    /// never blocks on VideoToolbox.
    func refresh(from renderer: AVSampleBufferVideoRenderer) {
        guard failure == nil else { return }
        if engine == nil {
            do {
                try prepare()
            } catch {
                failure = String(describing: error)
                onEvent?(.failed(failure!))
                return
            }
        }
        engine?.enqueue(renderer)
    }

    private func prepare() throws {
        guard lowLevelTexture == nil else { return }
        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.arrayLength = 1
        descriptor.width = Self.width
        descriptor.height = Self.height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = Self.mipmapLevelCount
        descriptor.pixelFormat = .rgba16Float
        descriptor.textureUsage = [.shaderRead, .shaderWrite, .renderTarget]
        let texture = try LowLevelTexture(descriptor: descriptor)
        lowLevelTexture = texture
        textureResource = try TextureResource(from: texture)
        preparation = Preparation(
            width: descriptor.width,
            height: descriptor.height,
            mipmapLevelCount: descriptor.mipmapLevelCount,
            pixelFormat: descriptor.pixelFormat
        )
        let engine = try Engine(texture: texture)
        engine.onPending = { [weak self] pending in
            self?.encodePending(pending)
        }
        engine.onFailure = { [weak self] message in
            self?.failure = message
            self?.onEvent?(.failed(message))
        }
        self.engine = engine
    }

    /// Runs on the main queue, right after the engine's background work
    /// produced a scaled source texture. Keeping `replace` + encode + commit
    /// here preserves RealityKit's update→render ordering: the texture write
    /// lands between scene updates instead of racing the render pass that
    /// samples it.
    private func encodePending(_ pending: Engine.PendingEncode) {
        guard let engine else { return }
        pendingEncode = pending
        do {
            let stats = try engine.encode(pending)
            frameCount = stats.frameCount
            lastFormat = stats.format
            lastPlaneCount = stats.planeCount
            onEvent?(.frameEncoded)
        } catch {
            failure = String(describing: error)
            onEvent?(.failed(failure!))
        }
        pendingEncode = nil
    }

    /// Owns the VideoToolbox transfer and the scaled-source wrapping on a
    /// dedicated serial queue. The Metal encode against the LowLevelTexture
    /// is handed back to the main queue (`PendingEncode`) so the texture
    /// write is committed between scene updates instead of racing the render
    /// pass that samples it.
    private nonisolated final class Engine: @unchecked Sendable {
        struct PendingEncode: @unchecked Sendable {
            var source: MTLTexture
            var sourceTexture: CVMetalTexture
            var frameCount: UInt64
            var format: OSType
            var planeCount: Int
        }

        private let queue = DispatchQueue(label: "app.enchron.reflection-transfer")
        private let commandQueue: MTLCommandQueue
        private let pipeline: MTLComputePipelineState
        private let textureCache: CVMetalTextureCache
        private let transferSession: VTPixelTransferSession
        private let scaledBuffers: [CVPixelBuffer]
        private let texture: LowLevelTexture
        private var writeIndex = 0
        private var pendingIndex: Int?
        private var lastBufferIdentity: UInt?
        private var frameCount: UInt64 = 0
        private var failure: String?

        var onPending: (@MainActor (PendingEncode) -> Void)?

        init(texture: LowLevelTexture) throws {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else {
                throw ReflectionError.metalUnavailable
            }
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            guard let cache else { throw ReflectionError.metalUnavailable }
            var session: VTPixelTransferSession?
            let created = VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
            guard created == noErr, let session else { throw ReflectionError.transferUnavailable(created) }
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Normal)
            VTSessionSetProperty(
                session,
                key: kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                value: kCVImageBufferColorPrimaries_ITU_R_709_2
            )
            VTSessionSetProperty(
                session,
                key: kVTPixelTransferPropertyKey_DestinationTransferFunction,
                value: kCVImageBufferTransferFunction_Linear
            )
            let attributes: [CFString: Any] = [
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
            ]
            var buffers: [CVPixelBuffer] = []
            for _ in 0..<2 {
                var scaled: CVPixelBuffer?
                let allocated = CVPixelBufferCreate(
                    nil, VideoReflectionTextureSource.width, VideoReflectionTextureSource.height,
                    kCVPixelFormatType_64RGBAHalf, attributes as CFDictionary, &scaled
                )
                guard allocated == kCVReturnSuccess, let scaled else {
                    throw ReflectionError.bufferUnavailable(allocated)
                }
                buffers.append(scaled)
            }
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "reflectionClamp") else {
                throw ReflectionError.pipelineMissing("reflectionClamp")
            }
            self.texture = texture
            commandQueue = queue
            textureCache = cache
            transferSession = session
            scaledBuffers = buffers
            pipeline = try device.makeComputePipelineState(function: function)
        }

        func enqueue(_ renderer: AVSampleBufferVideoRenderer) {
            queue.async { [weak self] in self?.perform(renderer) }
        }

        private func perform(_ renderer: AVSampleBufferVideoRenderer) {
            guard failure == nil else { return }
            guard pendingIndex == nil else { return }
            guard let pixelBuffer = renderer.displayedPixelBuffer() else { return }
            let identity = UInt(bitPattern: Int(CFHash(pixelBuffer)))
            guard identity != lastBufferIdentity else { return }
            let bufferIndex = writeIndex
            let transferred = VTPixelTransferSessionTransferImage(
                transferSession, from: pixelBuffer, to: scaledBuffers[bufferIndex]
            )
            guard transferred == noErr else {
                fail(ReflectionError.transferFailed(transferred))
                return
            }
            var cvTexture: CVMetalTexture?
            let wrapped = CVMetalTextureCacheCreateTextureFromImage(
                nil, textureCache, scaledBuffers[bufferIndex], nil, .rgba16Float,
                VideoReflectionTextureSource.width, VideoReflectionTextureSource.height, 0, &cvTexture
            )
            guard wrapped == kCVReturnSuccess, let cvTexture,
                  let source = CVMetalTextureGetTexture(cvTexture) else {
                fail(ReflectionError.textureUnavailable(wrapped))
                return
            }
            lastBufferIdentity = identity
            writeIndex = 1 - writeIndex
            pendingIndex = bufferIndex
            frameCount &+= 1
            let pending = PendingEncode(
                source: source,
                sourceTexture: cvTexture,
                frameCount: frameCount,
                format: CVPixelBufferGetPixelFormatType(pixelBuffer),
                planeCount: CVPixelBufferGetPlaneCount(pixelBuffer)
            )
            DispatchQueue.main.async { [onPending] in
                guard let onPending else { return }
                MainActor.assumeIsolated { onPending(pending) }
            }
        }

        private func fail(_ error: ReflectionError) {
            let message = String(describing: error)
            failure = message
            DispatchQueue.main.async { [onFailure] in
                guard let onFailure else { return }
                MainActor.assumeIsolated { onFailure(message) }
            }
        }

        var onFailure: (@MainActor (String) -> Void)?

        @MainActor
        func encode(_ pending: PendingEncode) throws -> PendingEncode {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw ReflectionError.metalUnavailable
            }
            let output = texture.replace(using: commandBuffer)
            var ceiling = VideoReflectionTextureSource.linearCeiling
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(pending.source, index: 0)
            encoder.setTexture(output, index: 1)
            encoder.setBytes(&ceiling, length: MemoryLayout<Float>.stride, index: 0)
            let threadWidth = pipeline.threadExecutionWidth
            let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
            encoder.dispatchThreads(
                MTLSize(width: VideoReflectionTextureSource.width,
                        height: VideoReflectionTextureSource.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
            )
            encoder.endEncoding()
            guard let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw ReflectionError.metalUnavailable
            }
            blit.generateMipmaps(for: output)
            blit.endEncoding()
            commandBuffer.commit()
            queue.async { [weak self] in self?.pendingIndex = nil }
            return pending
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void reflectionClamp(
            texture2d<half, access::read> source [[texture(0)]],
            texture2d<half, access::write> output [[texture(1)]],
            constant float &ceiling [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            float3 value = clamp(float3(source.read(gid).rgb), 0.0, ceiling);
            output.write(half4(half3(value), 1.0h), gid);
        }
        """
    }

    enum ReflectionError: Error {
        case metalUnavailable
        case pipelineMissing(String)
        case transferUnavailable(OSStatus)
        case transferFailed(OSStatus)
        case bufferUnavailable(CVReturn)
        case textureUnavailable(CVReturn)
    }
}
