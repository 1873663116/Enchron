@preconcurrency import AVFoundation
import Foundation

extension SampleBufferPlaybackSession {
    /// Puts a renderer no RealityView Entity has bound in front of the same open
    /// source, so a presentation conversion costs one intra-file refill instead
    /// of a second demuxer, a second track enumeration and a second network open.
    ///
    /// The replacement leaves video sample delivery suspended, because
    /// `AVSampleBufferVideoRenderer` rejects an enqueue until a video target is
    /// added. The caller binds the returned renderer to its new Entity and then
    /// refills through `restartVideoSampleDelivery(at:)`.
    ///
    /// The departing renderer stays on the synchronizer presenting its last frame
    /// until `retireDepartingVideoRendererGraph()`, so the outgoing Scene has
    /// something to show for the length of the transition.
    func replaceVideoRendererGraph() async throws -> AVSampleBufferVideoRenderer {
        guard !isClosed else { throw PlaybackControlError.noActiveMediaSession }
        let departing = renderer
        await suspendVideoSampleDelivery()

        let replacement = AVSampleBufferVideoRenderer()
        let revision = adoptVideoRendererGraph(
            renderer: replacement,
            sink: AVSampleBufferRendererInputSink(
                receiver: synchronizer.sampleBufferReceiver(adding: replacement)
            ),
            departing: departing
        )
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "rendererGraph.replaced",
            outcome: .succeeded,
            details: [
                "graphRevision": String(revision),
                "departingRenderer": PlaybackTrace.identity(departing),
                "renderer": PlaybackTrace.identity(replacement),
                "currentSeconds": String(currentTime().seconds),
            ]
        )
        return replacement
    }

    func retireDepartingVideoRendererGraph() async {
        guard let departing = takeDepartingVideoRenderer() else { return }
        await synchronizer.removeRenderer(departing, at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "rendererGraph.departingRetired",
            outcome: .succeeded,
            details: [
                "graphRevision": String(graphRevision),
                "departingRenderer": PlaybackTrace.identity(departing),
            ]
        )
    }
}
