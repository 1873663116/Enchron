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
    private let audioSessionQueryQueue = DispatchQueue(label: "app.enchron.stream-session.audio-session")
    private let audioSessionCacheLock = NSLock()
    private var audioSessionCache: (volume: Float, channels: Int, route: String, category: String) =
        (1, 2, "none", "playback")
    private var diagnosticsTimer: DispatchSourceTimer?

    public var onSnapshot: (@Sendable (SessionSnapshot) -> Void)?
    public var onBindingChange: (@Sendable (StreamRenderBinding) -> Void)?

    private var synchronizer = AVSampleBufferRenderSynchronizer()
    private var videoRenderer = AVSampleBufferVideoRenderer()
    private var videoSink: AVSampleBufferRendererInputSink
    private let audioOutput = StreamAudioOutput()
    private var pumpTimer: DispatchSourceTimer?
    private var pumpActive = false
    private var lastPumpTickNanoseconds: UInt64 = 0
    private var maxPumpGapMilliseconds: Double = 0
    private var renderingEventObservationActive = false
    private var graphVersion = 1

    private let videoQueueLock = NSLock()
    private struct PendingVideoFrame {
        let id: UInt64
        let sample: CMSampleBuffer
        let presentationTimeUs: Int64
        let arrivalDate: Date
    }

    private func removePendingFrame(id: UInt64) {
        videoQueueLock.withLock {
            if let index = pendingVideo.firstIndex(where: { $0.id == id }) {
                pendingVideo.remove(at: index)
            }
        }
    }

    private var pendingVideo: [PendingVideoFrame] = []
    private var pendingFrameSequence: UInt64 = 0
    private static let pendingVideoLimit = 8
    private static let pendingVideoKeep = 2
    private var recoveringFromRendererFailure = false
    private var lastReportedQueueDepth = 0
    private var lastSampledPresentedCount: Int64 = 0
    private var lastSampledVideoBytes: Int64 = 0
    private var lastSampledVideoOutcomes: (warnings: Int64, flush: Int64, requiresFlush: Int64, failed: Int64, decodeWarnings: Int64) = (0, 0, 0, 0, 0)
    private var lastSampledReceivedFrames: Int64 = 0
    private var requestedFrameRate = 0
    private var lowDeliverySeconds = 0
    private var streamingStableSeconds = 0
    private var didSignalHostFrameRateMismatch = false
    public var onHostFrameRateMismatch: (@Sendable () -> Void)?
    private var lastSampledAudioOutcomes: (short: Int64, long: Int64, other: Int64, underruns: Int64, overflowFrames: Int64) = (0, 0, 0, 0, 0)
    private var lastVideoSampleNanoseconds: UInt64 = 0
    private var lastVideoPresentationSeconds: Double = 0
    private var lastAudioFrameNanoseconds: UInt64 = 0
    private var lastSampledGaps: (decoded: Int64, videoGap: Int64, audioGap: Int64, ptsGap: Int64) = (0, 0, 0, 0)
    private var flushingRenderer = false
    private var lastCancelledByFlushIdrAt = Date.distantPast
    private var decodeFailureStreak = 0
    private var lastDecodeFailureAt = Date.distantPast
    private var decodeFailureIdrRequested = false
    private var decodeFailureRebuildRequested = false

    private enum DecodeFailureEscalation {
        case none
        case requestIdr
        case rebuild
    }
    private var videoDeliveryStartedAt: Date?
    private var surfaceBindingRevision: Int?
    private var surfaceHasBound = false
    private var lastAwaitingSurfaceReport = Date.distantPast

    private var frameBufferHoldSeconds: Double {
        1.5 / Double(max(options.frameRate, 1))
    }

    private var videoStatsTimer: DispatchSourceTimer?
    private var terminatedFallback: DispatchWorkItem?

    private var counters = Counters()
    private let gamepadInput = StreamGamepadInput()
    private let mouseInput = StreamMouseInput()
    private var controllerFlags: Int32 = 0

    private struct Counters {
        var presented: Int64 = 0
        var lastPresentedTimestampMs: Int64?
        var decodeRecoveries: Int64 = 0
        var idrRequests: Int64 = 0
        var packetsReceived: Int64 = 0
        var networkDroppedFrames: Int64 = 0
        var duplicatedFrames: Int64 = 0
        var audioFramesReceived: Int64 = 0
        var audioPeakAbs: Int32 = 0
        var audioFramesEnqueued: Int64 = 0
        var audioFramesDropped: Int64 = 0
        var framesAwaitingSurface: Int64 = 0
        var framesEnqueuedWithoutSurface: Int64 = 0
        var videoBytes: Int64 = 0
        var videoEnqueueWarnings: Int64 = 0
        var videoEnqueueCancelledByFlush: Int64 = 0
        var videoEnqueueRequiresFlush: Int64 = 0
        var videoEnqueueFailed: Int64 = 0
        var videoDecodeWarnings: Int64 = 0
        var audioFramesShort: Int64 = 0
        var audioFramesLong: Int64 = 0
        var audioFramesOther: Int64 = 0
        var videoFramesDecoded: Int64 = 0
        var videoGapCount: Int64 = 0
        var videoGapMaxMilliseconds: Double = 0
        var staleFramesDropped: Int64 = 0
        var framesHeldByBuffer: Int64 = 0
        var bufferHoldMaxMilliseconds: Double = 0
        var videoPTSGapCount: Int64 = 0
        var videoPTSGapMaxMilliseconds: Double = 0
        var audioGapCount: Int64 = 0
        var audioGapMaxMilliseconds: Double = 0
        var mouseEvents: Int64 = 0
        var scrollEvents: Int64 = 0
        var keyboardEvents: Int64 = 0
        var gamepadEvents: Int64 = 0
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

        publishActivity(.launching)
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

        stateLock.withLock {
            snapshotStorage.diagnostics.hostAudioPlaying = options.playAudioOnPC
            snapshotStorage.diagnostics.clientAudioOutput = options.playsAudioLocally
        }
        let probeSessionID = sessionID
        audioOutput.onEvent = { message in
            StreamSessionProbes.record("\(message) session=\(probeSessionID.rawValue)", retention: .evidence)
        }
        backend.controllerFeedbackHandler = { [weak self] feedback in
            self?.gamepadInput.handle(feedback)
        }
        gamepadInput.configureFeedback(
            sendMotion: { [weak self] controllerNumber, motionType, x, y, z in
                self?.backend.sendControllerMotion(
                    controllerNumber: controllerNumber,
                    motionType: motionType,
                    x: x,
                    y: y,
                    z: z
                )
            },
            sendBattery: { [weak self] controllerNumber, state, percentage in
                self?.backend.sendControllerBattery(
                    controllerNumber: controllerNumber,
                    state: state,
                    percentage: percentage
                )
            }
        )
        gamepadInput.start(
            onState: { [weak self] state in self?.sendGamepad(state) },
            onProfile: { [weak self] arrival in self?.handleControllerProfile(arrival) },
            onTouch: { [weak self] eventType, pointerId, x, y, pressure in
                self?.backend.sendControllerTouch(
                    controllerNumber: 0,
                    eventType: eventType,
                    pointerId: pointerId,
                    x: x,
                    y: y,
                    pressure: pressure
                )
            }
        )
        Task { @MainActor in StreamInputCapture.shared.start() }
        mouseInput.start(
            trackingMode: options.mouseTrackingMode,
            streamWidth: options.streamWidth,
            streamHeight: options.streamHeight,
            onMove: { [weak self] dx, dy in self?.sendMouseMove(dx: dx, dy: dy) },
            onPosition: { [weak self] x, y in
                self?.sendMousePosition(normalizedX: x, normalizedY: y)
            },
            onButton: { [weak self] code, down in self?.sendMouseButton(code: code, down: down) },
            onHighResScroll: { [weak self] vertical, horizontal in
                self?.backend.sendHighResScroll(vertical: Int16(clamping: vertical),
                                                horizontal: Int16(clamping: horizontal))
            },
            onPresence: { [weak self] attached in self?.handleMousePresence(attached) }
        )
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
        gamepadInput.stop()
        mouseInput.stop()
        Task { @MainActor in StreamInputCapture.shared.stop() }
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
        audioOutput.stop()

        videoQueueLock.withLock {
            pendingVideo.removeAll()
        }

        synchronizer.setRate(0, time: synchronizer.currentTime())
        synchronizer.removeRenderer(videoRenderer, at: synchronizer.currentTime())

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
        let sampleBytes = CMSampleBufferGetDataBuffer(sample).map {
            Int64(CMBlockBufferGetDataLength($0))
        } ?? Int64(CMSampleBufferGetTotalSampleSize(sample))
        stateLock.withLock {
            counters.videoBytes &+= max(0, sampleBytes)
        }
        guard videoSampleDeliveryIsOpen else {
            noteFrameAwaitingSurface()
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let ptsUs = max(0, Int64((pts.seconds * 1_000_000).rounded()))

        videoQueueLock.withLock {
            pendingFrameSequence &+= 1
            pendingVideo.append(
                PendingVideoFrame(
                    id: pendingFrameSequence,
                    sample: sample,
                    presentationTimeUs: ptsUs,
                    arrivalDate: Date()
                )
            )
        }
        let sampleTime = DispatchTime.now().uptimeNanoseconds
        stateLock.withLock {
            counters.videoFramesDecoded += 1
            let ptsSeconds = pts.seconds
            if lastVideoPresentationSeconds > 0 {
                let ptsGapMs = (ptsSeconds - lastVideoPresentationSeconds) * 1000
                let nominalMs = 1000.0 / Double(max(options.frameRate, 1))
                if ptsGapMs > nominalMs * 1.5 {
                    counters.videoPTSGapCount += 1
                    if ptsGapMs > counters.videoPTSGapMaxMilliseconds {
                        counters.videoPTSGapMaxMilliseconds = ptsGapMs
                    }
                }
            }
            lastVideoPresentationSeconds = ptsSeconds
            if lastVideoSampleNanoseconds != 0 {
                let gapMs = Double(sampleTime - lastVideoSampleNanoseconds) / 1_000_000
                if gapMs > 50 {
                    counters.videoGapCount += 1
                    if gapMs > counters.videoGapMaxMilliseconds {
                        counters.videoGapMaxMilliseconds = gapMs
                    }
                }
            }
            lastVideoSampleNanoseconds = sampleTime
        }
        reportQueueDepthIfNeeded()
        deliverQueue.async { [weak self] in
            self?.pumpVideoQueue()
        }
    }

    private func observeReadiness() {
        ensurePumpScheduled()
    }

    private func ensurePumpScheduled() {
        deliverQueue.async { [weak self] in
            guard let self, !self.pumpActive else { return }
            self.pumpActive = true
            let timer = DispatchSource.makeTimerSource(queue: self.deliverQueue)
            self.lastPumpTickNanoseconds = 0
            timer.schedule(
                deadline: .now() + .milliseconds(4),
                repeating: .milliseconds(4),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                if self.lastPumpTickNanoseconds != 0 {
                    let gapMs = Double(now - self.lastPumpTickNanoseconds) / 1_000_000
                    if gapMs > self.maxPumpGapMilliseconds {
                        self.maxPumpGapMilliseconds = gapMs
                    }
                }
                self.lastPumpTickNanoseconds = now
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
            guard let self else { return }
            switch fact {
            case .failure:
                self.recoverFromRendererFailure(reason: "renderer failure event")
            case .warning(_, let message):
                let now = Date()
                let count: Int64 = self.stateLock.withLock {
                    self.counters.videoDecodeWarnings += 1
                    if now.timeIntervalSince(self.lastDecodeFailureAt) > 1 {
                        self.decodeFailureStreak = 0
                        self.decodeFailureIdrRequested = false
                        self.decodeFailureRebuildRequested = false
                    }
                    self.lastDecodeFailureAt = now
                    self.decodeFailureStreak += 1
                    return self.counters.videoDecodeWarnings
                }
                if count <= 5 || count % 100 == 0 {
                    StreamSessionProbes.record(
                        "video decode warning session=\(self.sessionID.rawValue)"
                            + " count=\(count) message=\(message)",
                        retention: .evidence
                    )
                }
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
        publishActivity(.requestingKeyframe)
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
            if options.frameBuffer,
               pendingVideo.count <= 1,
               Date().timeIntervalSince(head.arrivalDate) < frameBufferHoldSeconds {
                videoQueueLock.unlock()
                stateLock.withLock {
                    counters.framesHeldByBuffer += 1
                    let held = Date().timeIntervalSince(head.arrivalDate) * 1000
                    if held > counters.bufferHoldMaxMilliseconds {
                        counters.bufferHoldMaxMilliseconds = held
                    }
                }
                ensurePumpScheduled()
                return
            }
            videoQueueLock.unlock()

            guard videoRenderer.isReadyForMoreMediaData else {
                if synchronizer.rate == 0 {
                    rearmSynchronizerIfStalled()
                }
                ensurePumpScheduled()
                return
            }

            let sampleToEnqueue = Self.immediateTimingSample(
                head.sample,
                presentationTime: synchronizer.currentTime()
            ) ?? head.sample
            let outcome: RendererEnqueueOutcome
            do {
                outcome = try videoSink.enqueueImmediately(
                    RendererInputSample(sampleBuffer: sampleToEnqueue)
                )
            } catch {
                recoverFromRendererFailure(reason: "enqueue threw")
                return
            }

            switch outcome {
            case .accepted:
                removePendingFrame(id: head.id)
                publishActivity(.streaming)
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
            case .acceptedWithWarnings:
                removePendingFrame(id: head.id)
                stateLock.withLock {
                    counters.presented += 1
                    counters.videoEnqueueWarnings += 1
                    counters.lastPresentedTimestampMs = head.presentationTimeUs / 1000
                }
                reportQueueDepthIfNeeded()
            case .cancelledByFlush:
                removePendingFrame(id: head.id)
                let flushDrop: (count: Int64, shouldRequestIDR: Bool) = stateLock.withLock {
                    counters.videoEnqueueCancelledByFlush += 1
                    let now = Date()
                    let shouldRequest = now.timeIntervalSince(lastCancelledByFlushIdrAt) >= 0.5
                    if shouldRequest {
                        lastCancelledByFlushIdrAt = now
                    }
                    return (counters.videoEnqueueCancelledByFlush, shouldRequest)
                }
                if flushDrop.count <= 5 || flushDrop.count % 100 == 0 {
                    StreamSessionProbes.record(
                        "video enqueue cancelled by flush session=\(sessionID.rawValue)"
                            + " count=\(flushDrop.count)",
                        retention: .evidence
                    )
                }
                if flushDrop.shouldRequestIDR {
                    requestIdrFrame(reason: "cancelledByFlush")
                }
            case .requiresFlush:
                stateLock.withLock { counters.videoEnqueueRequiresFlush += 1 }
                recoverFromFlushRequirement(reason: "enqueue outcome \(outcome)")
                return
            case .failed:
                stateLock.withLock { counters.videoEnqueueFailed += 1 }
                recoverFromRendererFailure(reason: "enqueue outcome \(outcome)")
                return
            }
        }
    }

    private static func immediateTimingSample(
        _ sample: CMSampleBuffer,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        guard status == noErr else { return nil }
        return copy
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
        guard depth > Self.pendingVideoLimit else { return }
        let dropped: Int = videoQueueLock.withLock {
            let excess = pendingVideo.count - Self.pendingVideoKeep
            guard excess > 0 else { return 0 }
            pendingVideo.removeFirst(excess)
            return excess
        }
        guard dropped > 0 else { return }
        stateLock.withLock { counters.staleFramesDropped += Int64(dropped) }
        StreamSessionProbes.record(
            "frame queue shed session=\(sessionID.rawValue) dropped=\(dropped) depth=\(depth)",
            retention: .evidence
        )
    }

    private func recoverFromFlushRequirement(reason: String) {
        let alreadyFlushing = videoQueueLock.withLock { () -> Bool in
            if flushingRenderer { return true }
            flushingRenderer = true
            pendingVideo.removeAll()
            return false
        }
        guard !alreadyFlushing else { return }
        StreamSessionProbes.record(
            "renderer flush session=\(sessionID.rawValue) reason=\(reason)",
            retention: .evidence
        )
        requestIdrFrame(reason: "flushRequired")
        Task { [weak self] in
            guard let self else { return }
            await self.videoSink.flush(removingDisplayedImage: false)
            self.videoQueueLock.withLock {
                self.flushingRenderer = false
            }
            self.ensurePumpScheduled()
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
        let presentedAtRebuild = stateLock.withLock { counters.presented }
        deliverQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let presented = self.stateLock.withLock { self.counters.presented }
            guard presented == presentedAtRebuild else { return }
            guard self.videoSampleDeliveryIsOpen else { return }
            StreamSessionProbes.record(
                "renderer rebuild stalled session=\(self.sessionID.rawValue)"
                    + " reason=\(reason)"
                    + " presented=\(presented)",
                retention: .evidence
            )
            self.requestIdrFrame(reason: "rebuildStalled")
        }
        publishSnapshot()
        return replacement
    }

    private func handleAudioFrame(_ frame: BackendAudioFrame) {
        let received: Int64 = stateLock.withLock {
            counters.audioFramesReceived += 1
            let frameTime = DispatchTime.now().uptimeNanoseconds
            if lastAudioFrameNanoseconds != 0 {
                let gapMs = Double(frameTime - lastAudioFrameNanoseconds) / 1_000_000
                if gapMs > 50 {
                    counters.audioGapCount += 1
                    if gapMs > counters.audioGapMaxMilliseconds {
                        counters.audioGapMaxMilliseconds = gapMs
                    }
                }
            }
            lastAudioFrameNanoseconds = frameTime
            switch frame.frameCount {
            case 240: counters.audioFramesShort += 1
            case 480: counters.audioFramesLong += 1
            default: counters.audioFramesOther += 1
            }
            var peak: Int32 = 0
            frame.pcm.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for value in samples {
                    let magnitude = abs(Int32(value))
                    if magnitude > peak { peak = magnitude }
                }
            }
            if peak > counters.audioPeakAbs { counters.audioPeakAbs = peak }
            return counters.audioFramesReceived
        }
        if received == 1 {
            StreamSessionProbes.record(
                "audio frames begin session=\(sessionID.rawValue) rate=\(frame.sampleRate) channels=\(frame.channels)",
                retention: .evidence
            )
        }
        if options.playsAudioLocally {
            audioOutput.enqueue(
                pcm: frame.pcm,
                channels: Int(frame.channels),
                sampleRate: Int(frame.sampleRate),
                frameCount: Int(frame.frameCount)
            )
            stateLock.withLock { counters.audioFramesEnqueued += 1 }
        }
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
            DispatchQueue.main.async { [weak self] in
                self?.gamepadInput.resendProfile()
                self?.gamepadInput.reportCurrentBattery()
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
                self.requestedFrameRate = frameRate
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
                snapshotStorage.diagnostics.clientAudioOutput = options.playsAudioLocally
                if var negotiated = snapshotStorage.negotiated {
                    negotiated.audioChannels = Int(channels)
                    snapshotStorage.negotiated = negotiated
                }
            }
            publishSnapshot()
        case .audioStopped:
            StreamSessionProbes.record("audio stop session=\(sessionID.rawValue)", retention: .evidence)
            publishSnapshot()
        case .statusUpdate(let status):
            stateLock.withLock {
                snapshotStorage.diagnostics.connectionQuality = status
            }
            StreamSessionProbes.record(
                "connection quality status=\(status)",
                retention: .evidence
            )
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
                    message: Self.disconnectReason(for: errorCode),
                    recovery: .reconnect,
                    upstreamDetail: "termination code \(errorCode)"
                )
            }
        }
    }

    /// The host closes the session with one of the protocol's termination codes.
    /// Naming the cause turns a bare number into something a player can act on.
    private static func disconnectReason(for errorCode: Int32) -> String {
        switch errorCode {
        case -100: "主机不再发送画面数据"
        case -101: "主机长时间没有新画面"
        case -102: "连接被提前关闭"
        case -103: "受保护内容无法解码"
        case -104: "画面格式转换失败"
        default: "连接中断（代码 \(errorCode)）"
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

    private func rearmSynchronizerIfStalled() {
        let state = stateLock.withLock { snapshotStorage.state }
        guard !isStopped(state), synchronizer.rate == 0 else { return }
        rearmSynchronizer()
    }

    private func rearmSynchronizer() {
        let stalledTime = synchronizer.currentTime()
        synchronizer.setRate(
            1.0,
            time: stalledTime,
            atHostTime: CMClockGetTime(CMClockGetHostTimeClock())
        )
        StreamSessionProbes.record(
            "synchronizer rearm session=\(sessionID.rawValue)"
                + " stalledTime=\(stalledTime.seconds)"
                + " rate=\(synchronizer.rate)",
            retention: .evidence
        )
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

    private func refreshAudioSessionCache() {
        audioSessionQueryQueue.async { [weak self] in
            guard let self else { return }
            let session = AVAudioSession.sharedInstance()
            let cache: (volume: Float, channels: Int, route: String, category: String) = (
                session.outputVolume,
                session.outputNumberOfChannels,
                session.currentRoute.outputs.first?.portType.rawValue ?? "none",
                session.category.rawValue
            )
            self.audioSessionCacheLock.withLock { self.audioSessionCache = cache }
        }
    }

    private func recoverFromSustainedDecodeFailures() {
        let escalation: DecodeFailureEscalation = stateLock.withLock {
            guard decodeFailureStreak >= 12 else { return .none }
            if !decodeFailureIdrRequested {
                decodeFailureIdrRequested = true
                return .requestIdr
            }
            guard decodeFailureStreak >= 30, !decodeFailureRebuildRequested else { return .none }
            decodeFailureRebuildRequested = true
            return .rebuild
        }
        switch escalation {
        case .requestIdr:
            requestIdrFrame(reason: "decodeFailures")
        case .rebuild:
            recoverFromRendererFailure(reason: "sustained decode failures")
        case .none:
            break
        }
    }

    private func sampleDiagnostics() {
        let diagnosticStartedAt = DispatchTime.now().uptimeNanoseconds
        recoverFromSustainedDecodeFailures()
        let stats = backend.videoStats()
        let audioPendingPeakMs = backend.audioPendingPeakMs()
        let rtt = backend.estimatedRTT()
        let pendingDepth = videoQueueLock.withLock { pendingVideo.count }
        let readyForMore = videoRenderer.isReadyForMoreMediaData
        let presentedNow = stateLock.withLock { counters.presented }
        let deliveredThisSample = presentedNow - lastSampledPresentedCount
        lastSampledPresentedCount = presentedNow
        let bytesNow = stateLock.withLock { counters.videoBytes }
        let bytesThisSample = max(0, bytesNow - lastSampledVideoBytes)
        lastSampledVideoBytes = bytesNow
        let measuredBitrateKbps = bytesThisSample * 8 / 1000
        rearmSynchronizerIfStalled()
        let syncRate: Float = synchronizer.rate
        let syncSeconds: Double = synchronizer.currentTime().seconds
        let audioCounters = stateLock.withLock {
            () -> (received: Int64, enqueued: Int64, dropped: Int64, peak: Int32) in
            let values = (
                counters.audioFramesReceived,
                counters.audioFramesEnqueued,
                counters.audioFramesDropped,
                counters.audioPeakAbs
            )
            counters.audioPeakAbs = 0
            return values
        }
        let audioStats = audioOutput.stats()
        refreshAudioSessionCache()
        let audioSessionInfo = audioSessionCacheLock.withLock { audioSessionCache }
        let outVolume: Float = audioSessionInfo.volume
        let outChannels = audioSessionInfo.channels
        let routeName = audioSessionInfo.route
        let audioMessage = "audio pump received=\(audioCounters.received)"
            + " enqueued=\(audioCounters.enqueued)"
            + " dropped=\(audioCounters.dropped)"
            + " peak=\(audioCounters.peak)"
            + " bufferedMs=\(String(format: "%.1f", audioStats.bufferedMilliseconds))"
            + " underruns=\(audioStats.underruns)"
            + " overflowFrames=\(audioStats.overflowFrames)"
            + " trimmedFrames=\(audioStats.trimmedFrames)"
            + " engine=\(audioStats.engineRunning)"
            + " engineStarts=\(audioStats.engineStarts)"
            + " syncRate=\(syncRate)"
            + " syncTime=\(syncSeconds)"
            + " volumeOut=\(outVolume)"
            + " outChannels=\(outChannels)"
            + " route=\(routeName)"
            + " cat=\(audioSessionInfo.category)"
        StreamSessionProbes.record(audioMessage, retention: .evidence)
        StreamSessionProbes.record(
            "video pump delivered=\(deliveredThisSample)"
                + " total=\(presentedNow)"
                + " pending=\(pendingDepth)"
                + " ready=\(readyForMore)"
                + " buffer=\(options.frameBuffer)",
            retention: .evidence
        )
        let details = stateLock.withLock {
            () -> (video: String, audio: String) in
            let videoNow = (
                counters.videoEnqueueWarnings,
                counters.videoEnqueueCancelledByFlush,
                counters.videoEnqueueRequiresFlush,
                counters.videoEnqueueFailed,
                counters.videoDecodeWarnings
            )
            let videoDelta = (
                videoNow.0 - lastSampledVideoOutcomes.warnings,
                videoNow.1 - lastSampledVideoOutcomes.flush,
                videoNow.2 - lastSampledVideoOutcomes.requiresFlush,
                videoNow.3 - lastSampledVideoOutcomes.failed,
                videoNow.4 - lastSampledVideoOutcomes.decodeWarnings
            )
            lastSampledVideoOutcomes = videoNow
            let audioNow = (
                counters.audioFramesShort,
                counters.audioFramesLong,
                counters.audioFramesOther,
                audioStats.underruns,
                audioStats.overflowFrames
            )
            let audioDelta = (
                audioNow.0 - lastSampledAudioOutcomes.short,
                audioNow.1 - lastSampledAudioOutcomes.long,
                audioNow.2 - lastSampledAudioOutcomes.other,
                audioNow.3 - lastSampledAudioOutcomes.underruns,
                audioNow.4 - lastSampledAudioOutcomes.overflowFrames
            )
            lastSampledAudioOutcomes = audioNow
            let statsText: String
            if let stats {
                statsText = "packets=\(stats.receivedFrames)"
                    + " totalFrames=\(stats.totalFrames)"
                    + " netDrop=\(stats.networkDroppedFrames)"
                    + " interval=\(stats.measuredIntervalSeconds)"
            } else {
                statsText = "packets=none"
            }
            let gapTotals = (
                decoded: counters.videoFramesDecoded,
                videoGap: counters.videoGapCount,
                audioGap: counters.audioGapCount,
                ptsGap: counters.videoPTSGapCount
            )
            let gapDelta = (
                decoded: gapTotals.decoded - lastSampledGaps.decoded,
                videoGap: gapTotals.videoGap - lastSampledGaps.videoGap,
                audioGap: gapTotals.audioGap - lastSampledGaps.audioGap,
                ptsGap: gapTotals.ptsGap - lastSampledGaps.ptsGap
            )
            lastSampledGaps = gapTotals
            let videoGapMax = counters.videoGapMaxMilliseconds
            let videoPTSGapMax = counters.videoPTSGapMaxMilliseconds
            counters.videoPTSGapMaxMilliseconds = 0
            let bufferHoldMax = counters.bufferHoldMaxMilliseconds
            counters.bufferHoldMaxMilliseconds = 0
            let audioGapMax = counters.audioGapMaxMilliseconds
            counters.videoGapMaxMilliseconds = 0
            counters.audioGapMaxMilliseconds = 0
            let receivedNow = Int64(stats?.receivedFrames ?? 0)
            let receivedDelta = receivedNow - lastSampledReceivedFrames
            let sampledInterval = stats?.measuredIntervalSeconds ?? 1
            let deliveredFps = sampledInterval > 0 ? Double(receivedDelta) / sampledInterval : 0
            let videoText = "video detail \(statsText)"
                + " enqWarn=\(videoDelta.0)"
                + " flushDrop=\(videoDelta.1)"
                + " reqFlush=\(videoDelta.2)"
                + " enqFail=\(videoDelta.3)"
                + " decodeWarn=\(videoDelta.4)"
                + " rebuilds=\(counters.decodeRecoveries)"
                + " awaitingSurface=\(counters.framesAwaitingSurface)"
                + " pumpGapMaxMs=\(String(format: "%.1f", maxPumpGapMilliseconds))"
                + " decoded=\(gapDelta.decoded)"
                + " vgap=\(gapDelta.videoGap)"
                + " vgapMaxMs=\(String(format: "%.0f", videoGapMax))"
                + " submitGap=\(stats?.submitGapCount ?? 0)"
                + " submitGapMax=\(stats?.submitGapMaxMs ?? 0)"
                + " zcFail=\(stats?.zeroCopyFallbacks ?? 0)"
                + " zcFrames=\(stats?.zeroCopyFrames ?? 0)"
                + " assembleMaxMs=\(stats?.assembleMaxMs ?? 0)"
                + " queueWaitMaxMs=\(stats?.queueWaitMaxMs ?? 0)"
                + " callbackMaxMs=\(stats?.callbackMaxMs ?? 0)"
                + " pendingMax=\(stats?.pendingMax ?? 0)"
                + " decoderQos=0x\(String(stats?.decoderQos ?? 0, radix: 16))"
                + " ptsGap=\(gapDelta.ptsGap)"
                + " ptsGapMaxMs=\(String(format: "%.0f", videoPTSGapMax))"
                + " shed=\(counters.staleFramesDropped)"
                + " held=\(counters.framesHeldByBuffer)"
                + " holdMaxMs=\(String(format: "%.1f", bufferHoldMax))"
                + " hostLatMs=\(String(format: "%.1f", stats?.averageHostProcessingLatencyMs ?? 0))"
                + " hostLatFrames=\(stats?.framesWithHostProcessingLatency ?? 0)"
                + " rttMs=\(backend.estimatedRTT()?.milliseconds ?? 0)"
                + " rttVar=\(backend.estimatedRTT()?.variance ?? 0)"
                + " reqFps=\(requestedFrameRate)"
                + " gotFps=\(String(format: "%.1f", deliveredFps))"
            maxPumpGapMilliseconds = 0
            lastSampledReceivedFrames = receivedNow
            if case .streaming = snapshotStorage.state {
                streamingStableSeconds += 1
            } else {
                streamingStableSeconds = 0
            }
            if requestedFrameRate >= 100,
               sampledInterval > 0,
               streamingStableSeconds >= 4,
               videoGapMax < 40,
               deliveredFps >= Double(requestedFrameRate) * 0.6,
               deliveredFps < Double(requestedFrameRate) * 0.95 {
                lowDeliverySeconds += 1
            } else {
                lowDeliverySeconds = 0
            }
            if lowDeliverySeconds >= 3, !didSignalHostFrameRateMismatch {
                didSignalHostFrameRateMismatch = true
                StreamSessionProbes.record(
                    "video host frame rate mismatch session=\(sessionID.rawValue)"
                        + " requested=\(requestedFrameRate)"
                        + " received=\(receivedDelta)"
                        + " interval=\(sampledInterval)",
                    retention: .evidence
                )
                onHostFrameRateMismatch?()
            }
            let audioText = "audio detail"
                + " underruns=\(audioDelta.3)"
                + " overflowFrames=\(audioDelta.4)"
                + " f240=\(audioDelta.0)"
                + " f480=\(audioDelta.1)"
                + " fOther=\(audioDelta.2)"
                + " agap=\(gapDelta.audioGap)"
                + " agapMaxMs=\(String(format: "%.0f", audioGapMax))"
                + " pendingPeakMs=\(audioPendingPeakMs)"
            return (videoText, audioText)
        }
        StreamSessionProbes.record(details.video, retention: .evidence)
        StreamSessionProbes.record(details.audio, retention: .evidence)
        let diagnosticMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - diagnosticStartedAt
        ) / 1_000_000
        StreamSessionProbes.record(
            "diagnostics tick ms=\(String(format: "%.1f", diagnosticMilliseconds))",
            retention: .evidence
        )
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
            if counters.videoBytes > 0 {
                snapshotStorage.diagnostics.measuredBitrateKbps = Int(
                    measuredBitrateKbps
                )
                snapshotStorage.diagnostics.presentedFramesPerSecond = Int(
                    deliveredThisSample
                )
            }
            snapshotStorage.diagnostics.audioFramesReceived = counters.audioFramesReceived
            snapshotStorage.diagnostics.audioFramesEnqueued = counters.audioFramesEnqueued
            snapshotStorage.diagnostics.audioFramesDropped = counters.audioFramesDropped
            snapshotStorage.input.mouseEventsSent = counters.mouseEvents
            snapshotStorage.input.scrollEventsSent = counters.scrollEvents
            snapshotStorage.input.keyboardEventsSent = counters.keyboardEvents
            snapshotStorage.input.gamepadEventsSent = counters.gamepadEvents
            snapshotStorage.input.pressedKeyCount = pressedKeys.count
            snapshotStorage.input.pressedButtonCount = pressedButtons.count
        }
        publishSnapshot()
    }

    private func publishActivity(_ activity: StreamSessionActivity) {
        let changed = stateLock.withLock { () -> Bool in
            guard snapshotStorage.activity != activity else { return false }
            snapshotStorage.activity = activity
            return true
        }
        guard changed else { return }
        StreamSessionProbes.record(
            "activity session=\(sessionID.rawValue) value=\(activity.rawValue)",
            retention: .evidence
        )
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

    private func handleMousePresence(_ attached: Bool) {
        let released: Set<Int32> = stateLock.withLock {
            snapshotStorage.input.hardwareMouse = attached
            guard !attached else { return [] }
            let pressed = pressedButtons
            pressedButtons.removeAll()
            return pressed
        }
        for code in released where !attached {
            backend.sendMouseButton(code: code, down: false)
        }
        StreamSessionProbes.record(
            "mouse \(attached ? "attached" : "detached")",
            retention: .evidence
        )
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

    public func sendHighResScroll(vertical: Int32, horizontal: Int32) {
        guard vertical != 0 || horizontal != 0 else { return }
        backend.sendHighResScroll(
            vertical: Int16(clamping: vertical),
            horizontal: Int16(clamping: horizontal)
        )
        stateLock.withLock { counters.scrollEvents += 1 }
    }

    @discardableResult
    public func sendGamepad(_ state: StreamGamepadState) -> Int32 {
        let flags = StreamGamepadMapping.buttonFlags(
            state.buttons,
            swapABXYButtons: options.swapABXYButtons
        )
        backend.sendControllerState(
            buttonFlags: flags,
            leftTrigger: state.leftTrigger,
            rightTrigger: state.rightTrigger,
            leftStickX: state.sticks.leftX,
            leftStickY: state.sticks.leftY,
            rightStickX: state.sticks.rightX,
            rightStickY: state.sticks.rightY
        )
        let changed = stateLock.withLock { () -> Bool in
            counters.gamepadEvents += 1
            let value = flags != controllerFlags
            controllerFlags = flags
            return value
        }
        if changed {
            StreamSessionProbes.record(
                "controller flags=\(flags) lt=\(state.leftTrigger) rt=\(state.rightTrigger)",
                retention: .evidence
            )
        }
        return flags
    }

#if DEBUG
    /// Test-channel hooks. Each one enters the same function the real controller
    /// and the real host feedback enter, so a simulator exercises the production
    /// path rather than a copy of it.
    public func simulateControllerProfile(_ arrival: StreamControllerArrival?) {
        handleControllerProfile(arrival)
    }

    public func simulateControllerFeedback(_ feedback: StreamControllerFeedback) {
        gamepadInput.handle(feedback)
    }

    public func simulateTouchpad(index: Int, x: Float, y: Float) {
        gamepadInput.simulateTouch(index: index, x: x, y: y)
    }

    public func setSimulatedMotion(_ enabled: Bool) {
        gamepadInput.setSimulatedMotion(enabled)
    }

    public func simulateBattery(state: UInt8, percentage: UInt8) {
        gamepadInput.simulateBattery(state: state, percentage: percentage)
    }
#endif

    public func handleControllerProfile(_ arrival: StreamControllerArrival?) {
        guard let arrival else {
            backend.sendControllerRemoval(controllerNumber: 0)
            StreamSessionProbes.record("controller removed", retention: .evidence)
            return
        }
        backend.sendControllerArrival(arrival)
        let afterConnection = stateLock.withLock { snapshotStorage.state == .streaming }
        StreamSessionProbes.record(
            "gamepad arrival type=\(arrival.kind.rawValue)"
                + " caps=0x\(String(arrival.capabilities.rawValue, radix: 16))"
                + " buttons=0x\(String(arrival.supportedButtons, radix: 16))",
            retention: .evidence
        )
        StreamSessionProbes.record(
            "gamepad arrival sent afterConnection=\(afterConnection)",
            retention: .evidence
        )
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
        if controllerFlags != 0 {
            sendGamepad(.neutral)
        }
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
