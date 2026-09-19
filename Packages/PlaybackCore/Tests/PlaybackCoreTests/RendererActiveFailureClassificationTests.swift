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

@Test("Repeating the same flush requirement does not restart recovery")
func repeatedFlushRequirementIsDeduplicated() {
    let session = SampleBufferPlaybackSession(traceID: "renderer-flush-repeated")
    defer { session.close() }
    let fact = RendererFailureFact(
        rendererKind: .video,
        errorType: "AVSampleBufferVideoRenderer.RequiresFlush",
        message: "Operation Interrupted",
        requiresFlushToResumeDecoding: true
    )

    session.publishRendererFailure(fact)
    session.publishRendererFailure(fact)

    #expect(session.needsVideoRendererRecovery)
    #expect(session.activeFailureContext == nil)
    #expect(session.debugSnapshot().lifecycle != .failed)
    #expect(session.debugSnapshot().lastFailure == nil)
}

@Test("A renderer failure while only a flush is owed still fails the session")
func rendererFailureWhileFlushIsOwedFailsTheSession() {
    let session = SampleBufferPlaybackSession(traceID: "renderer-failure-while-pending")
    defer { session.close() }
    _ = session.beginRendererFlushRecovery()

    session.publishRendererFailure(RendererFailureFact(
        rendererKind: .video,
        errorType: "AVSampleBufferVideoRenderer.Receiver",
        message: "The receiver cannot render this sample.",
        requiresFlushToResumeDecoding: false
    ))

    #expect(session.activeFailureContext == .decoder(.rendererFailed))
    #expect(session.debugSnapshot().lastFailure != nil)
}

@Test("Renderer failure publication preserves the fact and publishes its typed cause")
func rendererFailurePublicationPreservesEvidence() {
    let session = SampleBufferPlaybackSession(traceID: "renderer-failure-evidence")
    defer { session.close() }
    let fact = RendererFailureFact(
        rendererKind: .video,
        errorType: "AVSampleBufferVideoRenderer.Receiver",
        message: "The receiver cannot render this sample.",
        requiresFlushToResumeDecoding: false
    )

    session.publishRendererFailure(fact)

    #expect(session.activeFailureContext == .decoder(.rendererFailed))
    let recorded = session.debugSnapshot().lastFailure
    #expect(recorded?.rendererKind == fact.rendererKind.rawValue)
    #expect(recorded?.errorType == fact.errorType)
    #expect(recorded?.message == fact.message)
    #expect(
        recorded?.requiresFlushToResumeDecoding
            == fact.requiresFlushToResumeDecoding
    )
}
