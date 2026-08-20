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

struct PlaybackPrerollRequirement: Equatable {
    let timelineStart: CMTime
    let videoEnd: CMTime
    let audioEnd: CMTime
}

enum PlaybackBufferingPolicy {
    /// MPV's 0.2-second audio output buffer is the starting point for seek startup.
    /// TrueHD on Vision Pro arrives in 0.1-second buffers, so this admits two buffers.
    static let seekAudioLeadSeconds = 0.2

    /// The 2026-08-17 Vision Pro baseline recovered bounded delivery at 0.527–0.873
    /// seconds late. Keep the 0.5-second trigger that arrested unbounded lag.
    static let deliveryLagRecoveryTriggerSeconds = 0.5

    /// MPV's one-second underrun recovery reference is the starting point. The
    /// 2026-08-17 Vision Pro baseline showed that a five-second target caused
    /// 6.8–13.1-second pauses on remote 4K HEVC with TrueHD.
    static let deliveryLagRecoveryLeadSeconds = 1.0

    /// Vision Pro may opportunistically queue compressed samples while playback
    /// keeps pace. This is a ceiling, not a startup or recovery requirement.
    #if os(visionOS)
        static let opportunisticRendererMaximumLeadSeconds = 6.0
    #else
        static let opportunisticRendererMaximumLeadSeconds = 1.0
    #endif

    /// Five seconds bounds provider or renderer failure; it is not buffered-media
    /// policy. The 5-millisecond poll keeps activation responsive within that bound.
    static let audioPrerollTimeout: Duration = .seconds(5)
    static let audioPrerollPollInterval: Duration = .milliseconds(5)

    /// Seek coordination already used a five-second failure bound. Name it so it
    /// cannot be confused with the removed five-second media reserve.
    static let seekTargetCoordinationTimeout: Duration = .seconds(5)

    static func seekRequirement(
        target: CMTime,
        durationSeconds: Double
    ) -> PlaybackPrerollRequirement {
        PlaybackPrerollRequirement(
            timelineStart: target,
            videoEnd: target,
            audioEnd: clampedEnd(
                from: target,
                leadSeconds: seekAudioLeadSeconds,
                durationSeconds: durationSeconds
            )
        )
    }

    static func deliveryLagRecoveryRequirement(
        timelineTime: CMTime,
        durationSeconds: Double
    ) -> PlaybackPrerollRequirement {
        let end = clampedEnd(
            from: timelineTime,
            leadSeconds: deliveryLagRecoveryLeadSeconds,
            durationSeconds: durationSeconds
        )
        return PlaybackPrerollRequirement(
            timelineStart: timelineTime,
            videoEnd: end,
            audioEnd: end
        )
    }

    private static func clampedEnd(
        from start: CMTime,
        leadSeconds: Double,
        durationSeconds: Double
    ) -> CMTime {
        let unboundedEnd = start.seconds + leadSeconds
        let endSeconds = if durationSeconds.isFinite, durationSeconds > 0 {
            min(unboundedEnd, durationSeconds)
        } else {
            unboundedEnd
        }
        return CMTime(seconds: endSeconds, preferredTimescale: 60_000)
    }
}

/// Exposes one media session's renderer, read-only facts, and consumer binding evidence.
public final class SampleBufferPlaybackSession: @unchecked Sendable {
    struct EndState {
        var requiresAudio = false
        var videoProviderEnded = false
        var audioProviderEnded = true
        var maximumVideoPresentationTime: CMTime?
        var maximumVideoPresentationTimeBeforeDuration: CMTime?
        var videoPresentationEnd: CMTime?
        var audioPresentationEnd: CMTime?
        var didReportEnd = false
        var isClosed = false
    }

