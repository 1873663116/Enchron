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

/// Exposes one media session's renderer, read-only facts, and consumer binding evidence.
public final class SampleBufferPlaybackSession: @unchecked Sendable {
    struct EndState {
        var requiresAudio = false
        var videoProviderEnded = false
        var audioProviderEnded = true
        var maximumVideoPresentationTime: CMTime?
        var videoPresentationEnd: CMTime?
        var audioPresentationEnd: CMTime?
        var didReportEnd = false
        var isClosed = false
    }

    struct SubtitleState {
        var availableTracks: [PlaybackSubtitleTrack] = []
        var selectedTrackID: PlaybackSubtitleTrack.ID?
        var cues: [PlaybackSubtitleCue] = []
        var frameRenderer: SubtitleFrameRendering?
        var activeFrame: PlaybackSubtitleFrame?
        var streamEpoch: UInt64 = 1
        var selectionGeneration: UInt64 = 0
        var suppressesActiveCues = false
        var isClosed = false
        var lastPublishedCueIDs: [PlaybackSubtitleCue.ID] = []
    }

    public let traceID: String
    public let renderer = AVSampleBufferVideoRenderer()
    let audioRenderer = AVSampleBufferAudioRenderer()
    let synchronizer = AVSampleBufferRenderSynchronizer()
    let debugStore = PlaybackDiagnosticsStore()
    lazy var activationObservation = PlaybackActivationObservation(
        session: self,
        reapplyConfiguration: activationReapplyVerificationConfiguration,
        reapplyHooks: activationReapplyVerificationHooks
    )

    var onStatusChange: (@Sendable (PlaybackStatus) -> Void)?
    var onDiagnosticsChange: (@Sendable (PlaybackDiagnostics) -> Void)?
    var onSubtitleCuesChange: (@Sendable ([PlaybackSubtitleCue]) -> Void)?
    var onSubtitleFrameChange: (@Sendable (PlaybackSubtitleFrame?) -> Void)?

    let provider: VideoSampleProvider
    let audioProvider: AudioSampleProvider
    let subtitleProvider: SubtitleProvider
    let rendererSink: RendererInputSink
    let audioRendererSink: AudioRendererInputSink
    let videoSampleFormatOverride = VideoSampleFormatOverride()
    var rendererFailureMonitor: RendererFailureMonitoring?
    let rendererFailureLock = NSLock()
    var acceptsRendererFailure = true
    let videoTrackID: String
    let deliveryQueue = DispatchQueue(label: "PlaybackCore.sample-delivery")
    let audioDeliveryQueue = DispatchQueue(label: "PlaybackCore.audio-sample-delivery")
    let deliveryTaskLock = NSLock()
    var videoDeliveryTask: Task<Void, Never>?
    var videoDeliveryGeneration: UInt64 = 0
    var audioDeliveryTask: Task<Void, Never>?
    let pendingVideoSampleLock = NSLock()
    var pendingVideoSample: CMSampleBuffer?
    let decoderBootstrapLock = NSLock()
    var decoderBootstrapComplete = false
    var decoderBootstrapTargetSeconds: Double?
    var decoderBootstrapLastDecodeTimeSeconds: Double?
    var decoderBootstrapImmediateEnqueueCount: UInt64 = 0
    let endStateLock = NSLock()
    var endState = EndState()
    var hasStartedTimeline = false
    var timeObserver: Any?
    var isClosed = false
    let closeLock = NSLock()
    var isClosing = false
    var isCloseFinished = false
    var closeCompletions: [@Sendable () -> Void] = []
    var diagnostics = PlaybackDiagnostics()
    var lastDiagnosticsSecond = -1
    var didRecordFormat = false
    var timelineStartRate: Float = 1
    public private(set) var preferredPlaybackRate: Float = 1
    var sourceURL: URL?
    var sourceAsset: PlaybackAsset?
    var isResetting = false
    var mediaSessionRecord: MediaSessionRecord?
    var streamEpoch: UInt64 = 1
    var audioStreamEpoch: UInt64 = 1
    var formatRevision: UInt64 = 1
    var sourceEventSequence: UInt64 = 0
    var lastSourceEventID = "none"
    var lastRecordedSampleEpoch: UInt64 = 0
    var requestedTimelineStart = CMTime.invalid
    var isPrerolling = false
    var activeOperation: PlaybackOperationRecord?
    var flushCount: UInt64 = 0
    var graphRevision: UInt64 = 1
    var stereoLayoutOverride: VideoStereoLayout?
    var projectionOverride: VideoProjectionOverride?
    var hasRequestedVideoData = false
    var hasAudio = false
    var audioSampleBufferCount: UInt64 = 0
    var audioFrameCount: UInt64 = 0
    let audioTimestampOffsetLock = NSLock()
    var audioTimestampOffsetEpoch: UInt64 = 0
    var audioTimestampOffset: CMTime = .zero
    let videoPerformanceMetricsLock = NSLock()
    var videoPerformanceMetricsRequestInFlight = false
    let displayedPixelBufferProbeLock = NSLock()
    var displayedPixelBufferProbeInFlight = false
    let rendererStateLock = NSLock()
    var videoRendererStatus = "unknown"
    var videoRendererError: String?
    var audioRendererError: String?
    var lastRecordedAudioRendererStatus: String?
    var lastRecordedAudioRendererError: String?
    public internal(set) var selectedAudioStreamIndex: Int?
    public private(set) var availableAudioTracks: [PlaybackAudioTrack] = []
    let subtitleStateLock = NSLock()
    var subtitleState = SubtitleState()
    let logger = Logger(subsystem: "com.xiongzhipeng.PlaybackCore", category: "Playback")
    let activationReapplyVerificationConfiguration:
        PlaybackActivationReapplyVerificationConfiguration
    let activationReapplyVerificationHooks: PlaybackActivationReapplyVerificationHooks

