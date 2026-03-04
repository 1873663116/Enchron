import CoreVideo
import Metal

public enum CVPixelBufferTextureError: Error {
    case textureCreationFailed
}

public extension CVPixelBuffer {
    func makeMetalTexture(
        cache: CVMetalTextureCache,
        pixelFormat: MTLPixelFormat,
        planeIndex: Int = 0
    ) throws -> MTLTexture {
        let width: Int
        let height: Int
        
        if CVPixelBufferIsPlanar(self) {
            width = CVPixelBufferGetWidthOfPlane(self, planeIndex)
            height = CVPixelBufferGetHeightOfPlane(self, planeIndex)
        } else {
            width = CVPixelBufferGetWidth(self)
            height = CVPixelBufferGetHeight(self)
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            self,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            throw CVPixelBufferTextureError.textureCreationFailed
        }

        return texture
    }
}
