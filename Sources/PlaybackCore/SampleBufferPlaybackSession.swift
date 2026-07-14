@preconcurrency import AVFoundation
import Foundation
import OSLog

enum RendererFailureKind: String, Sendable {
    case video
    case audio
}

struct RendererFailureFact: Equatable, Sendable {
    var rendererKind: RendererFailureKind
    var errorType: String
    var message: String
    var requiresFlushToResumeDecoding: Bool?
}

protocol RendererFailureMonitoring: AnyObject {
    func start(handler: @escaping @Sendable (RendererFailureFact) -> Void)
    func stop()
}

private final class AVRendererFailureMonitor: RendererFailureMonitoring, @unchecked Sendable {
    private let videoRenderer: AVSampleBufferVideoRenderer
    private let audioRenderer: AVSampleBufferAudioRenderer
    private let lock = NSLock()
    private var videoStatusObservation: NSKeyValueObservation?
    private var audioStatusObservation: NSKeyValueObservation?

    init(
        videoRenderer: AVSampleBufferVideoRenderer,
        audioRenderer: AVSampleBufferAudioRenderer
    ) {
        self.videoRenderer = videoRenderer
        self.audioRenderer = audioRenderer
    }

    func start(handler: @escaping @Sendable (RendererFailureFact) -> Void) {
        stop()
        let videoObservation = videoRenderer.observe(\.status, options: [.initial, .new]) {
            renderer,
            _ in
            guard renderer.status == .failed else { return }
            let error = renderer.error
            handler(RendererFailureFact(
                rendererKind: .video,
                errorType: error.map { String(reflecting: type(of: $0)) }
                    ?? "AVSampleBufferVideoRenderer",
                message: error?.localizedDescription
                    ?? "Video renderer entered failed status.",
                requiresFlushToResumeDecoding: renderer.requiresFlushToResumeDecoding
            ))
        }
        let audioObservation = audioRenderer.observe(\.status, options: [.initial, .new]) {
            renderer,
            _ in
            guard renderer.status == .failed else { return }
            let error = renderer.error
            handler(RendererFailureFact(
                rendererKind: .audio,
                errorType: error.map { String(reflecting: type(of: $0)) }
                    ?? "AVSampleBufferAudioRenderer",
                message: error?.localizedDescription
                    ?? "Audio renderer entered failed status.",
                requiresFlushToResumeDecoding: nil
            ))
        }
        lock.withLock {
            videoStatusObservation = videoObservation
            audioStatusObservation = audioObservation
        }
    }

    func stop() {
        let observations = lock.withLock {
            let observations = (videoStatusObservation, audioStatusObservation)
            videoStatusObservation = nil
            audioStatusObservation = nil
            return observations
        }
        observations.0?.invalidate()
        observations.1?.invalidate()
    }
}

public final class SampleBufferPlaybackSession: @unchecked Sendable {
    private struct EndState {
        var requiresAudio = false
        var videoProviderEnded = false
        var audioProviderEnded = true
        var maximumVideoPresentationTime: CMTime?
        var videoPresentationEnd: CMTime?
        var audioPresentationEnd: CMTime?
        var didReportEnd = false
        var isClosed = false
    }

    public let route: PlaybackRoute
    public let traceID: String
    public let renderer = AVSampleBufferVideoRenderer()
    public let audioRenderer = AVSampleBufferAudioRenderer()
    public let synchronizer = AVSampleBufferRenderSynchronizer()
    let debugStore = PlaybackDiagnosticsStore()

    public var onStatusChange: (@Sendable (PlaybackStatus) -> Void)?
    public var onDiagnosticsChange: (@Sendable (PlaybackDiagnostics) -> Void)?

    private let provider: VideoSampleProvider
    private let audioProvider: AudioSampleProvider
    private let rendererSink: RendererInputSink
    private let videoSampleFormatOverride = VideoSampleFormatOverride()
    private var rendererFailureMonitor: RendererFailureMonitoring?
    private let rendererFailureLock = NSLock()
    private var acceptsRendererFailure = true
    private let videoTrackID: String
    private let deliveryQueue = DispatchQueue(label: "PlaybackLab.sample-delivery")
    private let audioDeliveryQueue = DispatchQueue(label: "PlaybackLab.audio-sample-delivery")
    private let endStateLock = NSLock()
    private var endState = EndState()
    private var hasStartedTimeline = false
    private var timeObserver: Any?
    private var isClosed = false
    private let closeLock = NSLock()
    private var isClosing = false
    private var isCloseFinished = false
    private var closeCompletions: [@Sendable () -> Void] = []
    private var diagnostics = PlaybackDiagnostics()
    private var lastDiagnosticsSecond = -1
    private var didRecordFormat = false
    private var timelineStartRate: Float = 1
    public private(set) var preferredPlaybackRate: Float = 1
    private var sourceURL: URL?
    private var isResetting = false
    private var mediaSessionRecord: MediaSessionRecord?
    private var streamEpoch: UInt64 = 1
    private var audioStreamEpoch: UInt64 = 1
    private var formatRevision: UInt64 = 1
    private var sourceEventSequence: UInt64 = 0
    private var lastSourceEventID = "none"
    private var lastRecordedSampleEpoch: UInt64 = 0
    private var requestedTimelineStart = CMTime.invalid
    private var isPrerolling = false
    private var activeOperation: PlaybackOperationRecord?
    private var pendingRouteSwitchOperation: PlaybackOperationRecord?
    private var flushCount: UInt64 = 0
    private var graphRevision: UInt64 = 1
    private var stereoLayoutOverride: VideoStereoLayout?
    private var projectionOverride: VideoProjectionOverride?
    private var hasRequestedVideoData = false
    private var hasAudio = false
    private var audioSampleBufferCount: UInt64 = 0
    private var audioFrameCount: UInt64 = 0
    public private(set) var selectedAudioStreamIndex: Int?
    public private(set) var availableAudioTracks: [PlaybackAudioTrack] = []
    private let logger = Logger(subsystem: "com.xiongzhipeng.PlaybackLab", category: "Playback")

    public convenience init(route: PlaybackRoute, traceID: String = UUID().uuidString) {
        let provider: VideoSampleProvider = switch route {
        case .appleCompressed:
            AppleCompressedSampleProvider()
        case .ffmpegCompressed:
            FFmpegSampleProvider(route: route)
        }
        self.init(
            route: route,
            traceID: traceID,
            provider: provider,
            audioProvider: FFmpegAudioSampleProvider(),
            rendererSink: nil
        )
    }

