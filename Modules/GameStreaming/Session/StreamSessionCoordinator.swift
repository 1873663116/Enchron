import AVFAudio
import AVFoundation
import CoreMedia
import Foundation
import SampleBufferRendering

public final class StreamSessionCoordinator: @unchecked Sendable {
    public let sessionID: SessionID
    public let hostID: HostID
    public let appID: AppID
    public let hostName: String
    public let appName: String

    private let backend: any BackendSession
    private let options: StreamOptions

    private let stateLock = NSLock()
    private var snapshotStorage: SessionSnapshot
    private var sessionEndRecorded = false
    private var deliverQueue = DispatchQueue(label: "app.enchron.stream-session.deliver")
    private var diagnosticsTimer: DispatchSourceTimer?

    public var onSnapshot: (@Sendable (SessionSnapshot) -> Void)?
    public var onBindingChange: (@Sendable (StreamRenderBinding) -> Void)?

    private var synchronizer = AVSampleBufferRenderSynchronizer()
    private var videoRenderer = AVSampleBufferVideoRenderer()
    private var videoSink: AVSampleBufferRendererInputSink
    private var audioRenderer = AVSampleBufferAudioRenderer()
    private var audioSink: AVSampleBufferAudioRendererInputSink
    private var pumpTimer: DispatchSourceTimer?
    private var pumpActive = false
    private var renderingEventObservationActive = false
    private var graphVersion = 1

    private let videoQueueLock = NSLock()
    private var pendingVideo: [(sample: CMSampleBuffer, presentationTimeUs: Int64)] = []
    private var recoveringFromRendererFailure = false
    private var lastReportedQueueDepth = 0
    private var videoDeliveryStartedAt: Date?
    private var surfaceBindingRevision: Int?
    private var surfaceHasBound = false
    private var lastAwaitingSurfaceReport = Date.distantPast

    private var nextAudioPTS: CMTime = .invalid
    private var firstVideoPTS: CMTime = .invalid
    private var audioFormatDescription: CMAudioFormatDescription?
    private var audioFormatKey: String?
    private var audioFrameDurationSeconds: Double = 0

    private var videoStatsTimer: DispatchSourceTimer?
    private var terminatedFallback: DispatchWorkItem?

    private var counters = Counters()

    private struct Counters {
        var presented: Int64 = 0
        var lastPresentedTimestampMs: Int64?
        var decodeRecoveries: Int64 = 0
        var idrRequests: Int64 = 0
        var packetsReceived: Int64 = 0
        var networkDroppedFrames: Int64 = 0
        var duplicatedFrames: Int64 = 0
        var audioFramesReceived: Int64 = 0
        var audioFramesEnqueued: Int64 = 0
        var audioFramesDropped: Int64 = 0
        var framesAwaitingSurface: Int64 = 0
        var framesEnqueuedWithoutSurface: Int64 = 0
        var mouseEvents: Int64 = 0
        var scrollEvents: Int64 = 0
        var keyboardEvents: Int64 = 0
    }

    private var pressedKeys: Set<UInt32> = []
    private var pressedButtons: Set<Int32> = []

    public init(
        sessionID: SessionID,
        hostID: HostID,
        appID: AppID,
        hostName: String,
        appName: String,
        options: StreamOptions,
        backend: any BackendSession
    ) {
        self.sessionID = sessionID
        self.hostID = hostID
        self.appID = appID
        self.hostName = hostName
        self.appName = appName
        self.options = options
        self.backend = backend

        let sink = AVSampleBufferRendererInputSink(
            receiver: synchronizer.sampleBufferReceiver(adding: videoRenderer)
        )
        videoSink = sink
        audioSink = AVSampleBufferAudioRendererInputSink(
            receiver: synchronizer.sampleBufferReceiver(adding: audioRenderer)
        )

        snapshotStorage = SessionSnapshot(
            id: sessionID,
            hostID: hostID,
            appID: appID,
            hostName: hostName,
            appName: appName,
            state: .connecting(stage: "starting"),
            requested: options
        )
    }

    public var binding: StreamRenderBinding {
        StreamRenderBinding(sessionID: sessionID, version: graphVersion, videoRenderer: videoRenderer)
    }

