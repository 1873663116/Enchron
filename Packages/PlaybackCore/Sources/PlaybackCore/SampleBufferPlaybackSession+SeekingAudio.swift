@preconcurrency import AVFoundation
import Foundation
import OSLog

struct PlaybackSeekProgressSignal: Equatable, Sendable {
    var sourceBytesRead: UInt64
    var videoSourceEventID: String?
    var videoPresentationSeconds: Double?
    var audioStreamEpoch: UInt64?
    var audioPresentationSeconds: Double?
    var rendererInputSourceEventID: String?
    var rendererInputStreamEpoch: UInt64?
}

extension SampleBufferPlaybackSession {
    func seek(
        to time: CMTime,
        startsPaused: Bool,
        removingDisplayedImage: Bool = true,
        requiresAudioTarget: Bool = true,
        endsPlayback: Bool = false
    ) async throws {
        guard !isClosed, let sourceURL else { return }
        if mediaKind == .audioOnly {
            try await seekAudioOnly(
                to: time,
                startsPaused: startsPaused,
                sourceURL: sourceURL,
                endsPlayback: endsPlayback
            )
            return
        }
        let target = try clampedSeekTime(time).seconds
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedBySeek)
        try Task.checkCancellation()
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

        let teardownStarted = ContinuousClock.now
        var videoProviderReopened: ContinuousClock.Instant?
        let framesInFlightAtTeardown = videoFramesInFlightLock.withLock {
            videoFramesInFlight.count(timelineSeconds: timelineClockReading().mediaTime.seconds)
        }
        stopVideoDelivery()
        stopAudioDelivery()
        discardPendingVideoSample()
        setTimelineStopped(reason: .seek)
        let deliveryStopped = ContinuousClock.now
        deliveryQueue.sync {
            isResetting = true
            provider.cancel()
        }
        let videoProviderCancelled = ContinuousClock.now
        audioDeliveryQueue.sync {
            audioProvider.cancel()
        }
        let audioProviderCancelled = ContinuousClock.now
        await rendererSink.flush(removingDisplayedImage: removingDisplayedImage)
        clearRendererFlushRecovery()
        discardVideoFramesInFlight()
        let rendererFlushed = ContinuousClock.now
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.seek.teardownStages",
            outcome: .succeeded,
            details: [
                "stopDeliveryMilliseconds":
                    Self.milliseconds(from: teardownStarted, to: deliveryStopped),
                "videoProviderCancelMilliseconds":
                    Self.milliseconds(from: deliveryStopped, to: videoProviderCancelled),
                "audioProviderCancelMilliseconds":
                    Self.milliseconds(from: videoProviderCancelled, to: audioProviderCancelled),
                "rendererFlushMilliseconds":
                    Self.milliseconds(from: audioProviderCancelled, to: rendererFlushed),
                "totalMilliseconds":
                    Self.milliseconds(from: teardownStarted, to: rendererFlushed),
                "leadFrames": String(videoLeadFrames),
                "framesInFlight": String(framesInFlightAtTeardown)
            ]
        )
        diagnostics.lastSeekFlushMilliseconds = Self.milliseconds(from: teardownStarted, to: rendererFlushed)
        diagnostics.lastSeekFramesInFlight = framesInFlightAtTeardown
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
                    ?? "none"
            ]
        )

        let seeksToKnownEnd = endsPlayback
            || (diagnostics.durationSeconds > 0
                && abs(target - diagnostics.durationSeconds) <= 1.0 / 60_000)
        if seeksToKnownEnd {
            completeSeekAtEnd(target: target, subtitleSeekEpoch: subtitleSeekEpoch)
            return
        }

        do {
            try demuxSession?.seek(to: target)
            try await provider.prepare(
                url: sourceURL,
                asset: sourceAsset,
                startTime: CMTime(seconds: target, preferredTimescale: 60_000)
            )
            try Task.checkCancellation()
            try provider.start()
            videoProviderReopened = ContinuousClock.now
            if hasAudio {
                do {
                    try await audioProvider.prepare(
                        url: sourceURL,
                        asset: sourceAsset,
                        startTime: CMTime(seconds: target, preferredTimescale: 60_000),
                        streamIndex: selectedAudioStreamIndex
                    )
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        throw error
                    }
                    retireAudio(
                        after: error,
                        node: .providerOpen,
                        kind: "audioProvider.seekOpenFailed.videoContinues"
                    )
                }
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
            prerollCoveringPresentationTime = nil
            prerollFramesBeyondTarget = 0
            pausedSeekAwaitsCoverage = preservedRate == 0
            isPrerolling = false
            lastSourceEventID = "none"
            didRecordFormat = false
            isResetting = false
        }
        prerollRequirementLock.withLock {
            prerollRequirement = preservedRate > 0
                ? PlaybackBufferingPolicy.seekRequirement(
                    target: requestedTimelineStart,
                    durationSeconds: diagnostics.durationSeconds
                )
                : nil
        }
        recordTimelineControlState()
        startVideoDelivery()

        let expectedEpoch = streamEpoch
        let expectedAudioEpoch = audioStreamEpoch
        let waitStarted = ContinuousClock.now
        var lastProgress = seekProgressSignal()
        var lastProgressAt = waitStarted
        var stallWasTraced = false
        var videoReachedTarget = false
        do {
            while true {
                try Task.checkCancellation()
                let snapshot = debugStore.snapshot()
                let audioReady = !requiresAudioTarget || !hasAudio || (
                    snapshot.lastAudioSample?.streamEpoch == expectedAudioEpoch &&
                    snapshot.lastAudioSample.map {
                        samplePresentationCoversTarget(
                            presentationTime: $0.presentationTimeSeconds,
                            duration: $0.durationSeconds,
                            target: target
                        )
                    } == true
                )
                let latestSampleReachedTarget = if let sample = snapshot.lastVideoSample,
                    let input = snapshot.lastAcceptedRendererInput {
                    sample.streamEpoch == expectedEpoch
                        && samplePresentationCoversTarget(
                            presentationTime: sample.presentationTimeSeconds,
                            duration: sample.durationSeconds,
                            target: target
                        )
                        && input.streamEpoch == expectedEpoch
                        && input.sourceEventID == sample.sourceEventID
                        && input.outcome == .accepted
                } else {
                    false
                }
                let maximumPresentationTimeReachedTarget = !requiresAudioTarget
                    && maximumAcceptedVideoPresentationTime.map {
                        CMTimeCompare(
                            $0,
                            CMTime(seconds: target, preferredTimescale: 60_000)
                        ) >= 0
                    } == true
                videoReachedTarget = videoReachedTarget
                    || latestSampleReachedTarget
                    || maximumPresentationTimeReachedTarget
                if latestSampleReachedTarget || maximumPresentationTimeReachedTarget,
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
                            "reopenMilliseconds": videoProviderReopened.map {
                                Self.milliseconds(from: teardownStarted, to: $0)
                            } ?? "unavailable",
                            "totalMilliseconds": Self.milliseconds(
                                from: teardownStarted,
                                to: ContinuousClock.now
                            )
                        ]
                    )
                    diagnostics.lastSeekTotalMilliseconds = Self.milliseconds(
                        from: teardownStarted,
                        to: ContinuousClock.now
                    )
                    completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
                    finishActiveOperation(.completed)
                    if preservedRate == 0 {
                        publishTargetTimelineState(
                            at: CMTime(seconds: target, preferredTimescale: 60_000)
                        )
                    }
                    return
                }
                if let endEvent = snapshot.lastMediaEvent,
                   endEvent.kind == .end,
                   endEvent.streamEpoch == expectedEpoch {
                    guard acceptedVideoCoversTarget(target) else {
                        completeSeekAtEnd(target: target, subtitleSeekEpoch: subtitleSeekEpoch)
                        return
                    }
                    if audioReady || audioProviderHasEnded {
                        debugStore.emit(
                            mediaSessionID: traceID,
                            kind: "control.seek.completedAtInputEnd",
                            outcome: .succeeded,
                            details: [
                                "targetSeconds": String(target),
                                "streamEpoch": String(expectedEpoch),
                                "audioReady": String(audioReady)
                            ]
                        )
                        completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
                        finishActiveOperation(.completed)
                        if preservedRate == 0 {
                            publishTargetTimelineState(
                                at: CMTime(seconds: target, preferredTimescale: 60_000)
                            )
                        }
                        return
                    }
                }
                if let error = snapshot.lastError,
                   snapshot.lastFailure?.recoverability
                    != "audioRetiredVideoContinues" {
                    throw PlaybackProviderError.ffmpeg(error)
                }
                let progress = seekProgressSignal(snapshot)
                let now = ContinuousClock.now
                if progress != lastProgress {
                    lastProgress = progress
                    lastProgressAt = now
                }
                let flatDuration = now - lastProgressAt
                if flatDuration
                    >= PlaybackBufferingPolicy.transportBoundStallLimit ||
                    (flatDuration
                        >= PlaybackBufferingPolicy.seekProgressStallTimeout
                        && sourceReadPending == false) {
                    break
                }
                if stallWasTraced == false,
                   now - waitStarted
                    > PlaybackBufferingPolicy.seekProgressStallTimeout {
                    stallWasTraced = true
                    traceSeekStall(
                        target: target,
                        lastProgressAt: lastProgressAt,
                        now: now
                    )
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
        if videoReachedTarget, requiresAudioTarget, hasAudio {
            let error = CorePlaybackError.audioPrerollTimedOut(target)
            retireAudio(
                after: error,
                node: .rendererInputCoordination,
                kind: "audioRenderer.seekPrerollFailed.videoContinues"
            )
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "control.seek.completed",
                outcome: .succeeded,
                details: [
                    "targetSeconds": String(target),
                    "streamEpoch": String(expectedEpoch),
                    "audioStreamEpoch": String(expectedAudioEpoch),
                    "subtitleStreamEpoch": String(subtitleSeekEpoch),
                    "audioRetired": "true",
                    "reopenMilliseconds": videoProviderReopened.map {
                        Self.milliseconds(from: teardownStarted, to: $0)
                    } ?? "unavailable",
                    "totalMilliseconds": Self.milliseconds(
                        from: teardownStarted,
                        to: ContinuousClock.now
                    )
                ]
            )
            diagnostics.lastSeekTotalMilliseconds = Self.milliseconds(
                from: teardownStarted,
                to: ContinuousClock.now
            )
            completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
            finishActiveOperation(.completed)
            return
        }
        let error = CorePlaybackError.seekTimedOut(target)
        recordFailure(
            error,
            node: .rendererInputCoordination,
            kind: "control.seek.failed",
            progressAgeMilliseconds: Self.millisecondValue(
                from: lastProgressAt,
                to: ContinuousClock.now
            )
        )
        onStatusChange?(.failed(error.localizedDescription))
        throw error
    }

    private func seekAudioOnly(
        to time: CMTime,
        startsPaused: Bool,
        sourceURL: URL,
        endsPlayback: Bool
    ) async throws {
        let target = try clampedSeekTime(time).seconds
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedBySeek)
        try Task.checkCancellation()
        let currentRate = currentRate()
        let preservedRate: Float = startsPaused
            ? 0
            : (currentRate > 0 ? currentRate : preferredPlaybackRate)
        beginOperation(.seek, targetTimeSeconds: target)
        let subtitleSeekEpoch = beginSubtitleTimelineDiscontinuity()
        stopAudioDelivery()
        setTimelineStopped(reason: .seek)
        audioDeliveryQueue.sync { audioProvider.cancel() }
        audioRendererSink.flush()
        resetEndState(requiresAudio: true)
        audioStreamEpoch += 1

        let seeksToKnownEnd = endsPlayback
            || (diagnostics.durationSeconds > 0
                && abs(target - diagnostics.durationSeconds) <= 1.0 / 60_000)
        if seeksToKnownEnd {
            let endTime = CMTime(seconds: diagnostics.durationSeconds, preferredTimescale: 60_000)
            timelineStartRate = 0
            requestedTimelineStart = endTime
            hasStartedTimeline = true
            setTimelineStopped(at: endTime, reason: .seekToEnd)
            diagnostics.currentSeconds = diagnostics.durationSeconds
            updateLifecycle(.ended)
            publishDiagnostics(at: endTime, force: true)
            completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
            finishActiveOperation(.completed)
            onStatusChange?(.ended(PlaybackEndReceipt.seekToEnd(
                endSeconds: diagnostics.durationSeconds
            )))
            return
        }

        let targetTime = CMTime(seconds: target, preferredTimescale: 60_000)
        do {
            try demuxSession?.seek(to: target)
            try await audioProvider.prepare(
                url: sourceURL,
                asset: sourceAsset,
                startTime: targetTime,
                streamIndex: selectedAudioStreamIndex
            )
        } catch {
            recordFailure(error, node: .providerOpen, kind: "audioProvider.seekOpenFailed")
            finishActiveOperation(.failed, failure: error.localizedDescription)
            onStatusChange?(.failed(error.localizedDescription))
            throw error
        }

        timelineStartRate = preservedRate
        requestedTimelineStart = targetTime
        hasStartedTimeline = false
        prerollCoveringPresentationTime = nil
        prerollFramesBeyondTarget = 0
        pausedSeekAwaitsCoverage = false
        isPrerolling = false
        recordTimelineControlState()
        startAudioDelivery()

        let expectedEpoch = audioStreamEpoch
        let waitStarted = ContinuousClock.now
        var lastProgress = seekProgressSignal()
        var lastProgressAt = waitStarted
        var stallWasTraced = false
        while true {
            try Task.checkCancellation()
            let snapshot = debugStore.snapshot()
            let sample = snapshot.lastAudioSample
            if sample?.streamEpoch == expectedEpoch,
               sample.map({
                   samplePresentationCoversTarget(
                       presentationTime: $0.presentationTimeSeconds,
                       duration: $0.durationSeconds,
                       target: target
                   )
               }) == true {
                completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
                finishActiveOperation(.completed)
                return
            }
            if let error = snapshot.lastError {
                throw PlaybackProviderError.ffmpeg(error)
            }
            let progress = seekProgressSignal(snapshot)
            let now = ContinuousClock.now
            if progress != lastProgress {
                lastProgress = progress
                lastProgressAt = now
            }
            let flatDuration = now - lastProgressAt
            if flatDuration
                >= PlaybackBufferingPolicy.transportBoundStallLimit ||
                (flatDuration
                    >= PlaybackBufferingPolicy.seekProgressStallTimeout
                    && sourceReadPending == false) {
                break
            }
            if stallWasTraced == false,
               now - waitStarted > PlaybackBufferingPolicy.seekProgressStallTimeout {
                stallWasTraced = true
                traceSeekStall(target: target, lastProgressAt: lastProgressAt, now: now)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let error = CorePlaybackError.seekTimedOut(target)
        recordFailure(
            error,
            node: .rendererInputCoordination,
            kind: "control.seek.failed",
            progressAgeMilliseconds: Self.millisecondValue(
                from: lastProgressAt,
                to: ContinuousClock.now
            )
        )
        finishActiveOperation(.failed, failure: error.localizedDescription)
        onStatusChange?(.failed(error.localizedDescription))
        throw error
    }

    func restoreEndedPresentation(_ continuity: PlaybackEndedContinuity) {
        stopVideoDelivery()
        stopAudioDelivery()
        setTimelineStopped(reason: .restoreEndedPresentation)
        deliveryQueue.sync {
            timelineStartRate = 0
            requestedTimelineStart = continuity.logicalPosition
            hasStartedTimeline = true
        }
        recordTimelineControlState()
        endStateLock.withLock {
            endState.didReportEnd = true
        }
        diagnostics.currentSeconds = continuity.logicalPosition.seconds
        updateLifecycle(.ended)
        recordRendererState(at: continuity.logicalPosition)
        publishDiagnostics(at: continuity.logicalPosition, force: true)
    }

    func clampedSeekTime(_ time: CMTime) throws -> CMTime {
        let requestedSeconds = time.seconds
        guard time.isValid, time.isNumeric, requestedSeconds.isFinite else {
            throw PlaybackControlError.invalidSeekTime(requestedSeconds)
        }
        let lowerBoundedSeconds = max(0, requestedSeconds)
        let duration = diagnostics.durationSeconds
        let boundedSeconds = if duration.isFinite, duration > 0 {
            min(lowerBoundedSeconds, duration)
        } else {
            lowerBoundedSeconds
        }
        return CMTime(
            seconds: boundedSeconds,
            preferredTimescale: max(time.timescale, 60_000)
        )
    }

    private func completeSeekAtEnd(target: Double, subtitleSeekEpoch: UInt64) {
        let endSeconds = diagnostics.durationSeconds > 0
            ? diagnostics.durationSeconds
            : (acceptedVideoPresentationEndSeconds ?? target)
        let endTime = CMTime(seconds: endSeconds, preferredTimescale: 60_000)
        let reportsEnd = claimEndReport()
        var reportedTruncation = false
        if reportsEnd {
            let deliveredEndSeconds = acceptedVideoPresentationEndSeconds
            if let receipt = PlaybackEndReceipt.completion(
                reason: .seekToEnd,
                deliveredEndSeconds: deliveredEndSeconds ?? target,
                declaredDurationSeconds: diagnostics.durationSeconds > 0
                    ? diagnostics.durationSeconds
                    : nil
            ) {
                deliveryQueue.sync {
                    timelineStartRate = 0
                    requestedTimelineStart = endTime
                    hasStartedTimeline = true
                    isPrerolling = false
                    isResetting = false
                }
                setTimelineStopped(at: endTime, reason: .seekToEnd)
                diagnostics.currentSeconds = endSeconds
                updateLifecycle(.ended)
                recordRendererState(at: endTime)
                publishDiagnostics(at: endTime, force: true)
                onStatusChange?(.ended(receipt))
            } else {
                reportedTruncation = true
                reportTruncatedInputEnd(
                    deliveredEndSeconds: deliveredEndSeconds,
                    declaredDurationSeconds: diagnostics.durationSeconds
                )
            }
        }
        completeSubtitleTimelineDiscontinuity(epoch: subtitleSeekEpoch)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.seek.completedAtEnd",
            outcome: .succeeded,
            details: [
                "targetSeconds": String(target),
                "endSeconds": String(endSeconds),
                "streamEpoch": String(streamEpoch),
                "endReason": PlaybackEndReason.seekToEnd.rawValue,
                "reportedEnd": String(reportsEnd),
                "reportedTruncation": String(reportedTruncation)
            ]
        )
        if !reportedTruncation {
            finishActiveOperation(.completed)
        }
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
        return mediaSessionRecord?.lifecycle == .playing ? preferredPlaybackRate : 0
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
        let deliveryHasStarted = deliveryQueue.sync { hasRequestedVideoData }
        let time = hasStartedTimeline || !requestedTimelineStart.isNumeric
            ? currentTime()
            : requestedTimelineStart
        let rate = interruptionRecoveryRate()
        if deliveryHasStarted {
            setTimelineStopped(reason: .audioTrackSelection)
        }
        stopAudioDelivery()
        audioDeliveryQueue.sync { audioProvider.cancel() }
        audioRendererSink.flush()
        resetAudioEndState(requiresAudio: previouslyHadAudio)
        let rearmsVideoDelivery = deliveryHasStarted
            && demuxSession != nil
            && mediaKind == .video
        if let demuxSession {
            try demuxSession.seek(to: time.seconds)
            if mediaKind == .video {
                if rearmsVideoDelivery {
                    stopVideoDelivery()
                    discardPendingVideoSample()
                    deliveryQueue.sync {
                        isResetting = true
                        provider.cancel()
                    }
                    await rendererSink.flush(removingDisplayedImage: false)
                    discardVideoFramesInFlight()
                    resetDecoderBootstrap()
                    streamEpoch += 1
                    flushCount += 1
                    recordRendererState(at: time)
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "renderer.flushedForAudioTrackSelection",
                        outcome: .succeeded,
                        details: ["streamEpoch": String(streamEpoch)]
                    )
                } else {
                    deliveryQueue.sync { provider.cancel() }
                }
                do {
                    try await provider.prepare(
                        url: sourceURL,
                        asset: sourceAsset,
                        startTime: time
                    )
                    if rearmsVideoDelivery {
                        try provider.start()
                    }
                } catch {
                    deliveryQueue.sync { isResetting = false }
                    throw error
                }
            }
        }
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
                retireAudio(
                    after: error,
                    node: .rendererInputCoordination,
                    kind: "control.audioTrack.rollbackFailed.videoContinues"
                )
                setTimelineRateForDiscontinuity(
                    rate,
                    at: time,
                    reason: .audioTrackRollbackFailure
                )
                if demuxSession != nil, mediaKind == .video {
                    startVideoDelivery()
                }
                return
            }
            hasAudio = previouslyHadAudio
            resetAudioEndState(requiresAudio: previouslyHadAudio)
            audioStreamEpoch += 1
            if deliveryHasStarted {
                rearmTimelineAfterAudioTrackChange(
                    rate: rate,
                    at: time,
                    rearmsVideoDelivery: rearmsVideoDelivery
                )
            }
            recordAudioRendererState()
            debugStore.emit(
                mediaSessionID: traceID,
                kind: "control.audioTrack.failed",
                outcome: .failed,
                details: [
                    "streamIndex": String(streamIndex),
                    "rollback": "restored",
                    "error": replacementError.localizedDescription
                ]
            )
            throw replacementError
        }
        selectedAudioStreamIndex = streamIndex
        hasAudio = true
        diagnostics.audioRetired = false
        diagnostics.audioRetirementReason = nil
        onDiagnosticsChange?(diagnostics)
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
        if deliveryHasStarted {
            rearmTimelineAfterAudioTrackChange(
                rate: rate,
                at: time,
                rearmsVideoDelivery: rearmsVideoDelivery
            )
        }
        recordAudioRendererState()
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "control.audioTrack.completed",
            outcome: .succeeded,
            details: ["streamIndex": String(streamIndex)]
        )
    }

    private func rearmTimelineAfterAudioTrackChange(
        rate: Float,
        at time: CMTime,
        rearmsVideoDelivery: Bool
    ) {
        deliveryQueue.sync {
            timelineStartRate = rate
            requestedTimelineStart = time
            hasStartedTimeline = false
            prerollCoveringPresentationTime = nil
            prerollFramesBeyondTarget = 0
            pausedSeekAwaitsCoverage = false
            isPrerolling = false
            if rearmsVideoDelivery {
                lastSourceEventID = "none"
                didRecordFormat = false
                isResetting = false
            }
        }
        prerollRequirementLock.withLock {
            prerollRequirement = rate > 0
                ? PlaybackBufferingPolicy.seekRequirement(
                    target: time,
                    durationSeconds: diagnostics.durationSeconds
                )
                : nil
        }
        recordTimelineControlState()
        if hasAudio {
            startAudioDelivery()
        }
        if rearmsVideoDelivery {
            startVideoDelivery()
        }
    }

    static func millisecondValue(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let components = (end - start).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> String {
        String(format: "%.1f", millisecondValue(from: start, to: end))
    }

    func seekProgressSignal(
        _ snapshot: PlaybackDebugSnapshotV1? = nil
    ) -> PlaybackSeekProgressSignal {
        let observed = snapshot ?? debugStore.snapshot()
        return PlaybackSeekProgressSignal(
            sourceBytesRead: sourceReadMeter?.totalBytesRead ?? 0,
            videoSourceEventID: observed.lastVideoSample?.sourceEventID,
            videoPresentationSeconds: observed.lastVideoSample?.presentationTimeSeconds,
            audioStreamEpoch: observed.lastAudioSample?.streamEpoch,
            audioPresentationSeconds: observed.lastAudioSample?.presentationTimeSeconds,
            rendererInputSourceEventID: observed.lastAcceptedRendererInput?.sourceEventID,
            rendererInputStreamEpoch: observed.lastAcceptedRendererInput?.streamEpoch
        )
    }

    func traceSeekStall(
        target: Double,
        lastProgressAt: ContinuousClock.Instant,
        now: ContinuousClock.Instant
    ) {
        let lastProgressMilliseconds = Self.milliseconds(from: lastProgressAt, to: now)
        PlaybackTrace.event(
            "session.seek.stalled seconds=\(target)"
                + " lastProgressMs=\(lastProgressMilliseconds)"
        )
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "session.seek.stalled",
            outcome: .succeeded,
            details: [
                "targetSeconds": String(target),
                "lastProgressMs": lastProgressMilliseconds
            ]
        )
    }

}
