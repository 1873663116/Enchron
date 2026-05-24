import CoreVideo

public nonisolated protocol FrameOutput: AnyObject {
    func didOutputFrame(_ pixelBuffer: CVPixelBuffer)
}