    init(
        route: PlaybackRoute,
        traceID: String,
        provider: VideoSampleProvider,
        audioProvider: AudioSampleProvider = NoAudioSampleProvider(),
        rendererSink: RendererInputSink? = nil,
        rendererFailureMonitor: RendererFailureMonitoring? = nil
    ) {
        self.route = route
        self.traceID = traceID
        self.videoTrackID = "\(traceID).video.0"
        precondition(provider.route == route)
        self.provider = provider
        self.audioProvider = audioProvider
        let usesSystemRendererSink = rendererSink == nil
        self.rendererSink = rendererSink ?? AVSampleBufferRendererInputSink(renderer: renderer)
        if let rendererFailureMonitor {
            self.rendererFailureMonitor = rendererFailureMonitor
        } else if usesSystemRendererSink {
            self.rendererFailureMonitor = AVRendererFailureMonitor(
                videoRenderer: renderer,
                audioRenderer: audioRenderer
            )
        }
        diagnostics.requestedRoute = route.rawValue
        diagnostics.selectedRoute = route.rawValue
        diagnostics.rendererInputKind = route.rendererInputKind.rawValue
        synchronizer.addRenderer(renderer)
        synchronizer.addRenderer(audioRenderer)
        PlaybackTrace.event(
            "session.init id=\(traceID) route=\(route.rawValue) " +
            "renderer=\(PlaybackTrace.identity(renderer)) synchronizer=\(PlaybackTrace.identity(synchronizer))"
        )
        timeObserver = synchronizer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: deliveryQueue
        ) { [weak self] time in
            self?.updatePresentationStatus(at: time)
        }
    }

    public func prepare(
        url: URL,
        startTime: CMTime = .zero,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        provenance: String = "appOpen",
        accessRequirement: String = "appAdapterManaged"
    ) async throws {
        PlaybackTrace.event(
            "session.prepare.begin id=\(traceID) start=\(startTime.seconds) paused=\(startsPaused)"
        )
        resetEndState(requiresAudio: false)
        let requestedRate = initialRate ?? 1
        preferredPlaybackRate = requestedRate > 0 ? requestedRate : 1
        timelineStartRate = startsPaused || requestedRate == 0
            ? 0
            : preferredPlaybackRate
        sourceURL = url
        availableAudioTracks = audioProvider.tracks(in: url)
        debugStore.recordAvailableAudioTracks(availableAudioTracks)
        requestedTimelineStart = startTime
        beginOperation(.open, targetTimeSeconds: startTime.seconds)
        let sourceRecord = MediaSourceRecord(
            locator: url,
            provenance: provenance,
            privacySafeSummary: url.lastPathComponent,
            accessRequirement: accessRequirement
        )
        let sessionRecord = MediaSessionRecord(
            mediaSessionID: traceID,
            source: sourceRecord,
            route: route,
            initialTimeSeconds: startTime.seconds,
            startsPaused: startsPaused,
            initialRate: initialRate ?? timelineStartRate
        )
        mediaSessionRecord = sessionRecord
        debugStore.recordSession(sessionRecord)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .mediaSessionAndRouteBinding,
            kind: "mediaSession.bound",
            outcome: .succeeded,
            details: ["source": url.lastPathComponent]
        )
        do {
            try await provider.prepare(url: url, startTime: startTime)
        } catch {
            recordFailure(error, node: .providerOpen, kind: "provider.openFailed")
            throw error
        }
        do {
            try audioProvider.prepare(
                url: url,
                startTime: startTime,
                streamIndex: selectedAudioStreamIndex
            )
            hasAudio = true
            if let info = audioProvider.info {
                selectedAudioStreamIndex = info.streamIndex
                debugStore.recordAudioTrack(AudioTrackRecord(
                    mediaSessionID: traceID,
                    audioTrackID: "\(traceID).audio.\(info.streamIndex)",
                    rawStreamIndex: info.streamIndex,
                    codecName: info.codecName,
                    sampleRate: info.sampleRate,
                    channelCount: info.channelCount,
                    selected: true
                ))
                debugStore.emit(
                    mediaSessionID: traceID,
                    route: route,
                    node: .videoTrackModel,
                    kind: "audioTrack.selected",
                    outcome: .succeeded,
                    details: [
                        "streamIndex": String(info.streamIndex),
                        "codec": info.codecName,
                        "sampleRate": String(info.sampleRate),
                        "channels": String(info.channelCount),
                    ]
                )
            }
        } catch AudioSampleProviderError.noAudioStream {
            hasAudio = false
            debugStore.recordAudioTrack(nil)
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .videoTrackModel,
                kind: "audioTrack.none",
                outcome: .succeeded
            )
        } catch {
            recordFailure(error, node: .providerOpen, kind: "audioProvider.openFailed")
            throw error
        }
        resetAudioEndState(requiresAudio: hasAudio)
        recordAudioRendererState()
        diagnostics.durationSeconds = provider.info.durationSeconds
        diagnostics.nominalFrameRate = provider.info.nominalFrameRate
        diagnostics.codecName = provider.info.codecName
        diagnostics.trackFormatHasMasteringDisplayMetadata = provider.info.trackFormatHasMasteringDisplayMetadata
        diagnostics.trackFormatHasContentLightLevelMetadata = provider.info.trackFormatHasContentLightLevelMetadata
        let openSnapshot = ProviderOpenSnapshot(
            mediaSessionID: traceID,
            route: route,
            sourceSummary: url.lastPathComponent,
            providerKind: provider.info.providerKind,
            containerFormat: provider.info.containerFormat,
            durationSeconds: provider.info.durationSeconds,
            seekability: provider.info.seekability,
            selectedRawTrackMapping: provider.info.selectedRawTrackMapping,
            codecName: provider.info.codecName,
            codecTag: provider.info.codecTag,
            dimensions: provider.info.dimensions,
            nominalFrameRate: provider.info.nominalFrameRate,
            timebase: provider.info.timebase,
            codecConfigurationSummary: provider.info.codecConfigurationSummary,
            formatSignaling: provider.info.formatSignaling
        )
        debugStore.recordProviderOpen(openSnapshot)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .providerOpen,
            kind: "provider.opened",
            outcome: .succeeded,
            details: [
                "provider": provider.info.providerKind,
                "codec": provider.info.codecName,
                "codecTag": provider.info.codecTag,
                "dimensions": provider.info.dimensions,
            ]
        )
        let trackRecord = VideoTrackRecord(
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            rawSourceMapping: provider.info.selectedRawTrackMapping.value
                ?? provider.info.selectedRawTrackMapping.availability.rawValue,
            codecName: provider.info.codecName,
            sourceSnapshotID: openSnapshot.snapshotID,
            dimensions: provider.info.dimensions,
            nominalFrameRate: provider.info.nominalFrameRate,
            timebase: provider.info.timebase,
            formatSummary: "\(provider.info.codecTag) \(provider.info.dimensions)",
            selected: true
        )
        debugStore.recordVideoTrack(trackRecord)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .videoTrackModel,
            kind: "videoTrack.selected",
            outcome: .succeeded,
            details: ["videoTrackID": videoTrackID]
        )

        logger.info("Prepared route=\(self.route.rawValue, privacy: .public) codec=\(self.diagnostics.codecName, privacy: .public) duration=\(self.diagnostics.durationSeconds, format: .fixed(precision: 3))s")
        PlaybackTrace.event(
            "session.prepare.end id=\(traceID) codec=\(diagnostics.codecName) " +
            "duration=\(diagnostics.durationSeconds)"
        )
        startRendererFailureMonitoring()
    }

    public func start() throws {
        guard !isClosed else { return }
        let shouldStart = deliveryQueue.sync {
            guard !hasRequestedVideoData else { return false }
            hasRequestedVideoData = true
            return true
        }
        guard shouldStart else {
            PlaybackTrace.event("session.start.alreadyStarted id=\(traceID)")
            return
        }
        PlaybackTrace.event("session.start.begin id=\(traceID)")
        do {
            try provider.start()
        } catch {
            recordFailure(error, node: .routeMediaEventStream, kind: "provider.startFailed")
            throw error
        }
        rendererSink.requestMediaDataWhenReady(on: deliveryQueue) { [weak self] in
            self?.deliverSamples()
        }
        if hasAudio {
            audioRenderer.requestMediaDataWhenReady(on: audioDeliveryQueue) { [weak self] in
                self?.deliverAudioSamples()
            }
        }
        PlaybackTrace.event("session.start.end id=\(traceID)")
    }

    public func play() throws {
        try admitTimelineControl(.play)
        beginOperation(.play, targetRate: preferredPlaybackRate)
        synchronizer.rate = preferredPlaybackRate
        updateLifecycle(.playing)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.play.completed",
            outcome: .succeeded
        )
        finishActiveOperation(.completed)
        onStatusChange?(.playing)
    }

    public func pause() throws {
        try admitTimelineControl(.pause)
        beginOperation(.pause, targetRate: 0)
        synchronizer.rate = 0
        updateLifecycle(.paused)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.pause.completed",
            outcome: .succeeded
        )
        finishActiveOperation(.completed)
        publishDiagnostics(at: synchronizer.currentTime(), force: true)
        onStatusChange?(.paused)
    }

    public func setRate(_ rate: Float) throws {
        guard rate.isFinite, rate >= 0 else {
            rejectControl(.setRate, reason: "invalidRate", targetRate: rate)
            throw PlaybackControlError.invalidRate(rate)
        }
        try admitTimelineControl(.setRate, targetRate: rate)
        beginOperation(.setRate, targetRate: rate)
        if rate > 0 {
            preferredPlaybackRate = rate
        }
        timelineStartRate = rate
        synchronizer.rate = rate
        let lifecycle: PlaybackLifecycle = rate == 0 ? .paused : .playing
        updateLifecycle(lifecycle)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.setRate.completed",
            outcome: .succeeded,
            details: ["rate": String(rate)]
        )
        finishActiveOperation(.completed)
        onStatusChange?(rate == 0 ? .paused : .playing)
    }

    public var effectiveStereoLayout: VideoStereoLayout {
        let snapshot = debugStore.snapshot()
        if let sample = snapshot.lastVideoSample,
           let input = snapshot.lastAcceptedRendererInput,
           input.sourceEventID == sample.sourceEventID,
           input.formatRevision == sample.formatRevision,
           input.outcome == .accepted {
            return Self.stereoLayout(
                forViewPackingKind: sample.formatSignaling.viewPackingKind.value
            )
        }
        let explicit = deliveryQueue.sync { stereoLayoutOverride }
        if let explicit { return explicit }
        let packing = snapshot.providerOpen?.formatSignaling.viewPackingKind.value
        return Self.stereoLayout(forViewPackingKind: packing)
    }

    @discardableResult
    func setStereoLayout(_ layout: VideoStereoLayout) async throws -> UInt64 {
        try await setStereoLayoutOverride(layout)
    }

    @discardableResult
    func clearStereoLayoutOverride() async throws -> UInt64 {
        try await setStereoLayoutOverride(nil)
    }

    private func setStereoLayoutOverride(
        _ layout: VideoStereoLayout?
    ) async throws -> UInt64 {
        guard !isClosed else { throw PlaybackControlError.mediaSessionClosed }
        let currentOverride = deliveryQueue.sync { stereoLayoutOverride }
        if currentOverride == layout {
            let state = deliveryQueue.sync { (hasRequestedVideoData, formatRevision) }
            if !state.0 { return state.1 }
            return try await waitForStereoLayout(
                layout,
                minimumRevision: state.1
            )
        }
        if deliveryQueue.sync(execute: { hasRequestedVideoData }), videoProviderHasEnded {
            throw CorePlaybackError.stereoOverrideUnavailable(layout)
        }

        let change = applyStereoLayoutOverride(layout)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.stereo.started",
            outcome: .succeeded,
            details: [
                "layout": layout?.rawValue ?? "source",
                "formatRevision": String(change.revision),
            ]
        )
        guard change.awaitsSample else {
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .rendererInputCoordination,
                kind: "control.stereo.completed",
                outcome: .succeeded,
                details: [
                    "layout": layout?.rawValue ?? "source",
                    "formatRevision": String(change.revision),
                    "boundary": "beforeFirstSample",
                ]
            )
            return change.revision
        }

        let effectiveRevision: UInt64
        do {
            effectiveRevision = try await waitForStereoLayout(
                layout,
                minimumRevision: change.revision
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                debugStore.emit(
                    mediaSessionID: traceID,
                    route: route,
                    node: .rendererInputCoordination,
                    kind: "control.stereo.cancelled",
                    outcome: .terminatedByCleanup,
                    details: ["layout": layout?.rawValue ?? "source"]
                )
                throw error
            }
            let rollback = applyStereoLayoutOverride(change.previous)
            var rollbackState = "restoredBeforeFirstSample"
            if rollback.awaitsSample {
                do {
                    _ = try await waitForStereoLayout(
                        change.previous,
                        minimumRevision: rollback.revision
                    )
                    rollbackState = "restored"
                } catch {
                    rollbackState = "failed"
                }
            }
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .rendererInputCoordination,
                kind: "control.stereo.failed",
                outcome: .failed,
                details: [
                    "layout": layout?.rawValue ?? "source",
                    "rollback": rollbackState,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }

        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.stereo.completed",
            outcome: .succeeded,
            details: [
                "layout": layout?.rawValue ?? "source",
                "formatRevision": String(effectiveRevision),
            ]
        )
        return effectiveRevision
    }

    private struct StereoLayoutChange {
        let previous: VideoStereoLayout?
        let revision: UInt64
        let awaitsSample: Bool
        let shouldResumeDelivery: Bool
    }

    private func applyStereoLayoutOverride(
        _ layout: VideoStereoLayout?
    ) -> StereoLayoutChange {
        rendererSink.stopRequestingMediaData()
        let change = deliveryQueue.sync {
            let providerResetIsInFlight = isResetting
            let previous = stereoLayoutOverride
            stereoLayoutOverride = layout
            if diagnostics.enqueuedSampleCount > 0 {
                formatRevision += 1
            }
            didRecordFormat = false
            let awaitsSample = hasRequestedVideoData
                && !videoProviderHasEnded
                && !isClosed
                && renderer.status != .failed
            return StereoLayoutChange(
                previous: previous,
                revision: formatRevision,
                awaitsSample: awaitsSample,
                shouldResumeDelivery: awaitsSample && !providerResetIsInFlight
            )
        }
        if change.shouldResumeDelivery {
            rendererSink.requestMediaDataWhenReady(on: deliveryQueue) { [weak self] in
                self?.deliverSamples()
            }
        }
        return change
    }

    private func waitForStereoLayout(
        _ layout: VideoStereoLayout?,
        minimumRevision: UInt64
    ) async throws -> UInt64 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let snapshot = debugStore.snapshot()
            if let sample = snapshot.lastVideoSample,
               let input = snapshot.lastAcceptedRendererInput,
               sample.formatRevision >= minimumRevision,
               input.formatRevision == sample.formatRevision,
               input.sourceEventID == sample.sourceEventID,
               input.outcome == .accepted,
               stereoLayout(layout, matches: sample.formatSignaling.viewPackingKind.value) {
                return sample.formatRevision
            }
            if videoProviderHasEnded {
                break
            }
            if isClosed || renderer.status == .failed {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CorePlaybackError.stereoOverrideTimedOut(layout)
    }

    private func stereoLayout(
        _ layout: VideoStereoLayout?,
        matches viewPackingKind: String?
    ) -> Bool {
        guard let layout else {
            let sourcePacking = debugStore.snapshot().providerOpen?
                .formatSignaling.viewPackingKind.value
            return Self.normalizedPacking(viewPackingKind) == Self.normalizedPacking(sourcePacking)
        }
        switch layout {
        case .mono:
            return viewPackingKind == nil
        case .sideBySide:
            return Self.normalizedPacking(viewPackingKind).contains("sidebyside")
        case .overUnder:
            return Self.normalizedPacking(viewPackingKind).contains("overunder")
        }
    }

    private static func stereoLayout(forViewPackingKind value: String?) -> VideoStereoLayout {
        let normalized = normalizedPacking(value)
        if normalized.contains("sidebyside") { return .sideBySide }
        if normalized.contains("overunder") || normalized.contains("topbottom") {
            return .overUnder
        }
        return .mono
    }

    private static func normalizedPacking(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public var effectiveProjectionKind: String? {
        let snapshot = debugStore.snapshot()
        if let sample = snapshot.lastVideoSample,
           let input = snapshot.lastAcceptedRendererInput,
           input.sourceEventID == sample.sourceEventID,
           input.formatRevision == sample.formatRevision,
           input.outcome == .accepted {
            return sample.formatSignaling.projectionKind.value
        }
        if let projection = deliveryQueue.sync(execute: { projectionOverride }) {
            return Self.projectionKind(for: projection)
        }
        return snapshot.providerOpen?.formatSignaling.projectionKind.value
    }

    @discardableResult
    func setProjectionOverride(_ projection: VideoProjectionOverride) async throws -> UInt64 {
        try await setProjectionOverrideValue(projection)
    }

    @discardableResult
    func clearProjectionOverride() async throws -> UInt64 {
        try await setProjectionOverrideValue(nil)
    }

    private func setProjectionOverrideValue(
        _ projection: VideoProjectionOverride?
    ) async throws -> UInt64 {
        guard !isClosed else { throw PlaybackControlError.mediaSessionClosed }
        let currentOverride = deliveryQueue.sync { projectionOverride }
        if currentOverride == projection {
            let state = deliveryQueue.sync { (hasRequestedVideoData, formatRevision) }
            if !state.0 { return state.1 }
            return try await waitForProjectionOverride(
                projection,
                minimumRevision: state.1
            )
        }
        if deliveryQueue.sync(execute: { hasRequestedVideoData }), videoProviderHasEnded {
            throw CorePlaybackError.projectionOverrideUnavailable(projection)
        }

        let change = applyProjectionOverride(projection)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.projection.started",
            outcome: .succeeded,
            details: [
                "projection": projection?.rawValue ?? "source",
                "formatRevision": String(change.revision),
            ]
        )
        guard change.awaitsSample else {
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .rendererInputCoordination,
                kind: "control.projection.completed",
                outcome: .succeeded,
                details: [
                    "projection": projection?.rawValue ?? "source",
                    "formatRevision": String(change.revision),
                    "boundary": "beforeFirstSample",
                ]
            )
            return change.revision
        }

        let effectiveRevision: UInt64
        do {
            effectiveRevision = try await waitForProjectionOverride(
                projection,
                minimumRevision: change.revision
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                debugStore.emit(
                    mediaSessionID: traceID,
                    route: route,
                    node: .rendererInputCoordination,
                    kind: "control.projection.cancelled",
                    outcome: .terminatedByCleanup,
                    details: ["projection": projection?.rawValue ?? "source"]
                )
                throw error
            }
            let rollback = applyProjectionOverride(change.previous)
            var rollbackState = "restoredBeforeFirstSample"
            if rollback.awaitsSample {
                do {
                    _ = try await waitForProjectionOverride(
                        change.previous,
                        minimumRevision: rollback.revision
                    )
                    rollbackState = "restored"
                } catch {
                    rollbackState = "failed"
                }
            }
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .rendererInputCoordination,
                kind: "control.projection.failed",
                outcome: .failed,
                details: [
                    "projection": projection?.rawValue ?? "source",
                    "rollback": rollbackState,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }

        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "control.projection.completed",
            outcome: .succeeded,
            details: [
                "projection": projection?.rawValue ?? "source",
                "formatRevision": String(effectiveRevision),
            ]
        )
        return effectiveRevision
    }

    private struct ProjectionChange {
        let previous: VideoProjectionOverride?
        let revision: UInt64
        let awaitsSample: Bool
        let shouldResumeDelivery: Bool
    }

    private func applyProjectionOverride(
        _ projection: VideoProjectionOverride?
    ) -> ProjectionChange {
        rendererSink.stopRequestingMediaData()
        let change = deliveryQueue.sync {
            let providerResetIsInFlight = isResetting
            let previous = projectionOverride
            projectionOverride = projection
            if diagnostics.enqueuedSampleCount > 0 {
                formatRevision += 1
            }
            didRecordFormat = false
            let awaitsSample = hasRequestedVideoData
                && !videoProviderHasEnded
                && !isClosed
                && renderer.status != .failed
            return ProjectionChange(
                previous: previous,
                revision: formatRevision,
                awaitsSample: awaitsSample,
                shouldResumeDelivery: awaitsSample && !providerResetIsInFlight
            )
        }
        if change.shouldResumeDelivery {
            rendererSink.requestMediaDataWhenReady(on: deliveryQueue) { [weak self] in
                self?.deliverSamples()
            }
        }
        return change
    }

    private func waitForProjectionOverride(
        _ projection: VideoProjectionOverride?,
        minimumRevision: UInt64
    ) async throws -> UInt64 {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let snapshot = debugStore.snapshot()
            if let sample = snapshot.lastVideoSample,
               let input = snapshot.lastAcceptedRendererInput,
               sample.formatRevision >= minimumRevision,
               input.formatRevision == sample.formatRevision,
               input.sourceEventID == sample.sourceEventID,
               input.outcome == .accepted,
               projectionOverride(
                   projection,
                   matches: sample.formatSignaling.projectionKind.value,
                   source: snapshot.providerOpen?.formatSignaling.projectionKind.value
               ) {
                return sample.formatRevision
            }
            if videoProviderHasEnded || isClosed || renderer.status == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CorePlaybackError.projectionOverrideTimedOut(projection)
    }

    private func projectionOverride(
        _ projection: VideoProjectionOverride?,
        matches projectionKind: String?,
        source sourceProjectionKind: String?
    ) -> Bool {
        let normalized = Self.normalizedProjection(projectionKind)
        switch projection {
        case .rectilinear:
            return normalized.contains("rectilinear")
        case .equirectangular:
            return normalized.contains("equirectangular")
                && !normalized.contains("halfequirectangular")
        case .halfEquirectangular:
            return normalized.contains("halfequirectangular")
        case nil:
            return normalized == Self.normalizedProjection(sourceProjectionKind)
        }
    }

    private static func projectionKind(for projection: VideoProjectionOverride) -> String {
        switch projection {
        case .rectilinear:
            kCMFormatDescriptionProjectionKind_Rectilinear as String
        case .equirectangular:
            kCMFormatDescriptionProjectionKind_Equirectangular as String
        case .halfEquirectangular:
            kCMFormatDescriptionProjectionKind_HalfEquirectangular as String
        }
    }

    private static func normalizedProjection(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public func seek(to time: CMTime, startsPaused: Bool) async throws {
        guard !isClosed, let sourceURL else { return }
        try Task.checkCancellation()
        let target = max(0, time.seconds.isFinite ? time.seconds : 0)
        let currentRate = currentRate()
        let preservedRate: Float = startsPaused
            ? 0
            : (currentRate > 0 ? currentRate : preferredPlaybackRate)
        beginOperation(.seek, targetTimeSeconds: target)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "control.seek.started",
            outcome: .succeeded,
            details: ["targetSeconds": String(target)]
        )

        rendererSink.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        synchronizer.rate = 0
        deliveryQueue.sync {
            isResetting = true
            provider.cancel()
        }
        audioDeliveryQueue.sync {
            audioProvider.cancel()
        }
        await withCheckedContinuation { continuation in
            rendererSink.flush(removingDisplayedImage: true) {
                continuation.resume()
            }
        }
        audioRenderer.flush()
        resetEndState(requiresAudio: hasAudio)

        streamEpoch += 1
        audioStreamEpoch += 1
        flushCount += 1
        recordRendererState(at: currentTime())
        sourceEventSequence += 1
        let flushEvent = RouteMediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .flush,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordRouteEvent(flushEvent)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "renderer.flushedForSeek",
            outcome: .succeeded,
            details: ["streamEpoch": String(streamEpoch)]
        )

        do {
            try await provider.prepare(
                url: sourceURL,
                startTime: CMTime(seconds: target, preferredTimescale: 60_000)
            )
            try Task.checkCancellation()
            try provider.start()
            if hasAudio {
                try audioProvider.prepare(
                    url: sourceURL,
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
                    route: route,
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
        updateLifecycle(.ready)
        rendererSink.requestMediaDataWhenReady(on: deliveryQueue) { [weak self] in
            self?.deliverSamples()
        }
        if hasAudio {
            audioRenderer.requestMediaDataWhenReady(on: audioDeliveryQueue) { [weak self] in
                self?.deliverAudioSamples()
            }
        }

        let expectedEpoch = streamEpoch
        let expectedAudioEpoch = audioStreamEpoch
        let deadline = ContinuousClock.now + .seconds(5)
        do {
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let snapshot = debugStore.snapshot()
                let audioReady = !hasAudio || (
                    snapshot.lastAudioSample?.streamEpoch == expectedAudioEpoch &&
                    (snapshot.lastAudioSample?.presentationTimeSeconds ?? -.infinity) >= target
                )
                if let sample = snapshot.lastVideoSample,
                   let input = snapshot.lastAcceptedRendererInput,
                   sample.streamEpoch == expectedEpoch,
                   sample.presentationTimeSeconds >= target,
                   input.streamEpoch == expectedEpoch,
                   input.sourceEventID == sample.sourceEventID,
                   input.outcome == .accepted,
                   audioReady {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        route: route,
                        kind: "control.seek.completed",
                        outcome: .succeeded,
                        details: [
                            "targetSeconds": String(target),
                            "streamEpoch": String(expectedEpoch),
                            "audioStreamEpoch": String(expectedAudioEpoch),
                        ]
                    )
                    finishActiveOperation(.completed)
                    return
                }
                if let endEvent = snapshot.lastRouteEvent,
                   endEvent.kind == .end,
                   endEvent.streamEpoch == expectedEpoch,
                   targetEpochEndedBeforeVideoPTS(target) {
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
                    route: route,
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

    public func currentTime() -> CMTime {
        hasStartedTimeline ? synchronizer.currentTime() : .zero
    }

    public func currentRate() -> Float {
        hasStartedTimeline ? synchronizer.rate : timelineStartRate
    }

    public var currentVolume: Float {
        audioRenderer.volume
    }

    public var isMuted: Bool {
        audioRenderer.isMuted
    }

    public func setVolume(_ volume: Float) throws {
        guard volume.isFinite, (0...1).contains(volume) else {
            throw PlaybackControlError.invalidVolume(volume)
        }
        audioRenderer.volume = volume
        recordAudioRendererState()
    }

    public func setMuted(_ muted: Bool) {
        audioRenderer.isMuted = muted
        recordAudioRendererState()
    }

    public func selectAudioTrack(streamIndex: Int) throws {
        guard let sourceURL else { throw PlaybackControlError.noActiveMediaSession }
        guard availableAudioTracks.contains(where: { $0.streamIndex == streamIndex }) else {
            throw PlaybackControlError.invalidAudioTrack(streamIndex)
        }
        guard streamIndex != selectedAudioStreamIndex else { return }
        let previousStreamIndex = selectedAudioStreamIndex
        let previouslyHadAudio = hasAudio
        let time = currentTime()
        let rate = currentRate()
        synchronizer.rate = 0
        audioRenderer.stopRequestingMediaData()
        audioDeliveryQueue.sync { audioProvider.cancel() }
        audioRenderer.flush()
        resetAudioEndState(requiresAudio: previouslyHadAudio)
        do {
            try audioProvider.prepare(url: sourceURL, startTime: time, streamIndex: streamIndex)
        } catch {
            let replacementError = error
            do {
                try audioProvider.prepare(
                    url: sourceURL,
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
                audioRenderer.requestMediaDataWhenReady(on: audioDeliveryQueue) { [weak self] in
                    self?.deliverAudioSamples()
                }
            }
            synchronizer.setRate(rate, time: time)
            recordAudioRendererState()
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
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
        audioRenderer.requestMediaDataWhenReady(on: audioDeliveryQueue) { [weak self] in
            self?.deliverAudioSamples()
        }
        synchronizer.setRate(rate, time: time)
        recordAudioRendererState()
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "control.audioTrack.completed",
            outcome: .succeeded,
            details: ["streamIndex": String(streamIndex)]
        )
    }

    public func debugEvents() -> AsyncStream<PlaybackDebugEvent> {
        debugStore.events()
    }

    public func debugSnapshot() -> PlaybackDebugSnapshotV1 {
        debugStore.snapshot()
    }

    public func debugSnapshotJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(debugStore.snapshot()), as: UTF8.self)
    }

    public func correlateEvidenceID(_ evidenceID: String) {
        debugStore.correlateEvidenceID(evidenceID)
    }

    public func recordDebugCommand(_ command: String) {
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "debug.command.received",
            outcome: .succeeded,
            details: ["command": command]
        )
    }

    private func admitTimelineControl(
        _ kind: PlaybackOperationKind,
        targetRate: Float? = nil
    ) throws {
        guard !isClosed else {
            rejectControl(kind, reason: "mediaSessionClosed", targetRate: targetRate)
            throw PlaybackControlError.mediaSessionClosed
        }
        guard hasStartedTimeline else {
            rejectControl(kind, reason: "timelineNotReady", targetRate: targetRate)
            throw PlaybackControlError.timelineNotReady
        }
    }

    private func rejectControl(
        _ kind: PlaybackOperationKind,
        reason: String,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil
    ) {
        let rejection = ControlRejectionRecord(
            mediaSessionID: traceID,
            kind: kind,
            reason: reason,
            targetTimeSeconds: targetTimeSeconds,
            targetRate: targetRate
        )
        debugStore.recordControlRejection(rejection)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "control.\(kind.rawValue).rejected",
            outcome: .failed,
            details: ["reason": reason]
        )
    }

    public func registerPendingRouteSwitch(
        from sourceRoute: PlaybackRoute,
        startedAt: Date
    ) {
        let operation = PlaybackOperationRecord(
            mediaSessionID: traceID,
            kind: .switchRoute,
            startedAt: startedAt,
            sourceRoute: sourceRoute,
            targetRoute: route
        )
        pendingRouteSwitchOperation = operation
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "operation.switchRoute.started",
            outcome: .succeeded,
            details: [
                "operationID": operation.operationID,
                "sourceRoute": sourceRoute.rawValue,
                "targetRoute": route.rawValue,
            ]
        )
    }

    public func recordSupersededSeekRequest(targetSeconds: Double) {
        let operation = PlaybackOperationRecord(
            mediaSessionID: traceID,
            kind: .seek,
            targetTimeSeconds: targetSeconds,
            sourceRoute: route
        ).finishing(as: .terminatedByCleanup)
        debugStore.recordOperation(operation)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "operation.seek.superseded",
            outcome: .terminatedByCleanup,
            details: [
                "operationID": operation.operationID,
                "targetSeconds": String(targetSeconds),
            ]
        )
    }

    public func recordRealityKitBinding(entityIdentity: String, active: Bool) {
        let current = debugStore.snapshot().realityKitBinding
        if isClosed || (active && current?.entityIdentity != nil && current?.entityIdentity != entityIdentity) ||
            (!active && current?.entityIdentity != nil && current?.entityIdentity != entityIdentity) {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .realityKitRendererBinding,
                kind: "realityKit.bindingRejected",
                outcome: .failed,
                details: ["entity": entityIdentity]
            )
            return
        }
        if active, current?.entityIdentity == entityIdentity, current?.active == true { return }
        if !active, current == nil { return }
        let record = active ? RealityKitBindingRecord(
            mediaSessionID: traceID,
            route: route,
            bindingID: "\(traceID).realityKitBinding",
            graphID: "\(traceID).rendererGraph",
            rendererIdentity: PlaybackTrace.identity(renderer),
            componentAttached: true,
            componentRendererIdentity: PlaybackTrace.identity(renderer),
            entityIdentity: entityIdentity,
            active: true
        ) : nil
        debugStore.recordRealityKitBinding(record)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .realityKitRendererBinding,
            kind: active ? "realityKit.bound" : "realityKit.unbound",
            outcome: active ? .succeeded : .terminatedByCleanup,
            details: ["entity": entityIdentity]
        )
    }

    public func recordPresentationBinding(
        realityViewIdentity: String,
        platform: String,
        attached: Bool,
        sceneContainer: String = "WindowGroup",
        sceneLifecycle: String = "activeRealityView"
    ) {
        let current = debugStore.snapshot().presentationBinding
        if isClosed ||
            (attached && current?.realityViewIdentity != nil &&
                current?.realityViewIdentity != realityViewIdentity) ||
            (!attached && current?.realityViewIdentity != nil &&
                current?.realityViewIdentity != realityViewIdentity) {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .realityViewPresentation,
                kind: "presentation.bindingRejected",
                outcome: .failed,
                details: ["realityView": realityViewIdentity]
            )
            return
        }
        if attached,
           current?.realityViewIdentity == realityViewIdentity,
           current?.entityAttached == true { return }
        if !attached, current == nil { return }
        if attached, mediaSessionRecord?.lifecycle == .opening {
            updateLifecycle(.ready)
        }
        let record = attached ? PresentationBindingRecord(
            mediaSessionID: traceID,
            route: route,
            presentationBindingID: "\(traceID).presentationBinding",
            rendererBindingID: "\(traceID).realityKitBinding",
            realityViewIdentity: realityViewIdentity,
            entityAttached: true,
            platform: platform,
            provenance: "appAdapter",
            appAdapterKind: platform == "macOS" ? "PlaybackLab" : "PlaybackLabVision",
            sceneContainer: .init(.known, value: sceneContainer),
            sceneLifecycle: .init(.known, value: sceneLifecycle)
        ) : nil
        debugStore.recordPresentationBinding(record)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .realityViewPresentation,
            kind: attached ? "presentation.attached" : "presentation.detached",
            outcome: attached ? .succeeded : .terminatedByCleanup,
            details: [
                "realityView": realityViewIdentity,
                "platform": platform,
            ]
        )
        if attached, activeOperation?.kind == .open {
            finishActiveOperation(.completed)
        }
        if attached {
            finishPendingRouteSwitch(.completed)
        }
    }

    public func recordPresentationState(_ record: PresentationStateRecord) {
        guard !isClosed,
              record.mediaSessionID == traceID,
              record.route == route else {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .realityViewPresentation,
                kind: "presentation.stateRejected",
                outcome: .failed
            )
            return
        }
        debugStore.recordPresentationState(record)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .realityViewPresentation,
            kind: "presentation.stateChanged",
            outcome: record.transitionError.availability == .known ? .failed : .succeeded,
            details: [
                "requestedMode": record.requestedMode,
                "phase": record.phase,
            ]
        )
    }

    public func close() {
        close(completion: {})
    }

    public func closeAndWait() async {
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
            "rendererStatus=\(renderer.status) displayed=\(renderer.displayedPixelBuffer() != nil)"
        )
        if activeOperation != nil {
            finishActiveOperation(.terminatedByCleanup)
        }
        finishPendingRouteSwitch(.terminatedByCleanup)
        beginOperation(.close)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "session.cleanup",
            outcome: .terminatedByCleanup
        )
        closeEndState()
        rendererSink.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
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
        audioRenderer.flush()
        debugStore.recordCleanupStep(.audioRendererFlushed)
        rendererSink.flush(removingDisplayedImage: true) { [self] in
            finishCloseAfterFlush()
        }
    }

    private func finishCloseAfterFlush() {
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

    private func deliverSamples() {
        while rendererSink.isReadyForMoreMediaData, !isClosed, !isResetting {
            let sourceSample: CMSampleBuffer
            do {
                let event = try provider.copyNextEvent()
                switch event {
                case .sample(let sample):
                    sourceSample = sample
                case .formatChanged:
                    handleProviderControlEvent(.formatChanged)
                    return
                case .flush:
                    handleProviderControlEvent(.flush)
                    return
                case .end:
                    finishDelivery()
                    return
                }
            } catch {
                rendererSink.stopRequestingMediaData()
                provider.cancel()
                recordRouteErrorEvent()
                recordFailure(error, node: .routeMediaEventStream, kind: "provider.readFailed")
                onStatusChange?(.failed(error.localizedDescription))
                return
            }

            guard CMSampleBufferGetNumSamples(sourceSample) > 0,
                  CMSampleBufferGetFormatDescription(sourceSample) != nil else {
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
                rendererSink.stopRequestingMediaData()
                recordFailure(
                    error,
                    node: .rendererInputCoordination,
                    kind: "videoFormatOverride.failed"
                )
                onStatusChange?(.failed(error.localizedDescription))
                return
            }
            let sourceEventID = recordVideoSample(renderSample)
            updateCompressedDiagnostics(sample: renderSample)
            lastSourceEventID = sourceEventID

            markAsPrerollIfNeeded(renderSample, presentationTime: presentationTime)
            if !hasStartedTimeline {
                let hasPreroll = requestedTimelineStart.isNumeric &&
                    requestedTimelineStart > presentationTime
                let timelineStart = hasPreroll ? presentationTime : targetTimelineTime(
                    fallback: presentationTime
                )
                let initialRate: Float = hasPreroll ? 1 : timelineStartRate
                PlaybackTrace.event(
                    "session.firstSample id=\(traceID) pts=\(presentationTime.seconds) " +
                    "timelineStart=\(timelineStart.seconds) " +
                    "input=\(route.rendererInputKind)"
                )
                synchronizer.setRate(initialRate, time: timelineStart)
                hasStartedTimeline = true
                isPrerolling = hasPreroll
                if !hasPreroll {
                    publishTargetTimelineState(at: timelineStart)
                }
                PlaybackTrace.event(
                    "session.timeline.set id=\(traceID) rate=\(initialRate) " +
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
            }
            diagnostics.enqueuedSampleCount += 1
            rendererSink.enqueue(renderSample)
            let rendererRecord = RendererInputRecord(
                mediaSessionID: traceID,
                route: route,
                sourceEventID: lastSourceEventID,
                videoTrackID: videoTrackID,
                streamEpoch: streamEpoch,
                formatRevision: formatRevision,
                graphRevision: 1,
                inputKind: route.rendererInputKind,
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
                    route: route,
                    node: .rendererInputCoordination,
                    kind: "renderer.firstEnqueue",
                    outcome: .succeeded,
                    details: [
                        "timelineConfiguredBeforeFirstEnqueue": String(hasStartedTimeline),
                        "sourceEventID": lastSourceEventID,
                    ]
                )
                PlaybackTrace.event(
                    "session.firstEnqueue id=\(traceID) rendererStatus=\(renderer.status) " +
                    "rendererError=\(renderer.error?.localizedDescription ?? "none")"
                )
            }
        }
        if !isClosed, !videoProviderHasEnded, !rendererSink.isReadyForMoreMediaData {
            debugStore.recordRendererInput(RendererInputRecord(
                mediaSessionID: traceID,
                route: route,
                sourceEventID: lastSourceEventID,
                videoTrackID: videoTrackID,
                streamEpoch: streamEpoch,
                formatRevision: formatRevision,
                graphRevision: 1,
                inputKind: route.rendererInputKind,
                timelineConfiguredBeforeFirstEnqueue: hasStartedTimeline,
                action: "readiness",
                outcome: .deferredByBackpressure
            ))
        }
    }

    private func deliverAudioSamples() {
        while audioRenderer.isReadyForMoreMediaData, !isClosed, !isResetting {
            do {
                guard let sample = try audioProvider.copyNextSample() else {
                    audioRenderer.stopRequestingMediaData()
                    markAudioProviderEnded()
                    debugStore.emit(
                        mediaSessionID: traceID,
                        route: route,
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
                audioRenderer.enqueue(sample)
                audioSampleBufferCount += 1
                audioFrameCount += UInt64(max(0, record.sampleCount))
                if audioSampleBufferCount == 1 {
                    debugStore.emit(
                        mediaSessionID: traceID,
                        route: route,
                        kind: "audioRenderer.firstEnqueue",
                        outcome: .succeeded,
                        details: ["audioTrackID": trackID]
                    )
                }
                recordAudioRendererState()
            } catch {
                audioRenderer.stopRequestingMediaData()
                recordFailure(error, node: .rendererInputCoordination, kind: "audioRenderer.deliveryFailed")
                onStatusChange?(.failed(error.localizedDescription))
                return
            }
        }
    }

    private func recordAudioRendererState() {
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
            error: audioRenderer.error?.localizedDescription
        ))
    }


    private func finishDelivery() {
        rendererSink.stopRequestingMediaData()
        markVideoProviderEnded()
        sourceEventSequence += 1
        let event = RouteMediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .end,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordRouteEvent(event)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .routeMediaEventStream,
            kind: "provider.inputEnded",
            outcome: .succeeded
        )
    }

    private func handleProviderControlEvent(_ kind: RouteMediaEventKind) {
        rendererSink.stopRequestingMediaData()
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
        let event = RouteMediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: kind,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordRouteEvent(event)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .routeMediaEventStream,
            kind: "provider.\(kind.rawValue)",
            outcome: .succeeded,
            details: [
                "streamEpoch": String(streamEpoch),
                "formatRevision": String(formatRevision),
            ]
        )
        didRecordFormat = false
        resetVideoEndState()
        flushCount += 1
        rendererSink.flush(removingDisplayedImage: false) { [weak self] in
            guard let self else { return }
            self.deliveryQueue.async { [self] in
                guard !self.isClosed else { return }
                self.isResetting = false
                self.recordRendererState(at: self.currentTime())
                self.rendererSink.requestMediaDataWhenReady(on: self.deliveryQueue) { [weak self] in
                    self?.deliverSamples()
                }
            }
        }
    }

    private func recordRouteErrorEvent() {
        sourceEventSequence += 1
        debugStore.recordRouteEvent(RouteMediaEventRecord(
            eventID: "\(traceID).event.\(sourceEventSequence)",
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .error,
            providerProvenance: provider.info.providerKind
        ))
    }

    private func resetEndState(requiresAudio: Bool) {
        endStateLock.withLock {
            endState = EndState()
            endState.requiresAudio = requiresAudio
            endState.audioProviderEnded = !requiresAudio
        }
    }

    private func resetVideoEndState() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.videoProviderEnded = false
            endState.maximumVideoPresentationTime = nil
            endState.videoPresentationEnd = nil
            endState.didReportEnd = false
        }
    }

    private func resetAudioEndState(requiresAudio: Bool) {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.requiresAudio = requiresAudio
            endState.audioProviderEnded = !requiresAudio
            endState.audioPresentationEnd = nil
            endState.didReportEnd = false
        }
    }

    private func closeEndState() {
        endStateLock.withLock {
            endState = EndState()
            endState.isClosed = true
        }
    }

    private func recordVideoPresentation(
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

    private func targetEpochEndedBeforeVideoPTS(_ targetSeconds: Double) -> Bool {
        endStateLock.withLock {
            guard endState.videoProviderEnded else { return false }
            guard let maximumPTS = endState.maximumVideoPresentationTime,
                  maximumPTS.isNumeric else { return true }
            return maximumPTS.seconds < targetSeconds
        }
    }

    private func recordAudioPresentationEnd(_ presentationEnd: CMTime) {
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

    private func markVideoProviderEnded() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.videoProviderEnded = true
        }
    }

    private func markAudioProviderEnded() {
        endStateLock.withLock {
            guard !endState.isClosed else { return }
            endState.audioProviderEnded = true
        }
    }

    private var videoProviderHasEnded: Bool {
        endStateLock.withLock { endState.videoProviderEnded }
    }

    private func claimEndIfReady(at time: CMTime) -> Bool {
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

    private func updatePresentationStatus(at time: CMTime) {
        publishDiagnostics(at: time)
        guard claimEndIfReady(at: time) else { return }
        synchronizer.rate = 0
        updateLifecycle(.ended)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: .rendererInputCoordination,
            kind: "timeline.ended",
            outcome: .succeeded
        )
        onStatusChange?(.ended)
    }

    private func publishDiagnostics(at time: CMTime, force: Bool = false) {
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        let wholeSecond = Int(seconds * 2)
        guard force || wholeSecond != lastDiagnosticsSecond else { return }
        lastDiagnosticsSecond = wholeSecond
        diagnostics.currentSeconds = seconds
        diagnostics.rendererStatus = String(describing: renderer.status)
        diagnostics.rendererError = renderer.error?.localizedDescription ?? "none"
        recordRendererState(at: time)
        PlaybackTrace.event(
            "session.heartbeat id=\(traceID) time=\(time.seconds) samples=\(diagnostics.enqueuedSampleCount) " +
            "rendererStatus=\(diagnostics.rendererStatus) rendererError=\(diagnostics.rendererError) " +
            "displayed=\(renderer.displayedPixelBuffer() != nil)"
        )
        onDiagnosticsChange?(diagnostics)
    }

    private func updateCompressedDiagnostics(sample: CMSampleBuffer) {
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

    private func recordVideoSample(_ sample: CMSampleBuffer) -> String {
        sourceEventSequence += 1
        let eventID = "\(traceID).event.\(sourceEventSequence)"
        let routeEvent = RouteMediaEventRecord(
            eventID: eventID,
            mediaSessionID: traceID,
            route: route,
            videoTrackID: videoTrackID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            kind: .sample,
            providerProvenance: provider.info.providerKind
        )
        debugStore.recordRouteEvent(routeEvent)

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
            route: route,
            videoTrackID: videoTrackID,
            sourceEventID: eventID,
            streamEpoch: streamEpoch,
            formatRevision: formatRevision,
            inputKind: route.rendererInputKind,
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
            dumpVideoSampleIfRequested(sample)
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .routeMediaEventStream,
                kind: "routeMediaEvent.firstSample",
                outcome: .succeeded,
                details: ["sourceEventID": eventID]
            )
            debugStore.emit(
                mediaSessionID: traceID,
                route: route,
                node: .videoSampleStream,
                kind: "videoSample.firstProduced",
                outcome: .succeeded,
                details: [
                    "inputKind": route.rendererInputKind.rawValue,
                    "mediaSubtype": sampleRecord.mediaSubtype,
                ]
            )
        }
        return eventID
    }

    private func dumpVideoSampleIfRequested(_ sample: CMSampleBuffer) {
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
        fputs("[VIDEO-DESCRIPTION] route=\(route.rawValue) \(hex)\n", stderr)
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
                    "[VIDEO-SAMPLE] route=\(route.rawValue) length=\(sampleLength) " +
                    "pts=\(CMSampleBufferGetPresentationTimeStamp(sample).seconds) " +
                    "dts=\(CMSampleBufferGetDecodeTimeStamp(sample).seconds) " +
                    "duration=\(CMSampleBufferGetDuration(sample).seconds) " +
                    "attachments=\(String(describing: attachments)) prefix=\(payloadHex)\n",
                    stderr
                )
            }
        }
    }

    private func numericSeconds(_ time: CMTime) -> Double? {
        guard time.isValid, time.isNumeric else { return nil }
        return time.seconds
    }

    private func formatSignalingSummary(
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
            rangeFact = .init(.known, value: fullRange ? "full" : "video")
        } else if let imageBuffer {
            rangeFact = .init(
                .known,
                value: pixelRange(CVPixelBufferGetPixelFormatType(imageBuffer))
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

    private func observedStringFact(
        _ values: [String: Any],
        key: CFString
    ) -> ObservedStringFact {
        guard let value = values[key as String] else { return .init(.none) }
        return .init(.known, value: normalized(String(describing: value)))
    }

    private func observedBooleanFact(
        _ values: [String: Any],
        key: CFString
    ) -> ObservedBooleanFact {
        guard let value = values[key as String] as? Bool else { return .init(.none) }
        return .init(.known, value: value)
    }

    private func presenceFact(_ value: Any?) -> ObservedBooleanFact {
        value == nil ? .init(.none, value: false) : .init(.known, value: true)
    }

    private func sampleAttachmentDictionary(_ sample: CMSampleBuffer) -> [String: Any] {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        ) as? [[String: Any]], let first = array.first else {
            return [:]
        }
        return first
    }

    private func markAsPrerollIfNeeded(
        _ sample: CMSampleBuffer,
        presentationTime: CMTime
    ) {
        guard requestedTimelineStart.isNumeric,
              requestedTimelineStart > .zero,
              presentationTime < requestedTimelineStart,
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

    private func targetTimelineTime(fallback: CMTime) -> CMTime {
        requestedTimelineStart.isNumeric && requestedTimelineStart > .zero
            ? requestedTimelineStart
            : fallback
    }

    private func publishTargetTimelineState(at time: CMTime) {
        let lifecycle: PlaybackLifecycle = timelineStartRate == 0 ? .paused : .playing
        updateLifecycle(lifecycle)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
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

    private func updateLifecycle(_ lifecycle: PlaybackLifecycle) {
        guard var record = mediaSessionRecord else { return }
        record.lifecycle = lifecycle
        mediaSessionRecord = record
        debugStore.recordSession(record)
    }

    private func recordFailure(_ error: Error, node: PlaybackNode, kind: String) {
        updateLifecycle(.failed)
        debugStore.recordFailure(PlaybackFailureRecord(
            mediaSessionID: traceID,
            route: route,
            node: node,
            stage: kind,
            errorType: String(reflecting: type(of: error)),
            message: error.localizedDescription,
            recoverability: "notRecoverableWithinMediaSession"
        ))
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            node: node,
            kind: kind,
            outcome: .failed,
            details: ["error": error.localizedDescription]
        )
        if activeOperation != nil {
            finishActiveOperation(.failed, failure: error.localizedDescription)
        }
    }

    private func publishRendererFailure(_ fact: RendererFailureFact) {
        guard claimRendererFailure() else { return }
        rendererFailureMonitor?.stop()
        closeEndState()
        synchronizer.rate = 0
        rendererSink.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        provider.cancel()
        audioDeliveryQueue.sync {
            audioProvider.cancel()
        }

        updateLifecycle(.failed)
        let stage = "\(fact.rendererKind.rawValue)Renderer.failed"
        debugStore.recordFailure(PlaybackFailureRecord(
            mediaSessionID: traceID,
            route: route,
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
            route: route,
            node: .rendererInputCoordination,
            kind: stage,
            outcome: .failed,
            details: [
                "error": fact.message,
                "errorType": fact.errorType,
                "rendererKind": fact.rendererKind.rawValue,
                "requiresFlushToResumeDecoding": fact.requiresFlushToResumeDecoding
                    .map(String.init) ?? "notAvailable",
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

    private func startRendererFailureMonitoring() {
        rendererFailureMonitor?.start { [weak self] fact in
            self?.deliveryQueue.async { [weak self] in
                self?.publishRendererFailure(fact)
            }
        }
    }

    private func claimRendererFailure() -> Bool {
        rendererFailureLock.withLock {
            guard acceptsRendererFailure else { return false }
            acceptsRendererFailure = false
            return true
        }
    }

    private func stopRendererFailureMonitoring() {
        rendererFailureLock.withLock {
            acceptsRendererFailure = false
        }
        rendererFailureMonitor?.stop()
    }

    private func beginOperation(
        _ kind: PlaybackOperationKind,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil,
        targetRoute: PlaybackRoute? = nil
    ) {
        let operation = PlaybackOperationRecord(
            mediaSessionID: traceID,
            kind: kind,
            targetTimeSeconds: targetTimeSeconds,
            targetRate: targetRate,
            sourceRoute: route,
            targetRoute: targetRoute
        )
        activeOperation = operation
        debugStore.recordOperation(operation)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "operation.\(kind.rawValue).started",
            outcome: .succeeded,
            details: ["operationID": operation.operationID]
        )
    }

    private func finishActiveOperation(
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
            route: route,
            kind: "operation.\(operation.kind.rawValue).\(state.rawValue)",
            outcome: outcome,
            details: ["operationID": operation.operationID]
        )
    }

    private func finishPendingRouteSwitch(_ state: PlaybackOperationState) {
        guard let operation = pendingRouteSwitchOperation else { return }
        pendingRouteSwitchOperation = nil
        let finished = operation.finishing(as: state)
        debugStore.recordOperation(finished)
        debugStore.emit(
            mediaSessionID: traceID,
            route: route,
            kind: "operation.switchRoute.\(state.rawValue)",
            outcome: state == .completed ? .succeeded : .terminatedByCleanup,
            details: ["operationID": operation.operationID]
        )
    }

    private func recordRendererState(at time: CMTime) {
        debugStore.recordRendererState(RendererStateRecord(
            mediaSessionID: traceID,
            route: route,
            graphID: "\(traceID).rendererGraph",
            graphRevision: graphRevision,
            streamEpoch: streamEpoch,
            rendererIdentity: PlaybackTrace.identity(renderer),
            synchronizerIdentity: PlaybackTrace.identity(synchronizer),
            timelineConfigured: hasStartedTimeline,
            currentTimeSeconds: numericSeconds(time) ?? 0,
            rate: synchronizer.rate,
            rendererStatus: String(describing: renderer.status),
            rendererError: renderer.error?.localizedDescription,
            readyForMoreMediaData: rendererSink.isReadyForMoreMediaData,
            displayedPixelBuffer: renderer.displayedPixelBuffer() != nil,
            flushCount: flushCount
        ))
    }

    private func attachmentString(_ attachments: [String: Any], key: CFString) -> String {
        guard let value = attachments[key as String] else { return "missing" }
        return normalized(String(describing: value))
    }

    private func extensionString(_ extensions: [String: Any], key: CFString) -> String {
        guard let value = extensions[key as String] else { return "missing" }
        return normalized(String(describing: value))
    }

    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "ITU_R_", with: "")
            .replacingOccurrences(of: "SMPTE_", with: "")
    }

    private func pixelRange(_ format: OSType) -> String {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: "full-range"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: "video-range"
        default: "unknown"
        }
    }
}