    struct SubtitleState {
        var availableTracks: [PlaybackSubtitleTrack] = []
        var sourceURLByTrackID: [PlaybackSubtitleTrack.ID: URL] = [:]
        var externalSourceIDByTrackID: [PlaybackSubtitleTrack.ID: String] = [:]
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
    public private(set) var mediaKind: PlaybackMediaKind = .video
    /// A presentation conversion needs a renderer its new RealityView Entity has
    /// never bound, which is a different renderer graph on the same timeline and
    /// the same open source. `videoRendererGraph` is the only mutable part of the
    /// session, so a conversion replaces it instead of the session.
    private struct VideoRendererGraph {
        var renderer: AVSampleBufferVideoRenderer
        var sink: RendererInputSink
        var revision: UInt64
        var departingRenderer: AVSampleBufferVideoRenderer?
    }

    private let videoRendererGraphLock = NSLock()
    private var videoRendererGraph: VideoRendererGraph

    public var renderer: AVSampleBufferVideoRenderer {
        videoRendererGraphLock.withLock { videoRendererGraph.renderer }
    }

    var rendererSink: RendererInputSink {
        videoRendererGraphLock.withLock { videoRendererGraph.sink }
    }

    /// Callers must have suspended video sample delivery, so the departing sink
    /// has no enqueue in flight when the replacement takes its place.
    func adoptVideoRendererGraph(
        renderer: AVSampleBufferVideoRenderer,
        sink: RendererInputSink,
        departing departingRenderer: AVSampleBufferVideoRenderer
    ) -> UInt64 {
        let departingSink = videoRendererGraphLock.withLock { () -> RendererInputSink in
            let departingSink = videoRendererGraph.sink
            videoRendererGraph = VideoRendererGraph(
                renderer: renderer,
                sink: sink,
                revision: videoRendererGraph.revision &+ 1,
                departingRenderer: departingRenderer
            )
            return departingSink
        }
        departingSink.stopRenderingEventObservation()
        rendererStateLock.withLock {
            videoRendererStatus = "unknown"
            videoRendererError = nil
        }
        deliveryQueue.sync {
            lastDisplayedFrameIdentity = nil
            displayedFrameObservationCount = 0
            didRecordFormat = false
        }
        return graphRevision
    }

    func takeDepartingVideoRenderer() -> AVSampleBufferVideoRenderer? {
        videoRendererGraphLock.withLock {
            let departing = videoRendererGraph.departingRenderer
            videoRendererGraph.departingRenderer = nil
            return departing
        }
    }
    let audioRenderer: AVSampleBufferAudioRenderer
    let audioRendererSink: AudioRendererInputSink
    let synchronizer: AVSampleBufferRenderSynchronizer
    let debugStore = PlaybackDiagnosticsStore()
    lazy var activationObservation = PlaybackActivationObservation(
        session: self,
        reapplyConfiguration: activationReapplyVerificationConfiguration,
        reapplyHooks: activationReapplyVerificationHooks
    )

    var onStatusChange: (@Sendable (PlaybackStatus) -> Void)?
    var onDiagnosticsChange: (@Sendable (PlaybackDiagnostics) -> Void)?
    var onAcceptedVideoFormatRevisionChange: (@Sendable (UInt64) -> Void)?
    var onSubtitleCuesChange: (@Sendable ([PlaybackSubtitleCue]) -> Void)?
    var onSubtitleFrameChange: (@Sendable (PlaybackSubtitleFrame?) -> Void)?
    var onAudioSpectrumFrameChange: (@Sendable (AudioSpectrumFrame) -> Void)?

