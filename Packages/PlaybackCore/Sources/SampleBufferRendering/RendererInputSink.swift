@preconcurrency import AVFoundation
import Foundation

public enum RendererEnqueueOutcome: Sendable, Equatable {
    case accepted
    case acceptedWithWarnings([String])
    case cancelledByFlush
    case requiresFlush(String?)
    case failed(String)
}

public struct RendererInputSample: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer

    public init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

public enum RendererInputEventFact: Sendable {
    case warning(rendererKind: RendererFailureKind, message: String)
    case failure(RendererFailureFact)
}

public protocol RendererInputSink: AnyObject {
    func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome
    func flush(removingDisplayedImage: Bool) async
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    )
    func stopRenderingEventObservation()
}

public protocol AudioRendererInputSink: AnyObject {
    func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome
    func flush()
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    )
    func stopRenderingEventObservation()
}

public extension RendererInputSink {
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {}
    func stopRenderingEventObservation() {}
}

public extension AudioRendererInputSink {
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {}
    func stopRenderingEventObservation() {}
}

public final class AVSampleBufferRendererInputSink: RendererInputSink, @unchecked Sendable {
    private let receiver: AVSampleBufferVideoRenderer.Receiver
    private let eventTaskLock = NSLock()
    private var eventTask: Task<Void, Never>?

    public init(receiver: consuming AVSampleBufferVideoRenderer.Receiver) {
        self.receiver = receiver
    }

    public func enqueueImmediately(_ input: RendererInputSample) throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(receiver.enqueueImmediately(readySample))
    }

    private static func outcome(
        _ result: AVSampleBufferVideoRenderer.Receiver.EnqueueResult
    ) -> RendererEnqueueOutcome {
        switch result {
        case .enqueued:
            return .accepted
        case .enqueuedWithDecodeFailures(let errors):
            return .acceptedWithWarnings(errors.map(\.localizedDescription))
        case .cancelledDueToFlush:
            return .cancelledByFlush
        case .cancelledDueToFlushRequiredToResume(let error):
            return .requiresFlush(error.localizedDescription)
        case .cancelledDueToError(let error):
            return .failed(error.localizedDescription)
        @unknown default:
            return .failed("Video receiver returned an unknown enqueue result.")
        }
    }

    public func flush(removingDisplayedImage: Bool) async {
        await receiver.flush(removingDisplayedImage: removingDisplayedImage)
    }

    public func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {
        stopRenderingEventObservation()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            for await event in receiver.renderingEventsAfterFinishedEnqueuing {
                switch event {
                case .didFailToDecode(let errors):
                    handler(.warning(
                        rendererKind: .video,
                        message: errors.map(\.localizedDescription).joined(separator: " | ")
                    ))
                case .failed(let error):
                    handler(.failure(RendererFailureFact(
                        rendererKind: .video,
                        errorType: String(reflecting: type(of: error)),
                        message: error.localizedDescription,
                        requiresFlushToResumeDecoding: false
                    )))
                default:
                    handler(.failure(RendererFailureFact(
                        rendererKind: .video,
                        errorType: "AVSampleBufferVideoRenderer.RequiresFlush",
                        message: "Video renderer requires a flush before decoding can resume.",
                        requiresFlushToResumeDecoding: true
                    )))
                }
            }
        }
        eventTaskLock.withLock { eventTask = task }
    }

    public func stopRenderingEventObservation() {
        eventTaskLock.withLock {
            eventTask?.cancel()
            eventTask = nil
        }
    }
}

public final class AVSampleBufferAudioRendererInputSink: AudioRendererInputSink, @unchecked Sendable {
    private let receiver: AVSampleBufferAudioRenderer.Receiver
    private let eventTaskLock = NSLock()
    private var eventTask: Task<Void, Never>?

    public init(receiver: consuming AVSampleBufferAudioRenderer.Receiver) {
        self.receiver = receiver
    }

    public func enqueueImmediately(_ input: RendererInputSample) throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(receiver.enqueueImmediately(readySample))
    }

    private static func outcome(
        _ result: AVSampleBufferAudioRenderer.Receiver.EnqueueResult
    ) -> RendererEnqueueOutcome {
        switch result {
        case .enqueued:
            .accepted
        case .enqueuedWithSuggestedFlush(let reasons):
            .acceptedWithWarnings(reasons.map { String(describing: $0) })
        case .cancelledDueToFlush:
            .cancelledByFlush
        case .cancelledDueToError(let error):
            .failed(error.localizedDescription)
        @unknown default:
            .failed("Audio receiver returned an unknown enqueue result.")
        }
    }

    public func flush() {
        receiver.flush()
    }

    public func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {
        stopRenderingEventObservation()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            for await event in self.receiver.renderingEventsAfterFinishedEnqueuing {
                switch event {
                case .wasFlushedAutomatically(let time):
                    handler(.warning(
                        rendererKind: .audio,
                        message: "Audio receiver flushed automatically at \(time.seconds)s."
                    ))
                case .outputConfigurationChanged:
                    handler(.warning(
                        rendererKind: .audio,
                        message: "Audio receiver output configuration changed."
                    ))
                case .failed(let error):
                    handler(.failure(RendererFailureFact(
                        rendererKind: .audio,
                        errorType: String(reflecting: type(of: error)),
                        message: error.localizedDescription,
                        requiresFlushToResumeDecoding: nil
                    )))
                @unknown default:
                    handler(.warning(
                        rendererKind: .audio,
                        message: "Audio receiver emitted an unknown rendering event."
                    ))
                }
            }
        }
        eventTaskLock.withLock { eventTask = task }
    }

    public func stopRenderingEventObservation() {
        eventTaskLock.withLock {
            eventTask?.cancel()
            eventTask = nil
        }
    }
}
