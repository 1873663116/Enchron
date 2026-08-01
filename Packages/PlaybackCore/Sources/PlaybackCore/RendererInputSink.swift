@preconcurrency import AVFoundation
import Foundation

enum RendererEnqueueOutcome: Sendable, Equatable {
    case accepted
    case acceptedWithWarnings([String])
    case cancelledByFlush
    case requiresFlush(String?)
    case failed(String)
}

enum RendererEnqueueStrategy: Sendable {
    case receiverBackpressure
    case boundedImmediateLead
}

struct RendererInputSample: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

enum RendererInputEventFact: Sendable {
    case warning(rendererKind: RendererFailureKind, message: String)
    case failure(RendererFailureFact)
}

protocol RendererInputSink: AnyObject {
    var enqueueStrategy: RendererEnqueueStrategy { get }
    func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome
    func enqueue(_ sample: RendererInputSample) async throws -> RendererEnqueueOutcome
    func flush(removingDisplayedImage: Bool) async
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    )
    func stopRenderingEventObservation()
}

protocol AudioRendererInputSink: AnyObject {
    var enqueueStrategy: RendererEnqueueStrategy { get }
    func enqueueImmediately(_ sample: RendererInputSample) throws -> RendererEnqueueOutcome
    func enqueue(_ sample: RendererInputSample) async throws -> RendererEnqueueOutcome
    func flush()
    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    )
    func stopRenderingEventObservation()
}

extension RendererInputSink {
    var enqueueStrategy: RendererEnqueueStrategy { .receiverBackpressure }

    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {}
    func stopRenderingEventObservation() {}
}

extension AudioRendererInputSink {
    var enqueueStrategy: RendererEnqueueStrategy { .receiverBackpressure }

    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {}
    func stopRenderingEventObservation() {}
}

final class AVSampleBufferRendererInputSink: RendererInputSink, @unchecked Sendable {
    private let receiver: AVSampleBufferVideoRenderer.Receiver
    private let eventTaskLock = NSLock()
    private var eventTask: Task<Void, Never>?

    init(receiver: consuming AVSampleBufferVideoRenderer.Receiver) {
        self.receiver = receiver
    }

    // visionOS can leave the Receiver's async backpressure suspended for a
    // compressed HDR stream even while its timebase is advancing. Keep the
    // delivery lane bounded by media time and submit through enqueueImmediately.
    var enqueueStrategy: RendererEnqueueStrategy { .boundedImmediateLead }

    func enqueueImmediately(_ input: RendererInputSample) throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(receiver.enqueueImmediately(readySample))
    }

    func enqueue(_ input: RendererInputSample) async throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(try await receiver.enqueue(readySample))
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

    func flush(removingDisplayedImage: Bool) async {
        await receiver.flush(removingDisplayedImage: removingDisplayedImage)
    }

    func observeRenderingEventsAfterFinishedEnqueuing(
        handler: @escaping @Sendable (RendererInputEventFact) -> Void
    ) {
        stopRenderingEventObservation()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            for await event in self.receiver.renderingEventsAfterFinishedEnqueuing {
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

    func stopRenderingEventObservation() {
        eventTaskLock.withLock {
            eventTask?.cancel()
            eventTask = nil
        }
    }
}

final class AVSampleBufferAudioRendererInputSink: AudioRendererInputSink, @unchecked Sendable {
    private let receiver: AVSampleBufferAudioRenderer.Receiver
    private let eventTaskLock = NSLock()
    private var eventTask: Task<Void, Never>?

    init(receiver: consuming AVSampleBufferAudioRenderer.Receiver) {
        self.receiver = receiver
    }

    var enqueueStrategy: RendererEnqueueStrategy { .boundedImmediateLead }

    func enqueueImmediately(_ input: RendererInputSample) throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(receiver.enqueueImmediately(readySample))
    }

    func enqueue(_ input: RendererInputSample) async throws -> RendererEnqueueOutcome {
        let sample = input.sampleBuffer
        if !CMSampleBufferDataIsReady(sample) {
            try sample.makeDataReady()
        }
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        return Self.outcome(try await receiver.enqueue(readySample))
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

    func flush() {
        receiver.flush()
    }

    func observeRenderingEventsAfterFinishedEnqueuing(
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

    func stopRenderingEventObservation() {
        eventTaskLock.withLock {
            eventTask?.cancel()
            eventTask = nil
        }
    }
}
