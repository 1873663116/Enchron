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
            let sourceSample: CMSampleBuffer
            if let pendingSample = currentPendingVideoSample() {
                sourceSample = pendingSample
            } else {
                do {
                    let event = try await provider.nextEvent()
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
            markAsPrerollIfNeeded(renderSample, presentationTime: presentationTime)
            let shouldActivateTimelineAfterEnqueue = !hasStartedTimeline
            if shouldActivateTimelineAfterEnqueue {
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
                isPrerolling = hasPreroll
                PlaybackTrace.event(
                    "session.timeline.set id=\(traceID) rate=0.0 " +
                    "time=\(timelineStart.seconds)"
                )
                publishDiagnostics(at: timelineStart, force: true)
            } else if isPrerolling,
                      requestedTimelineStart.isNumeric,
                      presentationTime >= requestedTimelineStart {
                synchronizer.setRate(timelineStartRate, time: requestedTimelineStart)
                isPrerolling = false
                publishTargetTimelineState(at: requestedTimelineStart)
                publishDiagnostics(at: requestedTimelineStart, force: true)
            }
            if diagnostics.enqueuedSampleCount == 0 {
                diagnostics.timelineConfiguredBeforeFirstEnqueue = hasStartedTimeline
                dumpVideoSampleIfRequested(renderSample)
            }
            let isFirstVideoSample = diagnostics.enqueuedSampleCount == 0
            let decodeTime = CMSampleBufferGetDecodeTimeStamp(renderSample)
            let decoderBootstrapTarget = targetTimelineTime(fallback: presentationTime)
            let bootstrapIncomplete = !decoderBootstrapLock.withLock { decoderBootstrapComplete }
            let requiresImmediateDecoderBootstrap = bootstrapIncomplete && (
                isFirstVideoSample || !decodeTime.isNumeric || decodeTime <= decoderBootstrapTarget
            )
            let outcome: RendererEnqueueOutcome
            do {
                let enqueueSample = try CMSampleBuffer(copying: renderSample)
                let input = RendererInputSample(sampleBuffer: enqueueSample)
                if requiresImmediateDecoderBootstrap {
                    outcome = try rendererSink.enqueueImmediately(input)
                } else {
                    outcome = try await rendererSink.enqueue(input)
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
            if bootstrapIncomplete,
               !decodeTime.isNumeric || decodeTime >= decoderBootstrapTarget {
                decoderBootstrapLock.withLock { decoderBootstrapComplete = true }
            }
            if shouldActivateTimelineAfterEnqueue {
                let activationRate: Float = isPrerolling ? 1 : timelineStartRate
                synchronizer.rate = activationRate
                if !isPrerolling {
                    publishTargetTimelineState(
                        at: targetTimelineTime(fallback: presentationTime)
                    )
                }
                PlaybackTrace.event(
                    "session.timeline.activated id=\(traceID) rate=\(activationRate)"
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

    func deliverAudioSamples() async {
        while !Task.isCancelled, !isClosed, !isResetting {
            do {
                guard let sample = try await audioProvider.copyNextSample() else {
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
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                let duration = CMSampleBufferGetDuration(sample)
                let presentationEnd = duration.isNumeric
                    ? CMTimeAdd(presentationTime, duration)
                    : presentationTime
                recordAudioPresentationEnd(presentationEnd)
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
                let outcome = try await audioRendererSink.enqueue(
                    RendererInputSample(sampleBuffer: sample)
                )
                guard handleAudioEnqueueOutcome(outcome) else { return }
                audioSampleBufferCount += 1
                audioFrameCount += UInt64(max(0, record.sampleCount))
                recordAudioRendererState()
                if audioSampleBufferCount == 1 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        kind: "audioRenderer.firstEnqueue",
                        outcome: .succeeded,
                        details: ["audioTrackID": trackID]
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
        debugStore.recordAudioRendererState(AudioRendererStateRecord(
            mediaSessionID: traceID,
            graphID: "\(traceID).rendererGraph",
            rendererIdentity: PlaybackTrace.identity(audioRenderer),
            videoRendererIdentity: PlaybackTrace.identity(renderer),
            synchronizerIdentity: PlaybackTrace.identity(synchronizer),
            streamEpoch: audioStreamEpoch,
            enqueuedSampleBufferCount: audioSampleBufferCount,
            enqueuedAudioFrameCount: audioFrameCount,
            volume: audioRenderer.volume,
            muted: audioRenderer.isMuted,
            error: currentAudioRendererError
        ))
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
            formatRevision += 1
        case .flush:
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

    func targetEpochEndedBeforeVideoPTS(_ targetSeconds: Double) -> Bool {
        endStateLock.withLock {
            guard endState.videoProviderEnded else { return false }
            guard let maximumPTS = endState.maximumVideoPresentationTime,
                  maximumPTS.isNumeric else { return true }
            return maximumPTS.seconds < targetSeconds
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
