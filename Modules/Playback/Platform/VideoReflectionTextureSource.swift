import AVFoundation
import CoreVideo
import Metal
import RealityKit

@MainActor
final class VideoReflectionTextureSource {
    static let width = 128
    static let height = 72

    private(set) var textureResource: TextureResource?
    private var lowLevelTexture: LowLevelTexture?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelines: [String: MTLComputePipelineState] = [:]
    private var textureCache: CVMetalTextureCache?
    private var lastBufferIdentity: UInt?
    private(set) var failure: String?
    private(set) var frameCount: UInt64 = 0
    private(set) var preparation: Preparation?
    private(set) var lastFormat: OSType?
    private(set) var lastPlaneCount = 0

    struct Preparation: Equatable {
        var width: Int
        var height: Int
        var pixelFormat: MTLPixelFormat
    }

    struct Conversion {
        var matrix: Int32
        var fullRange: Int32
        var transfer: Int32
        var bitDepthScale: Float
        var padding: Float = 0
    }

    func refresh(from renderer: AVSampleBufferVideoRenderer) -> Bool {
        guard failure == nil else { return false }
        guard let pixelBuffer = renderer.displayedPixelBuffer() else { return false }
        let identity = UInt(bitPattern: Int(CFHash(pixelBuffer)))
        guard identity != lastBufferIdentity else { return false }
        do {
            try prepareIfNeeded()
            try encode(pixelBuffer)
            lastBufferIdentity = identity
            frameCount &+= 1
            return true
        } catch {
            failure = String(describing: error)
            return false
        }
    }

