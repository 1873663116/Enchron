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
    private var audioRenderer = AVSampleBufferAudioRenderer()
    private var audioSink: AVSampleBufferAudioRendererInputSink
    private var pumpTimer: DispatchSourceTimer?
    private var pumpActive = false
    private var lastPumpTickNanoseconds: UInt64 = 0
    private var maxPumpGapMilliseconds: Double = 0
    private var renderingEventObservationActive = false
    private var graphVersion = 1

    private let videoQueueLock = NSLock()
    private var pendingVideo: [(sample: CMSampleBuffer, presentationTimeUs: Int64)] = []
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
    private var lastSampledAudioOutcomes: (warnings: Int64, flushDrops: Int64, failed: Int64, autoFlush: Int64, config: Int64, short: Int64, long: Int64, other: Int64) = (0, 0, 0, 0, 0, 0, 0, 0)
    private var lastVideoSampleNanoseconds: UInt64 = 0
    private var lastVideoPresentationSeconds: Double = 0
    private var lastAudioFrameNanoseconds: UInt64 = 0
    private var lastSampledGaps: (decoded: Int64, videoGap: Int64, audioGap: Int64, late: Int64, ptsGap: Int64) = (0, 0, 0, 0, 0)
    private var flushingRenderer = false
    private var lastCancelledByFlushIdrAt = Date.distantPast
    private var videoDeliveryStartedAt: Date?
    private var surfaceBindingRevision: Int?
    private var surfaceHasBound = false
    private var lastAwaitingSurfaceReport = Date.distantPast

    private var nextAudioPTS: CMTime = .invalid
    private var firstVideoPTS: CMTime = .invalid
    private var audioPTSProbeLogged = false
    private var audioSampleProbeLogged = false
    private var audioPTSReanchorCount = 0

    private enum TimelineGovernorState {
        case measuring
        case running
        case recovering
    }

    private var governorState: TimelineGovernorState = .measuring
    private var streamingDisplaysImmediately: Bool { !options.framePacing }
    private var governorTargetLeadSeconds = 0.016
    private var governorLeadEmaSeconds: Double = .nan
    private var governorSecondLeads: [Double] = []

    private func governorSecondLeadP95() -> Double {
        guard governorSecondLeads.isEmpty == false else { return 0 }
        let ordered = governorSecondLeads.sorted()
        let index = min(ordered.count - 1, Int(Double(ordered.count) * 0.95))
        return ordered[index]
    }
    private var governorSecondLate = 0
    private var governorSecondTotal = 0
    private var governorResyncCount: Int64 = 0
    private var governorResyncMaxPauseMilliseconds: Double = 0
    private var governorPauseStartedAt: Date?
    private var governorLastAdjustAt = Date.distantPast
    private var governorLastRecoveryAt = Date.distantPast
    private var governorSettleUntil = Date.distantPast
    private var governorSevereLateSince: Date?
    private var governorCleanSeconds = 0
    private var governorDriftFixes: Int64 = 0
    private var audioFormatDescription: CMAudioFormatDescription?
    private var audioFormatKey: String?
    private var audioFrameDurationSeconds: Double = 0

    private var videoStatsTimer: DispatchSourceTimer?
    private var terminatedFallback: DispatchWorkItem?

    private var counters = Counters()
    private let gamepadInput = StreamGamepadInput()
    private let mouseInput = StreamMouseInput()
    private var controllerFlags: Int32 = 0
    private var hardwareMouseActive = false

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
        var audioEnqueueWarnings: Int64 = 0
        var audioEnqueueCancelledByFlush: Int64 = 0
        var audioEnqueueFailed: Int64 = 0
        var audioFlushEvents: Int64 = 0
        var audioOutputConfigurationEvents: Int64 = 0
        var audioFailureEvents: Int64 = 0
        var audioFramesShort: Int64 = 0
        var audioFramesLong: Int64 = 0
        var audioFramesOther: Int64 = 0
        var videoFramesDecoded: Int64 = 0
        var videoGapCount: Int64 = 0
        var videoGapMaxMilliseconds: Double = 0
        var videoLateFrames: Int64 = 0
        var videoLateMaxMilliseconds: Double = 0
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
        }
        activateAudioSession()
        gamepadInput.start(
            onState: { [weak self] state in self?.sendGamepad(state) },
            onPresence: { [weak self] connected in self?.handleControllerPresence(connected) }
        )
        if options.bluetoothMouseEnabled {
            mouseInput.start(
                onMove: { [weak self] dx, dy in self?.sendMouseMove(dx: dx, dy: dy) },
                onButton: { [weak self] code, down in self?.sendMouseButton(code: code, down: down) },
                onScrollClicks: { [weak self] clicks in self?.sendScroll(amount: clicks) },
                onPresence: { [weak self] attached in self?.handleMousePresence(attached) }
            )
        }
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
            let rateBefore = self.synchronizer.rate
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
                let rateAfter = self.synchronizer.rate
                if rateAfter == 0 {
                    self.rearmSynchronizer()
                }
                StreamSessionProbes.record(
                    "audio session active session=\(self.sessionID.rawValue)"
                        + " rateBefore=\(rateBefore)"
                        + " rateAfter=\(rateAfter)"
                        + " rearmed=\(rateAfter == 0)",
                    retention: .evidence
                )
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
            pendingVideo.append((sample, ptsUs))
        }
        let sampleTime = DispatchTime.now().uptimeNanoseconds
        stateLock.withLock {
            if !firstVideoPTS.isValid {
                firstVideoPTS = pts
            }
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
                let count: Int64 = self.stateLock.withLock {
                    self.counters.videoDecodeWarnings += 1
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
        audioSink.observeRenderingEventsAfterFinishedEnqueuing { [weak self] fact in
            guard let self else { return }
            switch fact {
            case .warning(_, let message):
                let counts: (flush: Int64, config: Int64) = self.stateLock.withLock {
                    if message.contains("configuration") {
                        self.counters.audioOutputConfigurationEvents += 1
                    } else {
                        self.counters.audioFlushEvents += 1
                        self.nextAudioPTS = .invalid
                    }
                    return (self.counters.audioFlushEvents, self.counters.audioOutputConfigurationEvents)
                }
                if counts.flush + counts.config <= 8 || (counts.flush + counts.config) % 100 == 0 {
                    StreamSessionProbes.record(
                        "audio renderer warning session=\(self.sessionID.rawValue)"
                            + " count=\(counts.flush + counts.config) message=\(message)",
                        retention: .evidence
                    )
                }
            case .failure:
                self.stateLock.withLock { self.counters.audioFailureEvents += 1 }
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
            if options.framePacing && videoSinkAcceptsHold(pendingCount: pendingVideo.count) {
                videoQueueLock.unlock()
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

            let clockSeconds = synchronizer.currentTime().seconds
            let ptsSeconds = Double(head.presentationTimeUs) / 1_000_000
            if !governorRecord(ptsSeconds: ptsSeconds, clockSeconds: clockSeconds) {
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
                continue
            }

            if !streamingDisplaysImmediately {
                let lateMilliseconds = (synchronizer.currentTime().seconds * 1_000_000 - Double(head.presentationTimeUs)) / 1000
                if lateMilliseconds > 4 {
                    stateLock.withLock {
                        counters.videoLateFrames += 1
                        if lateMilliseconds > counters.videoLateMaxMilliseconds {
                            counters.videoLateMaxMilliseconds = lateMilliseconds
                        }
                    }
                }
            }
            var sampleToEnqueue = head.sample
            if streamingDisplaysImmediately,
               let immediate = Self.immediateTimingSample(
                   head.sample,
                   presentationTime: synchronizer.currentTime()
               ) {
                sampleToEnqueue = immediate
            }
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
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
                governorFinishRecovery()
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
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
                governorFinishRecovery()
                stateLock.withLock {
                    counters.presented += 1
                    counters.videoEnqueueWarnings += 1
                    counters.lastPresentedTimestampMs = head.presentationTimeUs / 1000
                }
                reportQueueDepthIfNeeded()
            case .cancelledByFlush:
                videoQueueLock.withLock {
                    if !pendingVideo.isEmpty {
                        pendingVideo.removeFirst()
                    }
                }
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

    private func videoSinkAcceptsHold(pendingCount: Int) -> Bool {
        pendingCount <= 1
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

    private var governorFloorLeadSeconds: Double {
        max(0.012, 1.5 / Double(max(options.frameRate, 1)))
    }

    private var governorSettling: Bool {
        Date() < governorSettleUntil
    }

    private func governorSetClock(leadSeconds: Double, ptsSeconds: Double) {
        synchronizer.setRate(
            1.0,
            time: CMTime(seconds: max(0, ptsSeconds - leadSeconds), preferredTimescale: 600),
            atHostTime: CMClockGetTime(CMClockGetHostTimeClock())
        )
        stateLock.withLock { nextAudioPTS = .invalid }
    }

    private func governorShiftClock(bySeconds seconds: Double) {
        let time = CMTimeAdd(
            synchronizer.currentTime(),
            CMTime(seconds: seconds, preferredTimescale: 600)
        )
        synchronizer.setRate(
            1.0,
            time: time,
            atHostTime: CMClockGetTime(CMClockGetHostTimeClock())
        )
        stateLock.withLock { nextAudioPTS = .invalid }
    }

    private func governorRecord(ptsSeconds: Double, clockSeconds: Double) -> Bool {
        let lead = ptsSeconds - clockSeconds
        if streamingDisplaysImmediately {
            governorState = .running
            return true
        }

        if governorState == .measuring {
            governorSetClock(leadSeconds: governorTargetLeadSeconds, ptsSeconds: ptsSeconds)
            governorState = .running
            governorSettleUntil = Date().addingTimeInterval(0.6)
            governorLeadEmaSeconds = .nan
            publishActivity(.aligningClock)
            return true
        }

        if governorState == .recovering {
            governorSetClock(leadSeconds: governorTargetLeadSeconds, ptsSeconds: ptsSeconds)
            return true
        }

        guard !governorSettling else { return true }

        governorLeadEmaSeconds = governorLeadEmaSeconds.isNaN
            ? lead
            : governorLeadEmaSeconds * 0.9 + lead * 0.1
        governorSecondLeads.append(lead * 1000)
        if governorSecondLeads.count > 400 {
            governorSecondLeads.removeFirst(governorSecondLeads.count - 400)
        }
        governorSecondTotal += 1
        if lead < 0 {
            governorSecondLate += 1
        }

        governorTrackSevereLateness(leadSeconds: lead)
        governorMaybeAdjustClock()
        return true
    }

    private func governorTrackSevereLateness(leadSeconds: Double) {
        guard leadSeconds < -0.150 else {
            governorSevereLateSince = nil
            return
        }
        let now = Date()
        if let since = governorSevereLateSince {
            if now.timeIntervalSince(since) > 1.0,
               now.timeIntervalSince(governorLastRecoveryAt) > 5.0 {
                governorBeginRecovery(reason: "severeLate")
            }
        } else {
            governorSevereLateSince = now
        }
    }

    private func governorMaybeAdjustClock() {
        let now = Date()
        guard now.timeIntervalSince(governorLastAdjustAt) >= 0.5 else { return }
        let ema = governorLeadEmaSeconds
        guard !ema.isNaN else { return }
        let target = governorTargetLeadSeconds
        let shortfall = target - ema
        let excess = ema - target

        if shortfall > target * 0.5 {
            let shift = min(shortfall, 0.040)
            governorShiftClock(bySeconds: -shift)
            governorLeadEmaSeconds = ema + shift
            governorLastAdjustAt = now
            governorSettleUntil = now.addingTimeInterval(0.25)
            governorDriftFixes += 1
        } else if excess > target * 2.0 {
            let shift = min(excess, 0.040)
            governorShiftClock(bySeconds: shift)
            governorLeadEmaSeconds = ema - shift
            governorLastAdjustAt = now
            governorSettleUntil = now.addingTimeInterval(0.25)
            governorDriftFixes += 1
        }
    }

    private func governorAdaptTargetLead(lateRate: Double) {
        let now = Date()
        guard now.timeIntervalSince(governorLastAdjustAt) >= 2.0 else { return }
        if lateRate > 0.05 {
            governorCleanSeconds = 0
            governorTargetLeadSeconds = min(
                governorTargetLeadSeconds + 0.008,
                governorResyncLeadCapSeconds
            )
            governorLastAdjustAt = now
        } else if lateRate == 0 {
            governorCleanSeconds += 1
            guard governorCleanSeconds >= 3 else { return }
            governorTargetLeadSeconds = max(
                governorFloorLeadSeconds,
                governorTargetLeadSeconds - 0.004
            )
            governorLastAdjustAt = now
        } else {
            governorCleanSeconds = 0
        }
    }

    private var governorResyncLeadCapSeconds: Double {
        0.120
    }

    private func governorFinishRecovery() {
        guard governorState != .measuring || governorPauseStartedAt != nil else { return }
        guard governorPauseStartedAt != nil else { return }
        governorState = .running
        let pauseMilliseconds = governorPauseStartedAt.map {
            Date().timeIntervalSince($0) * 1000
        } ?? 0
        governorPauseStartedAt = nil
        governorResyncMaxPauseMilliseconds = max(
            governorResyncMaxPauseMilliseconds,
            pauseMilliseconds
        )
        governorSettleUntil = Date().addingTimeInterval(0.6)
        governorLeadEmaSeconds = .nan
        governorSevereLateSince = nil
        governorSecondLeads.removeAll()
        governorSecondLate = 0
        governorSecondTotal = 0
        publishActivity(.streaming)
        StreamSessionProbes.record(
            "video timeline resync end session=\(sessionID.rawValue)"
                + " pauseMs=\(String(format: "%.0f", pauseMilliseconds))"
                + " targetMs=\(String(format: "%.0f", governorTargetLeadSeconds * 1000))"
                + " count=\(governorResyncCount)",
            retention: .evidence
        )
    }

    private func governorBeginRecovery(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(governorLastRecoveryAt) > 5.0 else { return }
        governorLastRecoveryAt = now
        governorState = .recovering
        publishActivity(.buffering)
        governorPauseStartedAt = now
        governorResyncCount += 1
        synchronizer.setRate(0, time: synchronizer.currentTime())
        videoQueueLock.lock()
        pendingVideo.removeAll()
        videoQueueLock.unlock()
        requestIdrFrame(reason: "timelineResync")
        Task { [weak self] in
            await self?.videoSink.flush(removingDisplayedImage: false)
        }
        StreamSessionProbes.record(
            "video timeline resync begin session=\(sessionID.rawValue)"
                + " reason=\(reason)"
                + " targetMs=\(String(format: "%.0f", governorTargetLeadSeconds * 1000))"
                + " count=\(governorResyncCount)",
            retention: .evidence
        )
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
        publishSnapshot()
        return replacement
    }

    private func handleAudioFrame(_ frame: BackendAudioFrame) {
        rearmSynchronizerIfStalled()
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
            let frameDurationTime = CMTimeMakeWithSeconds(frameDuration, preferredTimescale: 1_000_000)
            let current = synchronizer.currentTime()
            let lead = nextAudioPTS.isValid
                ? CMTimeSubtract(nextAudioPTS, current).seconds
                : Double.nan
            if !nextAudioPTS.isValid || lead < -0.05 || lead > 0.35 {
                nextAudioPTS = CMTimeAdd(
                    current,
                    CMTimeMakeWithSeconds(0.030, preferredTimescale: 1_000_000)
                )
                if !lead.isNaN {
                    audioPTSReanchorCount += 1
                    if audioPTSReanchorCount <= 5 || audioPTSReanchorCount % 100 == 0 {
                        StreamSessionProbes.record(
                            "audio pts re-anchor session=\(sessionID.rawValue)"
                                + " count=\(audioPTSReanchorCount)"
                                + " lead=\(lead)"
                                + " syncTime=\(current.seconds)",
                            retention: .diagnostic
                        )
                    }
                }
            }
            if !audioPTSProbeLogged {
                audioPTSProbeLogged = true
                StreamSessionProbes.record(
                    "audio first pts=\(nextAudioPTS.seconds)"
                        + " syncTime=\(synchronizer.currentTime().seconds)"
                        + " syncRate=\(synchronizer.rate)",
                    retention: .evidence
                )
            }
            resolvedPTS = nextAudioPTS
            nextAudioPTS = CMTimeAdd(nextAudioPTS, frameDurationTime)
        }

        guard let sample = Self.makeAudioSampleBuffer(
            frame: frame,
            formatDescription: formatDescription,
            presentationTime: resolvedPTS
        ) else {
            return
        }

        let reportFirstSample = stateLock.withLock { () -> Bool in
            guard !audioSampleProbeLogged else { return false }
            audioSampleProbeLogged = true
            return true
        }
        if reportFirstSample {
            let dataLength = CMSampleBufferGetDataBuffer(sample)
                .map { CMBlockBufferGetDataLength($0) } ?? -1
            StreamSessionProbes.record(
                "audio first sample frames=\(CMSampleBufferGetNumSamples(sample))"
                    + " duration=\(CMSampleBufferGetDuration(sample).seconds)"
                    + " bytes=\(dataLength)"
                    + " pcmBytes=\(frame.pcm.count)",
                retention: .evidence
            )
        }

        do {
            let outcome = try audioSink.enqueueImmediately(RendererInputSample(sampleBuffer: sample))
            switch outcome {
            case .accepted:
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
            case .acceptedWithWarnings:
                stateLock.withLock {
                    counters.audioFramesEnqueued += 1
                    counters.audioEnqueueWarnings += 1
                }
            case .cancelledByFlush:
                stateLock.withLock {
                    counters.audioFramesDropped += 1
                    counters.audioEnqueueCancelledByFlush += 1
                }
            case .requiresFlush:
                stateLock.withLock {
                    counters.audioFramesDropped += 1
                    counters.audioEnqueueFailed += 1
                }
            case .failed:
                stateLock.withLock {
                    counters.audioFramesDropped += 1
                    counters.audioEnqueueFailed += 1
                }
            }
        } catch {
            stateLock.withLock {
                counters.audioFramesDropped += 1
                counters.audioEnqueueFailed += 1
            }
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
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let bytesPerFrame = Int(frame.channels) * MemoryLayout<Int16>.size
        let byteCount = frame.pcm.count
        guard frame.sampleRate > 0,
              frame.frameCount > 0,
              bytesPerFrame > 0,
              byteCount == Int(frame.frameCount) * bytesPerFrame else {
            StreamSessionProbes.record(
                "audio frame rejected frames=\(frame.frameCount)"
                    + " channels=\(frame.channels)"
                    + " rate=\(frame.sampleRate)"
                    + " bytes=\(byteCount)",
                retention: .evidence
            )
            return nil
        }

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

        let copied = frame.pcm.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kCVReturnError }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard copied == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frame.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frame.frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
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
        stateLock.withLock { nextAudioPTS = .invalid }
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

    private func sampleDiagnostics() {
        let diagnosticStartedAt = DispatchTime.now().uptimeNanoseconds
        let stats = backend.videoStats()
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
            () -> (received: Int64, enqueued: Int64, dropped: Int64, peak: Int32, lead: Double) in
            let values = (
                counters.audioFramesReceived,
                counters.audioFramesEnqueued,
                counters.audioFramesDropped,
                counters.audioPeakAbs,
                nextAudioPTS.isValid ? nextAudioPTS.seconds - syncSeconds : Double.nan
            )
            counters.audioPeakAbs = 0
            return values
        }
        let tbRate: Double = audioRenderer.timebase.rate
        refreshAudioSessionCache()
        let audioSessionInfo = audioSessionCacheLock.withLock { audioSessionCache }
        let outVolume: Float = audioSessionInfo.volume
        let outChannels = audioSessionInfo.channels
        let routeName = audioSessionInfo.route
        let audioReady: Bool = audioRenderer.isReadyForMoreMediaData
        let audioStatus: Int = audioRenderer.status.rawValue
        let rendererVolume: Float = audioRenderer.volume
        let rendererMuted: Bool = audioRenderer.isMuted
        let rendererError = audioRenderer.error?.localizedDescription ?? "none"
        let audioMessage = "audio pump received=\(audioCounters.received)"
            + " enqueued=\(audioCounters.enqueued)"
            + " dropped=\(audioCounters.dropped)"
            + " peak=\(audioCounters.peak)"
            + " lead=\(audioCounters.lead)"
            + " ready=\(audioReady)"
            + " status=\(audioStatus)"
            + " syncRate=\(syncRate)"
            + " syncTime=\(syncSeconds)"
            + " tbRate=\(tbRate)"
            + " rendererVol=\(rendererVolume)"
            + " rendererMuted=\(rendererMuted)"
            + " rendererError=\(rendererError)"
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
                + " pacing=\(options.framePacing)",
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
                counters.audioEnqueueWarnings,
                counters.audioEnqueueCancelledByFlush,
                counters.audioEnqueueFailed,
                counters.audioFlushEvents,
                counters.audioOutputConfigurationEvents,
                counters.audioFramesShort,
                counters.audioFramesLong,
                counters.audioFramesOther
            )
            let audioDelta = (
                audioNow.0 - lastSampledAudioOutcomes.warnings,
                audioNow.1 - lastSampledAudioOutcomes.flushDrops,
                audioNow.2 - lastSampledAudioOutcomes.failed,
                audioNow.3 - lastSampledAudioOutcomes.autoFlush,
                audioNow.4 - lastSampledAudioOutcomes.config,
                audioNow.5 - lastSampledAudioOutcomes.short,
                audioNow.6 - lastSampledAudioOutcomes.long,
                audioNow.7 - lastSampledAudioOutcomes.other
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
                late: counters.videoLateFrames,
                ptsGap: counters.videoPTSGapCount
            )
            let gapDelta = (
                decoded: gapTotals.decoded - lastSampledGaps.decoded,
                videoGap: gapTotals.videoGap - lastSampledGaps.videoGap,
                audioGap: gapTotals.audioGap - lastSampledGaps.audioGap,
                late: gapTotals.late - lastSampledGaps.late,
                ptsGap: gapTotals.ptsGap - lastSampledGaps.ptsGap
            )
            lastSampledGaps = gapTotals
            let videoGapMax = counters.videoGapMaxMilliseconds
            let videoLateMax = counters.videoLateMaxMilliseconds
            counters.videoLateMaxMilliseconds = 0
            let videoPTSGapMax = counters.videoPTSGapMaxMilliseconds
            counters.videoPTSGapMaxMilliseconds = 0
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
                + " late=\(gapDelta.late)"
                + " lateMaxMs=\(String(format: "%.0f", videoLateMax))"
                + " submitGap=\(stats?.submitGapCount ?? 0)"
                + " submitGapMax=\(stats?.submitGapMaxMs ?? 0)"
                + " zcFail=\(stats?.zeroCopyFallbacks ?? 0)"
                + " zcFrames=\(stats?.zeroCopyFrames ?? 0)"
                + " ptsGap=\(gapDelta.ptsGap)"
                + " ptsGapMaxMs=\(String(format: "%.0f", videoPTSGapMax))"
                + " leadAvgMs=\(String(format: "%.1f", governorSecondLeads.isEmpty ? 0 : governorSecondLeads.reduce(0, +) / Double(governorSecondLeads.count)))"
                + " leadP95Ms=\(String(format: "%.1f", governorSecondLeadP95()))"
                + " latePct=\(String(format: "%.0f", governorSecondTotal == 0 ? 0 : Double(governorSecondLate) / Double(governorSecondTotal) * 100))"
                + " targetMs=\(String(format: "%.0f", governorTargetLeadSeconds * 1000))"
                + " resync=\(governorResyncCount)"
                + " resyncMaxMs=\(String(format: "%.0f", governorResyncMaxPauseMilliseconds))"
                + " driftFix=\(governorDriftFixes)"
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
            let governorLateRate = governorSecondTotal == 0
                ? 0
                : Double(governorSecondLate) / Double(governorSecondTotal)
            governorAdaptTargetLead(lateRate: governorLateRate)
            governorSecondLeads.removeAll()
            governorSecondLate = 0
            governorSecondTotal = 0
            let audioText = "audio detail"
                + " enqWarn=\(audioDelta.0)"
                + " flushDrop=\(audioDelta.1)"
                + " enqFail=\(audioDelta.2)"
                + " autoFlush=\(audioDelta.3)"
                + " cfgChange=\(audioDelta.4)"
                + " evFail=\(counters.audioFailureEvents)"
                + " f240=\(audioDelta.5)"
                + " f480=\(audioDelta.6)"
                + " fOther=\(audioDelta.7)"
                + " agap=\(gapDelta.audioGap)"
                + " agapMaxMs=\(String(format: "%.0f", audioGapMax))"
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
        guard !hardwareMouseActive else { return }
        backend.sendMousePosition(normalizedX: normalizedX, normalizedY: normalizedY)
        stateLock.withLock { counters.mouseEvents += 1 }
    }

    /// The window's gaze and pinch layer is the pointer path for hand control.
    /// While an external mouse drives the host, that layer must not also move
    /// the pointer or click, or every mouse click would arrive twice.
    public func sendGestureClick(normalizedX: Float, normalizedY: Float) {
        guard !hardwareMouseActive else { return }
        sendMousePosition(normalizedX: normalizedX, normalizedY: normalizedY)
        sendMouseButton(code: StreamMouseInput.leftButtonCode, down: true)
        sendMouseButton(code: StreamMouseInput.leftButtonCode, down: false)
    }

    private func handleMousePresence(_ attached: Bool) {
        let released: Set<Int32> = stateLock.withLock {
            hardwareMouseActive = attached
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

    public func handleControllerPresence(_ connected: Bool) {
        backend.sendControllerPresence(connected: connected)
        StreamSessionProbes.record(
            "controller \(connected ? "arrived" : "removed")",
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
