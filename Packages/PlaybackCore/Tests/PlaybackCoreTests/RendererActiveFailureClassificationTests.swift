@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import PlaybackCore

@Test("A flush-required renderer fact retains its explicit recovery evidence")
func flushRequiredRendererFactHasTypedCause() {
    let fact = RendererFailureFact(
        rendererKind: .video,
        errorType: "AVSampleBufferVideoRenderer.RequiresFlush",
        message: "Video renderer requires a flush before decoding can resume.",
        requiresFlushToResumeDecoding: true
    )

    #expect(
        SampleBufferPlaybackSession.activeFailureCause(for: fact)
            == .rendererRequiresFlush
    )
}

@Test("A media-services reset renderer fact is not reported as corrupt media")
func mediaServicesResetRendererFactHasTypedCause() {
    let error = NSError(domain: AVFoundationErrorDomain, code: -11819)
    let fact = RendererFailureFact(
        rendererKind: .video,
        errorType: String(reflecting: type(of: error)),
        message: error.localizedDescription,
        requiresFlushToResumeDecoding: false
    )

    #expect(
        SampleBufferPlaybackSession.activeFailureCause(for: fact)
            == .mediaServicesReset
    )
}

@Test("An otherwise unclassified renderer failure stays a renderer failure")
func otherRendererFactHasTypedCause() {
    for requiresFlush in [false, nil] as [Bool?] {
        let fact = RendererFailureFact(
            rendererKind: .video,
            errorType: "AVSampleBufferVideoRenderer.Receiver",
            message: "The receiver cannot render this sample.",
            requiresFlushToResumeDecoding: requiresFlush
        )

        #expect(
            SampleBufferPlaybackSession.activeFailureCause(for: fact)
                == .rendererFailed
        )
    }
}

@Test("Renderer failure publication preserves the fact and publishes its typed cause")
func rendererFailurePublicationPreservesEvidence() {
    let session = SampleBufferPlaybackSession(traceID: "renderer-failure-evidence")
    defer { session.close() }
    let fact = RendererFailureFact(
        rendererKind: .video,
        errorType: "AVSampleBufferVideoRenderer.RequiresFlush",
        message: "Video renderer requires a flush before decoding can resume.",
        requiresFlushToResumeDecoding: true
    )

    session.publishRendererFailure(fact)

    #expect(session.activeFailureContext == .decoder(.rendererRequiresFlush))
    let recorded = session.debugSnapshot().lastFailure
    #expect(recorded?.rendererKind == fact.rendererKind.rawValue)
    #expect(recorded?.errorType == fact.errorType)
    #expect(recorded?.message == fact.message)
    #expect(
        recorded?.requiresFlushToResumeDecoding
            == fact.requiresFlushToResumeDecoding
    )
}