    private func prepareIfNeeded() throws {
        guard lowLevelTexture == nil else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw ReflectionError.metalUnavailable
        }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let cache else { throw ReflectionError.metalUnavailable }
        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.arrayLength = 1
        descriptor.width = Self.width
        descriptor.height = Self.height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = 1
        descriptor.pixelFormat = .rgba16Float
        descriptor.textureUsage = [.shaderRead, .shaderWrite]
        let texture = try LowLevelTexture(descriptor: descriptor)
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        for name in ["reflectionFromBiplanar", "reflectionFromBGRA"] {
            guard let function = library.makeFunction(name: name) else {
                throw ReflectionError.pipelineMissing(name)
            }
            pipelines[name] = try device.makeComputePipelineState(function: function)
        }
        self.device = device
        commandQueue = queue
        textureCache = cache
        lowLevelTexture = texture
        textureResource = try TextureResource(from: texture)
        preparation = Preparation(
            width: descriptor.width,
            height: descriptor.height,
            pixelFormat: descriptor.pixelFormat
        )
    }

    private func encode(_ pixelBuffer: CVPixelBuffer) throws {
        guard let device, let commandQueue, let textureCache, let lowLevelTexture else {
            throw ReflectionError.metalUnavailable
        }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        var conversion = Conversion(
            matrix: Self.matrixCode(for: pixelBuffer),
            fullRange: Self.isFullRange(format) ? 1 : 0,
            transfer: Self.transferCode(for: pixelBuffer),
            bitDepthScale: 1
        )
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ReflectionError.metalUnavailable
        }
        let output = lowLevelTexture.replace(using: commandBuffer)
        if planeCount == 2 {
            let tenBit = Self.isTenBit(format)
            let luma = try Self.planeTexture(
                pixelBuffer, plane: 0, format: tenBit ? .r16Unorm : .r8Unorm, cache: textureCache
            )
            let chroma = try Self.planeTexture(
                pixelBuffer, plane: 1, format: tenBit ? .rg16Unorm : .rg8Unorm, cache: textureCache
            )
            guard let pipeline = pipelines["reflectionFromBiplanar"] else {
                throw ReflectionError.pipelineMissing("reflectionFromBiplanar")
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(CVMetalTextureGetTexture(luma), index: 0)
            encoder.setTexture(CVMetalTextureGetTexture(chroma), index: 1)
            encoder.setTexture(output, index: 2)
            encoder.setBytes(&conversion, length: MemoryLayout<Conversion>.stride, index: 0)
            Self.dispatch(encoder, pipeline: pipeline, device: device)
        } else if format == kCVPixelFormatType_32BGRA {
            let color = try Self.planeTexture(pixelBuffer, plane: 0, format: .bgra8Unorm, cache: textureCache)
            guard let pipeline = pipelines["reflectionFromBGRA"] else {
                throw ReflectionError.pipelineMissing("reflectionFromBGRA")
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(CVMetalTextureGetTexture(color), index: 0)
            encoder.setTexture(output, index: 2)
            encoder.setBytes(&conversion, length: MemoryLayout<Conversion>.stride, index: 0)
            Self.dispatch(encoder, pipeline: pipeline, device: device)
        } else {
            encoder.endEncoding()
            throw ReflectionError.unsupportedPixelFormat(format)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        lastFormat = format
        lastPlaneCount = planeCount
    }

    private static func dispatch(
        _ encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        device: MTLDevice
    ) {
        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        )
    }

    private static func planeTexture(
        _ pixelBuffer: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat,
        cache: CVMetalTextureCache
    ) throws -> CVMetalTexture {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, format, width, height, plane, &texture
        )
        guard status == kCVReturnSuccess, let texture else {
            throw ReflectionError.planeUnavailable(plane, status)
        }
        return texture
    }

    private static func isTenBit(_ format: OSType) -> Bool {
        switch format {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
            true
        default:
            false
        }
    }

    private static func isFullRange(_ format: OSType) -> Bool {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_32BGRA:
            true
        default:
            false
        }
    }

    private static func matrixCode(for pixelBuffer: CVPixelBuffer) -> Int32 {
        guard let value = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil),
              let matrix = value as? String else {
            return 0
        }
        if matrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String { return 1 }
        if matrix == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String { return 2 }
        return 0
    }

    private static func transferCode(for pixelBuffer: CVPixelBuffer) -> Int32 {
        guard let value = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil),
              let transfer = value as? String else {
            return 0
        }
        if transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { return 1 }
        if transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { return 2 }
        return 0
    }

    enum ReflectionError: Error {
        case metalUnavailable
        case pipelineMissing(String)
        case unsupportedPixelFormat(OSType)
        case planeUnavailable(Int, CVReturn)
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Conversion {
        int matrix;
        int fullRange;
        int transfer;
        float bitDepthScale;
        float padding;
    };

    static float3 ycbcrToRGB(float3 ycc, constant Conversion &c) {
        float y = ycc.x * c.bitDepthScale;
        float cb = ycc.y * c.bitDepthScale - 0.5;
        float cr = ycc.z * c.bitDepthScale - 0.5;
        if (c.fullRange == 0) {
            y = (y - 16.0 / 255.0) * (255.0 / 219.0);
            cb *= 255.0 / 224.0;
            cr *= 255.0 / 224.0;
        }
        float kr, kb;
        if (c.matrix == 1) { kr = 0.2627; kb = 0.0593; }
        else if (c.matrix == 2) { kr = 0.299; kb = 0.114; }
        else { kr = 0.2126; kb = 0.0722; }
        float kg = 1.0 - kr - kb;
        float r = y + 2.0 * (1.0 - kr) * cr;
        float b = y + 2.0 * (1.0 - kb) * cb;
        float g = (y - kr * r - kb * b) / kg;
        return saturate(float3(r, g, b));
    }

    static float3 toLinear(float3 encoded, constant Conversion &c) {
        if (c.transfer == 1) {
            float m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
            float3 p = pow(encoded, 1.0 / m2);
            float3 num = max(p - c1, 0.0);
            float3 den = c2 - c3 * p;
            float3 nits = pow(num / den, 1.0 / m1) * 10000.0;
            return min(nits / 203.0, 4.0);
        }
        if (c.transfer == 2) {
            float3 lin;
            for (int i = 0; i < 3; i++) {
                float v = encoded[i];
                lin[i] = v <= 0.5 ? (v * v) / 3.0 : (exp((v - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
            }
            return min(lin * 4.0, 4.0);
        }
        return pow(encoded, 2.2);
    }

    kernel void reflectionFromBiplanar(
        texture2d<float, access::sample> luma [[texture(0)]],
        texture2d<float, access::sample> chroma [[texture(1)]],
        texture2d<half, access::write> output [[texture(2)]],
        constant Conversion &conversion [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
        constexpr sampler linearSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float y = luma.sample(linearSampler, uv).r;
        float2 cbcr = chroma.sample(linearSampler, uv).rg;
        float3 rgb = ycbcrToRGB(float3(y, cbcr), conversion);
        float3 lin = toLinear(rgb, conversion);
        output.write(half4(half3(lin), 1.0h), gid);
    }

    kernel void reflectionFromBGRA(
        texture2d<float, access::sample> color [[texture(0)]],
        texture2d<half, access::write> output [[texture(2)]],
        constant Conversion &conversion [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
        constexpr sampler linearSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float3 rgb = color.sample(linearSampler, uv).rgb;
        float3 lin = toLinear(rgb, conversion);
        output.write(half4(half3(lin), 1.0h), gid);
    }
    """
}