    public var snapshot: SessionSnapshot {
        stateLock.withLock { snapshotStorage }
    }

    public func start() {
        backend.videoSampleHandler = { [weak self] sample in
            self?.handleVideoSample(sample)
        }
        backend.audioFrameHandler = { [weak self] frame in
            self?.handleAudioFrame(frame)
        }
        backend.eventHandler = { [weak self] event in
            self?.handleEvent(event)
        }

        observeRenderingEvents()
        startDiagnosticsTimer()

        StreamSessionProbes.record(
            "session start session=\(sessionID.rawValue) host=\(hostName) app=\(appName)",
            retention: .evidence
        )
        StreamSessionProbes.record(
            "renderer group create session=\(sessionID.rawValue)",
            retention: .evidence
        )
        stateLock.withLock {
            videoDeliveryStartedAt = Date()
        }

        synchronizer.setRate(
            1.0,
            time: .zero,
            atHostTime: CMClockGetTime(CMClockGetHostTimeClock())
        )

        activateAudioSession()
        backend.start()
    }

    /// Stops the session and records the end here as well as in the teardown,
    /// because the teardown's delayed fallback dies with this coordinator once
    /// the model drops the session.
    public func stop(reason: String = "user") {
        stateLock.withLock {
            guard !isStopped(snapshotStorage.state) else { return }
            snapshotStorage.state = .stopping
        }
        publishSnapshot()

        StreamSessionProbes.record(
            "input release session=\(sessionID.rawValue) cause=\(reason)",
            retention: .evidence
        )
        recordSessionEnd(reason: reason)
        backend.releaseAllInput()
        clearPressed()

        videoStatsTimer?.cancel()
        videoStatsTimer = nil

        synchronizer.setRate(0, time: synchronizer.currentTime())
        backend.stop()

        let fallback = DispatchWorkItem { [weak self] in
            self?.finishTeardown(reason: reason)
        }
        terminatedFallback = fallback
        deliverQueue.asyncAfter(deadline: .now() + 5, execute: fallback)
    }

