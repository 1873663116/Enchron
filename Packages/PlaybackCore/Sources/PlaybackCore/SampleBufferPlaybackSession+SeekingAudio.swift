@preconcurrency import AVFoundation
import Foundation
import OSLog

extension SampleBufferPlaybackSession {
    func seek(to time: CMTime, startsPaused: Bool) async throws {
        guard !isClosed, let sourceURL else { return }
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedBySeek)
        try Task.checkCancellation()
        let target = max(0, time.seconds.isFinite ? time.seconds : 0)
        let currentRate = currentRate()
        let preservedRate: Float = startsPaused
            ? 0
            : (currentRate > 0 ? currentRate : preferredPlaybackRate)
        beginOperation(.seek, targetTimeSeconds: target)
        let subtitleSeekEpoch = beginSubtitleTimelineDiscontinuity()
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "control.seek.started",
            outcome: .succeeded,
            details: ["targetSeconds": String(target)]
        )

        stopVideoDelivery()
        stopAudioDelivery()
        discardPendingVideoSample()
        synchronizer.rate = 0
        deliveryQueue.sync {
            isResetting = true
            provider.cancel()
        }
        audioDeliveryQueue.sync {
            audioProvider.cancel()
        }
        await rendererSink.flush(removingDisplayedImage: true)
        resetDecoderBootstrap()
        audioRendererSink.flush()
        resetEndState(requiresAudio: hasAudio)

        streamEpoch += 1
        audioStreamEpoch += 1
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
                "audioRendererStatus": audioRendererStatusLabel,
                "audioRendererError": audioRenderer.error?.localizedDescription
                    ?? currentAudioRendererError
                    ?? "none",
            ]
        )

        let seeksToKnownEnd = diagnostics.durationSeconds > 0
            && abs(target - diagnostics.durationSeconds) <= 1.0 / 60_000
        if seeksToKnownEnd {
            let endTime = CMTime(
                seconds: diagnostics.durationSeconds,
                preferredTimescale: 60_000
            )
            deliveryQueue.sync {
                timelineStartRate = 0
                requestedTimelineStart = endTime
                hasStartedTimeline = true
                isPrerolling = false
                isResetting = false
            }
            synchronizer.setRate(0, time: endTime)
            diagnostics.currentSeconds = diagnostics.durationSeconds
            updateLifecycle(.ended)
            recordRendererState(at: endTime)
            publishDiagnostics(at: endTime, force: true)
            completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "control.seek.completedAtEnd",
                outcome: .succeeded,
                details: [
                    "targetSeconds": String(target),
                    "streamEpoch": String(streamEpoch),
                    "endReason": PlaybackEndReason.seekToEnd.rawValue,
                ]
            )
            finishActiveOperation(.completed)
            onStatusChange?(.ended(.seekToEnd))
            return
        }

        do {
            try await provider.prepare(
                url: sourceURL,
                asset: sourceAsset,
                startTime: CMTime(seconds: target, preferredTimescale: 60_000)
            )
            try Task.checkCancellation()
            try provider.start()
            if hasAudio {
                try await audioProvider.prepare(
                    url: sourceURL,
                    asset: sourceAsset,
                    startTime: CMTime(seconds: target, preferredTimescale: 60_000),
                    streamIndex: selectedAudioStreamIndex
                )
            }
        } catch {
            deliveryQueue.sync { isResetting = false }
            if error is CancellationError || Task.isCancelled {
                provider.cancel()
                debugStore.emit(
                    mediaSessionID: traceID,
                    kind: "control.seek.superseded",
                    outcome: .terminatedByCleanup,
                    details: ["targetSeconds": String(target)]
                )
                finishActiveOperation(.terminatedByCleanup)
                throw CorePlaybackError.seekSuperseded(target)
            }
            recordFailure(error, node: .providerOpen, kind: "control.seek.failed")
            finishActiveOperation(.failed, failure: error.localizedDescription)
            onStatusChange?(.failed(error.localizedDescription))
            throw error
        }

        deliveryQueue.sync {
            timelineStartRate = preservedRate
            requestedTimelineStart = CMTime(
                seconds: target,
                preferredTimescale: 60_000
            )
            hasStartedTimeline = false
            isPrerolling = false
            lastSourceEventID = "none"
            didRecordFormat = false
            isResetting = false
        }
        startVideoDelivery()

        let expectedEpoch = streamEpoch
        let expectedAudioEpoch = audioStreamEpoch
        let deadline = ContinuousClock.now + .seconds(5)
        do {
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let snapshot = debugStore.snapshot()
                let audioReady = !hasAudio || (
                    snapshot.lastAudioSample?.streamEpoch == expectedAudioEpoch &&
                    snapshot.lastAudioSample.map {
                        samplePresentationCoversTarget(
                            presentationTime: $0.presentationTimeSeconds,
                            duration: $0.durationSeconds,
                            target: target
                        )
                    } == true
                )
                if let sample = snapshot.lastVideoSample,
                   let input = snapshot.lastAcceptedRendererInput,
                   sample.streamEpoch == expectedEpoch,
                   samplePresentationCoversTarget(
                       presentationTime: sample.presentationTimeSeconds,
                       duration: sample.durationSeconds,
                       target: target
                   ),
                   input.streamEpoch == expectedEpoch,
                   input.sourceEventID == sample.sourceEventID,
                   input.outcome == .accepted,
                   audioReady {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        kind: "control.seek.completed",
                        outcome: .succeeded,
                        details: [
                            "targetSeconds": String(target),
                            "streamEpoch": String(expectedEpoch),
                            "audioStreamEpoch": String(expectedAudioEpoch),
                            "subtitleStreamEpoch": String(subtitleSeekEpoch),
                        ]
                    )
                    completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
                    finishActiveOperation(.completed)
                    return
                }
                if let endEvent = snapshot.lastMediaEvent,
                   endEvent.kind == .end,
                   endEvent.streamEpoch == expectedEpoch,
                   targetEpochEndedBeforeVideoPresentation(target) {
                    let lastPTS = snapshot.lastVideoSample.flatMap { sample in
                        sample.streamEpoch == expectedEpoch
                            ? sample.presentationTimeSeconds
                            : nil
                    }
                    let error = CorePlaybackError.seekTargetUnavailable(target, lastPTS)
                    recordFailure(
                        error,
                        node: .rendererInputCoordination,
                        kind: "control.seek.targetUnavailable"
                    )
                    onStatusChange?(.failed(error.localizedDescription))
                    throw error
                }
                if let error = snapshot.lastError {
                    throw PlaybackProviderError.ffmpeg(error)
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                debugStore.emit(
                    mediaSessionID: traceID,
                    kind: "control.seek.superseded",
                    outcome: .terminatedByCleanup,
                    details: ["targetSeconds": String(target)]
                )
                finishActiveOperation(.terminatedByCleanup)
                throw CorePlaybackError.seekSuperseded(target)
            }
            throw error
        }
        let error = CorePlaybackError.seekTimedOut(target)
        recordFailure(error, node: .rendererInputCoordination, kind: "control.seek.failed")
        onStatusChange?(.failed(error.localizedDescription))
        throw error
    }

    func samplePresentationCoversTarget(
        presentationTime: Double,
        duration: Double,
        target: Double
    ) -> Bool {
        guard presentationTime.isFinite, target.isFinite else { return false }
        guard presentationTime >= target else {
            return duration.isFinite
                && duration > 0
                && presentationTime + duration >= target
        }
        return true
    }

    public func currentTime() -> CMTime {
        hasStartedTimeline ? synchronizer.currentTime() : .zero
    }

    public func currentRate() -> Float {
        guard hasStartedTimeline else { return timelineStartRate }
        return debugStore.snapshot().lifecycle == .playing ? preferredPlaybackRate : 0
    }

    public var currentVolume: Float {
        audioRenderer.volume
    }

    public var isMuted: Bool {
        audioRenderer.isMuted
    }

    func setVolume(_ volume: Float) throws {
        guard volume.isFinite, (0...1).contains(volume) else {
            throw PlaybackControlError.invalidVolume(volume)
        }
        audioRenderer.volume = volume
        recordAudioRendererState()
    }

    func setMuted(_ muted: Bool) {
        audioRenderer.isMuted = muted
        recordAudioRendererState()
    }

    func selectAudioTrack(streamIndex: Int) async throws {
        guard let sourceURL else { throw PlaybackControlError.noActiveMediaSession }
        guard availableAudioTracks.contains(where: { $0.streamIndex == streamIndex }) else {
            throw PlaybackControlError.invalidAudioTrack(streamIndex)
        }
        guard streamIndex != selectedAudioStreamIndex else { return }
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByRateChange)
        let previousStreamIndex = selectedAudioStreamIndex
        let previouslyHadAudio = hasAudio
        let time = currentTime()
        let rate = interruptionRecoveryRate()
        synchronizer.rate = 0
        stopAudioDelivery()
        audioDeliveryQueue.sync { audioProvider.cancel() }
        audioRendererSink.flush()
        resetAudioEndState(requiresAudio: previouslyHadAudio)
        do {
            try await audioProvider.prepare(
                url: sourceURL,
                asset: sourceAsset,
                startTime: time,
                streamIndex: streamIndex
            )
        } catch {
            let replacementError = error
            do {
                try await audioProvider.prepare(
                    url: sourceURL,
                    asset: sourceAsset,
                    startTime: time,
                    streamIndex: previousStreamIndex
                )
            } catch {
                hasAudio = false
                selectedAudioStreamIndex = nil
                resetAudioEndState(requiresAudio: false)
                debugStore.recordAudioTrack(nil)
                synchronizer.setRate(rate, time: time)
                recordFailure(
                    error,
                    node: .rendererInputCoordination,
                    kind: "control.audioTrack.rollbackFailed"
                )
                onStatusChange?(.failed(error.localizedDescription))
                throw error
            }
            hasAudio = previouslyHadAudio
            resetAudioEndState(requiresAudio: previouslyHadAudio)
            audioStreamEpoch += 1
            if hasAudio {
                startAudioDelivery()
            }
            synchronizer.setRate(rate, time: time)
            recordAudioRendererState()
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "control.audioTrack.failed",
                outcome: .failed,
                details: [
                    "streamIndex": String(streamIndex),
                    "rollback": "restored",
                    "error": replacementError.localizedDescription,
                ]
            )
            throw replacementError
        }
        selectedAudioStreamIndex = streamIndex
        hasAudio = true
        resetAudioEndState(requiresAudio: true)
        if let info = audioProvider.info {
            debugStore.recordAudioTrack(AudioTrackRecord(
                mediaSessionID: traceID,
                audioTrackID: "\(traceID).audio.\(info.streamIndex)",
                rawStreamIndex: info.streamIndex,
                codecName: info.codecName,
                sampleRate: info.sampleRate,
                channelCount: info.channelCount,
                selected: true
            ))
        }
        audioStreamEpoch += 1
        startAudioDelivery()
        synchronizer.setRate(rate, time: time)
        recordAudioRendererState()
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "control.audioTrack.completed",
            outcome: .succeeded,
            details: ["streamIndex": String(streamIndex)]
        )
    }

}