enum CorePlaybackError: LocalizedError {
    case seekTimedOut(Double)
    case seekSuperseded(Double)
    case seekTargetUnavailable(Double, Double?)
    case stereoOverrideUnavailable(VideoStereoLayout?)
    case stereoOverrideTimedOut(VideoStereoLayout?)
    case projectionOverrideUnavailable(VideoProjectionOverride?)
    case projectionOverrideTimedOut(VideoProjectionOverride?)

    var errorDescription: String? {
        switch self {
        case .seekTimedOut(let seconds): "Seek to \(seconds) seconds did not reach renderer input coordination."
        case .seekSuperseded(let seconds): "Seek to \(seconds) seconds was superseded by a newer request."
        case .seekTargetUnavailable(let target, let lastPTS):
            "Seek target \(target) seconds is unavailable because the target epoch ended first; last video PTS: \(lastPTS.map { String($0) } ?? "none")."
        case .stereoOverrideUnavailable(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") cannot be applied after the video input ended."
        case .stereoOverrideTimedOut(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") did not reach renderer input coordination."
        case .projectionOverrideUnavailable(let projection):
            "Projection \(projection?.rawValue ?? "source") cannot be applied after the video input ended."
        case .projectionOverrideTimedOut(let projection):
            "Projection \(projection?.rawValue ?? "source") did not reach renderer input coordination."
        }
    }
}
