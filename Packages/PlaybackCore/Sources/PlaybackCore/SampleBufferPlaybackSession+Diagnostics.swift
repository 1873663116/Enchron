@preconcurrency import AVFoundation
import Foundation
import OSLog
import VideoToolbox

extension SampleBufferPlaybackSession {
    func updatePresentationStatus(at time: CMTime) {
        recordSubtitleState(at: time)
        publishSubtitleCues(at: time)
        publishDiagnostics(at: time)
        guard claimEndIfReady(at: time) else { return }
        synchronizer.rate = 0
        updateLifecycle(.ended)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timeline.ended",
            outcome: .succeeded
        )
        onStatusChange?(.ended(.naturalCompletion))
    }

    func publishDiagnostics(at time: CMTime, force: Bool = false) {
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        let wholeSecond = Int(seconds * 2)
        guard force || wholeSecond != lastDiagnosticsSecond else { return }
        lastDiagnosticsSecond = wholeSecond
        diagnostics.currentSeconds = seconds
        diagnostics.rendererStatus = currentVideoRendererStatus
        diagnostics.rendererError = currentVideoRendererError ?? "none"
        recordRendererState(at: time)
        recordAudioRendererState()
        refreshVideoPerformanceMetrics()
        let actualTimebaseRate = CMTimebaseGetRate(synchronizer.timebase)
        if actualTimebaseRate == 0 {
            refreshDisplayedPixelBufferDetails()
        }
        PlaybackTrace.event(
            "session.heartbeat id=\(traceID) time=\(time.seconds) samples=\(diagnostics.enqueuedSampleCount) " +
            "rendererStatus=\(diagnostics.rendererStatus) rendererError=\(diagnostics.rendererError) " +
            "requestedRate=\(synchronizer.rate) actualTimebaseRate=\(actualTimebaseRate)"
        )
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timeline.heartbeat",
            outcome: .succeeded,
            details: [
                "timeSeconds": String(seconds),
                "videoSampleCount": String(diagnostics.enqueuedSampleCount),
                "audioSampleBufferCount": String(audioSampleBufferCount),
                "requestedRate": String(synchronizer.rate),
                "actualTimebaseRate": String(actualTimebaseRate),
            ]
        )
        onDiagnosticsChange?(diagnostics)
    }

    func refreshVideoPerformanceMetrics() {
        let shouldRequest = videoPerformanceMetricsLock.withLock {
            guard videoPerformanceMetricsRequestInFlight == false else { return false }
            videoPerformanceMetricsRequestInFlight = true
            return true
        }
        guard shouldRequest else { return }
        renderer.loadVideoPerformanceMetrics { [weak self] metrics in
            guard let self else { return }
            self.videoPerformanceMetricsLock.withLock {
                self.videoPerformanceMetricsRequestInFlight = false
            }
            let details: [String: String]
            if let metrics {
                details = [
                    "totalFrames": String(metrics.totalNumberOfFrames),
                    "droppedFrames": String(metrics.numberOfDroppedFrames),
                    "corruptedFrames": String(metrics.numberOfCorruptedFrames),
                    "optimizedCompositingFrames": String(
                        metrics.numberOfFramesDisplayedUsingOptimizedCompositing
                    ),
                    "accumulatedFrameDelay": String(metrics.totalAccumulatedFrameDelay),
                ]
            } else {
                details = ["availability": "none"]
            }
            self.debugStore.emit(
                mediaSessionID: self.traceID,
                node: .rendererInputCoordination,
                kind: "videoRenderer.performanceMetrics",
                outcome: .succeeded,
                details: details
            )
        }
    }

    func refreshDisplayedPixelBufferDetails() {
        let shouldProbe = displayedPixelBufferProbeLock.withLock {
            guard displayedPixelBufferProbeInFlight == false else { return false }
            displayedPixelBufferProbeInFlight = true
            return true
        }
        guard shouldProbe else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            defer {
                self.displayedPixelBufferProbeLock.withLock {
                    self.displayedPixelBufferProbeInFlight = false
                }
            }
            guard let pixelBuffer = self.renderer.displayedPixelBuffer() else {
                self.recordDisplayedPixelBufferDetails(["availability": "none"])
                return
            }
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var image: CGImage?
            let conversionStatus = VTCreateCGImageFromCVPixelBuffer(
                pixelBuffer,
                options: nil,
                imageOut: &image
            )
            guard conversionStatus == noErr, let image else {
                self.recordDisplayedPixelBufferDetails([
                    "conversionStatus": String(conversionStatus),
                    "format": fourCC(format),
                    "height": String(height),
                    "width": String(width),
                ])
                return
            }

            let sampleWidth = 64
            let sampleHeight = 64
            let bytesPerRow = sampleWidth * 4
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * sampleHeight)
            let drewImage = pixels.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress,
                      let context = CGContext(
                        data: baseAddress,
                        width: sampleWidth,
                        height: sampleHeight,
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else {
                    return false
                }
                context.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
                )
                return true
            }
            guard drewImage else {
                self.recordDisplayedPixelBufferDetails([
                    "conversionStatus": "cgContextUnavailable",
                    "format": fourCC(format),
                    "height": String(height),
                    "width": String(width),
                ])
                return
            }

            var minimum = UInt16.max
            var maximum: UInt16 = 0
            var total: UInt64 = 0
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let luminance = UInt16(pixels[offset]) * 54
                    + UInt16(pixels[offset + 1]) * 183
                    + UInt16(pixels[offset + 2]) * 19
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                total += UInt64(luminance)
            }
            let sampleCount = UInt64(sampleWidth * sampleHeight)
            self.recordDisplayedPixelBufferDetails([
                "format": fourCC(format),
                "height": String(height),
                "lumaAverage": String(Double(total) / Double(sampleCount * 256)),
                "lumaMaximum": String(Double(maximum) / 256),
                "lumaMinimum": String(Double(minimum) / 256),
                "lumaRange": String(Double(maximum - minimum) / 256),
                "sampleCount": String(sampleCount),
                "width": String(width),
            ])
        }
    }

    func recordDisplayedPixelBufferDetails(_ details: [String: String]) {
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "videoRenderer.displayedPixelBuffer",
            outcome: .succeeded,
            details: details
        )
    }

    func updateCompressedDiagnostics(sample: CMSampleBuffer) {
        guard !didRecordFormat, let format = CMSampleBufferGetFormatDescription(sample) else { return }
        didRecordFormat = true
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        diagnostics.sourcePixelFormat = "compressed"
        diagnostics.destinationPixelFormat = fourCC(CMFormatDescriptionGetMediaSubType(format))
        diagnostics.dimensions = "\(dimensions.width)×\(dimensions.height)"
        diagnostics.colorPrimaries = extensionString(extensions, key: kCMFormatDescriptionExtension_ColorPrimaries)
        diagnostics.transferFunction = extensionString(extensions, key: kCMFormatDescriptionExtension_TransferFunction)
        diagnostics.yCbCrMatrix = extensionString(extensions, key: kCMFormatDescriptionExtension_YCbCrMatrix)
        diagnostics.range = (extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool) == true
            ? "full-range" : "video-range"
        diagnostics.projectionKind = extensionString(
            extensions,
            key: kCMFormatDescriptionExtension_ProjectionKind
        )
        diagnostics.viewPackingKind = extensionString(
            extensions,
            key: kCMFormatDescriptionExtension_ViewPackingKind
        )
        diagnostics.hasLeftStereoEyeView =
            extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool == true
        diagnostics.hasRightStereoEyeView =
            extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool == true
        diagnostics.sourceFormatHasMasteringDisplayMetadata = extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] != nil
        diagnostics.sourceFormatHasContentLightLevelMetadata = extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] != nil
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Any] ?? [:]
        diagnostics.formatHasHvcC = atoms["hvcC"] != nil
        diagnostics.formatHasDvcC = atoms["dvcC"] != nil
        diagnostics.formatHasDvvC = atoms["dvvC"] != nil
        diagnostics.formatHasAmbientViewingEnvironment =
            extensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String] != nil ||
            atoms["amve"] != nil
        PlaybackTrace.event(
            "session.compressedFormat id=\(traceID) subtype=\(diagnostics.destinationPixelFormat) " +
            "hvcC=\(diagnostics.formatHasHvcC) dvcC=\(diagnostics.formatHasDvcC) " +
            "dvvC=\(diagnostics.formatHasDvvC) amve=\(diagnostics.formatHasAmbientViewingEnvironment)"
        )
    }

    func recordVideoSample(_ sample: CMSampleBuffer) -> String {
        sourceEventSequence += 1
        let eventID = "\(traceID).event.\(sourceEventSequence)"
        let mediaEvent = MediaEventRecord(
            eventID: eventID,
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .sample,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordMediaEvent(mediaEvent)

        let format = CMSampleBufferGetFormatDescription(sample)
        let dimensions = format.map(CMVideoFormatDescriptionGetDimensions)
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
        let decodeTime = CMSampleBufferGetDecodeTimeStamp(sample)
        let duration = CMSampleBufferGetDuration(sample)
        let attachments = sampleAttachmentDictionary(sample)
        let isNotSync = attachments[kCMSampleAttachmentKey_NotSync as String] as? Bool
        let dependsOnOthers = attachments[
            kCMSampleAttachmentKey_DependsOnOthers as String
        ] as? Bool
        let sampleRecord = VideoSampleRecord(
            mediaSessionID: traceID,
            videoTrackID: videoTrackID,
            sourceEventID: eventID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            inputKind: .compressed,
            presentationTimeSeconds: numericSeconds(presentationTime) ?? 0,
            decodeTimeSeconds: numericSeconds(decodeTime),
            durationSeconds: numericSeconds(duration) ?? 0,
            mediaSubtype: format.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown",
            dimensions: dimensions.map { "\($0.width)x\($0.height)" } ?? "unknown",
            sampleCount: CMSampleBufferGetNumSamples(sample),
            formatIdentity: PlaybackTrace.identity(format),
            syncSummary: isNotSync == true ? "notSync" : "syncOrNotMarked",
            dependencySummary: dependsOnOthers.map {
                $0 ? "dependsOnOthers" : "independent"
            } ?? "notMarked",
            formatSignaling: formatSignalingSummary(for: sample),
            payloadOwnershipState: "retainedCMSampleBuffer"
        )
        let isFirstSample = lastRecordedSampleEpoch != streamEpoch
        if isFirstSample { lastRecordedSampleEpoch = streamEpoch }
        debugStore.recordVideoSample(sampleRecord)
        if isFirstSample {
            debugStore.emit(
                mediaSessionID: traceID,
                node: .mediaEventStream,
                kind: "mediaEvent.firstSample",
                outcome: .succeeded,
                details: ["sourceEventID": eventID]
            )
            debugStore.emit(
                mediaSessionID: traceID,
                node: .videoSampleStream,
                kind: "videoSample.firstProduced",
                outcome: .succeeded,
                details: [
                    "inputKind": RendererInputKind.compressed.rawValue,
                    "mediaSubtype": sampleRecord.mediaSubtype,
                ]
            )
        }
        return eventID
    }

    func dumpVideoSampleIfRequested(_ sample: CMSampleBuffer) {
        guard ProcessInfo.processInfo.environment["PLAYBACKLAB_DUMP_VIDEO_DESCRIPTION"] == "1",
              let format = CMSampleBufferGetFormatDescription(sample) else { return }
        var blockBuffer: CMBlockBuffer?
        let status = CMVideoFormatDescriptionCopyAsBigEndianImageDescriptionBlockBuffer(
            allocator: kCFAllocatorDefault,
            videoFormatDescription: format,
            stringEncoding: CFStringGetSystemEncoding(),
            flavor: nil,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            fputs("[VIDEO-DESCRIPTION] copy failed: \(status)\n", stderr)
            return
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var bytes = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(
            blockBuffer,
            atOffset: 0,
            dataLength: length,
            destination: &bytes
        ) == noErr else { return }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        fputs("[VIDEO-DESCRIPTION] \(hex)\n", stderr)
        if let dataBuffer = CMSampleBufferGetDataBuffer(sample) {
            let sampleLength = CMBlockBufferGetDataLength(dataBuffer)
            let prefixLength = min(sampleLength, 64)
            var prefix = [UInt8](repeating: 0, count: prefixLength)
            if CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: prefixLength,
                destination: &prefix
            ) == noErr {
                let payloadHex = prefix.map { String(format: "%02x", $0) }.joined()
                let attachments = CMSampleBufferGetSampleAttachmentsArray(
                    sample,
                    createIfNecessary: false
                )
                fputs(
                    "[VIDEO-SAMPLE] length=\(sampleLength) " +
                    "pts=\(CMSampleBufferGetPresentationTimeStamp(sample).seconds) " +
                    "dts=\(CMSampleBufferGetDecodeTimeStamp(sample).seconds) " +
                    "duration=\(CMSampleBufferGetDuration(sample).seconds) " +
                    "attachments=\(String(describing: attachments)) prefix=\(payloadHex)\n",
                    stderr
                )
            }
        }
    }

    func numericSeconds(_ time: CMTime) -> Double? {
        guard time.isValid, time.isNumeric else { return nil }
        return time.seconds
    }

    func formatSignalingSummary(
        for sample: CMSampleBuffer
    ) -> VideoFormatSignalingSummary {
        let formatExtensions = CMSampleBufferGetFormatDescription(sample)
            .map { CMFormatDescriptionGetExtensions($0) as? [String: Any] ?? [:] } ?? [:]
        let atoms = formatExtensions[
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        ] as? [String: Any] ?? [:]
        let imageBuffer = CMSampleBufferGetImageBuffer(sample)
        let imageAttachments = imageBuffer.flatMap {
            CVBufferCopyAttachments($0, .shouldPropagate) as? [String: Any]
        } ?? [:]
        let decoded = imageBuffer != nil
        let colorSource = decoded ? imageAttachments : formatExtensions
        let rangeFact: ObservedStringFact
        if let fullRange = formatExtensions[
            kCMFormatDescriptionExtension_FullRangeVideo as String
        ] as? Bool {
            rangeFact = .init(known: fullRange ? "full" : "video")
        } else if let imageBuffer {
            rangeFact = .init(
                known: pixelRange(CVPixelBufferGetPixelFormatType(imageBuffer))
            )
        } else {
            rangeFact = .init(.unknown)
        }
        return VideoFormatSignalingSummary(
            provenance: decoded
                ? "CVPixelBuffer.shouldPropagate+CMFormatDescription"
                : "CMFormatDescription.sampleDescription",
            colorPrimaries: observedStringFact(
                colorSource,
                key: decoded
                    ? kCVImageBufferColorPrimariesKey
                    : kCMFormatDescriptionExtension_ColorPrimaries
            ),
            transferFunction: observedStringFact(
                colorSource,
                key: decoded
                    ? kCVImageBufferTransferFunctionKey
                    : kCMFormatDescriptionExtension_TransferFunction
            ),
            yCbCrMatrix: observedStringFact(
                colorSource,
                key: decoded
                    ? kCVImageBufferYCbCrMatrixKey
                    : kCMFormatDescriptionExtension_YCbCrMatrix
            ),
            range: rangeFact,
            projectionKind: observedStringFact(
                formatExtensions,
                key: kCMFormatDescriptionExtension_ProjectionKind
            ),
            viewPackingKind: observedStringFact(
                formatExtensions,
                key: kCMFormatDescriptionExtension_ViewPackingKind
            ),
            hasLeftStereoEyeView: observedBooleanFact(
                formatExtensions,
                key: kCMFormatDescriptionExtension_HasLeftStereoEyeView
            ),
            hasRightStereoEyeView: observedBooleanFact(
                formatExtensions,
                key: kCMFormatDescriptionExtension_HasRightStereoEyeView
            ),
            masteringDisplayMetadata: presenceFact(
                imageAttachments[kCVImageBufferMasteringDisplayColorVolumeKey as String]
                    ?? formatExtensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String]
            ),
            contentLightLevelMetadata: presenceFact(
                imageAttachments[kCVImageBufferContentLightLevelInfoKey as String]
                    ?? formatExtensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String]
            ),
            hvcC: decoded ? .init(.notAvailable) : presenceFact(atoms["hvcC"]),
            dvcC: decoded ? .init(.notAvailable) : presenceFact(atoms["dvcC"]),
            dvvC: decoded ? .init(.notAvailable) : presenceFact(atoms["dvvC"]),
            ambientViewingEnvironment: presenceFact(
                imageAttachments[kCVImageBufferAmbientViewingEnvironmentKey as String]
                    ?? formatExtensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String]
                    ?? atoms["amve"]
            )
        )
    }

    func observedStringFact(
        _ values: [String: Any],
        key: CFString
    ) -> ObservedStringFact {
        guard let value = values[key as String] else { return .init(.none) }
        return .init(known: normalized(String(describing: value)))
    }

    func observedBooleanFact(
        _ values: [String: Any],
        key: CFString
    ) -> ObservedBooleanFact {
        guard let value = values[key as String] as? Bool else { return .init(.none) }
        return .init(known: value)
    }

    func presenceFact(_ value: Any?) -> ObservedBooleanFact {
        value == nil ? .init(.none) : .init(known: true)
    }

    func sampleAttachmentDictionary(_ sample: CMSampleBuffer) -> [String: Any] {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        ) as? [[String: Any]], let first = array.first else {
            return [:]
        }
        return first
    }

    func markAsPrerollIfNeeded(
        _ sample: CMSampleBuffer,
        presentationTime: CMTime,
        presentationEnd: CMTime
    ) {
        guard requestedTimelineStart.isNumeric,
              requestedTimelineStart > .zero,
              presentationTime < requestedTimelineStart,
              presentationEnd < requestedTimelineStart,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else {
            return
        }
        let dictionary = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0),
            to: CFMutableDictionary.self
        )
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DoNotDisplay).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    func targetTimelineTime(fallback: CMTime) -> CMTime {
        requestedTimelineStart.isNumeric
            ? requestedTimelineStart
            : fallback
    }

    func resetDecoderBootstrap() {
        decoderBootstrapLock.withLock {
            decoderBootstrapComplete = false
            decoderBootstrapTargetSeconds = nil
            decoderBootstrapLastDecodeTimeSeconds = nil
            decoderBootstrapImmediateEnqueueCount = 0
        }
        debugStore.recordDecoderBootstrap(nil)
    }

    func beginDecoderBootstrap(target: CMTime) {
        let targetSeconds = numericSeconds(target) ?? 0
        let record = decoderBootstrapLock.withLock {
            decoderBootstrapTargetSeconds = targetSeconds
            return DecoderBootstrapRecord(
                mediaSessionID: traceID,
                streamEpoch: streamEpoch,
                targetDecodeTimeSeconds: targetSeconds,
                immediateEnqueueCount: decoderBootstrapImmediateEnqueueCount,
                targetRate: timelineStartRate,
                complete: decoderBootstrapComplete
            )
        }
        debugStore.recordDecoderBootstrap(record)
    }

    func recordAcceptedDecoderBootstrapSample(
        decodeTime: CMTime,
        target: CMTime,
        usedImmediateEnqueue: Bool
    ) -> DecoderBootstrapRecord {
        let targetSeconds = numericSeconds(target) ?? 0
        let decodeSeconds = numericSeconds(decodeTime)
        let record = decoderBootstrapLock.withLock {
            if decoderBootstrapComplete == false {
                decoderBootstrapTargetSeconds = targetSeconds
                decoderBootstrapLastDecodeTimeSeconds = decodeSeconds
                if usedImmediateEnqueue {
                    decoderBootstrapImmediateEnqueueCount &+= 1
                }
                if decodeSeconds == nil || (decodeSeconds ?? -.infinity) >= targetSeconds {
                    decoderBootstrapComplete = true
                }
            }
            return DecoderBootstrapRecord(
                mediaSessionID: traceID,
                streamEpoch: streamEpoch,
                targetDecodeTimeSeconds: decoderBootstrapTargetSeconds ?? targetSeconds,
                lastDecodeTimeSeconds: decoderBootstrapLastDecodeTimeSeconds,
                immediateEnqueueCount: decoderBootstrapImmediateEnqueueCount,
                targetRate: timelineStartRate,
                complete: decoderBootstrapComplete
            )
        }
        debugStore.recordDecoderBootstrap(record)
        return record
    }

    func publishTargetTimelineState(at time: CMTime) {
        let lifecycle: PlaybackLifecycle = timelineStartRate == 0 ? .paused : .playing
        updateLifecycle(lifecycle)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "timeline.targetApplied",
            outcome: .succeeded,
            details: [
                "rate": String(timelineStartRate),
                "time": String(time.seconds),
            ]
        )
        onStatusChange?(timelineStartRate == 0 ? .paused : .playing)
    }

    func updateLifecycle(_ lifecycle: PlaybackLifecycle) {
        guard var record = mediaSessionRecord else { return }
        record.lifecycle = lifecycle
        mediaSessionRecord = record
        debugStore.recordSession(record)
    }

    func recordFailure(_ error: Error, node: PlaybackNode, kind: String) {
        updateLifecycle(.failed)
        debugStore.recordFailure(PlaybackFailureRecord(
            mediaSessionID: traceID,
            node: node,
            stage: kind,
            errorType: String(reflecting: type(of: error)),
            message: error.localizedDescription,
            recoverability: "notRecoverableWithinMediaSession"
        ))
        debugStore.emit(
            mediaSessionID: traceID,
            node: node,
            kind: kind,
            outcome: .failed,
            details: ["error": error.localizedDescription]
        )
        if activeOperation != nil {
            finishActiveOperation(.failed, failure: error.localizedDescription)
        }
    }

    func publishRendererFailure(_ fact: RendererFailureFact) {
        guard claimRendererFailure() else { return }
        rendererFailureMonitor?.stop()
        closeEndState()
        synchronizer.rate = 0
        stopVideoDelivery()
        stopAudioDelivery()
        discardPendingVideoSample()
        provider.cancel()
        audioDeliveryQueue.sync {
            audioProvider.cancel()
        }

        switch fact.rendererKind {
        case .video:
            setVideoRendererState(status: "failed", error: fact.message)
        case .audio:
            setAudioRendererError(fact.message)
        }
        updateLifecycle(.failed)
        let stage = PlaybackArtifactEventName.renderer(
            fact.rendererKind,
            warning: false
        ).rawValue
        debugStore.recordFailure(PlaybackFailureRecord(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            stage: stage,
            errorType: fact.errorType,
            message: fact.message,
            recoverability: "notRecoverableWithinMediaSession",
            rendererKind: fact.rendererKind.rawValue,
            requiresFlushToResumeDecoding: fact.requiresFlushToResumeDecoding
        ))
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: stage,
            outcome: .failed,
            details: [
                "error": fact.message,
                "errorType": fact.errorType,
                "rendererKind": fact.rendererKind.rawValue,
                "requiresFlushToResumeDecoding": fact.requiresFlushToResumeDecoding
                    .map { String($0) } ?? "notAvailable",
            ]
        )
        if activeOperation != nil {
            finishActiveOperation(.failed, failure: fact.message)
        }
        recordRendererState(at: currentTime())
        recordAudioRendererState()
        logger.error("Renderer failed kind=\(fact.rendererKind.rawValue, privacy: .public) error=\(fact.message, privacy: .public)")
        onStatusChange?(.failed(fact.message))
    }

    func startRendererFailureMonitoring() {
        let failureHandler: @Sendable (RendererFailureFact) -> Void = { [weak self] fact in
            self?.deliveryQueue.async { [weak self] in
                self?.publishRendererFailure(fact)
            }
        }
        rendererFailureMonitor?.start(handler: failureHandler)
    }

    func rendererInputEventHandler() -> @Sendable (RendererInputEventFact) -> Void {
        { [weak self] event in
            self?.deliveryQueue.async { [weak self] in
                self?.handleRendererInputEvent(event)
            }
        }
    }

    func handleRendererInputEvent(_ event: RendererInputEventFact) {
        switch event {
        case .failure(let fact):
            publishRendererFailure(fact)
        case .warning(let rendererKind, let message):
            if rendererKind == .audio {
                recordAudioRendererState()
            }
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererInputCoordination,
                kind: PlaybackArtifactEventName.renderer(
                    rendererKind,
                    warning: true
                ).rawValue,
                outcome: .failed,
                details: [
                    "message": message,
                    "streamEpoch": rendererKind == .audio
                        ? String(audioStreamEpoch)
                        : String(streamEpoch),
                    "rendererStatus": rendererKind == .audio
                        ? audioRendererStatusLabel
                        : currentVideoRendererStatus,
                    "rendererError": rendererKind == .audio
                        ? (audioRenderer.error?.localizedDescription
                            ?? currentAudioRendererError
                            ?? "none")
                        : (currentVideoRendererError ?? "none"),
                ]
            )
        }
    }

    func claimRendererFailure() -> Bool {
        rendererFailureLock.withLock {
            guard acceptsRendererFailure else { return false }
            acceptsRendererFailure = false
            return true
        }
    }

    func stopRendererFailureMonitoring() {
        rendererFailureLock.withLock {
            acceptsRendererFailure = false
        }
        rendererFailureMonitor?.stop()
        rendererSink.stopRenderingEventObservation()
        audioRendererSink.stopRenderingEventObservation()
    }

    func beginOperation(
        _ kind: PlaybackOperationKind,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil
    ) {
        let operation = PlaybackOperationRecord(
            mediaSessionID: traceID,
            kind: kind,
            targetTimeSeconds: targetTimeSeconds,
            targetRate: targetRate
        )
        activeOperation = operation
        debugStore.recordOperation(operation)
        debugStore.emit(
            mediaSessionID: traceID,
            kind: PlaybackArtifactEventName.operationStarted(kind).rawValue,
            outcome: .succeeded,
            details: ["operationID": operation.operationID]
        )
    }

    func finishActiveOperation(
        _ state: PlaybackOperationState,
        failure: String? = nil
    ) {
        guard let operation = activeOperation else { return }
        let finished = operation.finishing(as: state, failure: failure)
        activeOperation = nil
        debugStore.recordOperation(finished)
        let outcome: NodeOutcome = switch state {
        case .completed: .succeeded
        case .failed: .failed
        case .terminatedByCleanup: .terminatedByCleanup
        case .running: .succeeded
        }
        debugStore.emit(
            mediaSessionID: traceID,
            kind: PlaybackArtifactEventName.operationFinished(
                operation.kind,
                as: state
            ).rawValue,
            outcome: outcome,
            details: ["operationID": operation.operationID]
        )
    }

    func recordRendererState(at time: CMTime) {
        debugStore.recordRendererState(RendererStateRecord(
            mediaSessionID: traceID,
            graphID: "\(traceID).rendererGraph",
            graphRevision: graphRevision,
            streamEpoch: streamEpoch,
            rendererIdentity: PlaybackTrace.identity(renderer),
            synchronizerIdentity: PlaybackTrace.identity(synchronizer),
            timelineConfigured: hasStartedTimeline,
            currentTimeSeconds: numericSeconds(time) ?? 0,
            rate: synchronizer.rate,
            actualTimebaseRate: Float(CMTimebaseGetRate(synchronizer.timebase)),
            effectiveTimebaseRate: Float(
                CMTimebaseGetEffectiveRate(synchronizer.timebase)
            ),
            rendererStatus: currentVideoRendererStatus,
            rendererError: currentVideoRendererError,
            inputModel: "boundedImmediateRendererLead",
            displayedPixelBuffer: renderer.displayedPixelBuffer() != nil,
            flushCount: flushCount
        ))
    }

    func attachmentString(_ attachments: [String: Any], key: CFString) -> String {
        guard let value = attachments[key as String] else { return "missing" }
        return normalized(String(describing: value))
    }

    func extensionString(_ extensions: [String: Any], key: CFString) -> String {
        guard let value = extensions[key as String] else { return "missing" }
        return normalized(String(describing: value))
    }

    func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "ITU_R_", with: "")
            .replacingOccurrences(of: "SMPTE_", with: "")
    }

    func pixelRange(_ format: OSType) -> String {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: "full-range"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: "video-range"
        default: "unknown"
        }
    }
}
