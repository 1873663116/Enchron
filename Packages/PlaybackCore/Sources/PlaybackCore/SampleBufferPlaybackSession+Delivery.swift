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

        hush()
        interruptSourceReadsForClose()
        stopRendererFailureMonitoring()
        cancelFirstVideoFrameDeadline()
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
        resetAudioSpectrum()
        discardPendingVideoSample()
        deliveryQueue.sync {
            isClosed = true
            provider.cancel()
            debugStore.recordCleanupStep(.videoProviderCancelled)
        }
        audioDeliveryQueue.sync {
            audioProvider.cancel()
            debugStore.recordCleanupStep(.audioProviderCancelled)
        }
        PlaybackTrace.event("session.close.queuesSynced id=\(traceID)")
        subtitleStateLock.withLock {
            subtitleState.selectionGeneration &+= 1
            subtitleState.streamEpoch &+= 1
            subtitleState.availableTracks = []
            subtitleState.sourceURLByTrackID = [:]
            subtitleState.externalSourceIDByTrackID = [:]
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
            discardVideoFramesInFlight()
            finishCloseAfterFlush()
        }
    }

    func hush() {
        setTimelineStopped(reason: .close)
    }

    func interruptSourceReadsForClose() {
        demuxSession?.interrupt()
        sourceReadMeter?.interruptReads()
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
        guard mediaKind == .video else { return }
        videoDeliveryStartHostSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let start = deliveryTaskLock.withLock { () -> (UInt64, Task<Void, Never>?)? in
            guard videoSampleDeliverySuspended == false else { return nil }
            videoDeliveryGeneration &+= 1
            let previousTask = videoDeliveryTask
            videoDeliveryTask = nil
            return (videoDeliveryGeneration, previousTask)
        }
        guard let (generation, previousTask) = start else { return }
        rendererSink.stopRenderingEventObservation()
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

    func stopVideoDelivery(caller: String = #function) {
        let task = deliveryTaskLock.withLock {
            videoDeliveryGeneration &+= 1
            let task = videoDeliveryTask
            videoDeliveryTask = nil
            return task
        }
        PlaybackTrace.event("session.videoDelivery.stop id=\(traceID) by=\(caller) hadTask=\(task != nil)")
        task?.cancel()
    }

    var videoSampleDeliveryIsSuspended: Bool {
        deliveryTaskLock.withLock { videoSampleDeliverySuspended }
    }

    func suspendVideoSampleDelivery(flushingRenderer: Bool = false, caller: String = #function) async {
        PlaybackTrace.event("session.videoDelivery.suspend id=\(traceID) by=\(caller) flush=\(flushingRenderer)")
        cancelFirstVideoFrameDeadline()
        let task = deliveryTaskLock.withLock {
            videoSampleDeliverySuspended = true
            videoDeliveryGeneration &+= 1
            let task = videoDeliveryTask
            videoDeliveryTask = nil
            return task
        }
        invalidateTimelineProgressRecovery()
        task?.cancel()
        await task?.value
        if flushingRenderer {
            await rendererSink.flush(removingDisplayedImage: false)
            discardVideoFramesInFlight()
            flushCount += 1
            recordRendererState(at: currentTime())
        }
    }

    func allowVideoSampleDeliveryRestart() {
        cancelFirstVideoFrameDeadline()
        deliveryTaskLock.withLock {
            videoSampleDeliverySuspended = false
        }
    }

    func resumeVideoSampleDelivery() {
        let wasSuspended = deliveryTaskLock.withLock {
            let wasSuspended = videoSampleDeliverySuspended
            videoSampleDeliverySuspended = false
            return wasSuspended
        }
        guard wasSuspended else { return }
        if mediaSessionRecord?.lifecycle == .playing {
            armTimelineProgressRecoveryForCurrentMapping()
        }
        let canResume = deliveryQueue.sync {
            hasRequestedVideoData
                && !videoProviderHasEnded
                && !isClosed
                && !isResetting
                && !isVideoRendererFailed
        }
        if canResume {
            startVideoDelivery()
        }
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

    func suspendAudioSampleDelivery() async {
        let task = deliveryTaskLock.withLock {
            let task = audioDeliveryTask
            audioDeliveryTask = nil
            return task
        }
        task?.cancel()
        await task?.value
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
                                "sampleOrdinal": String(sampleOrdinal)
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
                    publishFailureStatus(
                        error,
                        context: .sourceRead(
                            (error as? PlaybackProviderError)?.activeFailureCause
                        )
                    )
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

            #if os(visionOS)
                beginDeliveryLagRecoveryIfNeeded(
                    presentationEnd: presentationEnd,
                    generation: generation
                )
            #endif

            let formatSignaledSample: CMSampleBuffer
            do {
                if stereoLayoutOverride != nil || projectionOverride != nil
                    || dynamicRangeOverride != nil {
                    formatSignaledSample = try videoSampleFormatOverride.rewrite(
                        sourceSample,
                        stereoLayout: stereoLayoutOverride,
                        projection: projectionOverride,
                        dynamicRange: dynamicRangeOverride
                    )
                } else {
                    formatSignaledSample = sourceSample
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
                formatSignaledSample,
                presentationTime: presentationTime,
                presentationEnd: presentationEnd
            )
            let renderSample = videoSampleFormatOverride.taggedPresentationSample(
                formatSignaledSample,
                stereoLayout: stereoLayoutOverride,
                projection: projectionOverride
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
                setTimelineStopped(
                    at: timelineStart,
                    reason: .initialTimelineAnchor
                )
                hasStartedTimeline = true
                isPrerolling = true
                recordTimelineControlState()
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
                dumpVideoSampleIfRequested(formatSignaledSample)
            }
            let decodeTime = CMSampleBufferGetDecodeTimeStamp(formatSignaledSample)
            let decoderBootstrapTarget = targetTimelineTime(fallback: presentationTime)
            let requiresImmediateDecoderBootstrap =
                !decoderBootstrapLock.withLock { decoderBootstrapComplete }
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
                            "sampleOrdinal": String(sampleOrdinal)
                        ]
                    )
                }
                emitPlaybackDeliveryStage(
                    lane: "video",
                    stage: "boundedLead.enter",
                    epoch: streamEpoch,
                    sampleOrdinal: sampleOrdinal,
                    presentationTime: presentationTime,
                    decodeTime: decodeTime
                )
                try await waitForBoundedVideoLead(presentationTime: presentationTime)
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
                if outcome != .cancelledByFlush, isCurrentVideoDelivery(generation) {
                    recordVideoFrameInFlight(presentationEnd: presentationEnd)
                    recordVideoEnqueueLead(presentationTime: presentationTime)
                }
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
                if sampleOrdinal <= 8 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "videoRenderer.enqueue.completed",
                        outcome: .succeeded,
                        details: [
                            "result": String(describing: outcome),
                            "sampleOrdinal": String(sampleOrdinal)
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
            recordPausedSeekCoverageCandidate(presentationTime)
            let bootstrap = recordAcceptedDecoderBootstrapSample(
                decodeTime: decodeTime,
                target: decoderBootstrapTarget,
                usedImmediateEnqueue: requiresImmediateDecoderBootstrap
            )
            let requiredPreroll = prerollRequirementLock.withLock {
                prerollRequirement
            }
            let requiredVideoEnd = requiredPreroll?.videoEnd
                ?? requestedTimelineStart
            let targetReached = requiredVideoEnd.isNumeric == false
                || presentationTime >= requiredVideoEnd
                || presentationEnd >= requiredVideoEnd
            let isPausedSeekPreroll = isPrerolling
                && timelineStartRate == 0
                && pausedSeekAwaitsCoverage
            if isPausedSeekPreroll {
                if pausedSeekCoverageIsSettled(
                    target: targetTimelineTime(fallback: presentationTime)
                ) {
                    activatePausedSeekTimeline(
                        fallback: presentationTime,
                        capturedVideoDeliveryGeneration: generation
                    )
                }
            } else if isPrerolling, timelineStartRate > 0, bootstrap.complete, targetReached {
                if synchronizer.rate == timelineStartRate {
                    isPrerolling = false
                    clearPrerollRequirement()
                    recordTimelineControlState()
                    publishTargetTimelineState(
                        at: targetTimelineTime(fallback: presentationTime)
                    )
                    publishDiagnostics(
                        at: targetTimelineTime(fallback: presentationTime),
                        force: true
                    )
                    PlaybackTrace.event(
                        "session.timeline.activated id=\(traceID) rate=\(timelineStartRate) " +
                        "bootstrapComplete=true alreadyRunning=true"
                    )
                } else {
                let activationTime = pausedTimelineActivationTime(
                    target: targetTimelineTime(fallback: presentationTime),
                    firstDisplayablePresentationTime: presentationTime
                )
                do {
                    let audioRequirement = requiredPreroll
                        ?? PlaybackBufferingPolicy.seekRequirement(
                            target: activationTime,
                            durationSeconds: diagnostics.durationSeconds
                        )
                    try await waitForAudioPreroll(
                        through: audioRequirement.audioEnd,
                        after: audioRequirement.timelineStart
                    )
                } catch {
                    guard isCurrentVideoDelivery(generation), !isClosed else { return }
                    guard !(error is CancellationError), !Task.isCancelled else { return }
                    retireAudio(
                        after: error,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.prerollFailed.videoContinues"
                    )
                }
                let activationSequence = activationObservation.beginActivation(
                    requestedRate: timelineStartRate,
                    anchorTime: activationTime
                )
                setTimelineStopped(
                    at: activationTime,
                    reason: .decoderBootstrapPreActivation,
                    capturedVideoDeliveryGeneration: generation
                )
                setRateAtHostTime(
                    timelineStartRate,
                    time: activationTime,
                    reason: .decoderBootstrap,
                    capturedVideoDeliveryGeneration: generation
                )
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
                clearPrerollRequirement()
                recordTimelineControlState()
                publishTargetTimelineState(at: activationTime)
                publishDiagnostics(at: activationTime, force: true)
                PlaybackTrace.event(
                    "session.timeline.activated id=\(traceID) rate=\(timelineStartRate) " +
                    "bootstrapComplete=true immediateSamples=\(bootstrap.immediateEnqueueCount)"
                )
                }
            } else if shouldAnchorTimeline, !isPrerolling {
                let activationTime = targetTimelineTime(fallback: presentationTime)
                let activationSequence = activationObservation.beginActivation(
                    requestedRate: timelineStartRate,
                    anchorTime: activationTime
                )
                setRateAtHostTime(
                    timelineStartRate,
                    time: activationTime,
                    reason: .firstSample,
                    capturedVideoDeliveryGeneration: generation
                )
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
            let sourceEventID = recordVideoSample(formatSignaledSample)
            updateCompressedDiagnostics(sample: formatSignaledSample)
            lastSourceEventID = sourceEventID
            diagnostics.enqueuedSampleCount += 1
            #if DEBUG
                recordPlaybackSwitchRendererSample(
                    trigger: diagnostics.enqueuedSampleCount == 1
                        ? .firstInputAccepted
                        : .inputAccepted,
                    observesDisplayProgress: true
                )
            #endif
            let rendererRecord = RendererInputRecord(
                mediaSessionID: traceID,
                sourceEventID: lastSourceEventID,
                videoTrackID: videoTrackID,
                streamEpoch: streamEpoch,
                formatRevision: formatRevision,
                graphRevision: graphRevision,
                inputKind: .compressed,
                timelineConfiguredBeforeFirstEnqueue: hasStartedTimeline,
                action: "enqueue",
                outcome: .accepted,
                formatSignaling: rendererInputFormatSignalingSummary(for: renderSample)
            )
            debugStore.recordRendererInput(rendererRecord)
            if let signaling = rendererRecord.formatSignaling {
                let rendererInputIsMultiview =
                    signaling.hasLeftStereoEyeView.value == true
                    && signaling.hasRightStereoEyeView.value == true
                if diagnostics.rendererInputIsMultiview != rendererInputIsMultiview {
                    diagnostics.rendererInputIsMultiview = rendererInputIsMultiview
                    onDiagnosticsChange?(diagnostics)
                }
            }
            recordVideoPresentation(
                presentationTime: presentationTime,
                presentationEnd: presentationEnd
            )
            if lastPublishedAcceptedVideoFormatRevision != rendererRecord.formatRevision {
                lastPublishedAcceptedVideoFormatRevision = rendererRecord.formatRevision
                onAcceptedVideoFormatRevisionChange?(rendererRecord.formatRevision)
            }
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
                        "sourceEventID": lastSourceEventID
                    ]
                )
                PlaybackTrace.event(
                    "session.firstEnqueue id=\(traceID) rendererStatus=\(currentVideoRendererStatus) " +
                    "rendererError=\(currentVideoRendererError ?? "none")"
                )
            }
        }
    }

    func beginDeliveryLagRecoveryIfNeeded(
        presentationEnd: CMTime,
        generation: UInt64
    ) {
        guard presentationEnd.isNumeric,
              diagnostics.nominalFrameRate > 0,
              timelineStartRate > 0,
              !isPrerolling,
              activeOperation == nil,
              mediaSessionRecord?.lifecycle == .playing,
              isCurrentVideoDelivery(generation) else {
            return
        }
        let timelineTime = timelineClockReading().mediaTime
        guard timelineTime.isNumeric,
              timelineTime.seconds - presentationEnd.seconds >=
                PlaybackBufferingPolicy.deliveryLagRecoveryTriggerSeconds else {
            return
        }

        let requirement = PlaybackBufferingPolicy.deliveryLagRecoveryRequirement(
            timelineTime: timelineTime,
            durationSeconds: diagnostics.durationSeconds,
            leadFrames: videoLeadFrames,
            nominalFrameRate: diagnostics.nominalFrameRate
        )
        requestedTimelineStart = timelineTime
        isPrerolling = true
        prerollRequirementLock.withLock {
            prerollRequirement = requirement
        }
        let stoppedRun = timelineProgressRecoveryLock.withLock {
            timelineProgressRecovery.currentRun
        }
        setTimelineStopped(
            at: timelineTime,
            reason: .deliveryLagRecovery,
            capturedVideoDeliveryGeneration: generation
        )
        recordTimelineControlState()
        let mediaState = deliveryContinuityMediaState()
        let lagObservation = timelineProgressRecoveryLock.withLock {
            deliveryContinuity.observeDeliveryLag(
                frozenMediaTime: timelineTime,
                mediaState: mediaState,
                rateApplicationGeneration: stoppedRun?.generation ?? 0,
                videoStreamEpoch: streamEpoch,
                audioStreamEpoch: audioStreamEpoch,
                requestedRate: timelineStartRate
            )
        }
        if let lagObservation {
            publishDeliveryContinuity(lagObservation)
        }
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timeline.deliveryLagRecovery.started",
            outcome: .succeeded,
            details: [
                "lagSeconds": String(timelineTime.seconds - presentationEnd.seconds),
                "recoveryLeadSeconds": String(
                    requirement.videoEnd.seconds - timelineTime.seconds
                ),
                "requiredAudioEndSeconds": String(requirement.audioEnd.seconds),
                "requiredVideoEndSeconds": String(requirement.videoEnd.seconds),
                "timelineSeconds": String(timelineTime.seconds)
            ]
        )
        publishTargetTimelineState(at: timelineTime)
        publishDiagnostics(at: timelineTime, force: true)
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
                let nextSample: CMSampleBuffer?
                do {
                    nextSample = try await audioProvider.copyNextSample()
                } catch {
                    guard !Task.isCancelled, !isClosed else { return }
                    if mediaKind == .audioOnly {
                        recordFailure(
                            error,
                            node: .mediaEventStream,
                            kind: "audioProvider.readFailed"
                        )
                        publishFailureStatus(
                            error,
                            context: .sourceRead(
                                (error as? PlaybackProviderError)?.activeFailureCause
                            )
                        )
                        return
                    }
                    retireAudio(
                        after: error,
                        node: .mediaEventStream,
                        kind: "audioProvider.readFailed.videoContinues"
                    )
                    return
                }
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
                            "sampleOrdinal": String(sampleOrdinal)
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
                let shouldAnchorAudioTimeline = mediaKind == .audioOnly && !hasStartedTimeline
                if shouldAnchorAudioTimeline {
                    let timelineStart = targetTimelineTime(fallback: presentationTime)
                    setTimelineStopped(at: timelineStart, reason: .initialTimelineAnchor)
                    hasStartedTimeline = true
                    recordTimelineControlState()
                    publishDiagnostics(at: timelineStart, force: true)
                }
                let audioInfo = audioProvider.info
                let rawStreamIndex = audioInfo?.streamIndex
                    ?? selectedAudioStreamIndex
                    ?? -1
                let trackID = rawStreamIndex >= 0
                    ? "\(traceID).audio.\(rawStreamIndex)"
                    : "\(traceID).audio.unknown"
                if mediaKind == .audioOnly {
                    audioSpectrumAnalyzer.submit(
                        sample,
                        presentationTime: presentationTime
                    ) { [weak self] frame in
                        self?.enqueueAudioSpectrumFrame(frame)
                    }
                }
                let timestampObservation = recordAudioDeliveryPresentationTime(
                    presentationTime
                )
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
                    payloadOwnershipState: "retainedCMSampleBuffer",
                    deliveryObservation: audioDeliveryObservation(
                        for: sample,
                        providerInfo: audioInfo,
                        timestampsMonotonic: timestampObservation.monotonic,
                        timestampObservationCount: timestampObservation.count
                    )
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
                emitPlaybackDeliveryStage(
                    lane: "audio",
                    stage: "boundedLead.enter",
                    epoch: audioStreamEpoch,
                    sampleOrdinal: sampleOrdinal,
                    presentationTime: presentationTime,
                    decodeTime: decodeTime
                )
                try await waitForBoundedAudioLead(presentationTime: presentationTime)
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
                if sampleOrdinal <= 64 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.enqueue.completed",
                        outcome: .succeeded,
                        details: [
                            "result": String(describing: outcome),
                            "sampleOrdinal": String(sampleOrdinal)
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
                if shouldAnchorAudioTimeline {
                    let activationTime = targetTimelineTime(fallback: presentationTime)
                    if timelineStartRate > 0 {
                        setRateAtHostTime(
                            timelineStartRate,
                            time: activationTime,
                            reason: .firstSample
                        )
                        recordAudioRateActivation(
                            rate: timelineStartRate,
                            time: activationTime,
                            reason: "firstAudioSample"
                        )
                    }
                    publishTargetTimelineState(at: activationTime)
                    publishDiagnostics(at: activationTime, force: true)
                }
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
                if mediaKind == .audioOnly {
                    recordFailure(
                        error,
                        node: .rendererInputCoordination,
                        kind: "audioRenderer.deliveryFailed"
                    )
                    onStatusChange?(.failed(error.localizedDescription))
                    return
                }
                retireAudio(
                    after: error,
                    node: .rendererInputCoordination,
                    kind: "audioRenderer.deliveryFailed.videoContinues"
                )
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

    func recordVideoEnqueueLead(presentationTime: CMTime) {
        let hostSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        if let last = lastVideoEnqueueHostSeconds {
            let gap = hostSeconds - last
            videoEnqueueGapWindowMaxSeconds = max(videoEnqueueGapWindowMaxSeconds ?? 0, gap)
        }
        lastVideoEnqueueHostSeconds = hostSeconds
        let reading = timelineClockReading()
        guard presentationTime.isNumeric, reading.mediaTime.isNumeric, reading.directRate > 0 else { return }
        let lead = presentationTime.seconds - reading.mediaTime.seconds
        videoEnqueueLeadWindowMinSeconds = min(videoEnqueueLeadWindowMinSeconds ?? lead, lead)
        diagnostics.videoEnqueueLeadLastSeconds = lead
        if lead < 0 {
            lateVideoEnqueueCount &+= 1
        }
    }

    var videoLeadFrames: Int {
        let elapsed = videoDeliveryStartHostSeconds.map {
            CMClockGetTime(CMClockGetHostTimeClock()).seconds - $0
        }
        return RendererLeadBudget.frames(
            reorderDepth: diagnostics.videoReorderDepth,
            isRemoteSource: sourceIsRemote,
            secondsSinceDeliveryStart: elapsed,
            memoryPressure: MemoryPressureMonitor.shared.current
        )
    }

    func recordVideoFrameInFlight(presentationEnd: CMTime) {
        guard presentationEnd.isNumeric else { return }
        videoFramesInFlightLock.withLock {
            videoFramesInFlight.record(presentationEnd: presentationEnd.seconds)
        }
    }

    func discardVideoFramesInFlight() {
        videoFramesInFlightLock.withLock { videoFramesInFlight.removeAll() }
    }

    func waitForBoundedVideoLead(presentationTime: CMTime) async throws {
        guard presentationTime.isNumeric else { return }
        while true {
            try Task.checkCancellation()
            guard !isClosed, !isResetting else { throw CancellationError() }
            let budget = videoLeadFrames
            let reading = timelineClockReading()
            let reference = leadReferenceSeconds(reading)
            let (framesInFlight, earliestRetirement) = videoFramesInFlightLock.withLock {
                (
                    videoFramesInFlight.count(timelineSeconds: reference),
                    videoFramesInFlight.earliestRetirement()
                )
            }
            let isBlocked = framesInFlight >= budget
                || (timelineProgressRecoveryIsEligible && reading.directRate == 0)
            observeLeadDecision(
                lane: .video,
                isBlocked: isBlocked,
                presentationTime: presentationTime,
                reading: reading
            )
            if !isBlocked { return }
            try await Task.sleep(for: leadRetryDelay(
                until: earliestRetirement,
                from: reference,
                rate: reading.directRate
            ))
        }
    }

    func waitForBoundedAudioLead(presentationTime: CMTime) async throws {
        guard presentationTime.isNumeric else { return }
        while true {
            try Task.checkCancellation()
            guard !isClosed, !isResetting else { throw CancellationError() }
            let reading = timelineClockReading()
            let reference = leadReferenceSeconds(reading)
            let isBlocked = presentationTime.seconds
                > reference + PlaybackBufferingPolicy.opportunisticAudioMaximumLeadSeconds
                || (timelineProgressRecoveryIsEligible && reading.directRate == 0)
            observeLeadDecision(
                lane: .audio,
                isBlocked: isBlocked,
                presentationTime: presentationTime,
                reading: reading
            )
            if !isBlocked { return }
            try await Task.sleep(for: leadRetryDelay(
                until: presentationTime.seconds
                    - PlaybackBufferingPolicy.opportunisticAudioMaximumLeadSeconds,
                from: reference,
                rate: reading.directRate
            ))
        }
    }

    private func leadReferenceSeconds(_ reading: PlaybackTimelineClockReading) -> Double {
        let current = reading.mediaTime
        let target = targetTimelineTime(fallback: current)
        return max(
            current.isNumeric ? current.seconds : 0,
            target.isNumeric ? target.seconds : 0
        )
    }

    private func leadRetryDelay(
        until openSeconds: Double?,
        from referenceSeconds: Double,
        rate: Double
    ) -> Duration {
        guard let openSeconds, openSeconds.isFinite, rate > 0 else {
            return Self.stoppedTimelineLeadRetryDelay
        }
        let hostSeconds = (openSeconds - referenceSeconds) / rate
        guard hostSeconds.isFinite, hostSeconds > 0 else {
            return Self.minimumLeadRetryDelay
        }
        return max(
            Self.minimumLeadRetryDelay,
            min(Self.stoppedTimelineLeadRetryDelay, .seconds(hostSeconds))
        )
    }

    private static let minimumLeadRetryDelay = Duration.milliseconds(1)
    private static let stoppedTimelineLeadRetryDelay = Duration.milliseconds(20)

    private func observeLeadDecision(
        lane: PlaybackDeliveryLane,
        isBlocked: Bool,
        presentationTime: CMTime,
        reading: PlaybackTimelineClockReading
    ) {
        let mediaState = deliveryContinuityMediaState()
        let result: (
            decision: PlaybackTimelineProgressDecision,
            continuity: PlaybackDeliveryContinuityObservation?
        ) = timelineProgressRecoveryLock.withLock {
            if !isBlocked {
                let decision = timelineProgressRecovery.observeProgress(reading)
                let continuity = timelineProgressRecovery.currentRun.flatMap { run in
                    deliveryContinuity.observeProgress(
                        run: run,
                        reading: reading,
                        mediaState: mediaState
                    )
                }
                return (decision, continuity)
            }
            guard timelineProgressRecoveryIsEligible,
                  timelineProgressRecovery.matches(
                    videoStreamEpoch: streamEpoch,
                    audioStreamEpoch: audioStreamEpoch,
                    requestedRate: timelineStartRate
                  ) else {
                return (.none, nil)
            }
            let decision = timelineProgressRecovery.observeBlockedLane(
                lane,
                blockedPresentationTime: presentationTime,
                reading: reading,
                requiredLanes: timelineProgressRequiredLanes
            )
            let continuity = timelineProgressRecovery.currentRun.flatMap { run in
                deliveryContinuity.observeProgress(
                    run: run,
                    reading: reading,
                    mediaState: mediaState
                )
            }
            return (decision, continuity)
        }
        if let continuity = result.continuity {
            publishDeliveryContinuity(continuity)
        }
        handleTimelineProgressDecision(result.decision)
    }

    var timelineProgressRequiredLanes: Set<PlaybackDeliveryLane> {
        let requiresActiveAudio = endStateLock.withLock {
            endState.requiresAudio && !endState.audioProviderEnded
        }
        return requiresActiveAudio ? [.video, .audio] : [.video]
    }

    var timelineProgressRecoveryIsEligible: Bool {
        !isClosed
            && !isResetting
            && !isCloseInProgress
            && !isPrerolling
            && !videoSampleDeliveryIsSuspended
            && mediaSessionRecord?.lifecycle == .playing
            && timelineStartRate > 0
    }

    var timelineProgressWatchdogIsEligible: Bool {
        timelineProgressHostWatchdogIsEligible(
            isClosed: isClosed,
            isResetting: isResetting,
            isCloseInProgress: isCloseInProgress,
            deliveryPrerollIsPending: isPrerolling,
            videoSampleDeliveryIsSuspended: videoSampleDeliveryIsSuspended,
            lifecycleIsPlaying: mediaSessionRecord?.lifecycle == .playing,
            timelineStartRate: timelineStartRate,
            hasActiveOperation: activeOperation != nil
        )
    }

    func receiveTimelineProgressWatchdogTick(run: PlaybackTimelineProgressRun) {
        let reading = timelineClockReading()
        let mediaState = deliveryContinuityMediaState()
        PlaybackTrace.event(
            "session.watchdog.tick id=\(traceID) time=\(reading.mediaTime.seconds)"
                + " rate=\(reading.effectiveRate) eligible=\(timelineProgressWatchdogIsEligible)"
                + " activeOperation=\(activeOperation.map { String(describing: $0) } ?? "none")"
                + " suspended=\(videoSampleDeliveryIsSuspended)"
                + " lifecycle=\(mediaSessionRecord?.lifecycle.rawValue ?? "none")"
                + " startRate=\(timelineStartRate)"
        )
        let result: (
            decision: PlaybackTimelineProgressDecision,
            continuity: PlaybackDeliveryContinuityObservation?
        ) = timelineProgressRecoveryLock.withLock {
            guard timelineProgressWatchdogIsEligible,
                  timelineProgressRecovery.matches(run) else {
                return (.none, nil)
            }
            let decision = timelineProgressRecovery.observeHostWatchdog(
                run: run,
                reading: reading
            )
            let continuity = deliveryContinuity.observeProgress(
                run: run,
                reading: reading,
                mediaState: mediaState
            )
            return (decision, continuity)
        }
        if let continuity = result.continuity {
            publishDeliveryContinuity(continuity)
        }
        handleTimelineProgressDecision(result.decision)
    }

    func timelineClockReading() -> PlaybackTimelineClockReading {
        var mediaTime = CMTime.invalid
        var directRate = Float64.nan
        _ = CMTimebaseGetTimeAndRate(
            synchronizer.timebase,
            timeOut: &mediaTime,
            rateOut: &directRate
        )
        let source = CMTimebaseCopySource(synchronizer.timebase)
        let ultimateSource = CMTimebaseCopyUltimateSourceClock(synchronizer.timebase)
        return PlaybackTimelineClockReading(
            mediaTime: mediaTime,
            sourceTime: CMSyncGetTime(source),
            ultimateSourceTime: CMClockGetTime(ultimateSource),
            directRate: directRate,
            effectiveRate: CMTimebaseGetEffectiveRate(synchronizer.timebase)
        )
    }

    func handleTimelineProgressDecision(_ decision: PlaybackTimelineProgressDecision) {
        switch decision {
        case .none:
            return
        case .reanchor(let incident):
            let result = timelineProgressRecoveryLock.withLock { () -> (
                PlaybackTimelineProgressIncident,
                PlaybackTimelineClockReading,
                PlaybackDeliveryContinuityObservation?
            )? in
                guard timelineProgressDecisionIsEligible(
                        incident: incident,
                        blockedLaneIsEligible: timelineProgressRecoveryIsEligible,
                        hostWatchdogIsEligible: timelineProgressWatchdogIsEligible
                      ),
                      timelineProgressRecovery.matches(incident.run) else {
                    timelineProgressRecovery.cancelClaim(incident)
                    return nil
                }
                let fresh = timelineClockReading()
                guard CMTimeCompare(fresh.mediaTime, incident.frozenMediaTime) == 0 else {
                    timelineProgressRecovery.cancelClaim(incident)
                    return nil
                }
                let hostTime = playbackActivationHostTime()
                let activationSequence = debugStore.beginTimelineRateActivation(
                    reason: .timelineProgressRecovery,
                    mediaTimeSeconds: numericSeconds(incident.frozenMediaTime),
                    hostTimeSeconds: numericSeconds(hostTime),
                    currentVideoDeliveryGeneration: videoDeliveryGeneration,
                    capturedVideoDeliveryGeneration: nil,
                    currentState: timelineControlStateRecord()
                )
                synchronizer.setRate(
                    incident.run.requestedRate,
                    time: incident.frozenMediaTime,
                    atHostTime: hostTime
                )
                debugStore.recordTimelineRateActivationReturned(
                    sequence: activationSequence
                )
                guard let applied = timelineProgressRecovery.didApplyReanchor(
                    incident,
                    at: hostTime
                ) else { return nil }
                let continuity = deliveryContinuity.observeIncident(
                    applied,
                    mediaState: deliveryContinuityMediaState()
                )
                return (applied, fresh, continuity)
            }
            guard let result else { return }
            if let continuity = result.2 {
                publishDeliveryContinuity(continuity)
            }
            recordTimelineProgressRecovery(
                outcome: .stalled,
                incident: result.0,
                postReading: result.1
            )
            recordTimelineProgressRecovery(
                outcome: .reanchorApplied,
                incident: result.0,
                postReading: result.1
            )
        case .resumed(let incident, let reading):
            recordTimelineProgressRecovery(
                outcome: .resumed,
                incident: incident,
                postReading: reading
            )
        case .notResumed(let incident, let reading):
            recordTimelineProgressRecovery(
                outcome: .notResumed,
                incident: incident,
                postReading: reading
            )
        }
    }

    func recordTimelineProgressRecovery(
        outcome: PlaybackTimelineProgressRecoveryOutcome,
        incident: PlaybackTimelineProgressIncident,
        postReading: PlaybackTimelineClockReading
    ) {
        let mediaState = deliveryContinuityMediaState()
        let ends = mediaState.presentationEndByLane
            .map { "\($0.key.rawValue)=\($0.value.seconds)" }
            .sorted()
            .joined(separator: ",")
        PlaybackTrace.event(
            "session.timelineProgress outcome=\(outcome) incident=\(incident.incidentID)"
                + " frozen=\(incident.frozenMediaTime.seconds)"
                + " post=\(postReading.mediaTime.seconds) rate=\(postReading.effectiveRate)"
                + " required=\(mediaState.requiredLanes.map(\.rawValue).sorted())"
                + " ended=\(mediaState.providerEndedLanes.map(\.rawValue).sorted())"
                + " ends=\(ends)"
        )
        let detectionSource: PlaybackTimelineProgressDetectionSource
        let lanes: [PlaybackDeliveryLane]
        let firstReading: PlaybackTimelineClockReading
        let detectedReading: PlaybackTimelineClockReading
        let watchdogCause: PlaybackTimelineHostWatchdogCause?
        let watchdogConsecutiveObservationCount: Int?
        switch incident.evidence {
        case .blockedLanes(let frozenByLane):
            lanes = frozenByLane.keys.sorted { $0.rawValue < $1.rawValue }
            let laneEvidence = lanes.compactMap { frozenByLane[$0] }
            guard let firstEvidence = laneEvidence.first,
                  let lastEvidence = laneEvidence.last else { return }
            detectionSource = .blockedLanes
            firstReading = firstEvidence.previous
            detectedReading = lastEvidence.detected
            watchdogCause = nil
            watchdogConsecutiveObservationCount = nil
        case .hostWatchdog(let evidence):
            detectionSource = .hostWatchdog
            lanes = []
            firstReading = evidence.first
            detectedReading = evidence.detected
            watchdogCause = evidence.cause
            watchdogConsecutiveObservationCount = evidence.consecutiveObservationCount
        }
        let snapshot = debugStore.snapshot()
        let record = PlaybackTimelineProgressRecoveryRecord(
            incidentID: incident.incidentID,
            outcome: outcome,
            detectionSource: detectionSource,
            detectingLanes: lanes.map(\.rawValue),
            watchdogCause: watchdogCause,
            watchdogConsecutiveObservationCount: watchdogConsecutiveObservationCount,
            rateApplicationGeneration: incident.run.generation,
            videoStreamEpoch: incident.run.videoStreamEpoch,
            audioStreamEpoch: incident.run.audioStreamEpoch,
            requestedRate: incident.run.requestedRate,
            frozenMediaTimeSeconds: numericSeconds(incident.frozenMediaTime) ?? 0,
            previousUltimateSourceTimeSeconds:
                numericSeconds(firstReading.ultimateSourceTime) ?? 0,
            detectedUltimateSourceTimeSeconds:
                numericSeconds(detectedReading.ultimateSourceTime) ?? 0,
            sourceTimeSeconds: numericSeconds(detectedReading.sourceTime) ?? 0,
            directRate: detectedReading.directRate,
            effectiveRate: detectedReading.effectiveRate,
            reanchorHostTimeSeconds: incident.reanchorHostTime.flatMap(numericSeconds),
            postRecoveryMediaTimeSeconds: numericSeconds(postReading.mediaTime),
            postRecoveryUltimateSourceTimeSeconds:
                numericSeconds(postReading.ultimateSourceTime),
            attemptCount: 1,
            videoSampleCount: snapshot.sampleCount,
            acceptedRendererInputCount: snapshot.acceptedRendererInputCount,
            audioSampleBufferCount: snapshot.audioSampleBufferCount,
            displayedFrameObservationCount:
                snapshot.rendererState?.displayedFrameObservationCount,
            flushCount: flushCount
        )
        debugStore.recordTimelineProgressRecovery(record)
        let details: [String: String] = [
            "incidentID": "\(record.incidentID)",
            "detectionSource": record.detectionSource?.rawValue ?? "unknown",
            "lanes": record.detectingLanes.joined(separator: "+"),
            "watchdogCause": record.watchdogCause?.rawValue ?? "none",
            "watchdogConsecutiveObservationCount":
                record.watchdogConsecutiveObservationCount.map(String.init) ?? "none",
            "frozenMediaTimeSeconds": "\(record.frozenMediaTimeSeconds)",
            "previousUltimateSourceTimeSeconds":
                "\(record.previousUltimateSourceTimeSeconds)",
            "detectedUltimateSourceTimeSeconds":
                "\(record.detectedUltimateSourceTimeSeconds)",
            "reanchorHostTimeSeconds":
                record.reanchorHostTimeSeconds.map { "\($0)" } ?? "none",
            "postRecoveryMediaTimeSeconds":
                record.postRecoveryMediaTimeSeconds.map { "\($0)" } ?? "none",
            "directRate": "\(record.directRate)",
            "effectiveRate": "\(record.effectiveRate)",
            "flushCount": "\(record.flushCount)"
        ]
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timelineProgress.\(outcome.rawValue)",
            outcome: outcome == .notResumed ? .failed : .succeeded,
            details: details
        )
    }

    func deliveryContinuityMediaState() -> PlaybackDeliveryContinuityMediaState {
        endStateLock.withLock {
            let requiredLanes: Set<PlaybackDeliveryLane>
            if mediaKind == .audioOnly {
                requiredLanes = [.audio]
            } else if endState.requiresAudio && !endState.audioProviderEnded {
                requiredLanes = [.video, .audio]
            } else {
                requiredLanes = [.video]
            }
            var providerEndedLanes: Set<PlaybackDeliveryLane> = []
            if endState.videoProviderEnded {
                providerEndedLanes.insert(.video)
            }
            if endState.audioProviderEnded {
                providerEndedLanes.insert(.audio)
            }
            var presentationEndByLane: [PlaybackDeliveryLane: CMTime] = [:]
            presentationEndByLane[.video] = endState.videoPresentationEnd
            presentationEndByLane[.audio] = endState.audioPresentationEnd
            return PlaybackDeliveryContinuityMediaState(
                requiredLanes: requiredLanes,
                providerEndedLanes: providerEndedLanes,
                presentationEndByLane: presentationEndByLane
            )
        }
    }

    func observeDeliveryContinuityAfterMediaDelivery() {
        let isStarved = timelineProgressRecoveryLock.withLock {
            deliveryContinuity.isStarved
        }
        guard isStarved else { return }
        let mediaState = deliveryContinuityMediaState()
        let reading = timelineClockReading()
        let observation: PlaybackDeliveryContinuityObservation? =
            timelineProgressRecoveryLock.withLock {
            guard let run = timelineProgressRecovery.currentRun else { return nil }
            return deliveryContinuity.observeProgress(
                run: run,
                reading: reading,
                mediaState: mediaState
            )
        }
        if let observation {
            publishDeliveryContinuity(observation)
        }
    }

    func publishDeliveryContinuity(
        _ observation: PlaybackDeliveryContinuityObservation
    ) {
        debugStore.recordDeliveryContinuity(observation)
        let evidence = observation.evidence
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "deliveryContinuity.\(observation.phase.rawValue)",
            outcome: .succeeded,
            details: [
                "incidentID": evidence.map { String($0.incidentID) } ?? "none",
                "detectionSource": evidence?.detectionSource.rawValue ?? "none",
                "requiredLanes": evidence?.requiredLanes.joined(separator: "+") ?? "none",
                "rateApplicationGeneration": evidence.map {
                    String($0.rateApplicationGeneration)
                } ?? "none",
                "frozenMediaTimeSeconds": evidence.map {
                    String($0.frozenMediaTimeSeconds)
                } ?? "none",
                "recoveredMediaTimeSeconds": evidence?.recoveredMediaTimeSeconds.map {
                    String($0)
                } ?? "none"
            ]
        )
        onDeliveryContinuityChange?(observation)
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
                .map { String($0) } ?? "unavailable"
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

    func waitForAudioPreroll(
        through requiredEnd: CMTime,
        after timelineStart: CMTime
    ) async throws {
        guard hasAudio, requiredEnd.isNumeric, timelineStart.isNumeric else { return }
        let deadline = ContinuousClock.now + PlaybackBufferingPolicy.audioPrerollTimeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard !isClosed, !isResetting else { throw CancellationError() }
            guard hasAudio else { return }
            if audioHasPrerolled(through: requiredEnd, after: timelineStart) {
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
                        "requiredEndSeconds": String(requiredEnd.seconds),
                        "timelineStartSeconds": String(timelineStart.seconds),
                        "accumulatedPresentationEndSeconds": accumulatedPresentationEndSeconds,
                        "streamEpoch": String(audioStreamEpoch),
                        "rendererStatus": audioRendererStatusLabel,
                        "rendererError": audioRenderer.error?.localizedDescription
                            ?? currentAudioRendererError
                            ?? "none"
                    ]
                )
                return
            }
            if debugStore.snapshot().lifecycle == .failed {
                throw CorePlaybackError.audioPrerollTimedOut(requiredEnd.seconds)
            }
            try await Task.sleep(for: PlaybackBufferingPolicy.audioPrerollPollInterval)
        }
        throw CorePlaybackError.audioPrerollTimedOut(requiredEnd.seconds)
    }

    func retireAudio(
        after error: Error,
        node: PlaybackNode,
        kind: String,
        rendererFailure: RendererFailureFact? = nil
    ) {
        hasAudio = false
        resetAudioEndState(requiresAudio: false)
        stopAudioDelivery()
        audioRendererSink.stopRenderingEventObservation()
        audioProvider.cancel()
        audioRendererSink.flush()
        setAudioRendererError(error.localizedDescription)
        diagnostics.audioRetired = true
        diagnostics.audioRetirementReason = error.localizedDescription
        recordAudioRetirement(
            error,
            node: node,
            kind: kind,
            rendererFailure: rendererFailure
        )
        recordAudioRendererState()
        onDiagnosticsChange?(diagnostics)
    }

    // The subtitle counterpart of retireAudio: what subtitles cannot do is
    // never a reason for the video not to play. Reading the track list can
    // fail, the source can declare a track whose packets turn out to be
    // undecodable, a renderer can refuse to build - each of those loses the
    // subtitles and nothing else, and says so where the evidence is read.
    func retireSubtitles(
        after error: Error,
        node: PlaybackNode,
        kind: String
    ) {
        subtitleStateLock.withLock {
            subtitleState.selectionGeneration &+= 1
            subtitleState.streamEpoch &+= 1
            subtitleState.availableTracks = []
            subtitleState.sourceURLByTrackID = [:]
            subtitleState.externalSourceIDByTrackID = [:]
            subtitleState.selectedTrackID = nil
            subtitleState.cues = []
            subtitleState.frameRenderer = nil
            subtitleState.activeFrame = nil
        }
        diagnostics.subtitlesRetired = true
        diagnostics.subtitleRetirementReason = error.localizedDescription
        recordSubtitleRetirement(error, node: node, kind: kind)
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        onDiagnosticsChange?(diagnostics)
    }

    func resetFirstVideoFrameDeadline() {
        let task = firstVideoFrameLock.withLock {
            let task = firstVideoFrameDeadlineTask
            firstVideoFrameDeadlineTask = nil
            return task
        }
        task?.cancel()
    }

    func armFirstVideoFrameDeadline() {
        let deadline = firstVideoFrameDeadline
        let task = Task.detached { [weak self] in
            do {
                try await Task.sleep(for: deadline)
            } catch {
                return
            }
            self?.deliveryQueue.async { [weak self] in
                self?.failIfFirstVideoFrameIsStillMissing()
            }
        }
        let shouldCancel = firstVideoFrameLock.withLock {
            guard firstVideoFrameDeadlineTask == nil else {
                return true
            }
            firstVideoFrameDeadlineTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func cancelFirstVideoFrameDeadline() {
        let task = firstVideoFrameLock.withLock {
            let task = firstVideoFrameDeadlineTask
            firstVideoFrameDeadlineTask = nil
            return task
        }
        task?.cancel()
    }

    func failIfFirstVideoFrameIsStillMissing() {
        let shouldEvaluate = firstVideoFrameLock.withLock {
            guard firstVideoFrameDeadlineTask != nil else {
                return false
            }
            firstVideoFrameDeadlineTask = nil
            return true
        }
        guard shouldEvaluate, !isClosed else { return }
        let displayedFrame = firstVideoFrameObservation?()
            ?? (renderer.displayedPixelBuffer() != nil)
        guard displayedFrame == false else { return }
        provider.cancel()
        stopVideoDelivery()
        stopAudioDelivery()
        audioProvider.cancel()
        let components = firstVideoFrameDeadline.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let rendererError = renderer.error?.localizedDescription
            ?? currentVideoRendererError
        diagnostics.rendererFailedToDecode = rendererError != nil
        diagnostics.rendererStatus = currentVideoRendererStatus
        diagnostics.rendererError = rendererError ?? "none"
        onDiagnosticsChange?(diagnostics)
        let error = CorePlaybackError.firstVideoFrameTimedOut(
            seconds,
            rendererError: rendererError
        )
        recordFailure(
            error,
            node: .rendererInputCoordination,
            kind: "videoRenderer.firstFrameTimedOut"
        )
        onStatusChange?(.failed(error.localizedDescription))
    }

    func audioHasPrerolled(
        through requiredEnd: CMTime,
        after timelineStart: CMTime
    ) -> Bool {
        return endStateLock.withLock {
            guard let audioEnd = endState.audioPresentationEnd,
                  audioEnd.isNumeric else { return false }
            if CMTimeCompare(audioEnd, requiredEnd) >= 0 { return true }
            return endState.audioProviderEnded
                && CMTimeCompare(audioEnd, timelineStart) > 0
        }
    }

    func clearPrerollRequirement() {
        prerollRequirementLock.withLock {
            prerollRequirement = nil
        }
    }

    func audioSampleFormatDetails(_ sample: CMSampleBuffer) -> [String: String] {
        var details: [String: String] = [
            "sampleCount": String(CMSampleBufferGetNumSamples(sample)),
            "dataReady": String(CMSampleBufferDataIsReady(sample))
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

    func recordAudioDeliveryPresentationTime(
        _ presentationTime: CMTime
    ) -> (monotonic: Bool, count: UInt64) {
        audioDeliveryObservationLock.withLock {
            if audioDeliveryObservationEpoch != audioStreamEpoch {
                audioDeliveryObservationEpoch = audioStreamEpoch
                lastAudioDeliveryPresentationTime = nil
                audioDeliveryTimestampsMonotonic = true
                audioDeliveryTimestampObservationCount = 0
            }
            audioDeliveryTimestampObservationCount &+= 1
            if presentationTime.isNumeric {
                if let previous = lastAudioDeliveryPresentationTime,
                   CMTimeCompare(presentationTime, previous) <= 0 {
                    audioDeliveryTimestampsMonotonic = false
                }
                lastAudioDeliveryPresentationTime = presentationTime
            } else {
                audioDeliveryTimestampsMonotonic = false
            }
            return (
                audioDeliveryTimestampsMonotonic,
                audioDeliveryTimestampObservationCount
            )
        }
    }

    func audioDeliveryObservation(
        for sample: CMSampleBuffer,
        providerInfo: AudioSampleProviderInfo?,
        timestampsMonotonic: Bool,
        timestampObservationCount: UInt64
    ) -> AudioDeliveryObservation? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            return nil
        }
        let value = stream.pointee
        var channelLayoutSize = 0
        let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
            format,
            sizeOut: &channelLayoutSize
        )
        let isLinearPCM = value.mFormatID == kAudioFormatLinearPCM
        let ffmpegMetadata = CMGetAttachment(
            sample,
            key: "com.enchron.playbackcore.ffmpegAudioMetadata" as CFString,
            attachmentModeOut: nil
        ) as? [String: Any]
        func uint64Metadata(_ key: String) -> UInt64? {
            (ffmpegMetadata?[key] as? NSNumber)?.uint64Value
        }
        func uint32Metadata(_ key: String) -> UInt32? {
            (ffmpegMetadata?[key] as? NSNumber)?.uint32Value
        }
        return AudioDeliveryObservation(
            providerKind: providerInfo?.providerKind ?? "unknown",
            sourceCodecName: providerInfo?.codecName ?? "unknown",
            mediaSubtype: fourCC(CMFormatDescriptionGetMediaSubType(format)),
            formatID: fourCC(value.mFormatID),
            formatFlags: value.mFormatFlags,
            sourceSampleRate: providerInfo?.sampleRate ?? 0,
            deliveredSampleRate: value.mSampleRate,
            sourceChannelCount: providerInfo?.channelCount ?? 0,
            deliveredChannelCount: value.mChannelsPerFrame,
            bitsPerChannel: value.mBitsPerChannel,
            bytesPerFrame: value.mBytesPerFrame,
            framesPerPacket: value.mFramesPerPacket,
            isFloatPCM: isLinearPCM
                && value.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            isInterleaved: isLinearPCM
                ? value.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                : nil,
            channelLayoutTag: channelLayout.map {
                $0.pointee.mChannelLayoutTag
            },
            presentationTimestampsMonotonic: timestampsMonotonic,
            timestampObservationCount: timestampObservationCount,
            trueHDDecoderInputPacketCount: uint64Metadata(
                "trueHDDecoderInputPacketCount"
            ),
            trueHDDecoderBatchCount: uint64Metadata(
                "trueHDDecoderBatchCount"
            ),
            trueHDAggregatedDecoderBatchCount: uint64Metadata(
                "trueHDAggregatedDecoderBatchCount"
            ),
            trueHDOutputSampleBufferCount: uint64Metadata(
                "trueHDOutputSampleBufferCount"
            ),
            trueHDLastDecoderBatchInputPacketCount: uint32Metadata(
                "trueHDLastDecoderBatchInputPacketCount"
            )
        )
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
            isReadyForMoreMediaData: audioRenderer.isReadyForMoreMediaData,
            hasSufficientMediaDataForReliablePlaybackStart:
                audioRenderer.hasSufficientMediaDataForReliablePlaybackStart,
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
                    "muted": String(audioRenderer.isMuted)
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
                    ?? "none"
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
        if isPrerolling, timelineStartRate == 0, pausedSeekAwaitsCoverage {
            activatePausedSeekTimeline(
                fallback: targetTimelineTime(fallback: .zero),
                capturedVideoDeliveryGeneration: nil
            )
        }
        endPlaybackWhenInputEndsBeforeActivation()
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
        PlaybackTrace.event("session.providerControl id=\(traceID) kind=\(kind)")
        invalidateTimelineProgressRecovery()
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
                "formatRevision": String(formatRevision)
            ]
        )
        didRecordFormat = false
        resetVideoEndState()
        flushCount += 1
        await rendererSink.flush(removingDisplayedImage: false)
        discardVideoFramesInFlight()
        guard !isClosed else { return }
        isResetting = false
        if mediaSessionRecord?.lifecycle == .playing {
            armTimelineProgressRecoveryForCurrentMapping()
        }
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

    public var finalDisplayableVideoPresentationTime: CMTime? {
        let durationSeconds = provider.info.durationSeconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return maximumAcceptedVideoPresentationTime
        }
        let duration = CMTime(
            seconds: durationSeconds,
            preferredTimescale: 60_000
        )
        guard let maximumPresentationTime = maximumAcceptedVideoPresentationTime,
              maximumPresentationTime.isNumeric else {
            return nil
        }
        guard CMTimeCompare(maximumPresentationTime, duration) >= 0 else {
            return maximumPresentationTime
        }
        return maximumAcceptedVideoPresentationTimeBeforeDuration
    }

    var maximumAcceptedVideoPresentationTime: CMTime? {
        endStateLock.withLock { endState.maximumVideoPresentationTime }
    }

    var maximumAcceptedVideoPresentationTimeBeforeDuration: CMTime? {
        endStateLock.withLock {
            endState.maximumVideoPresentationTimeBeforeDuration
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
        resetAudioSpectrum()
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
            let durationSeconds = provider.info.durationSeconds
            if presentationTime.isNumeric,
               durationSeconds.isFinite,
               durationSeconds > 0,
               CMTimeCompare(
                   presentationTime,
                   CMTime(seconds: durationSeconds, preferredTimescale: 60_000)
               ) < 0,
               endState.maximumVideoPresentationTimeBeforeDuration.map({
                   CMTimeCompare($0, presentationTime) < 0
               }) ?? true {
                endState.maximumVideoPresentationTimeBeforeDuration = presentationTime
            }
            if presentationEnd.isNumeric,
               endState.videoPresentationEnd.map({
                   CMTimeCompare($0, presentationEnd) < 0
               }) ?? true {
                endState.videoPresentationEnd = presentationEnd
            }
        }
        observeDeliveryContinuityAfterMediaDelivery()
    }

    func endPlaybackWhenInputEndsBeforeActivation() {
        guard isPrerolling, timelineStartRate > 0, requestedTimelineStart.isNumeric else { return }
        let nothingLeftToPlay = maximumAcceptedVideoPresentationTime
            .map { $0.seconds <= requestedTimelineStart.seconds } ?? true
        guard nothingLeftToPlay, claimEndReport() else { return }
        let endSeconds = diagnostics.durationSeconds > 0
            ? diagnostics.durationSeconds
            : (acceptedVideoPresentationEndSeconds ?? requestedTimelineStart.seconds)
        let endTime = CMTime(seconds: endSeconds, preferredTimescale: 60_000)
        isPrerolling = false
        timelineStartRate = 0
        clearPrerollRequirement()
        setTimelineStopped(at: endTime, reason: .seekToEnd)
        diagnostics.currentSeconds = endSeconds
        updateLifecycle(.ended)
        recordTimelineControlState()
        publishDiagnostics(at: endTime, force: true)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timeline.ended",
            outcome: .succeeded,
            details: [
                "reason": "inputEndedBeforeActivation",
                "requestedSeconds": String(requestedTimelineStart.seconds),
                "endSeconds": String(endSeconds)
            ]
        )
        onStatusChange?(.ended(.seekToEnd))
    }

    func claimEndReport() -> Bool {
        endStateLock.withLock {
            guard !endState.isClosed, !endState.didReportEnd else { return false }
            endState.didReportEnd = true
            return true
        }
    }

    func acceptedVideoCoversTarget(_ targetSeconds: Double) -> Bool {
        endStateLock.withLock {
            if let maximum = endState.maximumVideoPresentationTime,
               maximum.isNumeric,
               maximum.seconds >= targetSeconds {
                return true
            }
            if let presentationEnd = endState.videoPresentationEnd,
               presentationEnd.isNumeric,
               presentationEnd.seconds >= targetSeconds {
                return true
            }
            return false
        }
    }

    var acceptedVideoPresentationEndSeconds: Double? {
        endStateLock.withLock {
            endState.videoPresentationEnd.flatMap { $0.isNumeric ? $0.seconds : nil }
        }
    }

    var audioProviderHasEnded: Bool {
        endStateLock.withLock { endState.audioProviderEnded }
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
        observeDeliveryContinuityAfterMediaDelivery()
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
            if mediaKind == .audioOnly {
                guard !endState.isClosed,
                      !endState.didReportEnd,
                      endState.audioProviderEnded,
                      let presentationEnd = endState.audioPresentationEnd,
                      CMTimeCompare(time, presentationEnd) >= 0 else {
                    return false
                }
                endState.didReportEnd = true
                return true
            }
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

func timelineProgressDecisionIsEligible(
    incident: PlaybackTimelineProgressIncident,
    blockedLaneIsEligible: Bool,
    hostWatchdogIsEligible: Bool
) -> Bool {
    switch incident.evidence {
    case .blockedLanes:
        blockedLaneIsEligible
    case .hostWatchdog:
        hostWatchdogIsEligible
    }
}

func timelineProgressHostWatchdogIsEligible(
    isClosed: Bool,
    isResetting: Bool,
    isCloseInProgress: Bool,
    deliveryPrerollIsPending _: Bool,
    videoSampleDeliveryIsSuspended: Bool,
    lifecycleIsPlaying: Bool,
    timelineStartRate: Float,
    hasActiveOperation: Bool
) -> Bool {
    !isClosed
        && !isResetting
        && !isCloseInProgress
        && !videoSampleDeliveryIsSuspended
        && lifecycleIsPlaying
        && timelineStartRate > 0
        && !hasActiveOperation
}