    let provider: VideoSampleProvider
    let audioProvider: AudioSampleProvider
    let subtitleProvider: SubtitleProvider
    let mediaSourceInformationLoader: (any MediaSourceInformationLoading)?
    let sourceReadMeter: PlaybackSourceReadMeter?
    let demuxSession: FFmpegDemuxSession?
    let sourceReadObservationLock = NSLock()
    var sourceReadRateSampler: PlaybackSourceReadRateSampler
    let videoSampleFormatOverride = VideoSampleFormatOverride()
    var rendererFailureMonitor: RendererFailureMonitoring?
    let rendererFailureLock = NSLock()
    var acceptsRendererFailure = true
    let videoTrackID: String
    let deliveryQueue = DispatchQueue(label: "PlaybackCore.sample-delivery")
    let audioDeliveryQueue = DispatchQueue(label: "PlaybackCore.audio-sample-delivery")
    let audioSpectrumAnalyzer = AudioSpectrumAnalyzer()
    let audioSpectrumFramesLock = NSLock()
    var audioSpectrumFrames: [AudioSpectrumFrame] = []
    let deliveryTaskLock = NSLock()
    let timelineProgressRecoveryLock = NSLock()
    var timelineProgressRecovery = PlaybackTimelineProgressRecovery()
    let timelineProgressWatchdogQueue = DispatchQueue(
        label: "PlaybackCore.timeline-progress-watchdog"
    )
    var timelineProgressWatchdog: DispatchSourceTimer?
    var videoDeliveryTask: Task<Void, Never>?
    var videoDeliveryGeneration: UInt64 = 0
    var videoSampleDeliverySuspended = false
    var audioDeliveryTask: Task<Void, Never>?
    let firstVideoFrameDeadline: Duration
    let firstVideoFrameObservation: (@Sendable () -> Bool)?
    let firstVideoFrameLock = NSLock()
    var firstVideoFrameDeadlineTask: Task<Void, Never>?
    var firstVideoFrameDeadlineWaitsForPlay = false
    let pendingVideoSampleLock = NSLock()
    var pendingVideoSample: CMSampleBuffer?
    let decoderBootstrapLock = NSLock()
    var decoderBootstrapComplete = false
    var decoderBootstrapTargetSeconds: Double?
    var decoderBootstrapLastDecodeTimeSeconds: Double?
    var decoderBootstrapImmediateEnqueueCount: UInt64 = 0
    let prerollRequirementLock = NSLock()
    var prerollRequirement: PlaybackPrerollRequirement?
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
    var lastPublishedAcceptedVideoFormatRevision: UInt64?
    var sourceEventSequence: UInt64 = 0
    var lastSourceEventID = "none"
    var lastRecordedSampleEpoch: UInt64 = 0
    var requestedTimelineStart = CMTime.invalid
    var isPrerolling = false
    var activeOperation: PlaybackOperationRecord?
    var flushCount: UInt64 = 0
    var graphRevision: UInt64 {
        videoRendererGraphLock.withLock { videoRendererGraph.revision }
    }
    var displayedFrameObservationCount: UInt64 = 0
    var lastDisplayedFrameIdentity: UInt64?
    var stereoLayoutOverride: VideoStereoLayout?
    var projectionOverride: VideoProjectionOverride?
    var dynamicRangeOverride: VideoDynamicRangeOverride?
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
        let sourceReadMeter = PlaybackSourceReadMeter()
        let demuxSession = FFmpegDemuxSession(sourceReadMeter: sourceReadMeter)
        self.init(
            traceID: traceID,
            provider: FFmpegSampleProvider(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            ),
            audioProvider: FFmpegAudioSampleProvider(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            ),
            subtitleProvider: FFmpegSubtitleProvider(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            ),
            mediaSourceInformationLoader: SystemMediaSourceInformationLoader(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            ),
            sourceReadMeter: sourceReadMeter,
            demuxSession: demuxSession,
            rendererSink: nil
        )
    }