    private func activateAudioSession() {
        Task { @MainActor in
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                StreamSessionProbes.record(
                    "audio session activation failed session=\(self.sessionID.rawValue) error=\(error.localizedDescription)",
                    retention: .evidence
                )
            }
        }
    }

    private func isStopped(_ state: StreamSessionState) -> Bool {
        switch state {
        case .stopping, .ended: true
        default: false
        }
    }

    private func finishTeardown(reason: String) {
        let alreadyEnded = stateLock.withLock {
            if case .ended = snapshotStorage.state { return true }
            return false
        }
        guard !alreadyEnded else { return }

        terminatedFallback?.cancel()
        terminatedFallback = nil

        cancelPumpTimer()
        stopRenderingEventObservation()

        videoSink.stopRenderingEventObservation()
        audioSink.stopRenderingEventObservation()

        videoQueueLock.withLock {
            pendingVideo.removeAll()
        }

        synchronizer.setRate(0, time: synchronizer.currentTime())
        synchronizer.removeRenderer(videoRenderer, at: synchronizer.currentTime())
        synchronizer.removeRenderer(audioRenderer, at: synchronizer.currentTime())

        StreamSessionProbes.record(
            "audio stop session=\(sessionID.rawValue)",
            retention: .evidence
        )
        recordSessionEnd(reason: reason)

        stateLock.withLock {
            snapshotStorage.state = .ended(reason: reason)
            snapshotStorage.diagnostics.queueDepth = 0
        }
        publishSnapshot()
    }

    private func recordSessionEnd(reason: String) {
        let alreadyRecorded = stateLock.withLock {
            if sessionEndRecorded { return true }
            sessionEndRecorded = true
            return false
        }
        guard !alreadyRecorded else { return }
        StreamSessionProbes.record(
            "session end session=\(sessionID.rawValue) reason=\(reason)",
            retention: .evidence
        )
    }

    private func handleVideoSample(_ sample: CMSampleBuffer) {
        guard videoSampleDeliveryIsOpen else {
            noteFrameAwaitingSurface()
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let ptsUs = max(0, Int64((pts.seconds * 1_000_000).rounded()))

        videoQueueLock.withLock {
            pendingVideo.append((sample, ptsUs))
        }
        stateLock.withLock {
            if !firstVideoPTS.isValid {
                firstVideoPTS = pts
            }
        }
        reportQueueDepthIfNeeded()
        pumpVideoQueue()
    }

    private func observeReadiness() {
        ensurePumpScheduled()
    }

    private func ensurePumpScheduled() {
        deliverQueue.async { [weak self] in
            guard let self, !self.pumpActive else { return }
            self.pumpActive = true
            let timer = DispatchSource.makeTimerSource(queue: self.deliverQueue)
            timer.schedule(
                deadline: .now() + .milliseconds(4),
                repeating: .milliseconds(4),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let empty = self.videoQueueLock.withLock { self.pendingVideo.isEmpty }
                if empty {
                    self.pumpTimer?.cancel()
                    self.pumpTimer = nil
                    self.pumpActive = false
                    return
                }
                self.pumpVideoQueue()
            }
            self.pumpTimer = timer
            timer.resume()
        }
    }

    private func cancelPumpTimer() {
        deliverQueue.async { [weak self] in
            self?.pumpTimer?.cancel()
            self?.pumpTimer = nil
            self?.pumpActive = false
        }
    }

    private func observeRenderingEvents() {
        guard !renderingEventObservationActive else { return }
        renderingEventObservationActive = true
        videoSink.observeRenderingEventsAfterFinishedEnqueuing { [weak self] fact in
            switch fact {
            case .failure:
                self?.recoverFromRendererFailure(reason: "renderer failure event")
            case .warning:
                break
            }
        }
    }

    private func stopRenderingEventObservation() {
        renderingEventObservationActive = false
        videoSink.stopRenderingEventObservation()
    }

    private static let surfaceBindingGrace: TimeInterval = 5

    private var videoSampleDeliveryIsOpen: Bool {
        stateLock.withLock {
            if surfaceBindingRevision != nil {
                return true
            }
            guard !surfaceHasBound, let videoDeliveryStartedAt else { return false }
            return Date().timeIntervalSince(videoDeliveryStartedAt)
                >= Self.surfaceBindingGrace
        }
    }

    private func noteFrameAwaitingSurface() {
        let report: (dropped: Int64, due: Bool) = stateLock.withLock {
            counters.framesAwaitingSurface += 1
            let dropped = counters.framesAwaitingSurface
            let now = Date()
            let due = dropped == 1
                || now.timeIntervalSince(lastAwaitingSurfaceReport) >= 1
            if due {
                lastAwaitingSurfaceReport = now
            }
            return (dropped, due)
        }
        guard report.due else { return }
        StreamSessionProbes.record(
            "frame awaiting surface session=\(sessionID.rawValue) dropped=\(report.dropped)",
            retention: .evidence
        )
    }

    /// The window surface reports which renderer graph revision it has bound,
    /// so video delivery can wait for a target that can consume frames; a
    /// renderer without a target drops every sample it is fed.
    public func videoSurfaceDidBind(revision: Int) {
        var firstBind = false
        let counts: (awaitingSurface: Int64, enqueuedWithoutSurface: Int64) =
            stateLock.withLock {
                firstBind = !surfaceHasBound
                surfaceHasBound = true
                surfaceBindingRevision = revision
                return (
                    counters.framesAwaitingSurface,
                    counters.framesEnqueuedWithoutSurface
                )
            }
        let droppedBacklog = videoQueueLock.withLock { () -> Int in
            let count = pendingVideo.count
            pendingVideo.removeAll()
            return count
        }
        StreamSessionProbes.record(
            "video surface bind session=\(sessionID.rawValue) revision=\(revision)"
                + " firstBind=\(firstBind)"
                + " droppedBacklog=\(droppedBacklog)"
                + " framesAwaitingSurface=\(counts.awaitingSurface)"
                + " framesEnqueuedWithoutSurface=\(counts.enqueuedWithoutSurface)",
            retention: .evidence
        )
        requestIdrFrame(reason: "surfaceBound")
    }

    public func videoSurfaceDidUnbind(revision: Int) {
        let wasBound: Bool = stateLock.withLock {
            guard surfaceBindingRevision == revision else { return false }
            surfaceBindingRevision = nil
            return true
        }
        guard wasBound else { return }
        StreamSessionProbes.record(
            "video surface unbind session=\(sessionID.rawValue) revision=\(revision)",
            retention: .evidence
        )
    }

    private func pumpVideoQueue() {
        while true {
            videoQueueLock.lock()
            guard let head = pendingVideo.first else {
                videoQueueLock.unlock()
                return
            }
            if options.framePacing && videoSinkAcceptsHold(pendingCount: pendingVideo.count) {
                videoQueueLock.unlock()
                return
            }
            videoQueueLock.unlock()

            guard videoRenderer.isReadyForMoreMediaData else {
                ensurePumpScheduled()
                return
            }

            let outcome: RendererEnqueueOutcome
            do {
                outcome = try videoSink.enqueueImmediately(
                    RendererInputSample(sampleBuffer: head.sample)
                )
            } catch {
                recoverFromRendererFailure(reason: "enqueue threw")
                return
            }

            switch outcome {
            case .accepted, .acceptedWithWarnings:
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
                stateLock.withLock {
                    counters.presented += 1
                    counters.lastPresentedTimestampMs = head.presentationTimeUs / 1000
                    if surfaceBindingRevision == nil {
                        counters.framesEnqueuedWithoutSurface += 1
                    }
                    snapshotStorage.diagnostics.framesPresented = counters.presented
                    snapshotStorage.diagnostics.lastPresentedTimestampMs = counters.lastPresentedTimestampMs
                    snapshotStorage.diagnostics.duplicatedFrames = counters.duplicatedFrames
                }
                reportQueueDepthIfNeeded()
            case .cancelledByFlush:
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
            case .requiresFlush, .failed:
                recoverFromRendererFailure(reason: "enqueue outcome \(outcome)")
                return
            }
        }
    }

    private func videoSinkAcceptsHold(pendingCount: Int) -> Bool {
        pendingCount <= 1
    }

    private func reportQueueDepthIfNeeded() {
        let depth = videoQueueLock.withLock { pendingVideo.count }
        stateLock.withLock {
            snapshotStorage.diagnostics.queueDepth = depth
        }
        let crossed = abs(depth - lastReportedQueueDepth) >= 8
        if crossed || (depth == 0 && lastReportedQueueDepth > 0) {
            lastReportedQueueDepth = depth
            StreamSessionProbes.record("frame queue depth session=\(sessionID.rawValue) depth=\(depth)")
        }
        let overflow = depth > 48
        if overflow {
            recoverFromRendererFailure(reason: "frame queue overflow depth=\(depth)")
        }
    }

    private func recoverFromRendererFailure(reason: String) {
        stateLock.withLock {
            counters.decodeRecoveries += 1
            snapshotStorage.diagnostics.decodeRecoveries = counters.decodeRecoveries
        }
        _ = rebuildRendererGraph(reason: reason)
    }

    /// Replaces the renderer graph and returns the renderer the session now
    /// feeds. The caller is either a failure recovery or a presentation root the
    /// current graph cannot follow. The departing graph keeps its last
    /// presentation and leaves the synchronizer afterwards.
    @discardableResult
    public func rebuildRendererGraph(reason: String) -> AVSampleBufferVideoRenderer {
        let departing = videoQueueLock.withLock { () -> AVSampleBufferVideoRenderer? in
            guard recoveringFromRendererFailure == false else { return nil }
            recoveringFromRendererFailure = true
            pendingVideo.removeAll()
            return videoRenderer
        }
        guard let departing else { return videoRenderer }

        let surfaceWasBound = stateLock.withLock { () -> Bool in
            let bound = surfaceBindingRevision != nil
            surfaceBindingRevision = nil
            return bound
        }
        StreamSessionProbes.record(
            "renderer rebuild session=\(sessionID.rawValue) reason=\(reason)"
                + " surfaceWasBound=\(surfaceWasBound)",
            retention: .evidence
        )

        let replacement = AVSampleBufferVideoRenderer()
        stopRenderingEventObservation()

        videoRenderer = replacement
        videoSink = AVSampleBufferRendererInputSink(
            receiver: synchronizer.sampleBufferReceiver(adding: replacement)
        )
        graphVersion += 1
        observeRenderingEvents()

        let newBinding = binding
        deliverQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.synchronizer.removeRenderer(departing, at: self.synchronizer.currentTime())
        }
        onBindingChange?(newBinding)

        requestIdrFrame(reason: "rendererRebuild")
        videoQueueLock.withLock {
            recoveringFromRendererFailure = false
        }
        publishSnapshot()
        return replacement
    }

    private func handleAudioFrame(_ frame: BackendAudioFrame) {
        let received: Int64 = stateLock.withLock {
            counters.audioFramesReceived += 1
            return counters.audioFramesReceived
        }
        if received == 1 {
            StreamSessionProbes.record(
                "audio frames begin session=\(sessionID.rawValue) rate=\(frame.sampleRate) channels=\(frame.channels)",
                retention: .evidence
            )
        }
        guard audioRenderer.isReadyForMoreMediaData else {
            let dropped: Int64 = stateLock.withLock {
                counters.audioFramesDropped += 1
                return counters.audioFramesDropped
            }
            if dropped == 25 || dropped % 500 == 0 {
                StreamSessionProbes.record(
                    "audio backpressure session=\(sessionID.rawValue) dropped=\(dropped) ready=false",
                    retention: .evidence
                )
            }
            return
        }

        let channels = frame.channels
        let sampleRate = frame.sampleRate
        let frameDuration = Double(frame.frameCount) / Double(sampleRate)

        stateLock.withLock {
            audioFrameDurationSeconds = frameDuration
        }

        let key = "\(sampleRate)/\(channels)"
        if audioFormatKey != key || audioFormatDescription == nil {
            audioFormatDescription = Self.makeLPCMFormatDescription(
                sampleRate: Double(sampleRate),
                channels: UInt32(channels)
            )
            audioFormatKey = key
        }
        guard let formatDescription = audioFormatDescription else { return }

        let pts: CMTime
        var resolvedPTS: CMTime = .invalid
        stateLock.withLock {
            if !nextAudioPTS.isValid {
                let current = synchronizer.currentTime()
                var anchor = firstVideoPTS.isValid ? firstVideoPTS : current
                anchor = CMTimeMaximum(anchor, current)
                nextAudioPTS = CMTimeAdd(anchor, CMTimeMakeWithSeconds(frameDuration * 2, preferredTimescale: 1_000_000))
            }
            resolvedPTS = nextAudioPTS
            nextAudioPTS = CMTimeAdd(nextAudioPTS, CMTimeMakeWithSeconds(frameDuration, preferredTimescale: 1_000_000))
        }

        guard let sample = Self.makeAudioSampleBuffer(
            frame: frame,
            formatDescription: formatDescription,
            presentationTime: resolvedPTS,
            duration: CMTimeMakeWithSeconds(frameDuration, preferredTimescale: 1_000_000)
        ) else {
            return
        }

        do {
            let outcome = try audioSink.enqueueImmediately(RendererInputSample(sampleBuffer: sample))
            switch outcome {
            case .accepted, .acceptedWithWarnings:
                let enqueued: Int64 = stateLock.withLock {
                    counters.audioFramesEnqueued += 1
                    return counters.audioFramesEnqueued
                }
                if enqueued == 1 {
                    StreamSessionProbes.record(
                        "audio enqueue begins session=\(sessionID.rawValue)",
                        retention: .evidence
                    )
                }
            default:
                stateLock.withLock { counters.audioFramesDropped += 1 }
            }
        } catch {
            stateLock.withLock { counters.audioFramesDropped += 1 }
        }
    }

    private static func makeLPCMFormatDescription(sampleRate: Double, channels: UInt32) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeEndian
                | kAudioFormatFlagIsSignedInteger
                | kAudioFormatFlagIsPacked,
            mBytesPerPacket: channels * 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: channels * 2,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr else { return nil }
        return formatDescription
    }

    private static func makeAudioSampleBuffer(
        frame: BackendAudioFrame,
        formatDescription: CMAudioFormatDescription,
        presentationTime: CMTime,
        duration: CMTime
    ) -> CMSampleBuffer? {
        let byteCount = frame.pcm.count
        guard byteCount > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else { return nil }

        let copied = frame.pcm.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard copied == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    private func handleEvent(_ event: BackendSessionEvent) {
        switch event {
        case .stage(let name, let phase):
            switch phase {
            case .starting:
                stateLock.withLock {
                    if case .ended = snapshotStorage.state {} else {
                        snapshotStorage.state = .connecting(stage: name)
                    }
                }
            case .complete, .failed:
                break
            }
            publishSnapshot()
        case .connected:
            stateLock.withLock {
                snapshotStorage.state = .connecting(stage: "connected")
            }
            publishSnapshot()
        case .firstFramePresented:
            stateLock.withLock {
                if case .connecting = snapshotStorage.state {
                    snapshotStorage.state = .streaming
                }
            }
            publishSnapshot()
        case .decoderConfigured(let width, let height, let frameRate, let codec):
            stateLock.withLock {
                let codecValue = StreamVideoCodec(rawValue: codec) ?? .h264
                snapshotStorage.negotiated = NegotiatedStreamConfiguration(
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    bitrateKbps: options.bitrateKbps,
                    codec: codecValue,
                    hostHdrActive: snapshotStorage.negotiated?.hostHdrActive
                        ?? snapshotStorage.hdrModeReported,
                    audioChannels: snapshotStorage.negotiated?.audioChannels ?? 2
                )
                snapshotStorage.adjustments = Self.adjustments(
                    requested: options,
                    negotiated: snapshotStorage.negotiated
                )
            }
            publishSnapshot()
        case .hdrMode(let active):
            stateLock.withLock {
                snapshotStorage.hdrModeReported = active
                if var negotiated = snapshotStorage.negotiated {
                    negotiated.hostHdrActive = active
                    snapshotStorage.negotiated = negotiated
                    snapshotStorage.adjustments = Self.adjustments(
                        requested: options,
                        negotiated: negotiated
                    )
                }
            }
            publishSnapshot()
        case .audioStarted(let sampleRate, let channels, _):
            StreamSessionProbes.record(
                "audio start session=\(sessionID.rawValue) rate=\(sampleRate) channels=\(channels)",
                retention: .evidence
            )
            stateLock.withLock {
                snapshotStorage.diagnostics.clientAudioOutput = true
                if var negotiated = snapshotStorage.negotiated {
                    negotiated.audioChannels = Int(channels)
                    snapshotStorage.negotiated = negotiated
                }
            }
            publishSnapshot()
        case .audioStopped:
            StreamSessionProbes.record("audio stop session=\(sessionID.rawValue)", retention: .evidence)
            publishSnapshot()
        case .statusUpdate:
            publishSnapshot()
        case .launchFailed(let message):
            fail(stage: .launch, kind: .applicationLaunchFailed, message: message, recovery: .retry)
        case .terminated(let errorCode):
            if errorCode == 0 {
                finishTeardown(reason: "remote")
            } else {
                fail(
                    stage: .network,
                    kind: .connectionLost,
                    message: "连接中断（代码 \(errorCode)）",
                    recovery: .reconnect
                )
            }
        }
    }

    private func fail(
        stage: StreamFailureStage,
        kind: StreamFailureKind,
        message: String,
        recovery: StreamRecoveryAction,
        upstreamDetail: String? = nil
    ) {
        let failure = StreamFailure(
            stage: stage,
            kind: kind,
            message: message,
            recovery: recovery,
            upstreamDetail: upstreamDetail
        )
        stateLock.withLock {
            snapshotStorage.failure = failure
            snapshotStorage.state = .interrupted(reason: message)
        }
        publishSnapshot()
    }

    private func startDiagnosticsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: deliverQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.sampleDiagnostics()
        }
        diagnosticsTimer = timer
        timer.resume()
    }

    private func sampleDiagnostics() {
        let stats = backend.videoStats()
        let rtt = backend.estimatedRTT()
        stateLock.withLock {
            if let stats {
                counters.packetsReceived = Int64(stats.receivedFrames)
                counters.networkDroppedFrames = Int64(stats.networkDroppedFrames)
                snapshotStorage.diagnostics.packetsReceived = counters.packetsReceived
                snapshotStorage.diagnostics.networkDroppedFrames = counters.networkDroppedFrames
            }
            if let rtt {
                snapshotStorage.diagnostics.estimatedRttMs = Int(rtt.milliseconds)
                snapshotStorage.diagnostics.estimatedRttVarianceMs = Int(rtt.variance)
            }
            snapshotStorage.diagnostics.decodeRecoveries = counters.decodeRecoveries
            snapshotStorage.diagnostics.idrRequests = counters.idrRequests
            snapshotStorage.diagnostics.audioFramesReceived = counters.audioFramesReceived
            snapshotStorage.diagnostics.audioFramesEnqueued = counters.audioFramesEnqueued
            snapshotStorage.diagnostics.audioFramesDropped = counters.audioFramesDropped
            snapshotStorage.input.mouseEventsSent = counters.mouseEvents
            snapshotStorage.input.scrollEventsSent = counters.scrollEvents
            snapshotStorage.input.keyboardEventsSent = counters.keyboardEvents
            snapshotStorage.input.pressedKeyCount = pressedKeys.count
            snapshotStorage.input.pressedButtonCount = pressedButtons.count
        }
        publishSnapshot()
    }

    private func publishSnapshot() {
        let copy = stateLock.withLock { snapshotStorage }
        onSnapshot?(copy)
    }

    public func sendMousePosition(normalizedX: Float, normalizedY: Float) {
        backend.sendMousePosition(normalizedX: normalizedX, normalizedY: normalizedY)
        stateLock.withLock { counters.mouseEvents += 1 }
    }

    public func sendMouseMove(dx: Int32, dy: Int32) {
        backend.sendMouseMove(dx: dx, dy: dy)
        stateLock.withLock { counters.mouseEvents += 1 }
    }

    public func sendMouseButton(code: Int32, down: Bool) {
        backend.sendMouseButton(code: code, down: down)
        stateLock.withLock {
            if down {
                pressedButtons.insert(code)
            } else {
                pressedButtons.remove(code)
            }
            counters.mouseEvents += 1
        }
    }

    public func sendScroll(amount: Int32) {
        backend.sendScroll(amount: amount)
        stateLock.withLock { counters.scrollEvents += 1 }
    }

    public func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {
        backend.sendKey(hidUsage: hidUsage, down: down, modifierFlags: modifierFlags)
        stateLock.withLock {
            if down {
                pressedKeys.insert(hidUsage)
            } else {
                pressedKeys.remove(hidUsage)
            }
            counters.keyboardEvents += 1
        }
    }

    public func releaseAllInput(cause: String) {
        backend.releaseAllInput()
        clearPressed()
        StreamSessionProbes.record(
            "input release session=\(sessionID.rawValue) cause=\(cause)",
            retention: .evidence
        )
        publishSnapshot()
    }

    private func clearPressed() {
        stateLock.withLock {
            pressedKeys.removeAll()
            pressedButtons.removeAll()
            snapshotStorage.input.pressedKeyCount = 0
            snapshotStorage.input.pressedButtonCount = 0
        }
    }

    public func requestIdrFrame(reason: String) {
        stateLock.withLock { counters.idrRequests += 1 }
        backend.requestIdrFrame()
        StreamSessionProbes.record("keyframe request session=\(sessionID.rawValue) reason=\(reason)")
    }

    private static func adjustments(
        requested: StreamOptions,
        negotiated: NegotiatedStreamConfiguration?
    ) -> [StreamAdjustmentNotice] {
        guard let negotiated else { return [] }
        var notices: [StreamAdjustmentNotice] = []

        if requested.hdrEnabled && !negotiated.hostHdrActive {
            notices.append(StreamAdjustmentNotice(
                summary: "主机当前输出 SDR",
                detail: "已请求 HDR，但主机没有提供 HDR 视频信号；画面按 SDR 解释。"
            ))
        }

        if requested.resolution.width != negotiated.width || requested.resolution.height != negotiated.height {
            notices.append(StreamAdjustmentNotice(
                summary: "分辨率与请求不一致",
                detail: "请求 \(requested.resolution.width)×\(requested.resolution.height)，实际 \(negotiated.width)×\(negotiated.height)。"
            ))
        }

        return notices
    }
}
