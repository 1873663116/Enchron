@preconcurrency import AVFoundation
import Foundation

protocol RendererInputSink: AnyObject {
    var isReadyForMoreMediaData: Bool { get }

    func requestMediaDataWhenReady(
        on queue: DispatchQueue,
        using block: @escaping @Sendable () -> Void
    )
    func stopRequestingMediaData()
    func enqueue(_ sample: CMSampleBuffer)
    func flush(removingDisplayedImage: Bool, completion: @escaping @Sendable () -> Void)
}

final class AVSampleBufferRendererInputSink: RendererInputSink {
    private let renderer: AVSampleBufferVideoRenderer

    init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }

    var isReadyForMoreMediaData: Bool {
        renderer.isReadyForMoreMediaData
    }

    func requestMediaDataWhenReady(
        on queue: DispatchQueue,
        using block: @escaping @Sendable () -> Void
    ) {
        renderer.requestMediaDataWhenReady(on: queue, using: block)
    }

    func stopRequestingMediaData() {
        renderer.stopRequestingMediaData()
    }

    func enqueue(_ sample: CMSampleBuffer) {
        renderer.enqueue(sample)
    }

    func flush(removingDisplayedImage: Bool, completion: @escaping @Sendable () -> Void) {
        renderer.flush(
            removingDisplayedImage: removingDisplayedImage,
            completionHandler: completion
        )
    }
}
