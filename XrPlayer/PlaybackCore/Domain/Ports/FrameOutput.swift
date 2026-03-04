import CoreVideo

public protocol FrameOutput: AnyObject {
    func didOutputFrame(_ pixelBuffer: CVPixelBuffer)
}
