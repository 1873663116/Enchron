import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import PlaybackCore

@MainActor
@Test func replacingTheRendererGraphKeepsOneMediaSessionAndOneSourceOpen() async throws {
    let sample = try makeCompressedH264Sample(presentationTimeSeconds: 0)
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in
            SampleBufferPlaybackSession(
                traceID: sessionID,
                provider: FakeVideoSampleProvider(events: [.sample(sample), .end])
            )
        },
        debugRecorderMode: .disabledForVerification
    )
    defer { controller.close() }

    let session = try await controller.open(URL(fileURLWithPath: "/fixtures/fake.mov"))
    let originalRenderer = session.renderer
    let originalRevision = session.graphRevision
    let recorder = EventKindRecorder(store: session.debugStore)
    defer { recorder.stop() }

    let replacement = try await controller.replaceVideoRendererGraph()

    #expect(replacement !== originalRenderer)
    #expect(session.renderer === replacement)
    #expect(session.graphRevision == originalRevision &+ 1)
    #expect(session.videoSampleDeliveryIsSuspended)
    #expect(controller.activeSession === session)
    #expect(session.debugSnapshot().mediaSession?.mediaSessionID == session.traceID)
    #expect(recorder.count(of: "rendererGraph.replaced") == 1)
    #expect(recorder.count(of: "source.acquired") == 0)
    #expect(recorder.count(of: "open.admitted") == 0)

    await controller.retireDepartingVideoRendererGraph()

    #expect(recorder.count(of: "rendererGraph.departingRetired") == 1)
    #expect(session.takeDepartingVideoRenderer() == nil)
}

@MainActor
@Test func replacingTheRendererGraphRejectsAClosedSession() async throws {
    let controller = PlaybackCoreController(
        sessionFactory: { sessionID in
            SampleBufferPlaybackSession(
                traceID: sessionID,
                provider: FakeVideoSampleProvider(events: [.end])
            )
        },
        debugRecorderMode: .disabledForVerification
    )
    _ = try await controller.open(URL(fileURLWithPath: "/fixtures/fake.mov"))
    await controller.closeAndWait()

    await #expect(throws: PlaybackControlError.self) {
        _ = try await controller.replaceVideoRendererGraph()
    }
}

private final class EventKindRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [String] = []
    private let store: PlaybackDiagnosticsStore
    private var observerID: UUID?

    init(store: PlaybackDiagnosticsStore) {
        self.store = store
        observerID = store.addEventObserver { [weak self] event in
            guard let self else { return }
            lock.withLock { kinds.append(event.kind) }
        }
    }

    func count(of kind: String) -> Int {
        lock.withLock { kinds.filter { $0 == kind }.count }
    }

    func stop() {
        if let observerID {
            store.removeEventObserver(observerID)
        }
        observerID = nil
    }
}
