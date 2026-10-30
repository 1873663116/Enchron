import CoreMedia
import Foundation

struct VideoLaneResetTimings {
    var deliveryStoppedMilliseconds: Double
    var providerCancelMilliseconds: Double
    var flushMilliseconds: Double
    var framesInFlight: Int
}

struct VideoAttachmentResult {
    var reset: VideoLaneResetTimings
    var providerReopened: ContinuousClock.Instant
    var reopenMilliseconds: Double
}

extension SampleBufferPlaybackSession {
    func abandonVideoAttachment() {
        deliveryQueue.sync {
            isResetting = false
            provider.cancel()
        }
    }

    func resetVideoLane(
        removingDisplayedImage: Bool,
        reason: String
    ) async -> VideoLaneResetTimings {
        let started = ContinuousClock.now
        stopVideoDelivery()
        discardPendingVideoSample()
        let framesInFlight = videoFramesInFlightLock.withLock {
            videoFramesInFlight.count(timelineSeconds: timelineClockReading().mediaTime.seconds)
        }
        let deliveryStopped = ContinuousClock.now
        deliveryQueue.sync {
            isResetting = true
            provider.cancel()
        }
        let providerCancelled = ContinuousClock.now
        await rendererSink.flush(removingDisplayedImage: removingDisplayedImage)
        clearRendererFlushRecovery()
        discardVideoFramesInFlight()
        resetDecoderBootstrap()
        streamEpoch += 1
        flushCount += 1
        recordRendererState(at: currentTime())
        sourceEventSequence += 1
        let flushEvent = MediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .flush,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordMediaEvent(flushEvent)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "renderer.flushedForSeek",
            outcome: .succeeded,
            details: [
                "streamEpoch": String(streamEpoch),
                "audioStreamEpoch": String(audioStreamEpoch),
                "reason": reason,
                "audioRendererStatus": audioRendererStatusLabel,
                "audioRendererError": audioRenderer.error?.localizedDescription
                    ?? currentAudioRendererError
                    ?? "none"
            ]
        )
        let flushed = ContinuousClock.now
        return VideoLaneResetTimings(
            deliveryStoppedMilliseconds: Self.millisecondValue(from: started, to: deliveryStopped),
            providerCancelMilliseconds: Self.millisecondValue(from: deliveryStopped, to: providerCancelled),
            flushMilliseconds: Self.millisecondValue(from: providerCancelled, to: flushed),
            framesInFlight: framesInFlight
        )
    }

    @discardableResult
    func openVideoAttachment(
        url: URL,
        asset: PlaybackAsset?,
        seconds: Double,
        removingDisplayedImage: Bool,
        reason: String,
        startsProvider: Bool = true
    ) async throws -> VideoAttachmentResult {
        let epochBefore = demuxSession?.currentEpoch()
        let reset = await resetVideoLane(
            removingDisplayedImage: removingDisplayedImage,
            reason: reason
        )
        let reopenStarted = ContinuousClock.now
        try await provider.prepare(
            url: url,
            asset: asset,
            startTime: CMTime(seconds: seconds, preferredTimescale: 60_000)
        )
        try Task.checkCancellation()
        if startsProvider {
            try provider.start()
        } else {
            deliveryQueue.sync { isResetting = false }
        }
        let epochAfter = demuxSession?.currentEpoch()
        if let epochBefore, let epochAfter, epochBefore != epochAfter {
            throw PlaybackProviderError.readerFailed(
                "source epoch moved from \(epochBefore) to \(epochAfter) while opening the video attachment"
            )
        }
        let reopened = ContinuousClock.now
        let epochLabel = epochAfter.map(String.init) ?? "none"
        let summary = "video.attach.open reason=\(reason) epoch=\(epochLabel)"
            + " seconds=\(String(format: "%.3f", seconds))"
        logger.info("\(summary, privacy: .public)")
        return VideoAttachmentResult(
            reset: reset,
            providerReopened: reopened,
            reopenMilliseconds: Self.millisecondValue(from: reopenStarted, to: reopened)
        )
    }
}
