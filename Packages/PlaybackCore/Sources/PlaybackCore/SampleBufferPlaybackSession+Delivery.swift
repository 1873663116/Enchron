@preconcurrency import AVFoundation
import Foundation
import OSLog

extension SampleBufferPlaybackSession {
    func close() {
        close(completion: {})
    }

    func closeAndWait() async {
        await withCheckedContinuation { continuation in
            close {
                continuation.resume()
            }
        }
    }

    func close(completion: @escaping @Sendable () -> Void) {
        closeLock.lock()
        if isCloseFinished {
            closeLock.unlock()
            completion()
            return
        }
        closeCompletions.append(completion)
        guard !isClosing else {
            closeLock.unlock()
            return
        }
        isClosing = true
        closeLock.unlock()

        stopRendererFailureMonitoring()
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByClose)
        activationObservation.stop()

        PlaybackTrace.event(
            "session.close.begin id=\(traceID) samples=\(diagnostics.enqueuedSampleCount) " +
            "rendererStatus=\(currentVideoRendererStatus) displayed=\(renderer.displayedPixelBuffer() != nil)"
        )
        if activeOperation != nil {
            finishActiveOperation(.terminatedByCleanup)
        }
        beginOperation(.close)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "session.cleanup",
            outcome: .terminatedByCleanup
        )
        closeEndState()
        stopVideoDelivery()
        stopAudioDelivery()
        discardPendingVideoSample()
        synchronizer.rate = 0
        deliveryQueue.sync {
            isClosed = true
            provider.cancel()
            debugStore.recordCleanupStep(.videoProviderCancelled)
        }
        audioDeliveryQueue.sync {
            audioProvider.cancel()
            debugStore.recordCleanupStep(.audioProviderCancelled)
        }
        subtitleStateLock.withLock {
            subtitleState.selectionGeneration &+= 1
            subtitleState.streamEpoch &+= 1
            subtitleState.availableTracks = []
            subtitleState.selectedTrackID = nil
            subtitleState.cues = []
            subtitleState.frameRenderer = nil
            subtitleState.activeFrame = nil
            subtitleState.suppressesActiveCues = true
            subtitleState.isClosed = true
        }
        subtitleProvider.cancel()
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        audioRendererSink.flush()
        debugStore.recordCleanupStep(.audioRendererFlushed)
        Task { [self] in
            await rendererSink.flush(removingDisplayedImage: true)
            finishCloseAfterFlush()
        }
    }

    func finishCloseAfterFlush() {
        flushCount += 1
        debugStore.recordCleanupStep(.videoRendererFlushed)
        PlaybackTrace.event("session.rendererFlushed id=\(traceID)")
        if let timeObserver {
            synchronizer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        PlaybackTrace.event("session.close.end id=\(traceID)")
        recordRendererState(at: currentTime())
        finishActiveOperation(.completed)
        debugStore.recordSession(nil)
        closeLock.lock()
        isCloseFinished = true
        let completions = closeCompletions
        closeCompletions.removeAll()
        closeLock.unlock()
        completions.forEach { $0() }
    }

    func startVideoDelivery() {
        rendererSink.stopRenderingEventObservation()
        let (generation, previousTask) = deliveryTaskLock.withLock {
            videoDeliveryGeneration &+= 1
            let previousTask = videoDeliveryTask
            videoDeliveryTask = nil
            return (videoDeliveryGeneration, previousTask)
        }
        previousTask?.cancel()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            await self.deliverSamples(generation: generation)
        }
        let shouldCancel = deliveryTaskLock.withLock {
            guard videoDeliveryGeneration == generation else {
                return true
            }
            self.videoDeliveryTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func stopVideoDelivery() {
        let task = deliveryTaskLock.withLock {
            videoDeliveryGeneration &+= 1
            let task = videoDeliveryTask
            videoDeliveryTask = nil
            return task
        }
        task?.cancel()
    }

    func startAudioDelivery() {
        audioRendererSink.stopRenderingEventObservation()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            await self.deliverAudioSamples()
        }
        let previousTask = deliveryTaskLock.withLock {
            let previousTask = audioDeliveryTask
            audioDeliveryTask = task
            return previousTask
        }
        previousTask?.cancel()
    }

    func stopAudioDelivery() {
        let task = deliveryTaskLock.withLock {
            let task = audioDeliveryTask
            audioDeliveryTask = nil
            return task
        }
        task?.cancel()
    }

    func deliverSamples(generation: UInt64) async {
        while isCurrentVideoDelivery(generation), !isClosed, !isResetting {
            let sampleOrdinal = UInt64(diagnostics.enqueuedSampleCount + 1)
            let sourceSample: CMSampleBuffer
            if let pendingSample = currentPendingVideoSample() {
                sourceSample = pendingSample
            } else {
                do {
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "providerRead.enter",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal
                    )
                    if sampleOrdinal <= 8 {
                        debugStore.emit(
                            mediaSessionID: traceID,
                            node: .mediaEventStream,
                            kind: "videoProvider.read.started",
                            outcome: .succeeded,
                            details: ["sampleOrdinal": String(sampleOrdinal)]
                        )
                    }
                    let event = try await provider.nextEvent()
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "providerRead.returned",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        outcome: providerEventKind(event)
                    )
                    if sampleOrdinal <= 8 {
                        debugStore.emit(
                            mediaSessionID: traceID,
                            node: .mediaEventStream,
                            kind: "videoProvider.read.completed",
                            outcome: .succeeded,
                            details: [
                                "eventKind": providerEventKind(event),
                                "sampleOrdinal": String(sampleOrdinal),
                            ]
                        )
                    }
                    switch event {
                    case .sample(let sample):
                        sourceSample = sample
                        setPendingVideoSample(sample)
                    case .formatChanged:
                        await handleProviderControlEvent(.formatChanged)
                        return
                    case .flush:
                        await handleProviderControlEvent(.flush)
                        return
                    case .end:
                        finishDelivery()
                        return
                    }
                    guard isCurrentVideoDelivery(generation), !isClosed, !isResetting else {
                        return
                    }
                } catch {
                    guard !Task.isCancelled, !isClosed else { return }
                    provider.cancel()
                    recordMediaErrorEvent()
                    recordFailure(error, node: .mediaEventStream, kind: "provider.readFailed")
                    onStatusChange?(.failed(error.localizedDescription))
                    return
                }
            }

            let sourceSampleCount = CMSampleBufferGetNumSamples(sourceSample)
            guard sourceSampleCount > 0,
                  CMSampleBufferGetFormatDescription(sourceSample) != nil else {
                clearPendingVideoSample(sourceSample)
                PlaybackTrace.event(
                    "session.videoSample.skipped id=\(traceID) sampleCount=\(sourceSampleCount)"
                )
                continue
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sourceSample)
            let duration = CMSampleBufferGetDuration(sourceSample)
            let presentationEnd = duration.isNumeric
                ? CMTimeAdd(presentationTime, duration)
                : presentationTime
            recordVideoPresentation(
                presentationTime: presentationTime,
                presentationEnd: presentationEnd
            )

            let renderSample: CMSampleBuffer
            do {
                if stereoLayoutOverride != nil || projectionOverride != nil {
                    renderSample = try videoSampleFormatOverride.rewrite(
                        sourceSample,
                        stereoLayout: stereoLayoutOverride,
                        projection: projectionOverride
                    )
                } else {
                    renderSample = sourceSample
                }
            } catch {
                recordFailure(
                    error,
                    node: .rendererInputCoordination,
                    kind: "videoFormatOverride.failed"
                )
                onStatusChange?(.failed(error.localizedDescription))
                return
            }
            markAsPrerollIfNeeded(
                renderSample,
                presentationTime: presentationTime,
                presentationEnd: presentationEnd
            )
            let shouldAnchorTimeline = !hasStartedTimeline
            if shouldAnchorTimeline {
                let hasPreroll = requestedTimelineStart.isNumeric &&
                    requestedTimelineStart > presentationTime
                let timelineStart = hasPreroll ? presentationTime : targetTimelineTime(
                    fallback: presentationTime
                )
                PlaybackTrace.event(
                    "session.firstSample id=\(traceID) pts=\(presentationTime.seconds) " +
                    "timelineStart=\(timelineStart.seconds) " +
                    "input=\(RendererInputKind.compressed.rawValue)"
                )
                synchronizer.setRate(0, time: timelineStart)
                hasStartedTimeline = true
                // The timeline must remain stopped until decoder bootstrap and,
                // when present, audio preroll have both crossed the start point.
                // This is also required when the first video PTS equals the
                // requested start: a nonzero PTS/DTS decode pipeline can still
                // need the bootstrap gate.
                isPrerolling = true
                beginDecoderBootstrap(
                    target: targetTimelineTime(fallback: presentationTime)
                )
                ensureAudioDeliveryStarted()
                PlaybackTrace.event(
                    "session.timeline.set id=\(traceID) rate=0.0 " +
                    "time=\(timelineStart.seconds)"
                )
                publishDiagnostics(at: timelineStart, force: true)
            }
            if diagnostics.enqueuedSampleCount == 0 {
                diagnostics.timelineConfiguredBeforeFirstEnqueue = hasStartedTimeline
                dumpVideoSampleIfRequested(renderSample)
            }
            let decodeTime = CMSampleBufferGetDecodeTimeStamp(renderSample)
            let decoderBootstrapTarget = targetTimelineTime(fallback: presentationTime)
            let bootstrapIncomplete = !decoderBootstrapLock.withLock { decoderBootstrapComplete }
            // The first DTS after the target is the sample that completes bootstrap.
            // Waiting for renderer backpressure before submitting that crossing sample
            // can deadlock while the synchronizer is intentionally held at rate zero.
            let requiresImmediateDecoderBootstrap = bootstrapIncomplete
            let outcome: RendererEnqueueOutcome
            do {
                let enqueueSample = try CMSampleBuffer(copying: renderSample)
                let input = RendererInputSample(sampleBuffer: enqueueSample)
                if sampleOrdinal <= 8 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "videoRenderer.enqueue.started",
                        outcome: .succeeded,
                        details: [
                            "decodeTimeSeconds": String(decodeTime.seconds),
                            "immediate": String(requiresImmediateDecoderBootstrap),
                            "presentationTimeSeconds": String(presentationTime.seconds),
                            "sampleOrdinal": String(sampleOrdinal),
                        ]
                    )
                }
                switch rendererSink.enqueueStrategy {
                case .boundedImmediateLead:
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "boundedLead.enter",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    try await waitForBoundedRendererLead(presentationTime: presentationTime)
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "boundedLead.returned",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.enter",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    outcome = try rendererSink.enqueueImmediately(input)
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.returned",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.outcome",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime,
                        outcome: String(describing: outcome)
                    )
                case .receiverBackpressure where requiresImmediateDecoderBootstrap:
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.enter",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    outcome = try rendererSink.enqueueImmediately(input)
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.returned",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    emitPlaybackDeliveryStage(
                        lane: "video",
                        stage: "enqueueImmediately.outcome",
                        epoch: streamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime,
                        outcome: String(describing: outcome)
                    )
                case .receiverBackpressure:
                    outcome = try await rendererSink.enqueue(input)
                }
                if sampleOrdinal <= 8 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "videoRenderer.enqueue.completed",
                        outcome: .succeeded,
                        details: [
                            "result": String(describing: outcome),
                            "sampleOrdinal": String(sampleOrdinal),
                        ]
                    )
                }
            } catch {
                guard isCurrentVideoDelivery(generation), !isClosed else { return }
                publishRendererFailure(RendererFailureFact(
                    rendererKind: .video,
                    errorType: String(reflecting: type(of: error)),
                    message: error.localizedDescription,
                    requiresFlushToResumeDecoding: nil
                ))
                return
            }
            guard isCurrentVideoDelivery(generation), !isClosed, !isResetting else {
                return
            }
            guard handleVideoEnqueueOutcome(outcome) else { return }
            activationObservation.recordAcceptedVideo(
                epoch: streamEpoch,
                presentationTime: presentationTime,
                decodeTime: decodeTime,
                presentationEnd: presentationEnd
            )
            let bootstrap = recordAcceptedDecoderBootstrapSample(
                decodeTime: decodeTime,
                target: decoderBootstrapTarget,
                usedImmediateEnqueue: requiresImmediateDecoderBootstrap
            )
            let targetReached = requestedTimelineStart.isNumeric == false
                || presentationTime >= requestedTimelineStart
                || presentationEnd >= requestedTimelineStart
            if isPrerolling, bootstrap.complete, targetReached {
                let activationTime = targetTimelineTime(fallback: presentationTime)
                do {
                    try await waitForAudioPreroll(through: activationTime)
                } catch {
                    guard isCurrentVideoDelivery(generation), !isClosed else { return }
                    recordFailure(
                        error,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.prerollFailed"
                    )
                    onStatusChange?(.failed(error.localizedDescription))
                    return
                }
                let activationSequence = activationObservation.beginActivation(
                    requestedRate: timelineStartRate,
                    anchorTime: activationTime
                )
                // Re-anchor the stopped timebase immediately before activation
                // so the rate change is applied to the same media position after
                // the preroll queues have been populated. Applying it against a
                // near-future host time avoids the visionOS race where an
                // asynchronous media-time update leaves the underlying timebase
                // stopped even though synchronizer.rate already reports 1.
                synchronizer.setRate(0, time: activationTime)
                setRateAtHostTime(timelineStartRate, time: activationTime)
                if let activationSequence {
                    activationObservation.rateApplicationReturned(
                        sequence: activationSequence
                    )
                }
                recordAudioRateActivation(
                    rate: timelineStartRate,
                    time: activationTime,
                    reason: "decoderBootstrap"
                )
                isPrerolling = false
                publishTargetTimelineState(at: activationTime)
                publishDiagnostics(at: activationTime, force: true)
                PlaybackTrace.event(
                    "session.timeline.activated id=\(traceID) rate=\(timelineStartRate) " +
                    "bootstrapComplete=true immediateSamples=\(bootstrap.immediateEnqueueCount)"
                )
            } else if shouldAnchorTimeline, !isPrerolling {
                let activationTime = targetTimelineTime(fallback: presentationTime)
                let activationSequence = activationObservation.beginActivation(
                    requestedRate: timelineStartRate,
                    anchorTime: activationTime
                )
                // A normal open has no future timeline target to preroll toward.
                // Start the synchronizer after the first accepted sample, matching
                // the established AVSampleBufferRenderSynchronizer startup path.
                setRateAtHostTime(timelineStartRate, time: activationTime)
                if let activationSequence {
                    activationObservation.rateApplicationReturned(
                        sequence: activationSequence
                    )
                }
                recordAudioRateActivation(
                    rate: timelineStartRate,
                    time: activationTime,
                    reason: "firstSample"
                )
                publishTargetTimelineState(at: activationTime)
                publishDiagnostics(at: activationTime, force: true)
                PlaybackTrace.event(
                    "session.timeline.activated id=\(traceID) rate=\(timelineStartRate) " +
                    "bootstrapComplete=\(bootstrap.complete) immediateSamples=\(bootstrap.immediateEnqueueCount)"
                )
            }
            clearPendingVideoSample(sourceSample)
            let sourceEventID = recordVideoSample(renderSample)
            updateCompressedDiagnostics(sample: renderSample)
            lastSourceEventID = sourceEventID
            diagnostics.enqueuedSampleCount += 1
            let rendererRecord = RendererInputRecord(
                mediaSessionID: traceID,
                sourceEventID: lastSourceEventID,
                videoTrackID: videoTrackID,
                streamEpoch: streamEpoch,
                formatRevision: formatRevision,
                graphRevision: 1,
                inputKind: .compressed,
                timelineConfiguredBeforeFirstEnqueue: hasStartedTimeline,
                action: "enqueue",
                outcome: .accepted
            )
            debugStore.recordRendererInput(rendererRecord)
            if rendererRecord.streamEpoch == streamEpoch {
                recordRendererState(at: synchronizer.currentTime())
            }
            if diagnostics.enqueuedSampleCount == 1 {
                debugStore.emit(
                    mediaSessionID: traceID,
                    node: .rendererInputCoordination,
                    kind: "renderer.firstEnqueue",
                    outcome: .succeeded,
                    details: [
                        "timelineConfiguredBeforeFirstEnqueue": String(hasStartedTimeline),
                        "sourceEventID": lastSourceEventID,
                    ]
                )
                PlaybackTrace.event(
                    "session.firstEnqueue id=\(traceID) rendererStatus=\(currentVideoRendererStatus) " +
                    "rendererError=\(currentVideoRendererError ?? "none")"
                )
            }
        }
    }

    func isCurrentVideoDelivery(_ generation: UInt64) -> Bool {
        guard !Task.isCancelled else { return false }
        return deliveryTaskLock.withLock { videoDeliveryGeneration == generation }
    }

    func currentPendingVideoSample() -> CMSampleBuffer? {
        pendingVideoSampleLock.withLock { pendingVideoSample }
    }

    func setPendingVideoSample(_ sample: CMSampleBuffer) {
        pendingVideoSampleLock.withLock { pendingVideoSample = sample }
    }

    func clearPendingVideoSample(_ sample: CMSampleBuffer) {
        pendingVideoSampleLock.withLock {
            if pendingVideoSample === sample {
                pendingVideoSample = nil
            }
        }
    }

    func discardPendingVideoSample() {
        pendingVideoSampleLock.withLock { pendingVideoSample = nil }
    }

    private func providerEventKind(_ event: VideoSampleProviderEvent) -> String {
        switch event {
        case .sample: "sample"
        case .formatChanged: "formatChanged"
        case .flush: "flush"
        case .end: "end"
        }
    }

    func deliverAudioSamples() async {
        while !Task.isCancelled, !isClosed, !isResetting {
            do {
                let sampleOrdinal = audioSampleBufferCount + 1
                emitPlaybackDeliveryStage(
                    lane: "audio",
                    stage: "providerRead.enter",
                    epoch: audioStreamEpoch,
                    sampleOrdinal: sampleOrdinal
                )
                if sampleOrdinal <= 64 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .mediaEventStream,
                        kind: "audioProvider.read.started",
                        outcome: .succeeded,
                        details: ["sampleOrdinal": String(sampleOrdinal)]
                    )
                }
                let nextSample = try await audioProvider.copyNextSample()
                emitPlaybackDeliveryStage(
                    lane: "audio",
                    stage: "providerRead.returned",
                    epoch: audioStreamEpoch,
                    sampleOrdinal: sampleOrdinal,
                    outcome: nextSample == nil ? "end" : "sample"
                )
                if sampleOrdinal <= 64 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .mediaEventStream,
                        kind: "audioProvider.read.completed",
                        outcome: .succeeded,
                        details: [
                            "hasSample": String(nextSample != nil),
                            "sampleOrdinal": String(sampleOrdinal),
                        ]
                    )
                }
                guard let sourceSample = nextSample else {
                    markAudioProviderEnded()
                    audioRendererSink.observeRenderingEventsAfterFinishedEnqueuing(
                        handler: rendererInputEventHandler()
                    )
                    debugStore.emit(
                        mediaSessionID: traceID,
                        kind: "audioProvider.inputEnded",
                        outcome: .succeeded
                    )
                    return
                }
                let sample = normalizeAudioSampleTimeline(sourceSample)
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                let decodeTime = CMSampleBufferGetDecodeTimeStamp(sample)
                let duration = CMSampleBufferGetDuration(sample)
                let presentationEnd = duration.isNumeric
                    ? CMTimeAdd(presentationTime, duration)
                    : presentationTime
                let audioInfo = audioProvider.info
                let rawStreamIndex = audioInfo?.streamIndex
                    ?? selectedAudioStreamIndex
                    ?? -1
                let trackID = rawStreamIndex >= 0
                    ? "\(traceID).audio.\(rawStreamIndex)"
                    : "\(traceID).audio.unknown"
                let record = AudioSampleRecord(
                    mediaSessionID: traceID,
                    audioTrackID: trackID,
                    streamEpoch: audioStreamEpoch,
                    rawStreamIndex: rawStreamIndex,
                    presentationTimeSeconds: numericSeconds(presentationTime) ?? 0,
                    durationSeconds: numericSeconds(duration) ?? 0,
                    sampleRate: audioInfo?.sampleRate ?? 0,
                    channelCount: audioInfo?.channelCount ?? 0,
                    sampleCount: CMSampleBufferGetNumSamples(sample),
                    payloadOwnershipState: "retainedCMSampleBuffer"
                )
                debugStore.recordAudioSample(record)
                if sampleOrdinal <= 64 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.enqueue.started",
                        outcome: .succeeded,
                        details: ["sampleOrdinal": String(sampleOrdinal)]
                    )
                }
                let input = RendererInputSample(sampleBuffer: sample)
                let outcome: RendererEnqueueOutcome
                switch audioRendererSink.enqueueStrategy {
                case .boundedImmediateLead:
                    emitPlaybackDeliveryStage(
                        lane: "audio",
                        stage: "boundedLead.enter",
                        epoch: audioStreamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    try await waitForBoundedRendererLead(presentationTime: presentationTime)
                    emitPlaybackDeliveryStage(
                        lane: "audio",
                        stage: "boundedLead.returned",
                        epoch: audioStreamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    emitPlaybackDeliveryStage(
                        lane: "audio",
                        stage: "enqueueImmediately.enter",
                        epoch: audioStreamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    outcome = try audioRendererSink.enqueueImmediately(input)
                    emitPlaybackDeliveryStage(
                        lane: "audio",
                        stage: "enqueueImmediately.returned",
                        epoch: audioStreamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime
                    )
                    emitPlaybackDeliveryStage(
                        lane: "audio",
                        stage: "enqueueImmediately.outcome",
                        epoch: audioStreamEpoch,
                        sampleOrdinal: sampleOrdinal,
                        presentationTime: presentationTime,
                        decodeTime: decodeTime,
                        outcome: String(describing: outcome)
                    )
                case .receiverBackpressure:
                    outcome = try await audioRendererSink.enqueue(input)
                }
                if sampleOrdinal <= 64 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.enqueue.completed",
                        outcome: .succeeded,
                        details: [
                            "result": String(describing: outcome),
                            "sampleOrdinal": String(sampleOrdinal),
                        ]
                    )
                }
                guard handleAudioEnqueueOutcome(outcome) else { return }
                activationObservation.recordAcceptedAudio(
                    epoch: audioStreamEpoch,
                    presentationTime: presentationTime,
                    presentationEnd: presentationEnd
                )
                audioSampleBufferCount += 1
                audioFrameCount += UInt64(max(0, record.sampleCount))
                recordAudioPresentationEnd(presentationEnd)
                recordAudioRendererState()
                if audioSampleBufferCount == 1 {
                    var details = audioSampleFormatDetails(sample)
                    details["audioTrackID"] = trackID
                    details["streamEpoch"] = String(audioStreamEpoch)
                    details["timelineOffsetSeconds"] = String(audioTimestampOffset.seconds)
                    details["rendererStatus"] = audioRendererStatusLabel
                    details["rendererError"] = audioRenderer.error?.localizedDescription
                        ?? currentAudioRendererError
                        ?? "none"
                    details["rendererVolume"] = String(audioRenderer.volume)
                    details["rendererMuted"] = String(audioRenderer.isMuted)
                    debugStore.emit(
                        mediaSessionID: traceID,
                        kind: "audioRenderer.firstEnqueue",
                        outcome: .succeeded,
                        details: details
                    )
                }
            } catch {
                guard !Task.isCancelled, !isClosed else { return }
                recordFailure(error, node: .rendererInputCoordination, kind: "audioRenderer.deliveryFailed")
                onStatusChange?(.failed(error.localizedDescription))
                return
            }
        }
    }

    func normalizeAudioSampleTimeline(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
        guard presentationTime.isNumeric else { return sample }

        let offset: CMTime = audioTimestampOffsetLock.withLock {
            if audioTimestampOffsetEpoch != audioStreamEpoch {
                audioTimestampOffsetEpoch = audioStreamEpoch
                audioTimestampOffset = presentationTime < .zero
                    ? CMTimeSubtract(.zero, presentationTime)
                    : .zero
            }
            return audioTimestampOffset
        }
        guard offset.isNumeric, offset != .zero else { return sample }

        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(
            sample,
            at: 0,
            timingInfoOut: &timing
        ) == noErr else { return sample }
        timing.presentationTimeStamp = CMTimeAdd(timing.presentationTimeStamp, offset)
        if timing.decodeTimeStamp.isNumeric {
            timing.decodeTimeStamp = CMTimeAdd(timing.decodeTimeStamp, offset)
        }

        var adjustedSample: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedSample
        )
        return status == noErr ? (adjustedSample ?? sample) : sample
    }

    func handleVideoEnqueueOutcome(_ outcome: RendererEnqueueOutcome) -> Bool {
        switch outcome {
        case .accepted:
            setVideoRendererState(status: "ready", error: nil)
            return true
        case .acceptedWithWarnings(let warnings):
            setVideoRendererState(status: "readyWithDecodeFailures", error: warnings.first)
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "videoRenderer.decodeFailures",
                outcome: .failed,
                details: ["errors": warnings.joined(separator: " | ")]
            )
            return true
        case .cancelledByFlush:
            return false
        case .requiresFlush(let message):
            publishRendererFailure(RendererFailureFact(
                rendererKind: .video,
                errorType: "AVSampleBufferVideoRenderer.RequiresFlush",
                message: message ?? "Video renderer requires a flush before decoding can resume.",
                requiresFlushToResumeDecoding: true
            ))
            return false
        case .failed(let message):
            publishRendererFailure(RendererFailureFact(
                rendererKind: .video,
                errorType: "AVSampleBufferVideoRenderer.Receiver",
                message: message,
                requiresFlushToResumeDecoding: false
            ))
            return false
        }
    }

    func handleAudioEnqueueOutcome(_ outcome: RendererEnqueueOutcome) -> Bool {
        switch outcome {
        case .accepted:
            setAudioRendererError(nil)
            return true
        case .acceptedWithWarnings(let warnings):
            setAudioRendererError(warnings.first)
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "audioRenderer.suggestedFlush",
                outcome: .succeeded,
                details: ["reasons": warnings.joined(separator: " | ")]
            )
            return true
        case .cancelledByFlush:
            return false
        case .requiresFlush(let message):
            publishRendererFailure(RendererFailureFact(
                rendererKind: .audio,
                errorType: "AVSampleBufferAudioRenderer.Receiver",
                message: message ?? "Audio renderer could not accept the sample.",
                requiresFlushToResumeDecoding: nil
            ))
            return false
        case .failed(let message):
            publishRendererFailure(RendererFailureFact(
                rendererKind: .audio,
                errorType: "AVSampleBufferAudioRenderer.Receiver",
                message: message,
                requiresFlushToResumeDecoding: nil
            ))
            return false
        }
    }

    func waitForBoundedRendererLead(presentationTime: CMTime) async throws {
        guard presentationTime.isNumeric else { return }
        while true {
            try Task.checkCancellation()
            guard !isClosed, !isResetting else { throw CancellationError() }
            let current = synchronizer.currentTime()
            let target = targetTimelineTime(fallback: current)
            let referenceSeconds = max(
                current.isNumeric ? current.seconds : 0,
                target.isNumeric ? target.seconds : 0
            )
            if presentationTime.seconds <= referenceSeconds + 1 {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func emitPlaybackDeliveryStage(
        lane: String,
        stage: String,
        epoch: UInt64,
        sampleOrdinal: UInt64,
        presentationTime: CMTime? = nil,
        decodeTime: CMTime? = nil,
        outcome: String? = nil
    ) {
        var details = [
            "streamEpoch": String(epoch),
            "sampleOrdinal": String(sampleOrdinal),
            "presentationTimeSeconds": presentationTime.flatMap { numericSeconds($0) }
                .map { String($0) } ?? "unavailable",
            "decodeTimeSeconds": decodeTime.flatMap { numericSeconds($0) }
                .map { String($0) } ?? "unavailable",
        ]
        if let outcome {
            details["outcome"] = outcome
        }
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "playbackDelivery.stage.\(lane).\(stage)",
            outcome: .succeeded,
            details: details
        )
    }

    func ensureAudioDeliveryStarted() {
        guard hasAudio else { return }
        let needsStart = deliveryTaskLock.withLock { audioDeliveryTask == nil }
        if needsStart {
            startAudioDelivery()
        }
    }

    func waitForAudioPreroll(through activationTime: CMTime) async throws {
        guard hasAudio, activationTime.isNumeric else { return }
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard !isClosed, !isResetting else { throw CancellationError() }
            if audioHasPrerolled(through: activationTime) {
                let accumulatedPresentationEnd = endStateLock.withLock {
                    endState.audioPresentationEnd
                }
                let accumulatedPresentationEndSeconds = accumulatedPresentationEnd
                    .flatMap(numericSeconds)
                    .map { String($0) } ?? "none"
                debugStore.emit(
                    mediaSessionID: traceID,
                    node: .rendererInputCoordination,
                    kind: "audioRenderer.prerollCompleted",
                    outcome: .succeeded,
                    details: [
                        "activationTimeSeconds": String(activationTime.seconds),
                        "accumulatedPresentationEndSeconds": accumulatedPresentationEndSeconds,
                        "streamEpoch": String(audioStreamEpoch),
                        "rendererStatus": audioRendererStatusLabel,
                        "rendererError": audioRenderer.error?.localizedDescription
                            ?? currentAudioRendererError
                            ?? "none",
                    ]
                )
                return
            }
            if debugStore.snapshot().lifecycle == .failed {
                throw CorePlaybackError.audioPrerollTimedOut(activationTime.seconds)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CorePlaybackError.audioPrerollTimedOut(activationTime.seconds)
    }

    func audioHasPrerolled(through activationTime: CMTime) -> Bool {
        let minimumEnd = CMTimeAdd(
            activationTime,
            CMTime(seconds: 0.25, preferredTimescale: 48_000)
        )
        return endStateLock.withLock {
            guard let audioEnd = endState.audioPresentationEnd,
                  audioEnd.isNumeric else { return false }
            if CMTimeCompare(audioEnd, minimumEnd) >= 0 { return true }
            return endState.audioProviderEnded
                && CMTimeCompare(audioEnd, activationTime) > 0
        }
    }

    func audioSampleFormatDetails(_ sample: CMSampleBuffer) -> [String: String] {
        var details: [String: String] = [
            "sampleCount": String(CMSampleBufferGetNumSamples(sample)),
            "dataReady": String(CMSampleBufferDataIsReady(sample)),
        ]
        if let dataBuffer = CMSampleBufferGetDataBuffer(sample) {
            details["dataByteCount"] = String(CMBlockBufferGetDataLength(dataBuffer))
        }
        guard let format = CMSampleBufferGetFormatDescription(sample) else {
            details["format"] = "missing"
            return details
        }
        details["formatIdentity"] = PlaybackTrace.identity(format)
        details["mediaSubtype"] = fourCC(CMFormatDescriptionGetMediaSubType(format))
        if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
            let value = stream.pointee
            details["asbd.sampleRate"] = String(value.mSampleRate)
            details["asbd.formatID"] = fourCC(value.mFormatID)
            details["asbd.formatFlags"] = String(value.mFormatFlags)
            details["asbd.bytesPerPacket"] = String(value.mBytesPerPacket)
            details["asbd.framesPerPacket"] = String(value.mFramesPerPacket)
            details["asbd.bytesPerFrame"] = String(value.mBytesPerFrame)
            details["asbd.channelsPerFrame"] = String(value.mChannelsPerFrame)
            details["asbd.bitsPerChannel"] = String(value.mBitsPerChannel)
            details["asbd.reserved"] = String(value.mReserved)
        }
        var cookieSize = 0
        let cookie = CMAudioFormatDescriptionGetMagicCookie(format, sizeOut: &cookieSize)
        details["magicCookieSize"] = String(cookieSize)
        details["hasMagicCookie"] = String(cookie != nil)
        if let cookie, cookieSize > 0 {
            details["magicCookieHash"] = stableDiagnosticHash(
                UnsafeRawBufferPointer(start: cookie, count: cookieSize)
            )
        } else {
            details["magicCookieHash"] = "none"
        }
        var channelLayoutSize = 0
        let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
            format,
            sizeOut: &channelLayoutSize
        )
        details["channelLayoutSize"] = String(channelLayoutSize)
        details["hasChannelLayout"] = String(channelLayout != nil)
        if let channelLayout {
            details["channelLayout.tag"] = String(channelLayout.pointee.mChannelLayoutTag)
            details["channelLayout.bitmap"] = String(
                channelLayout.pointee.mChannelBitmap.rawValue
            )
            details["channelLayout.descriptionCount"] = String(
                channelLayout.pointee.mNumberChannelDescriptions
            )
        }
        if let metadata = CMGetAttachment(
            sample,
            key: "com.enchron.playbackcore.ffmpegAudioMetadata" as CFString,
            attachmentModeOut: nil
        ) as? [String: Any] {
            for (key, value) in metadata {
                details["ffmpeg.\(key)"] = String(describing: value)
            }
        }
        details["presentationTime.value"] = String(CMSampleBufferGetPresentationTimeStamp(sample).value)
        details["presentationTime.timescale"] = String(CMSampleBufferGetPresentationTimeStamp(sample).timescale)
        details["decodeTime.value"] = String(CMSampleBufferGetDecodeTimeStamp(sample).value)
        details["decodeTime.timescale"] = String(CMSampleBufferGetDecodeTimeStamp(sample).timescale)
        details["duration.value"] = String(CMSampleBufferGetDuration(sample).value)
        details["duration.timescale"] = String(CMSampleBufferGetDuration(sample).timescale)
        return details
    }

    func stableDiagnosticHash(_ bytes: UnsafeRawBufferPointer) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "fnv1a64:%016llx", hash)
    }

    var isVideoRendererFailed: Bool {
        rendererStateLock.withLock { videoRendererStatus == "failed" }
    }

    var currentVideoRendererStatus: String {
        rendererStateLock.withLock { videoRendererStatus }
    }

    var currentVideoRendererError: String? {
        rendererStateLock.withLock { videoRendererError }
    }

    var currentAudioRendererError: String? {
        rendererStateLock.withLock { audioRendererError }
    }

    func setVideoRendererState(status: String, error: String?) {
        rendererStateLock.withLock {
            videoRendererStatus = status
            videoRendererError = error
        }
    }

    func setAudioRendererError(_ error: String?) {
        rendererStateLock.withLock { audioRendererError = error }
    }

    func recordAudioRendererState() {
        let rendererError = audioRenderer.error?.localizedDescription
            ?? currentAudioRendererError
        let rendererStatus = audioRendererStatusLabel
        let didChange = rendererStateLock.withLock {
            let changed = lastRecordedAudioRendererStatus != rendererStatus
                || lastRecordedAudioRendererError != rendererError
            lastRecordedAudioRendererStatus = rendererStatus
            lastRecordedAudioRendererError = rendererError
            return changed
        }
        debugStore.recordAudioRendererState(AudioRendererStateRecord(
            mediaSessionID: traceID,
            graphID: "\(traceID).rendererGraph",
            rendererIdentity: PlaybackTrace.identity(audioRenderer),
            videoRendererIdentity: PlaybackTrace.identity(renderer),
            synchronizerIdentity: PlaybackTrace.identity(synchronizer),
            streamEpoch: audioStreamEpoch,
            enqueuedSampleBufferCount: audioSampleBufferCount,
            enqueuedAudioFrameCount: audioFrameCount,
            status: rendererStatus,
            volume: audioRenderer.volume,
            muted: audioRenderer.isMuted,
            error: rendererError
        ))
        if didChange {
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: "audioRenderer.statusChanged",
                outcome: rendererStatus == "failed" ? .failed : .succeeded,
                details: [
                    "streamEpoch": String(audioStreamEpoch),
                    "status": rendererStatus,
                    "error": rendererError ?? "none",
                    "volume": String(audioRenderer.volume),
                    "muted": String(audioRenderer.isMuted),
                ]
            )
        }
    }

    func recordAudioRateActivation(rate: Float, time: CMTime, reason: String) {
        guard hasAudio else { return }
        let actualTime = synchronizer.currentTime()
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "audioRenderer.rateActivated",
            outcome: .succeeded,
            details: [
                "streamEpoch": String(describing: audioStreamEpoch),
                "rate": String(rate),
                "timeSeconds": numericSeconds(time).map { String($0) } ?? "invalid",
                "application": "setRateAtHostTime",
                "immediateActualRate": String(CMTimebaseGetRate(synchronizer.timebase)),
                "immediateCurrentTimeSeconds": numericSeconds(actualTime)
                    .map { String($0) } ?? "invalid",
                "reason": reason,
                "rendererStatus": audioRendererStatusLabel,
                "rendererError": audioRenderer.error?.localizedDescription
                    ?? currentAudioRendererError
                    ?? "none",
            ]
        )
    }

    var audioRendererStatusLabel: String {
        switch audioRenderer.status {
        case .unknown:
            "unknown"
        case .rendering:
            "rendering"
        case .failed:
            "failed"
        @unknown default:
            "unrecognized"
        }
    }


    func finishDelivery() {
        markVideoProviderEnded()
        rendererSink.observeRenderingEventsAfterFinishedEnqueuing(
            handler: rendererInputEventHandler()
        )
        sourceEventSequence += 1
        let event = MediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .end,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordMediaEvent(event)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .mediaEventStream,
            kind: "provider.inputEnded",
            outcome: .succeeded
        )
    }

    func handleProviderControlEvent(_ kind: MediaEventKind) async {
        isResetting = true
        switch kind {
        case .formatChanged:
            activationObservation.invalidateReapplyVerification(outcome: .invalidatedByEpochChange)
            formatRevision += 1
        case .flush:
            activationObservation.invalidateReapplyVerification(outcome: .invalidatedByEpochChange)
            streamEpoch += 1
            lastRecordedSampleEpoch = 0
        case .sample, .end, .error:
            return
        }
        sourceEventSequence += 1
        let event = MediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: kind,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordMediaEvent(event)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .mediaEventStream,
            kind: PlaybackArtifactEventName.providerControl(kind).rawValue,
            outcome: .succeeded,
            details: [
                "streamEpoch": String(streamEpoch),
                "formatRevision": String(formatRevision),
            ]
        )
        didRecordFormat = false
        resetVideoEndState()
        flushCount += 1
        await rendererSink.flush(removingDisplayedImage: false)
        guard !isClosed else { return }
        isResetting = false
        recordRendererState(at: currentTime())
        startVideoDelivery()
    }

    func recordMediaErrorEvent() {
        sourceEventSequence += 1
        debugStore.recordMediaEvent(MediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .error,
            providerProvenance: provider.info.providerKind
        ))
    }

    func resetEndState(requiresAudio: Bool) {
        endStateLock.withLock {
            endState = EndState()
            endState.requiresAudio = requiresAudio
            endState.audioProviderEnded = !requiresAudio
        }
    }

    func resetVideoEndState() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.videoProviderEnded = false
            endState.maximumVideoPresentationTime = nil
            endState.videoPresentationEnd = nil
            endState.didReportEnd = false
        }
    }

    func resetAudioEndState(requiresAudio: Bool) {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.requiresAudio = requiresAudio
            endState.audioProviderEnded = !requiresAudio
            endState.audioPresentationEnd = nil
            endState.didReportEnd = false
        }
    }

    func closeEndState() {
        endStateLock.withLock {
            endState = EndState()
            endState.isClosed = true
        }
    }

    func recordVideoPresentation(
        presentationTime: CMTime,
        presentationEnd: CMTime
    ) {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            if presentationTime.isNumeric,
               endState.maximumVideoPresentationTime.map({
                   CMTimeCompare($0, presentationTime) < 0
               }) ?? true {
                endState.maximumVideoPresentationTime = presentationTime
            }
            if presentationEnd.isNumeric,
               endState.videoPresentationEnd.map({
                   CMTimeCompare($0, presentationEnd) < 0
               }) ?? true {
                endState.videoPresentationEnd = presentationEnd
            }
        }
    }

    func targetEpochEndedBeforeVideoPresentation(_ targetSeconds: Double) -> Bool {
        endStateLock.withLock {
            guard endState.videoProviderEnded else { return false }
            guard let presentationEnd = endState.videoPresentationEnd,
                  presentationEnd.isNumeric else { return true }
            return presentationEnd.seconds < targetSeconds
        }
    }

    func recordAudioPresentationEnd(_ presentationEnd: CMTime) {
        guard presentationEnd.isNumeric else { return }
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            if let current = endState.audioPresentationEnd,
               CMTimeCompare(current, presentationEnd) >= 0 {
                return
            }
            endState.audioPresentationEnd = presentationEnd
        }
    }

    func markVideoProviderEnded() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.videoProviderEnded = true
        }
    }

    func markAudioProviderEnded() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.audioProviderEnded = true
        }
    }

    var videoProviderHasEnded: Bool {
        endStateLock.withLock { endState.videoProviderEnded }
    }

    func claimEndIfReady(at time: CMTime) -> Bool {
        guard time.isNumeric else { return false }
        return endStateLock.withLock {
            guard !endState.isClosed,
                  !endState.didReportEnd,
                  endState.videoProviderEnded,
                  !endState.requiresAudio || endState.audioProviderEnded,
                  var presentationEnd = endState.videoPresentationEnd else {
                return false
            }
            if endState.requiresAudio,
               let audioPresentationEnd = endState.audioPresentationEnd,
               CMTimeCompare(audioPresentationEnd, presentationEnd) > 0 {
                presentationEnd = audioPresentationEnd
            }
            guard CMTimeCompare(time, presentationEnd) >= 0 else { return false }
            endState.didReportEnd = true
            return true
        }
    }

}