    var isCloseInProgress: Bool {
        closeLock.withLock { isClosing }
    }

    convenience init(traceID: String = UUID().uuidString) {
        self.init(
            traceID: traceID,
            provider: FFmpegSampleProvider(),
            audioProvider: FFmpegCompressedAudioSampleProvider(),
            subtitleProvider: FFmpegSubtitleProvider(),
            rendererSink: nil
        )
    }

    init(
        traceID: String,
        provider: VideoSampleProvider,
        audioProvider: AudioSampleProvider = NoAudioSampleProvider(),
        subtitleProvider: SubtitleProvider = NoSubtitleProvider(),
        rendererSink: RendererInputSink? = nil,
        audioRendererSink: AudioRendererInputSink? = nil,
        rendererFailureMonitor: RendererFailureMonitoring? = nil,
        activationReapplyVerificationConfiguration:
            PlaybackActivationReapplyVerificationConfiguration = .processDefault,
        activationReapplyVerificationHooks: PlaybackActivationReapplyVerificationHooks = .init()
    ) {
        self.traceID = traceID
        self.videoTrackID = "\(traceID).video.0"
        self.provider = provider
        self.audioProvider = audioProvider
        self.subtitleProvider = subtitleProvider
        self.activationReapplyVerificationConfiguration =
            activationReapplyVerificationConfiguration
        self.activationReapplyVerificationHooks = activationReapplyVerificationHooks
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        audioRenderer.audioTimePitchAlgorithm = .timeDomain
        audioRenderer.allowedAudioSpatializationFormats = .monoAndStereo
        if let rendererSink {
            self.rendererSink = rendererSink
        } else {
            self.rendererSink = AVSampleBufferRendererInputSink(
                receiver: synchronizer.sampleBufferReceiver(adding: renderer)
            )
        }
        if let audioRendererSink {
            self.audioRendererSink = audioRendererSink
        } else {
            self.audioRendererSink = AVSampleBufferAudioRendererInputSink(
                receiver: synchronizer.sampleBufferReceiver(adding: audioRenderer)
            )
        }
        self.rendererFailureMonitor = rendererFailureMonitor
        PlaybackTrace.event(
            "session.init id=\(traceID) " +
            "renderer=\(PlaybackTrace.identity(renderer)) synchronizer=\(PlaybackTrace.identity(synchronizer))"
        )
        timeObserver = synchronizer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: deliveryQueue
        ) { [weak self] time in
            self?.updatePresentationStatus(at: time)
        }
        activationObservation.start()
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset? = nil,
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
        resetDecoderBootstrap()
        let requestedRate = initialRate ?? 1
        preferredPlaybackRate = requestedRate > 0 ? requestedRate : 1
        timelineStartRate = startsPaused || requestedRate == 0
            ? 0
            : preferredPlaybackRate
        sourceURL = url
        sourceAsset = asset
        availableAudioTracks = try await audioProvider.tracks(in: url, asset: asset)
        debugStore.recordAvailableAudioTracks(availableAudioTracks)
        let subtitleTracks = try await subtitleProvider.tracks(in: url, asset: asset)
        subtitleStateLock.withLock {
            subtitleState.availableTracks = subtitleTracks
            subtitleState.selectedTrackID = nil
            subtitleState.cues = []
            subtitleState.frameRenderer = nil
            subtitleState.activeFrame = nil
            subtitleState.streamEpoch = 1
            subtitleState.selectionGeneration = 0
            subtitleState.suppressesActiveCues = false
            subtitleState.isClosed = false
            subtitleState.lastPublishedCueIDs = []
        }
        recordSubtitleState(at: synchronizer.currentTime())
        publishSubtitleCues(at: synchronizer.currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            node: .videoTrackModel,
            kind: "subtitle.tracks.available",
            outcome: .succeeded,
            details: ["count": String(subtitleTracks.count)]
        )
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
            initialTimeSeconds: startTime.seconds,
            startsPaused: startsPaused,
            initialRate: initialRate ?? timelineStartRate
        )
        mediaSessionRecord = sessionRecord
        debugStore.recordSession(sessionRecord)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .mediaSessionBinding,
            kind: "mediaSession.bound",
            outcome: .succeeded,
            details: ["source": url.lastPathComponent]
        )
        do {
            try await provider.prepare(url: url, asset: asset, startTime: startTime)
        } catch {
            recordFailure(error, node: .providerOpen, kind: "provider.openFailed")
            throw error
        }
        do {
            try await audioProvider.prepare(
                url: url,
                asset: asset,
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
            node: .videoTrackModel,
            kind: "videoTrack.selected",
            outcome: .succeeded,
            details: ["videoTrackID": videoTrackID]
        )

        logger.info("Prepared codec=\(self.diagnostics.codecName, privacy: .public) duration=\(self.diagnostics.durationSeconds, format: .fixed(precision: 3))s")
        PlaybackTrace.event(
            "session.prepare.end id=\(traceID) codec=\(diagnostics.codecName) " +
            "duration=\(diagnostics.durationSeconds)"
        )
        startRendererFailureMonitoring()
    }

    func start() throws {
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
            recordFailure(error, node: .mediaEventStream, kind: "provider.startFailed")
            throw error
        }
        startVideoDelivery()
        PlaybackTrace.event("session.start.end id=\(traceID)")
    }

    func playbackActivationHostTime() -> CMTime {
        CMTimeAdd(
            CMClockGetTime(CMClockGetHostTimeClock()),
            CMTime(seconds: 0.05, preferredTimescale: 1_000_000)
        )
    }

    func setRateAtHostTime(_ rate: Float, time: CMTime) {
        synchronizer.setRate(
            rate,
            time: time,
            atHostTime: playbackActivationHostTime()
        )
    }

    func play() throws {
        try admitTimelineControl(.play)
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByRateChange)
        beginOperation(.play, targetRate: preferredPlaybackRate)
        let resumeTime = synchronizer.currentTime()
        // On visionOS, a media-time-only rate change can leave the underlying
        // timebase stopped after a pause. Bind the same media time to a near
        // future host time so the synchronizer has an explicit resume edge.
        setRateAtHostTime(preferredPlaybackRate, time: resumeTime)
        recordAudioRateActivation(rate: preferredPlaybackRate, time: resumeTime, reason: "play")
        updateLifecycle(.playing)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.play.completed",
            outcome: .succeeded
        )
        finishActiveOperation(.completed)
        onStatusChange?(.playing)
    }

    func pause() throws {
        try admitTimelineControl(.pause)
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByPause)
        beginOperation(.pause, targetRate: 0)
        synchronizer.rate = 0
        updateLifecycle(.paused)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.pause.completed",
            outcome: .succeeded
        )
        finishActiveOperation(.completed)
        publishDiagnostics(at: synchronizer.currentTime(), force: true)
        onStatusChange?(.paused)
    }

    func setRate(_ rate: Float) throws {
        guard rate.isFinite, rate >= 0 else {
            rejectControl(.setRate, reason: "invalidRate", targetRate: rate)
            throw PlaybackControlError.invalidRate(rate)
        }
        try admitTimelineControl(.setRate, targetRate: rate)
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByRateChange)
        beginOperation(.setRate, targetRate: rate)
        if rate > 0 {
            preferredPlaybackRate = rate
        }
        timelineStartRate = rate
        if rate > 0 {
            let rateChangeTime = synchronizer.currentTime()
            // Keep rate changes on the same visionOS-safe host-time activation
            // path as play(). The current synchronizer time is the anchor.
            setRateAtHostTime(rate, time: rateChangeTime)
            recordAudioRateActivation(rate: rate, time: rateChangeTime, reason: "setRate")
        } else {
            synchronizer.rate = 0
        }
        let lifecycle: PlaybackLifecycle = rate == 0 ? .paused : .playing
        updateLifecycle(lifecycle)
        recordRendererState(at: currentTime())
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererInputCoordination,
            kind: "control.setRate.completed",
            outcome: .succeeded,
            details: ["rate": String(rate)]
        )
        finishActiveOperation(.completed)
        onStatusChange?(rate == 0 ? .paused : .playing)
    }


}
