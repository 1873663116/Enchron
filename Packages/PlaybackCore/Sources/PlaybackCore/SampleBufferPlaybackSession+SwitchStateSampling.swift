#if DEBUG
@preconcurrency import AVFoundation
import Foundation

extension SampleBufferPlaybackSession {
    public func setPlaybackSwitchRendererSampleSink(
        _ sink: (any PlaybackSwitchRendererSampleSink)?
    ) {
        playbackSwitchSampleSinkLock.withLock {
            playbackSwitchSampleSink = sink
        }
    }

    public func capturePlaybackSwitchRendererState() {
        deliveryQueue.sync {
            recordPlaybackSwitchRendererSample(
                trigger: .lifecycleChanged,
                observesDisplayProgress: false
            )
        }
    }

    func recordPlaybackSwitchRendererSample(
        trigger: PlaybackSwitchSampleTrigger,
        observesDisplayProgress: Bool
    ) {
        guard let sink = playbackSwitchSampleSinkLock.withLock({ playbackSwitchSampleSink }) else {
            return
        }
        let displayedCount = if observesDisplayProgress {
            observeDisplayedFrame() ?? displayedFrameObservationCount
        } else {
            displayedFrameObservationCount
        }
        let actualRate = finiteRate(CMTimebaseGetRate(synchronizer.timebase))
        let effectiveRate = finiteRate(CMTimebaseGetEffectiveRate(synchronizer.timebase))
        let rendererGraph = playbackSwitchRendererGraphIdentity()
        sink.recordPlaybackSwitchRendererSample(PlaybackSwitchRendererSample(
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            trigger: trigger,
            technicalSessionID: traceID,
            rendererIdentity: rendererGraph.renderer,
            graphRevision: rendererGraph.revision,
            lifecycle: mediaSessionRecord?.lifecycle ?? .idle,
            acceptedInputCount: UInt64(diagnostics.enqueuedSampleCount),
            displayedFrameObservationCount: displayedCount,
            requestedRate: finiteRate(Double(synchronizer.rate)),
            actualTimebaseRate: actualRate,
            effectiveTimebaseRate: effectiveRate,
            streamEpoch: streamEpoch,
            flushCount: flushCount,
            departingRendererIdentity: rendererGraph.departingRenderer
        ))
    }

    private func finiteRate(_ rate: Double) -> Float {
        rate.isFinite ? Float(rate) : 0
    }
}
#endif
