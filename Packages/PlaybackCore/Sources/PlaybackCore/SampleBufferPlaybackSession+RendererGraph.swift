@preconcurrency import AVFoundation
import Foundation

extension SampleBufferPlaybackSession {
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
        #if DEBUG
            deliveryQueue.async { [weak self] in
                self?.recordPlaybackSwitchRendererSample(
                    trigger: .graphChanged,
                    observesDisplayProgress: true
                )
            }
        #endif
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