    init(
        traceID: String,
        provider: VideoSampleProvider,
        audioProvider: AudioSampleProvider = NoAudioSampleProvider(),
        subtitleProvider: SubtitleProvider = NoSubtitleProvider(),
        mediaSourceInformationLoader: (any MediaSourceInformationLoading)? = nil,
        sourceReadMeter: PlaybackSourceReadMeter? = nil,
        demuxSession: FFmpegDemuxSession? = nil,
        rendererSink: RendererInputSink? = nil,
        audioRendererSink: AudioRendererInputSink? = nil,
        rendererFailureMonitor: RendererFailureMonitoring? = nil,
        firstVideoFrameDeadline: Duration = .seconds(5),
        firstVideoFrameObservation: (@Sendable () -> Bool)? = nil,
        activationReapplyVerificationConfiguration:
            PlaybackActivationReapplyVerificationConfiguration = .processDefault,
        activationReapplyVerificationHooks: PlaybackActivationReapplyVerificationHooks = .init()
    ) {
        let initialRenderer = AVSampleBufferVideoRenderer()
        let initialAudioRenderer = AVSampleBufferAudioRenderer()
        let initialSynchronizer = AVSampleBufferRenderSynchronizer()
        self.traceID = traceID
        self.videoTrackID = "\(traceID).video.0"
        self.provider = provider
        self.audioProvider = audioProvider
        self.subtitleProvider = subtitleProvider
        self.mediaSourceInformationLoader = mediaSourceInformationLoader
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
        self.sourceReadRateSampler = PlaybackSourceReadRateSampler(
            startedAt: ProcessInfo.processInfo.systemUptime
        )
        self.firstVideoFrameDeadline = firstVideoFrameDeadline
        self.firstVideoFrameObservation = firstVideoFrameObservation
        self.activationReapplyVerificationConfiguration =
            activationReapplyVerificationConfiguration
        self.activationReapplyVerificationHooks = activationReapplyVerificationHooks
        initialSynchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        initialAudioRenderer.audioTimePitchAlgorithm = .timeDomain
        initialAudioRenderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        audioRenderer = initialAudioRenderer
        synchronizer = initialSynchronizer
        videoRendererGraph = VideoRendererGraph(
            renderer: initialRenderer,
            sink: rendererSink ?? AVSampleBufferRendererInputSink(
                receiver: initialSynchronizer.sampleBufferReceiver(adding: initialRenderer)
            ),
            revision: 1,
            departingRenderer: nil
        )
        if let audioRendererSink {
            self.audioRendererSink = audioRendererSink
        } else {
            self.audioRendererSink = AVSampleBufferAudioRendererInputSink(
                receiver: initialSynchronizer.sampleBufferReceiver(adding: initialAudioRenderer)
            )
        }
        self.rendererFailureMonitor = rendererFailureMonitor
        PlaybackTrace.event(
            "session.init id=\(traceID) " +
            "renderer=\(PlaybackTrace.identity(initialRenderer)) synchronizer=\(PlaybackTrace.identity(initialSynchronizer))"
        )
        timeObserver = initialSynchronizer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: deliveryQueue
        ) { [weak self] time in
            self?.updatePresentationStatus(at: time)
        }
        activationObservation.start()
        recordTimelineControlState()
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset? = nil,
        startTime: CMTime = .zero,
        startsPaused: Bool = false,
        initialRate: Float? = nil,
        sourceIsRemote: Bool = false,
        provenance: String = "appOpen",
        accessRequirement: String = "appAdapterManaged"
    ) async throws {
        PlaybackTrace.event(
            "session.prepare.begin id=\(traceID) start=\(startTime.seconds) paused=\(startsPaused)"
        )
        resetEndState(requiresAudio: false)
        resetFirstVideoFrameDeadline()
        resetDecoderBootstrap()
        let requestedRate = initialRate ?? 1
        preferredPlaybackRate = requestedRate > 0 ? requestedRate : 1
        firstVideoFrameDeadlineWaitsForPlay = startsPaused || requestedRate == 0
        timelineStartRate = startsPaused || requestedRate == 0
            ? 0
            : preferredPlaybackRate
        sourceURL = url
        sourceAsset = asset
        try demuxSession?.configureSource(isRemote: sourceIsRemote)
        let sourceInformation: MediaSourceInformation?
        if let mediaSourceInformationLoader {
            sourceInformation = if demuxSession != nil {
                try await mediaSourceInformationLoader.load(from: url)
            } else {
                try? await mediaSourceInformationLoader.load(from: url)
            }
        } else {
            sourceInformation = nil
        }
        if let demuxSession, startTime.isNumeric, startTime.seconds > 0 {
            try demuxSession.seek(to: startTime.seconds)
        }
        if let sourceInformation {
            mediaKind = sourceInformation.playbackMediaKind
            guard mediaKind != .unsupported else {
                throw CorePlaybackError.noPlayableMediaStream
            }
        } else {
            mediaKind = .video
        }
        if let sourceInformation {
            availableAudioTracks = try await audioProvider.tracks(
                in: url,
                asset: asset,
                sourceInformation: sourceInformation
            )
        } else if mediaSourceInformationLoader != nil {
            availableAudioTracks = []
        } else {
            availableAudioTracks = try await audioProvider.tracks(in: url, asset: asset)
        }
        debugStore.recordAvailableAudioTracks(availableAudioTracks)
        let subtitleTracks: [PlaybackSubtitleTrack]
        if let sourceInformation {
            subtitleTracks = try await subtitleProvider.tracks(
                in: url,
                asset: asset,
                sourceInformation: sourceInformation
            )
        } else if mediaSourceInformationLoader != nil {
            subtitleTracks = []
        } else {
            subtitleTracks = try await subtitleProvider.tracks(in: url, asset: asset)
        }
        subtitleStateLock.withLock {
            subtitleState.availableTracks = subtitleTracks
            subtitleState.sourceURLByTrackID = [:]
            subtitleState.externalSourceIDByTrackID = [:]
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
        recordTimelineControlState()
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
        if mediaKind == .video {
            do {
                try await provider.prepare(
                    url: url,
                    asset: asset,
                    sourceInformation: sourceInformation,
                    startTime: startTime
                )
            } catch {
                recordFailure(error, node: .providerOpen, kind: "provider.openFailed")
                throw error
            }
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
            if mediaKind == .audioOnly {
                throw CorePlaybackError.noPlayableMediaStream
            }
            hasAudio = false
            debugStore.recordAudioTrack(nil)
            debugStore.emit(
                mediaSessionID: traceID,
                node: .videoTrackModel,
                kind: "audioTrack.none",
                outcome: .succeeded
            )
        } catch {
            if mediaKind == .audioOnly {
                recordFailure(error, node: .providerOpen, kind: "audioProvider.openFailed")
                throw error
            }
            retireAudio(
                after: error,
                node: .providerOpen,
                kind: "audioProvider.openFailed.videoContinues"
            )
        }
        resetAudioEndState(requiresAudio: hasAudio)
        recordAudioRendererState()
        diagnostics.durationSeconds = mediaKind == .audioOnly
            ? (sourceInformation?.durationSeconds ?? 0)
            : provider.info.durationSeconds
        diagnostics.nominalFrameRate = mediaKind == .audioOnly ? 0 : provider.info.nominalFrameRate
        diagnostics.codecName = mediaKind == .audioOnly
            ? (audioProvider.info?.codecName ?? "audio")
            : provider.info.codecName
        diagnostics.isMVHEVC = mediaKind == .video && provider.info.isMVHEVC
        diagnostics.dolbyVisionProfile = sourceInformation?.dolbyVisionProfile ?? 0
        diagnostics.dolbyVisionCrossCompatibilityID =
            sourceInformation?.dolbyVisionCrossCompatibilityID ?? 0
        diagnostics.dolbyVisionHasEnhancementLayer =
            sourceInformation?.dolbyVisionHasEnhancementLayer ?? false
        diagnostics.trackFormatHasMasteringDisplayMetadata = mediaKind == .video
            && provider.info.trackFormatHasMasteringDisplayMetadata
        diagnostics.trackFormatHasContentLightLevelMetadata = mediaKind == .video
            && provider.info.trackFormatHasContentLightLevelMetadata
        if mediaKind == .audioOnly {
            logger.info("Prepared audio-only codec=\(self.diagnostics.codecName, privacy: .public) duration=\(self.diagnostics.durationSeconds, format: .fixed(precision: 3))s")
            PlaybackTrace.event(
                "session.prepare.end id=\(traceID) kind=audioOnly codec=\(diagnostics.codecName) " +
                "duration=\(diagnostics.durationSeconds)"
            )
            startRendererFailureMonitoring()
            return
        }
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
            isMVHEVC: provider.info.isMVHEVC,
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
        if mediaKind == .audioOnly {
            startAudioDelivery()
            PlaybackTrace.event("session.start.end id=\(traceID) kind=audioOnly")
            return
        } else {
            do {
                try provider.start()
            } catch {
                recordFailure(error, node: .mediaEventStream, kind: "provider.startFailed")
                throw error
            }
        }
        if firstVideoFrameDeadlineWaitsForPlay == false {
            armFirstVideoFrameDeadline()
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

    func timelineControlStateRecord() -> PlaybackTimelineControlStateRecord {
        PlaybackTimelineControlStateRecord(
            isPrerolling: isPrerolling,
            hasStartedTimeline: hasStartedTimeline,
            timelineStartRate: timelineStartRate,
            requestedTimelineStartSeconds: numericSeconds(requestedTimelineStart)
        )
    }

    func recordTimelineControlState() {
        debugStore.recordTimelineControlState(timelineControlStateRecord())
    }

    func setRateAtHostTime(
        _ rate: Float,
        time: CMTime,
        reason: PlaybackTimelineControlReason = .activationReapply,
        capturedVideoDeliveryGeneration: UInt64? = nil
    ) {
        let hostTime = playbackActivationHostTime()
        let activationSequence = debugStore.beginTimelineRateActivation(
            reason: reason,
            mediaTimeSeconds: numericSeconds(time),
            hostTimeSeconds: numericSeconds(hostTime),
            currentVideoDeliveryGeneration: videoDeliveryGeneration,
            capturedVideoDeliveryGeneration: capturedVideoDeliveryGeneration,
            currentState: timelineControlStateRecord()
        )
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
            synchronizer.setRate(rate, time: time, atHostTime: hostTime)
            guard rate > 0 else { return }
            activateTimelineProgressRecoveryLocked(
                requestedRate: rate,
                applicationHostTime: hostTime
            )
        }
        debugStore.recordTimelineRateActivationReturned(sequence: activationSequence)
    }

    func setTimelineStopped(
        reason: PlaybackTimelineControlReason,
        capturedVideoDeliveryGeneration: UInt64? = nil
    ) {
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
            synchronizer.rate = 0
        }
        debugStore.recordTimelineStop(
            reason: reason,
            mediaTimeSeconds: numericSeconds(synchronizer.currentTime()),
            currentVideoDeliveryGeneration: videoDeliveryGeneration,
            capturedVideoDeliveryGeneration: capturedVideoDeliveryGeneration,
            currentState: timelineControlStateRecord()
        )
    }

    func setTimelineStopped(
        at time: CMTime,
        reason: PlaybackTimelineControlReason,
        capturedVideoDeliveryGeneration: UInt64? = nil
    ) {
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
            synchronizer.setRate(0, time: time)
        }
        debugStore.recordTimelineStop(
            reason: reason,
            mediaTimeSeconds: numericSeconds(time),
            currentVideoDeliveryGeneration: videoDeliveryGeneration,
            capturedVideoDeliveryGeneration: capturedVideoDeliveryGeneration,
            currentState: timelineControlStateRecord()
        )
    }

    func setTimelineRateForDiscontinuity(
        _ rate: Float,
        at time: CMTime,
        reason: PlaybackTimelineControlReason
    ) {
        let activationSequence = rate > 0
            ? debugStore.beginTimelineRateActivation(
                reason: reason,
                mediaTimeSeconds: numericSeconds(time),
                hostTimeSeconds: nil,
                currentVideoDeliveryGeneration: videoDeliveryGeneration,
                capturedVideoDeliveryGeneration: nil,
                currentState: timelineControlStateRecord()
            )
            : nil
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
            synchronizer.setRate(rate, time: time)
            if rate > 0 {
                activateTimelineProgressRecoveryLocked(
                    requestedRate: rate,
                    applicationHostTime: CMClockGetTime(CMClockGetHostTimeClock())
                )
            }
        }
        if let activationSequence {
            debugStore.recordTimelineRateActivationReturned(
                sequence: activationSequence
            )
        } else {
            debugStore.recordTimelineStop(
                reason: reason,
                mediaTimeSeconds: numericSeconds(time),
                currentVideoDeliveryGeneration: videoDeliveryGeneration,
                capturedVideoDeliveryGeneration: nil,
                currentState: timelineControlStateRecord()
            )
        }
    }

    func armTimelineProgressRecoveryForCurrentMapping() {
        guard timelineStartRate > 0 else { return }
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
            activateTimelineProgressRecoveryLocked(
                requestedRate: timelineStartRate,
                applicationHostTime: CMClockGetTime(CMClockGetHostTimeClock())
            )
        }
    }

    func invalidateTimelineProgressRecovery() {
        timelineProgressRecoveryLock.withLock {
            invalidateTimelineProgressRecoveryLocked()
        }
    }

    private func activateTimelineProgressRecoveryLocked(
        requestedRate: Float,
        applicationHostTime: CMTime
    ) {
        let run = timelineProgressRecovery.activate(
            requestedRate: requestedRate,
            applicationHostTime: applicationHostTime,
            videoStreamEpoch: streamEpoch,
            audioStreamEpoch: audioStreamEpoch
        )
        let timer = DispatchSource.makeTimerSource(queue: timelineProgressWatchdogQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(500),
            repeating: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.deliveryQueue.async { [weak self] in
                self?.receiveTimelineProgressWatchdogTick(run: run)
            }
        }
        timelineProgressWatchdog = timer
        timer.resume()
    }

    private func invalidateTimelineProgressRecoveryLocked() {
        timelineProgressRecovery.invalidate()
        timelineProgressWatchdog?.setEventHandler {}
        timelineProgressWatchdog?.cancel()
        timelineProgressWatchdog = nil
    }

    func play(armingFirstVideoFrameDeadline: Bool = true) throws {
        try admitTimelineControl(.play)
        firstVideoFrameDeadlineWaitsForPlay = false
        if armingFirstVideoFrameDeadline {
            armFirstVideoFrameDeadline()
        }
        activationObservation.invalidateReapplyVerification(outcome: .invalidatedByRateChange)
        beginOperation(.play, targetRate: preferredPlaybackRate)
        // Play can arrive after the renderer timeline is anchored but before
        // decoder bootstrap activates it. Keep that pending activation aligned
        // with the latest transport intent so bootstrap cannot restore the
        // session's earlier starts-paused state.
        timelineStartRate = preferredPlaybackRate
        let resumeTime = synchronizer.currentTime()
        // On visionOS, a media-time-only rate change can leave the underlying
        // timebase stopped after a pause. Bind the same media time to a near
        // future host time so the synchronizer has an explicit resume edge.
        setRateAtHostTime(
            preferredPlaybackRate,
            time: resumeTime,
            reason: .play
        )
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
        // Pause is also the authoritative intent for a timeline whose decoder
        // bootstrap has not finished yet.
        timelineStartRate = 0
        setTimelineStopped(reason: .pause)
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
            setRateAtHostTime(rate, time: rateChangeTime, reason: .rateChange)
            recordAudioRateActivation(rate: rate, time: rateChangeTime, reason: "setRate")
        } else {
            setTimelineStopped(reason: .rateChange)
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
