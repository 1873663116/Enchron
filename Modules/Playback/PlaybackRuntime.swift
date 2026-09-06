import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
import MediaSource
import Observation
import OSLog
import PlaybackCore

#if DEBUG
private final class PlaybackSwitchRendererSampleForwarder:
    PlaybackSwitchRendererSampleSink,
    @unchecked Sendable {
    private let byteStreamHandle: MediaByteStreamHandle?
    private let handler: @Sendable (
        PlaybackSwitchRendererSample,
        MediaByteStreamDebugCounters?
    ) -> Void

    init(
        byteStreamHandle: MediaByteStreamHandle?,
        handler: @escaping @Sendable (
            PlaybackSwitchRendererSample,
            MediaByteStreamDebugCounters?
        ) -> Void
    ) {
        self.byteStreamHandle = byteStreamHandle
        self.handler = handler
    }

    func recordPlaybackSwitchRendererSample(_ sample: PlaybackSwitchRendererSample) {
        handler(sample, byteStreamHandle?.debugCounters())
    }
}
#endif

struct PlaybackPresentationSurfacePixelIdentity: Equatable {
    let technicalSessionID: String?
    let videoComponentRevision: UInt64
    let streamEpoch: UInt64?
}

@MainActor
@Observable
public final class PlaybackRuntime: PlaybackRuntimeControlling {
    #if DEBUG
    public enum DebugPresentationSettlementFault: String, Sendable {
        case timeout = "settlement-timeout"
    }
    #endif

    public enum PresentationState: Sendable, Equatable {
        case hidden
        case placeholder
        case videoVisible
        case audioVisible
    }

    public enum SessionLifecycleEvent: Equatable, Sendable {
        case activated(id: String)
        case replaced(previousID: String, currentID: String)
        case ended(id: String)
    }

    public enum TechnicalSessionReplacementStage: String, Sendable, Equatable {
        case inactive
        case retiringSource
        case openingReplacement
        case installingRenderer
        case restoringExternalSubtitles
        case restoringAudioTrack
        case restoringSubtitleTrack
        case completed
        case failed
    }

    public enum RuntimeError: LocalizedError {
        case noSession
        case sourceAccessUnavailable
        case unableToOpenFile
        case rendererConsumerBusy(PlaybackPresentation)
        case rendererTransferPending
        case mediaSessionChanged
        case presentationDidNotSettle(PlaybackPresentation)
        case spatialPlaybackTransportUnavailable(ProductPlaybackLifecycle)
        case rendererGraphPlaybackDidNotAdvance(RendererGraphPlaybackContinuity)
        case audioOnlyRequiresWindowPresentation

        public var errorDescription: String? {
            switch self {
            case .noSession:
                "No PlaybackCore media session is active."
            case .sourceAccessUnavailable:
                "The original media source is no longer available. Choose it again to restore access."
            case .unableToOpenFile:
                "Unable to open this file."
            case .rendererConsumerBusy(let presentation):
                "The \(presentation.rawValue) RealityView still owns the active video renderer."
            case .rendererTransferPending:
                "The video renderer is being prepared for another RealityView."
            case .mediaSessionChanged:
                "The media session changed before the operation completed."
            case .presentationDidNotSettle(let presentation):
                "The replacement playback session did not settle in the \(presentation.rawValue) presentation."
            case .spatialPlaybackTransportUnavailable(let lifecycle):
                "Playback cannot be paused or resumed while it is \(String(describing: lifecycle))."
            case .rendererGraphPlaybackDidNotAdvance(let condition):
                "The video renderer did not prove continuous playback: \(condition.rawValue)."
            case .audioOnlyRequiresWindowPresentation:
                "Audio-only playback is available in the window presentation only."
            }
        }
    }

    public private(set) var lifecycle: PlaybackStatus = .idle
    public private(set) var playbackPosition = PlaybackModel.PlaybackPosition(seconds: 0, duration: 0)
    public private(set) var currentPlaybackSpeed = PlaybackModel.PlaybackSpeed.default
    public private(set) var currentLaunchRequest: PlaybackLaunchRequest?
    public var currentPlaybackURL: URL? { currentLaunchRequest?.url }
    public private(set) var prefetchedMetadata: PlaybackMediaMetadata?
    public var overview: String? { prefetchedMetadata?.overview }
    public private(set) var presentationState: PresentationState = .hidden
    public private(set) var loadingState = PlaybackLoadingState.none
    public private(set) var diagnostics = PlaybackDiagnostics()
    public private(set) var availableAudioTracks: [PlaybackModel.AudioTrack] = []
    public private(set) var currentAudioTrackID: String?
    public private(set) var availableSubtitleTracks: [PlaybackModel.SubtitleTrack] = []
    public private(set) var currentSubtitleTrackID: String?
    public private(set) var activeSubtitleCues: [PlaybackSubtitleCue] = []
    public private(set) var activeSubtitleFrame: PlaybackSubtitleFrame?
    public private(set) var activeSessionID: String?
    public private(set) var activeTechnicalSessionID: String?
    public private(set) var actualPlaybackSeconds: Double = 0
    public private(set) var didEndNaturally = false
    public private(set) var mediaFormatIsKnown = false
    public private(set) var mediaKind: PlaybackMediaKind = .video
    public private(set) var audioSpectrumFrame: AudioSpectrumFrame = .silent
    var videoRendererIsPublished = false
    public private(set) var attachedPresentation: PlaybackPresentation?
    public var attachedRealityViewID: String? { attachment?.realityViewID }
    public private(set) var firstAttachedPresentationForActiveTechnicalSession:
        PlaybackPresentation?
    public private(set) var rendererConsumerPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerEntityID: String?
    public private(set) var videoComponentRevision: UInt64 = 0
    public private(set) var boundVideoComponentRevision: UInt64?
    public private(set) var rendererPixelVideoComponentRevision: UInt64?
    public private(set) var rendererPixelStreamEpoch: UInt64?
    public private(set) var effectiveVideoFormatRevision: UInt64?
    public private(set) var technicalSessionFormatReplacementIsPending = false
    public private(set) var technicalSessionReplacementStage =
        TechnicalSessionReplacementStage.inactive
    public private(set) var seekIsInProgress = false
    public private(set) var userVisibleIssue: PlaybackUserVisibleIssue?
    public var liveTechnicalSessionCount: Int {
        rendererTransferCoordinator.liveTechnicalSessionCount
            + (openingTechnicalSessionDriver?.liveTechnicalSessionCount ?? 0)
    }
    public var retiringTechnicalSessionCount: Int {
        rendererTransferCoordinator.retiringTechnicalSessionCount
            + (openingTechnicalSessionDriver?.retiringTechnicalSessionCount ?? 0)
    }

    public var onPlaybackEnded: (() -> Void)?
    public var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    public var onPlaybackObservation: ((PlaybackRuntimeObservation) -> Void)?
    public private(set) var observationGeneration: UInt64 = 0
    @ObservationIgnored
    private var sessionLifecycleHandler: ((SessionLifecycleEvent) -> Void)?
    @ObservationIgnored
    private var externalSubtitleSourceIDByURL: [URL: String] = [:]
    @ObservationIgnored
    private var externalSubtitleAccessBySourceID: [String: MediaAccessLease] = [:]
    #if DEBUG
        @ObservationIgnored
        private var playbackSwitchSampleHandler: (@Sendable (
            PlaybackSwitchRendererSample,
            MediaByteStreamDebugCounters?
        ) -> Void)?
        @ObservationIgnored
        private var playbackFormatSwitchHandler: (() -> Void)?
        @ObservationIgnored
        public private(set) var debugPendingPresentationSettlementFault:
            DebugPresentationSettlementFault?
    #endif

    public var hasActivePlaybackRequest: Bool { currentLaunchRequest != nil }
    public var productLifecycle: ProductPlaybackLifecycle {
        switch lifecycle {
        case .idle: .idle
        case .loading: .loading
        case .ready: .ready
        case .playing: .playing
        case .paused: .paused
        case .ended: .ended
        case .failed: .failed
        }
    }
    public var canPresentControls: Bool { currentLaunchRequest != nil }
    public var canEnterSpatialPresentation: Bool {
        guard currentLaunchRequest != nil,
              activeSessionID != nil,
              mediaKind == .video,
              renderer != nil,
              attachedPresentation != nil,
              presentationState == .videoVisible,
              userVisibleIssue?.interruptsPlayback != true else { return false }
        switch lifecycle {
        case .ready, .playing, .paused, .ended:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }
    public var effectiveStereoLayout: PlaybackModel.StereoLayout {
        return selectedStereoLayout
    }
    public var unmetCapabilities: [UnmetCapability] {
        UnmetCapability.all(
            from: Self.capabilityFacts(from: diagnostics)
        )
    }
    public var activeMediaFormatProvenance: MediaFormatProvenance {
        usesSourceFormat ? .source : .userOverride
    }
    public var dolbyVisionFallbackIsEnabled: Bool {
        usesDolbyVisionFallback
    }
    public var dolbyVisionFallbackIsAvailable: Bool {
        guard let dolbyVision = displayMediaProfile?.dolbyVision else { return false }
        return dolbyVision.offersUserSelectableFallback
    }
    public var acceptedRendererProjectionKind: String? {
        guard activeSessionID != nil else { return nil }
        return rendererTransferCoordinator.debugSnapshot()?
            .lastAcceptedRendererInput?
            .formatSignaling?.projectionKind.value
    }
    public var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation {
        let source = MediaFormatInterpreter.sourceFormat(
            contentKind: sourceVideoContentKind,
            stereoLayout: sourceStereoLayout
        )
        let formatOverride: MediaFormat? = usesSourceFormat
            ? nil
            : MediaFormatInterpreter.mediaFormat(
                projection: selectedProjectionType,
                horizontalFieldOfViewDegrees: selectedHorizontalFieldOfViewDegrees,
                stereoLayout: selectedStereoLayout,
                usesDolbyVisionFallback: usesDolbyVisionFallback
            )
        return MediaFormatInterpretationResolver.resolve(
            source: source,
            override: formatOverride
        )
    }
    public private(set) var sourceVideoContentKind: PlaybackModel.SourceVideoContentKind = .rectilinear
    public var sourceMediaFormatSummary: String {
        "\(sourceVideoContentKind.displayName) · \(MediaFormatInterpreter.stereoLayoutDisplayName(sourceStereoLayout))"
    }
    public var effectiveContentIsPanoramic: Bool {
        usesSourceFormat
            ? sourceVideoContentKind.isPanoramic
            : selectedProjectionType.isPanoramic
    }
    public var requestsSpatialVideoMode: Bool {
        usesSourceFormat && sourceVideoContentKind == .spatialVideo
    }
    public var displayMediaProfile: PlaybackModel.MediaProfile? {
        profile(from: diagnostics) ?? prefetchedMetadata?.mediaProfile
    }
    public var displayFileSizeInBytes: Int64? { prefetchedMetadata?.fileSizeInBytes }
    public var isHDRContent: Bool { displayMediaProfile?.hdrType != .sdr }

    private let audioSessionLifecycle: PlaybackAudioSessionLifecycle
    let rendererTransferCoordinator = RendererTransferCoordinator()
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackRuntime")
    private let signposter: OSSignposter
    @ObservationIgnored
    private var openingTechnicalSessionDriver: PlaybackMediaSessionDriver?
    private var attachment: Attachment?
    private var generation = 0
    var selectedProjectionType: MediaFormatInterpreter.Projection = .flat
    var selectedHorizontalFieldOfViewDegrees: Int?
    private var selectedStereoLayout: PlaybackModel.StereoLayout = .mono
    private var usesDolbyVisionFallback = false
    private var sourceStereoLayout: PlaybackModel.StereoLayout = .mono
    private var sourceMediaFormatIsCaptured = false
    private var usesSourceFormat = true
    private var displayedImageGeneration = 0
    private var lastResolvedProfile: PlaybackModel.MediaProfile?
    private var closingTask: Task<Void, Never>?
    private var startsWhenAttached = false
    private var playbackVolume: Float = 1
    private var playbackMuted = false
    private var technicalSessionMediaFormatInterpretation: EffectiveMediaFormatInterpretation?
    private var actualPlaybackAccumulator = ActualPlaybackAccumulator()
    private var seekIntentGeneration: UInt64 = 0
    private var pendingFrameStepDelta = 0
    private var frameStepTask: Task<Void, Never>?
    private var frameStepGeneration: UInt64 = 0
    private var activeSourceReadFailureSequence: UInt64 = 0
    private var loadingStateMachine = PlaybackLoadingStateMachine()

    private struct Attachment {
        let entityID: String
        let realityViewID: String
        let presentation: PlaybackPresentation
    }

    init(
        openingDriver: PlaybackMediaSessionDriver,
        audioSessionLifecycle: PlaybackAudioSessionLifecycle
    ) {
        openingTechnicalSessionDriver = openingDriver
        self.audioSessionLifecycle = audioSessionLifecycle
        self.signposter = OSSignposter(logger: logger)
        bindDriverCallbacks(to: openingDriver)
    }

    private func bindDriverCallbacks(to driver: PlaybackMediaSessionDriver) {
        driver.bindCallbacks(
            .init(
                onStatusChange: { [weak self, weak driver] status in
                    guard let self, let driver else { return }
                    receive(status, from: driver)
                },
                onDiagnosticsChange: { [weak self] diagnostics in
                    self?.receive(diagnostics)
                },
                onDeliveryContinuityChange: { [weak self, weak driver] observation in
                    guard let self, let driver else { return }
                    receive(observation, from: driver)
                },
                onAcceptedVideoFormatRevisionChange: { [weak self, weak driver] revision in
                    guard let self,
                          effectiveVideoFormatRevision.map({ revision >= $0 }) ?? true else {
                        return
                    }
                    if usesSourceFormat, let snapshot = driver?.debugSnapshot() {
                        publishSourceMediaFormat(
                            MediaFormatInterpreter.sourceFormat(
                                from: snapshot.mediaFormatSignaling
                            ),
                            isCaptured: snapshot.providerOpen != nil
                                || snapshot.lastVideoSample != nil
                        )
                    }
                    effectiveVideoFormatRevision = revision
                },
                onSubtitleCuesChange: { [weak self] cues in
                    self?.activeSubtitleCues = cues
                },
                onSubtitleFrameChange: { [weak self] frame in
                    self?.activeSubtitleFrame = frame
                },
                onAudioSpectrumFrameChange: { [weak self] frame in
                    guard let self, self.mediaKind == .audioOnly else { return }
                    audioSpectrumFrame = frame
                }
            )
        )
    }

    public func prepareForPlayback(_ request: PlaybackLaunchRequest) {
        SurfaceInputProbes.record(
            "rendererOwnership.prepareForPlayback source=\(request.displayName)"
                + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                + "/\(Self.probeEntity(rendererConsumerEntityID))"
                + " renderer=\(renderer == nil ? "none" : "present")"
        )
        if currentLaunchRequest == nil || currentLaunchRequest != request {
            observationGeneration &+= 1
        }
        currentLaunchRequest = request
        updateLoadingState { stateMachine in
            stateMachine.beginOpening(
                runtimeGeneration: observationGeneration,
                requestID: String(describing: request.id)
            )
        }
        prefetchedMetadata = request.initialMetadata
        diagnostics = PlaybackDiagnostics()
        playbackPosition = .init(seconds: 0, duration: 0)
        currentPlaybackSpeed = .default
        presentationState = .placeholder
        let retainedActiveFailure = userVisibleIssue?.activePlaybackFailure.flatMap {
            $0.requestID == request.id ? userVisibleIssue : nil
        }
        setUserVisibleIssue(
            retainedActiveFailure
                ?? (request.externalSubtitleResolutionFailed ? .externalSubtitleFailed : nil)
        )
        lastResolvedProfile = nil
        startsWhenAttached = true
        actualPlaybackSeconds = 0
        didEndNaturally = false
        actualPlaybackAccumulator.reset()
        selectedProjectionType = .flat
        selectedHorizontalFieldOfViewDegrees = nil
        selectedStereoLayout = .mono
        usesDolbyVisionFallback = false
        sourceVideoContentKind = .rectilinear
        sourceStereoLayout = .mono
        sourceMediaFormatIsCaptured = false
        usesSourceFormat = true
        mediaFormatIsKnown = false
        mediaKind = .video
        audioSpectrumFrame = .silent
        videoRendererIsPublished = false
        videoComponentRevision = 0
        boundVideoComponentRevision = nil
        rendererPixelVideoComponentRevision = nil
        rendererPixelStreamEpoch = nil
        effectiveVideoFormatRevision = nil
        technicalSessionFormatReplacementIsPending = false
        technicalSessionMediaFormatInterpretation = nil
        activeTechnicalSessionID = nil
        firstAttachedPresentationForActiveTechnicalSession = nil
        rendererTransferCoordinator.resetBindingHistoryForPlaybackPreparation()
        publishRendererTransferObservation()
        invalidatePendingDisplayedImageClear()
        resetFrameStepping()
    }

    public func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = prefetchedMetadata?.merging(with: metadata) ?? metadata
    }

    public func setSessionLifecycleHandler(
        _ handler: ((SessionLifecycleEvent) -> Void)?
    ) {
        sessionLifecycleHandler = handler
    }

    #if DEBUG
        public func debugSetPlaybackSwitchSampleHandler(
            _ handler: (@Sendable (
                PlaybackSwitchRendererSample,
                MediaByteStreamDebugCounters?
            ) -> Void)?
        ) {
            playbackSwitchSampleHandler = handler
            rendererTransferCoordinator.applyToActiveAndPreparedDrivers { driver in
                installPlaybackSwitchSampleHandler(
                    on: driver,
                    byteStreamHandle: currentLaunchRequest?.source.byteStreamHandle
                )
            }
        }

        public func debugSetPlaybackFormatSwitchHandler(_ handler: (() -> Void)?) {
            playbackFormatSwitchHandler = handler
        }

        public func debugCurrentByteStreamCounters() -> MediaByteStreamDebugCounters? {
            currentLaunchRequest?.source.byteStreamHandle?.debugCounters()
        }

        public func debugCapturePlaybackSwitchRendererState() {
            rendererTransferCoordinator.capturePlaybackSwitchRendererState()
        }

        public func debugArmPresentationSettlementFault(
            _ fault: DebugPresentationSettlementFault
        ) {
            debugPendingPresentationSettlementFault = fault
        }

        public func debugClearPresentationSettlementFault() {
            debugPendingPresentationSettlementFault = nil
        }

        private func debugConsumePresentationSettlementFault()
            -> DebugPresentationSettlementFault? {
            defer { debugPendingPresentationSettlementFault = nil }
            return debugPendingPresentationSettlementFault
        }

        private func installPlaybackSwitchSampleHandler(
            on driver: PlaybackMediaSessionDriver?,
            byteStreamHandle: MediaByteStreamHandle?
        ) {
            guard let driver else { return }
            guard let playbackSwitchSampleHandler else {
                driver.setPlaybackSwitchRendererSampleSink(nil)
                return
            }
            driver.setPlaybackSwitchRendererSampleSink(
                PlaybackSwitchRendererSampleForwarder(
                    byteStreamHandle: byteStreamHandle,
                    handler: playbackSwitchSampleHandler
                )
            )
            driver.capturePlaybackSwitchRendererState()
        }
    #endif

    public func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double = 0,
        initialSpeed: PlaybackModel.PlaybackSpeed = .default,
        initialFormat: MediaFormat? = nil
    ) async throws {
        let interval = signposter.beginInterval("OpenPlayback")
        defer { signposter.endInterval("OpenPlayback", interval) }
        generation += 1
        let openGeneration = generation
        let startTimeSeconds = max(0, startTimeSeconds)
        prepareForPlayback(request)
        currentPlaybackSpeed = initialSpeed
        if let initialFormat {
            publishFormat(
                projection: MediaFormatInterpreter.playbackProjection(
                    from: initialFormat.projection
                ),
                horizontalFieldOfViewDegrees: initialFormat.horizontalFieldOfViewDegrees,
                stereo: MediaFormatInterpreter.playbackStereoLayout(
                    from: initialFormat.stereoLayout
                ),
                usesDolbyVisionFallback: initialFormat.usesDolbyVisionFallback
            )
        }
        logger.info("open requested source=\(request.displayName, privacy: .public)")

        do {
            await closingTask?.value
            closingTask = nil
            guard request.sourceAccess?.ensureActive() != false else {
                throw RuntimeError.sourceAccessUnavailable
            }
            request.source.byteStreamHandle?.useContainerIndex(
                for: request.versionedIdentity?.contentRevision
            )
            let driver = rendererTransferCoordinator.driverForOpen(
                openingDriver: &openingTechnicalSessionDriver,
                bindIfCreated: { [self] in
                    bindDriverCallbacks(to: $0)
                }
            )
            let openResult: PlaybackMediaSessionDriver.OpenResult
            do {
                openResult = try await driver.open(
                    .init(
                        url: request.url,
                        startTime: CMTime(
                            seconds: startTimeSeconds,
                            preferredTimescale: 60_000
                        ),
                        initialRate: Float(initialSpeed.value),
                        sourceTransport: request.source.playbackCoreTransport,
                        stereoOverride: initialFormat.map {
                            MediaFormatInterpreter.playbackStereoLayout(
                                from: $0.stereoLayout
                            )
                        },
                        projectionOverride: initialFormat.map {
                            MediaFormatInterpreter.playbackProjection(
                                from: $0.projection
                            )
                        },
                        horizontalFieldOfViewDegrees:
                            initialFormat?.horizontalFieldOfViewDegrees,
                        usesDolbyVisionFallback:
                            initialFormat?.usesDolbyVisionFallback == true,
                        provenance: "Enchron",
                        accessRequirement: request.source.isRemote
                            ? "networkSource"
                            : "securityScopedFile"
                    )
                )
                request.source.byteStreamHandle?.finishContainerIndex()
            } catch {
                request.source.byteStreamHandle?.discardContainerIndex()
                throw error
            }
            let sourceSnapshot = openResult.debugSnapshot
            let sessionResource = openResult.resource
            #if DEBUG
                installPlaybackSwitchSampleHandler(
                    on: driver,
                    byteStreamHandle: request.source.byteStreamHandle
                )
            #endif
            let sourceFormat = MediaFormatInterpreter.sourceFormat(
                from: sourceSnapshot.mediaFormatSignaling
            )
            guard generation == openGeneration else {
                await driver.close()
                if openingTechnicalSessionDriver === driver {
                    openingTechnicalSessionDriver = nil
                }
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            try rendererTransferCoordinator.installActive(sessionResource)
            activeSourceReadFailureSequence = request.source.byteStreamHandle?
                .latestReadFailure()?.sequence ?? 0
            if openingTechnicalSessionDriver === driver {
                openingTechnicalSessionDriver = nil
            }
            mediaKind = openResult.mediaKind
            updateActiveSessionID(sessionResource.sessionID)
            activeTechnicalSessionID = sessionResource.sessionID
            updateLoadingState { stateMachine in
                stateMachine.bindTechnicalSession(
                    sessionResource.sessionID,
                    runtimeGeneration: observationGeneration
                )
            }
            publishSourceMediaFormat(
                sourceFormat,
                isCaptured: sourceSnapshot.providerOpen != nil
                    || sourceSnapshot.lastVideoSample != nil
            )
            publishEffectiveFormatAfterSourceDiscovery(initialFormat)
            technicalSessionMediaFormatInterpretation = effectiveMediaFormatInterpretation
            let selectedAudioStreamIndex = openResult.selectedAudioStreamIndex
            availableAudioTracks = driver.availableAudioTracks.map {
                Self.audioTrack(
                    $0,
                    isDefault: $0.streamIndex == selectedAudioStreamIndex
                )
            }
            currentAudioTrackID = selectedAudioStreamIndex.map(String.init)
            availableSubtitleTracks = driver.availableSubtitleTracks.map(Self.subtitleTrack)
            currentSubtitleTrackID = driver.selectedSubtitleTrackID
            activeSubtitleCues = driver.activeSubtitleCues
            activeSubtitleFrame = driver.activeSubtitleFrame
            await addAutomaticExternalSubtitleSources(
                request.externalSubtitleSources,
                mediaSessionID: sessionResource.sessionID,
                openGeneration: openGeneration
            )
            guard generation == openGeneration,
                  activeSessionID == sessionResource.sessionID,
                  rendererTransferCoordinator.isActive(driver) else {
                await driver.close()
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            try await audioSessionLifecycle.activateIfNeeded(
                hasAudio: !availableAudioTracks.isEmpty
            )
            guard generation == openGeneration,
                  activeSessionID == sessionResource.sessionID,
                  rendererTransferCoordinator.isActive(driver) else {
                await driver.close()
                if activeSessionID == nil {
                    await audioSessionLifecycle.deactivate()
                }
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            recordAudioSessionFact()
            videoRendererIsPublished = mediaKind == .video
            publishRendererTransferObservation()
            SurfaceInputProbes.record(
                "rendererOwnership.open stage=rendererPublished"
                    + " technical=\(sessionResource.sessionID)"
                    + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                    + "/\(Self.probeEntity(rendererConsumerEntityID))"
            )
            logger.info("session prepared id=\(sessionResource.sessionID, privacy: .public)")
            if mediaKind == .audioOnly {
                try rendererTransferCoordinator.audioOnlyPresentationDidBecomeReady()
                try rendererTransferCoordinator.start()
                startsWhenAttached = false
                presentationState = .audioVisible
                markActivePresentationUsable()
            }
        } catch {
            guard generation == openGeneration else {
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            let issue: PlaybackUserVisibleIssue
            if let activeFailure = userVisibleIssue?.activePlaybackFailure,
               activeFailure.requestID == request.id {
                issue = .activePlaybackFailure(activeFailure)
            } else if let runtimeError = error as? RuntimeError,
               case .sourceAccessUnavailable = runtimeError {
                issue = .sourceAccessUnavailable
            } else if let controlError = error as? PlaybackControlError,
                      case .unsupportedVideoCodec(let codecName) = controlError {
                issue = .unsupportedVideoCodec(
                    PlaybackUnsupportedVideoCodec(codecName: codecName)
                )
            } else {
                issue = .mediaOpeningFailed
            }
            fail(error, issue: issue)
            throw error
        }
    }

    public func attach(
        entityID: String,
        realityViewID: String,
        presentation: PlaybackPresentation
    ) throws {
        guard activeSessionID != nil,
              rendererTransferCoordinator.activeDriverSessionID != nil else {
            throw RuntimeError.noSession
        }
        if attachment?.entityID == entityID,
           attachment?.realityViewID == realityViewID,
           attachment?.presentation == presentation { return }
        detach()
        let shouldStart = startsWhenAttached
        rendererTransferCoordinator.recordRealityKitBinding(
            entityIdentity: entityID,
            active: true
        )
        rendererTransferCoordinator.recordPresentationBinding(
            realityViewIdentity: realityViewID,
            platform: platformName,
            attached: true,
            sceneContainer: presentation.sceneContainer,
            sceneLifecycle: "activeRealityView"
        )
        try rendererTransferCoordinator.presentationDidAttach()
        do {
            if shouldStart {
                try rendererTransferCoordinator.start()
                startsWhenAttached = false
            }
        } catch {
            let failedSessionID = activeSessionID
            Task { @MainActor [weak self] in
                guard let self,
                      activeSessionID == failedSessionID else { return }
                await audioSessionLifecycle.deactivate()
                recordAudioSessionFact()
            }
            rendererTransferCoordinator.recordPresentationBinding(
                realityViewIdentity: realityViewID,
                platform: platformName,
                attached: false,
                sceneContainer: presentation.sceneContainer,
                sceneLifecycle: "attachFailed"
            )
            rendererTransferCoordinator.recordRealityKitBinding(
                entityIdentity: entityID,
                active: false
            )
            throw error
        }
        attachment = Attachment(entityID: entityID, realityViewID: realityViewID, presentation: presentation)
        attachedPresentation = presentation
        if firstAttachedPresentationForActiveTechnicalSession == nil {
            firstAttachedPresentationForActiveTechnicalSession = presentation
        }
        presentationState = .placeholder
        logger.info("surface attached presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)")
    }

    public func detach() {
        guard activeSessionID != nil,
              rendererTransferCoordinator.hasActiveDriver,
              let attachment else { return }
        rendererTransferCoordinator.recordPresentationBinding(
            realityViewIdentity: attachment.realityViewID,
            platform: platformName,
            attached: false,
            sceneContainer: attachment.presentation.sceneContainer,
            sceneLifecycle: "detachedRealityView"
        )
        rendererTransferCoordinator.recordRealityKitBinding(
            entityIdentity: attachment.entityID,
            active: false
        )
        logger.info("surface detached presentation=\(String(describing: attachment.presentation), privacy: .public)")
        self.attachment = nil
        attachedPresentation = nil
    }

    public func detachSurface(entityID: String, realityViewID: String) {
        guard attachment?.entityID == entityID,
              attachment?.realityViewID == realityViewID else {
            logger.notice("stale surface detach ignored entity=\(entityID, privacy: .public)")
            return
        }
        detach()
    }

    public func claimRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String
    ) throws {
        let previous = rendererTransferCoordinator.consumerSnapshot
        let result = rendererTransferCoordinator.claimConsumer(
            presentation: presentation,
            entityID: entityID
        )
        let current = rendererTransferCoordinator.consumerSnapshot
        let discarded: RendererTransferCoordinator.DiscardedConsumer?
        if case .granted(let spentConsumer) = result {
            discarded = spentConsumer
        } else {
            discarded = nil
        }
        if let discarded {
            SurfaceInputProbes.record(
                "rendererOwnership.discardSpent"
                    + " holder=\(discarded.presentation.rawValue)"
                    + "/\(Self.probeEntity(discarded.entityID))"
                    + " recordEpoch=\(discarded.recordEpoch)"
                    + " currentEpoch=\(discarded.currentEpoch)"
            )
            clearVideoComponentBindingObservation()
        }
        let facts = discarded == nil
            ? previous
            : RendererTransferCoordinator.ConsumerSnapshot(
                presentation: nil,
                entityID: nil,
                releasedPresentation: nil,
                releasedEntityID: nil,
                rendererEpoch: current.rendererEpoch,
                consumerEpoch: nil,
                lastBoundEntityID: nil,
                boundVideoComponentRevision: nil
            )
        let releasedFacts: String
        if let releasedPresentation = facts.releasedPresentation,
           let releasedEntityID = facts.releasedEntityID {
            releasedFacts = "\(releasedPresentation.rawValue)"
                + "/\(Self.probeEntity(releasedEntityID))"
        } else {
            releasedFacts = "none"
        }
        let ownershipFacts = "target=\(presentation.rawValue)/\(Self.probeEntity(entityID))"
            + " holder=\(facts.presentation?.rawValue ?? "none")"
            + "/\(Self.probeEntity(facts.entityID))"
            + " released=\(releasedFacts)"
        publishRendererTransferObservation()
        switch result {
        case .unchanged:
            return
        case .granted:
            SurfaceInputProbes.record(
                "rendererOwnership.claim outcome=granted \(ownershipFacts)"
            )
        case .busy(let currentPresentation):
            SurfaceInputProbes.record(
                "rendererOwnership.claim outcome=busy \(ownershipFacts)"
            )
            throw RuntimeError.rendererConsumerBusy(currentPresentation)
        case .transferPending:
            SurfaceInputProbes.record(
                "rendererOwnership.claim outcome=transferPending \(ownershipFacts)"
            )
            throw RuntimeError.rendererTransferPending
        }
    }

    static func probeEntity(_ entityID: String?) -> String {
        guard let entityID else { return "none" }
        return String(entityID.suffix(10))
    }

    public func releaseRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String,
        preservingVideoComponent: Bool = false
    ) {
        let previous = rendererTransferCoordinator.consumerSnapshot
        guard rendererTransferCoordinator.releaseConsumer(
            presentation: presentation,
            entityID: entityID,
            preservingVideoComponent: preservingVideoComponent
        ) else {
            SurfaceInputProbes.record(
                "rendererOwnership.release outcome=guardRejected"
                    + " requested=\(presentation.rawValue)/\(Self.probeEntity(entityID))"
                    + " holder=\(previous.presentation?.rawValue ?? "none")"
                    + "/\(Self.probeEntity(previous.entityID))"
            )
            return
        }
        SurfaceInputProbes.record(
            "rendererOwnership.release outcome=released"
                + " holder=\(presentation.rawValue)/\(Self.probeEntity(entityID))"
        )
        if preservingVideoComponent == false {
            clearVideoComponentBindingObservation(for: entityID)
        }
        publishRendererTransferObservation()
        logger.notice(
            "renderer consumer released presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
        )
    }

    func waitUntilRendererConsumerIsReleased(
        from sourcePresentation: PlaybackPresentation? = nil,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        if rendererTransferCoordinator.consumerIsReleased(from: sourcePresentation) {
            return true
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if rendererTransferCoordinator.consumerIsReleased(from: sourcePresentation) {
                return true
            }
        }
        logger.error(
            "renderer consumer release timed out presentation=\(String(describing: self.rendererConsumerPresentation), privacy: .public)"
        )
        return false
    }

    public func pause() {
        updateLoadingState { $0.clearStarvation() }
        PlaybackTrace.event("runtime.pause.request lifecycle=\(lifecycle.label)")
        guard let activeSessionID else {
            fail(RuntimeError.noSession)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performSpatialPlaybackTransport(
                    .pause(mediaSessionID: activeSessionID)
                )
            } catch {
                fail(error)
            }
        }
    }

    public func resume() {
        PlaybackTrace.event("runtime.resume.request lifecycle=\(lifecycle.label)")
        guard let activeSessionID else {
            fail(RuntimeError.noSession)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await performSpatialPlaybackTransport(
                    .resume(mediaSessionID: activeSessionID)
                )
            } catch {
                fail(error)
            }
        }
    }

    public func performSpatialPlaybackTransport(
        _ intent: SpatialPlaybackTransportIntent
    ) async throws {
        guard activeSessionID == intent.mediaSessionID,
              rendererTransferCoordinator.hasActiveDriver else {
            throw RuntimeError.mediaSessionChanged
        }

        switch intent {
        case .pause:
            updateLoadingState { $0.clearStarvation() }
            if productLifecycle == .paused { return }
            guard productLifecycle == .playing else {
                throw RuntimeError.spatialPlaybackTransportUnavailable(productLifecycle)
            }
            PlaybackTrace.event("runtime.pause.request lifecycle=\(lifecycle.label)")
            try rendererTransferCoordinator.pause()
            PlaybackTrace.event("runtime.pause.completed")
        case .resume:
            if productLifecycle == .playing { return }
            guard productLifecycle == .paused || productLifecycle == .ready else {
                throw RuntimeError.spatialPlaybackTransportUnavailable(productLifecycle)
            }
            PlaybackTrace.event("runtime.resume.request lifecycle=\(lifecycle.label)")
            try await audioSessionLifecycle.activateIfNeeded(
                hasAudio: !availableAudioTracks.isEmpty
            )
            guard activeSessionID == intent.mediaSessionID,
                  rendererTransferCoordinator.hasActiveDriver else {
                throw RuntimeError.mediaSessionChanged
            }
            recordAudioSessionFact()
            if mediaKind == .audioOnly {
                try rendererTransferCoordinator.play()
                PlaybackTrace.event("runtime.resume.completed kind=audioOnly")
                return
            }
            let continuity = try await rendererTransferCoordinator
                .playAndVerifyRendererGraphContinuity()
            guard continuity.explicitPlayMayContinue else {
                try? rendererTransferCoordinator.pause()
                throw RuntimeError.rendererGraphPlaybackDidNotAdvance(continuity)
            }
            if continuity == .awaitingDisplayedFrameAdvance {
                logger.notice(
                    "explicit Play kept running while displayed-frame identity awaits visual evidence"
                )
            }
            if continuity == .supersededByPause {
                PlaybackTrace.event("runtime.resume.supersededByPause")
                return
            }
            PlaybackTrace.event("runtime.resume.completed")
        }

        guard activeSessionID == intent.mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
    }

    public func beginPlaybackForPresentationSettlement(
        mediaSessionID: String
    ) async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        guard activeSessionID == mediaSessionID,
              rendererTransferCoordinator.hasActiveDriver else {
            throw RuntimeError.mediaSessionChanged
        }
        if productLifecycle == .playing { return }
        guard productLifecycle == .paused || productLifecycle == .ready else {
            throw RuntimeError.spatialPlaybackTransportUnavailable(productLifecycle)
        }
        try await audioSessionLifecycle.activateIfNeeded(
            hasAudio: !availableAudioTracks.isEmpty
        )
        guard activeSessionID == mediaSessionID,
              rendererTransferCoordinator.hasActiveDriver else {
            throw RuntimeError.mediaSessionChanged
        }
        recordAudioSessionFact()
        try await rendererTransferCoordinator.waitUntilTimelineReadyForControl()
        guard activeSessionID == mediaSessionID,
              rendererTransferCoordinator.hasActiveDriver else {
            throw RuntimeError.mediaSessionChanged
        }
        try rendererTransferCoordinator.playWithExternallyManagedFirstVideoFrameDeadline()
    }

    public func seek(
        to seconds: Double,
        event: PlaybackSeekEvent = .progressBar
    ) {
        updateLoadingState { $0.clearStarvation() }
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let nonnegativeTarget = max(0, seconds)
        let target = playbackPosition.duration > 0
            ? min(playbackPosition.duration, nonnegativeTarget)
            : nonnegativeTarget
        let targetBoundary: PlaybackSeekTargetBoundary = playbackPosition.duration > 0
            && target >= playbackPosition.duration
            ? .end
            : .beforeEnd
        let intent = PlaybackSeekPolicy.intent(
            for: event,
            lifecycle: productLifecycle,
            targetBoundary: targetBoundary
        )
        seekIntentGeneration &+= 1
        let seekGeneration = seekIntentGeneration
        let playbackObservationGeneration = observationGeneration
        seekIsInProgress = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.seekIntentGeneration == seekGeneration {
                    self.seekIsInProgress = false
                }
            }
            do {
                guard rendererTransferCoordinator.hasActiveDriver else {
                    throw RuntimeError.noSession
                }
                try await rendererTransferCoordinator.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    after: intent
                )
                emitPlaybackObservation(
                    .seekCompleted(positionSeconds: target),
                    generation: playbackObservationGeneration
                )
            } catch let error as PlaybackControlError {
                if case .seekSuperseded = error { return }
                fail(error)
            } catch {
                fail(error)
            }
        }
    }

    public func skip(by delta: Double) {
        updateLoadingState { $0.clearStarvation() }
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let intent = PlaybackSeekPolicy.intent(
            for: .skip,
            lifecycle: productLifecycle,
            targetBoundary: .beforeEnd
        )
        let target = max(
            0,
            playbackPosition.duration > 0
                ? min(playbackPosition.duration, playbackPosition.seconds + delta)
                : playbackPosition.seconds + delta
        )
        seekIntentGeneration &+= 1
        let seekGeneration = seekIntentGeneration
        let playbackObservationGeneration = observationGeneration
        seekIsInProgress = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.seekIntentGeneration == seekGeneration {
                    self.seekIsInProgress = false
                }
            }
            do {
                guard rendererTransferCoordinator.hasActiveDriver else {
                    throw RuntimeError.noSession
                }
                try await rendererTransferCoordinator.seek(
                    by: CMTime(seconds: delta, preferredTimescale: 600),
                    after: intent
                )
                emitPlaybackObservation(
                    .seekCompleted(positionSeconds: target),
                    generation: playbackObservationGeneration
                )
            } catch let error as PlaybackControlError {
                if case .seekSuperseded = error { return }
                fail(error)
            } catch {
                fail(error)
            }
        }
    }

    public func setSpeed(_ speed: PlaybackModel.PlaybackSpeed) {
        resetActualPlaybackSampling()
        do {
            try rendererTransferCoordinator.setRate(Float(speed.value))
            currentPlaybackSpeed = speed
        } catch let error as RendererTransferCoordinator.TransferError {
            fail(runtimeError(for: error))
        } catch {
            fail(error)
        }
    }

    func setVolume(_ volume: Float) {
        do {
            try rendererTransferCoordinator.setVolume(volume)
            playbackVolume = volume
        } catch let error as RendererTransferCoordinator.TransferError {
            fail(runtimeError(for: error))
        } catch {
            fail(error)
        }
    }

    func setMuted(_ muted: Bool) {
        do {
            try rendererTransferCoordinator.setMuted(muted)
            playbackMuted = muted
        } catch let error as RendererTransferCoordinator.TransferError {
            fail(runtimeError(for: error))
        } catch {
            fail(error)
        }
    }

    public func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws {
        guard let streamIndex = Int(track.id) else { return }
        do {
            try await rendererTransferCoordinator.selectAudioTrack(streamIndex: streamIndex)
        } catch let error as RendererTransferCoordinator.TransferError {
            throw runtimeError(for: error)
        }
        currentAudioTrackID = track.id
    }

    public func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws {
        do {
            try await rendererTransferCoordinator.selectSubtitleTrack(id: track?.id)
        } catch let error as RendererTransferCoordinator.TransferError {
            throw runtimeError(for: error)
        }
        guard rendererTransferCoordinator.hasActiveDriver else {
            throw RuntimeError.noSession
        }
        currentSubtitleTrackID = rendererTransferCoordinator.selectedSubtitleTrackID
        activeSubtitleCues = rendererTransferCoordinator.activeSubtitleCues
    }

    private func addAutomaticExternalSubtitleSources(
        _ sources: [ResolvedExternalSubtitleSource],
        mediaSessionID: String,
        openGeneration: Int
    ) async {
        guard rendererTransferCoordinator.hasActiveDriver else {
            for source in sources {
                source.accessLease?.release()
            }
            return
        }
        var encounteredFailure = false
        for source in sources {
            guard generation == openGeneration,
                  activeSessionID == mediaSessionID,
                  rendererTransferCoordinator.activeDriverSessionID == mediaSessionID else {
                source.accessLease?.release()
                continue
            }
            guard source.accessLease?.ensureActive() != false else {
                encounteredFailure = true
                logger.error(
                    "external subtitle source access unavailable source=\(source.displayName, privacy: .public)"
                )
                source.accessLease?.release()
                continue
            }
            do {
                _ = try await rendererTransferCoordinator.addExternalSubtitleSource(
                    PlaybackExternalSubtitleSource(
                        id: source.id,
                        url: source.url,
                        displayName: source.displayName
                    )
                )
                guard generation == openGeneration,
                      activeSessionID == mediaSessionID,
                      rendererTransferCoordinator.activeDriverSessionID == mediaSessionID else {
                    source.accessLease?.release()
                    continue
                }
                if let accessLease = source.accessLease {
                    let previousAccessLease = externalSubtitleAccessBySourceID.updateValue(
                        accessLease,
                        forKey: source.id
                    )
                    if let previousAccessLease,
                       previousAccessLease !== accessLease {
                        previousAccessLease.release()
                    }
                }
                let normalizedURL = source.url.isFileURL
                    ? source.url.standardizedFileURL
                    : source.url
                externalSubtitleSourceIDByURL[normalizedURL] = source.id
            } catch {
                source.accessLease?.release()
                encounteredFailure = true
                logger.error(
                    "external subtitle load failed source=\(source.displayName, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        guard generation == openGeneration,
              activeSessionID == mediaSessionID,
              rendererTransferCoordinator.activeDriverSessionID == mediaSessionID else { return }
        availableSubtitleTracks = rendererTransferCoordinator.availableSubtitleTracks
            .map(Self.subtitleTrack)
        currentSubtitleTrackID = rendererTransferCoordinator.selectedSubtitleTrackID
        activeSubtitleCues = rendererTransferCoordinator.activeSubtitleCues
        activeSubtitleFrame = rendererTransferCoordinator.activeSubtitleFrame
        if encounteredFailure,
           userVisibleIssue?.activePlaybackFailure == nil {
            setUserVisibleIssue(.externalSubtitleFailed)
        }
    }

    private func prepareExternalSubtitleSources(
        _ sources: [ResolvedExternalSubtitleSource],
        on driver: PlaybackMediaSessionDriver
    ) async {
        for source in sources {
            guard source.accessLease?.ensureActive() != false else { continue }
            _ = try? await driver.addExternalSubtitleSource(
                PlaybackExternalSubtitleSource(
                    id: source.id,
                    url: source.url,
                    displayName: source.displayName
                )
            )
        }
    }

    public func replay() {
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let playbackObservationGeneration = observationGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioSessionLifecycle.activateIfNeeded(
                    hasAudio: !availableAudioTracks.isEmpty
                )
                recordAudioSessionFact()
                try await rendererTransferCoordinator.seek(
                    to: .zero,
                    after: PlaybackAfterSeekBehavior.play
                )
                emitPlaybackObservation(
                    .seekCompleted(positionSeconds: 0),
                    generation: playbackObservationGeneration
                )
                try rendererTransferCoordinator.play()
            } catch let error as PlaybackControlError {
                if case .seekSuperseded = error { return }
                fail(error)
            } catch {
                fail(error)
            }
        }
    }

    public func frameStepForward() {
        guard mediaKind == .video else { return }
        frameStep(direction: 1)
    }
    public func frameStepBackward() {
        guard mediaKind == .video else { return }
        frameStep(direction: -1)
    }

    func adoptUserFormat(
        projection: MediaFormatInterpreter.Projection,
        horizontalFieldOfViewDegrees: Int?,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool
    ) {
        publishFormat(
            projection: projection,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereo: stereo,
            usesDolbyVisionFallback: usesDolbyVisionFallback
        )
        technicalSessionFormatReplacementIsPending =
            technicalSessionMediaFormatInterpretation != effectiveMediaFormatInterpretation
        #if DEBUG
            if technicalSessionFormatReplacementIsPending {
                playbackFormatSwitchHandler?()
            }
        #endif
        effectiveVideoFormatRevision = nil
    }

    public func useSourceFormat() async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        publishSourceFormat()
        technicalSessionFormatReplacementIsPending =
            technicalSessionMediaFormatInterpretation != effectiveMediaFormatInterpretation
        #if DEBUG
            if technicalSessionFormatReplacementIsPending {
                playbackFormatSwitchHandler?()
            }
        #endif
        effectiveVideoFormatRevision = nil
    }

    public func prepareTechnicalSessionForPresentationConversion() async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        let interval = signposter.beginInterval("ReplaceTechnicalPlaybackSession")
        defer { signposter.endInterval("ReplaceTechnicalPlaybackSession", interval) }
        guard rendererTransferCoordinator.transferIsInFlight == false else {
            throw RuntimeError.rendererTransferPending
        }
        guard let request = currentLaunchRequest,
              let logicalSessionID = activeSessionID,
              let sourceTechnicalSessionID = rendererTransferCoordinator.activeSessionID else {
            throw RuntimeError.noSession
        }

        if technicalSessionFormatReplacementIsPending == false,
           rendererTransferCoordinator.activeDriverSessionID != nil {
            do {
                try rendererTransferCoordinator.beginTransfer(
                    generation: generation,
                    logicalSessionID: logicalSessionID,
                    sourceTechnicalSessionID: sourceTechnicalSessionID,
                    mode: .rendererGraph
                )
                try rendererTransferCoordinator.finishRendererGraphPreparation(
                    generation: generation,
                    logicalSessionID: logicalSessionID,
                    sourceTechnicalSessionID: sourceTechnicalSessionID
                )
            } catch let error as RendererTransferCoordinator.TransferError {
                throw runtimeError(for: error)
            }
            technicalSessionReplacementStage = .installingRenderer
            return
        }
        technicalSessionReplacementStage = .openingReplacement

        generation += 1
        let replacementGeneration = generation
        do {
            try rendererTransferCoordinator.beginTransfer(
                generation: replacementGeneration,
                logicalSessionID: logicalSessionID,
                sourceTechnicalSessionID: sourceTechnicalSessionID,
                mode: .technicalSession
            )
        } catch let error as RendererTransferCoordinator.TransferError {
            throw runtimeError(for: error)
        }
        guard let key = rendererTransferCoordinator.inFlightTransferKey else {
            throw RuntimeError.noSession
        }
        let startTimeSeconds = max(0, playbackPosition.seconds)
        let speed = currentPlaybackSpeed
        let selectedAudioTrackID = currentAudioTrackID
        let selectedSubtitleTrackID = currentSubtitleTrackID

        let replacementDriver = PlaybackMediaSessionDriver()
        var replacementWasAdopted = false
        openingTechnicalSessionDriver = replacementDriver
        defer {
            if openingTechnicalSessionDriver === replacementDriver {
                openingTechnicalSessionDriver = nil
            }
        }
        do {
            let replacement = try await replacementDriver.open(
                .init(
                    url: request.url,
                    startTime: CMTime(
                        seconds: startTimeSeconds,
                        preferredTimescale: 60_000
                    ),
                    startsPaused: true,
                    initialRate: Float(speed.value),
                    sourceTransport: request.source.playbackCoreTransport,
                    stereoOverride: usesSourceFormat ? nil : selectedStereoLayout,
                    projectionOverride: usesSourceFormat ? nil : selectedProjectionType,
                    horizontalFieldOfViewDegrees: usesSourceFormat
                        ? nil
                        : selectedHorizontalFieldOfViewDegrees,
                    usesDolbyVisionFallback: usesDolbyVisionFallback,
                    provenance: "presentationConversionPrepared",
                    accessRequirement: request.url.isFileURL
                        ? "securityScopedFile"
                        : "networkSource"
                )
            )
            #if DEBUG
                installPlaybackSwitchSampleHandler(
                    on: replacementDriver,
                    byteStreamHandle: request.source.byteStreamHandle
                )
            #endif
            guard generation == replacementGeneration,
                  activeSessionID == logicalSessionID else {
                await replacementDriver.close(clearSource: false)
                throw RuntimeError.mediaSessionChanged
            }

            technicalSessionReplacementStage = .restoringExternalSubtitles
            await prepareExternalSubtitleSources(
                request.externalSubtitleSources,
                on: replacementDriver
            )

            if let selectedAudioTrackID,
               let streamIndex = Int(selectedAudioTrackID),
               replacementDriver.availableAudioTracks.contains(where: {
                   $0.streamIndex == streamIndex
               }) {
                technicalSessionReplacementStage = .restoringAudioTrack
                try await replacementDriver.selectAudioTrack(streamIndex: streamIndex)
            }
            if let selectedSubtitleTrackID,
               replacementDriver.availableSubtitleTracks.contains(where: {
                   $0.id == selectedSubtitleTrackID
               }) {
                technicalSessionReplacementStage = .restoringSubtitleTrack
                try await replacementDriver.selectSubtitleTrack(id: selectedSubtitleTrackID)
            }
            try replacementDriver.setVolume(playbackVolume)
            try replacementDriver.setMuted(playbackMuted)
            try rendererTransferCoordinator.finishTechnicalSessionPreparation(
                key: key,
                replacement: .init(
                    resource: replacement.resource,
                    speed: speed,
                    selectedAudioTrackID: selectedAudioTrackID,
                    selectedSubtitleTrackID: selectedSubtitleTrackID
                )
            )
            replacementWasAdopted = true
            technicalSessionReplacementStage = .installingRenderer
            logger.info(
                "replacement technical session prepared logical=\(logicalSessionID, privacy: .public) technical=\(replacement.resource.sessionID, privacy: .public)"
            )
        } catch {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            if replacementWasAdopted == false {
                await replacementDriver.close(clearSource: false)
            }
            technicalSessionReplacementStage = .failed
            if let transferError = error as? RendererTransferCoordinator.TransferError {
                throw runtimeError(for: transferError)
            }
            throw error
        }
    }

    public func activatePreparedTechnicalSessionReplacement() async throws {
        if rendererTransferCoordinator.preparedTechnicalSession == nil,
           rendererTransferCoordinator.phase == .prepared {
            try await activateReplacementRendererGraph()
            return
        }
        guard let prepared = rendererTransferCoordinator.preparedTechnicalSession,
              let key = rendererTransferCoordinator.preparedTransferKey else {
            throw RuntimeError.noSession
        }
        guard let sourceTechnicalSessionID =
                rendererTransferCoordinator.activeDriverSessionID else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }
        guard generation == key.generation,
              activeSessionID == key.logicalSessionID,
              sourceTechnicalSessionID == key.sourceTechnicalSessionID,
              rendererTransferCoordinator.isPrepared(prepared.resource.driver),
              prepared.resource.driver.sessionID != nil else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }

        let initiallyEndedContinuity = rendererTransferCoordinator.endedContinuity
        let naturalEndNotificationWasPublished =
            productLifecycle == .ended && didEndNaturally
        do {
            try await rendererTransferCoordinator.suspendPreparedVideoSampleDelivery()
            if productLifecycle == .playing {
                try rendererTransferCoordinator.pause()
            }
        } catch {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw error
        }
        guard let cutoverTime = rendererTransferCoordinator.currentTime() else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }
        let sourcePresentation = attachedPresentation
        let endedContinuity = rendererTransferCoordinator.endedContinuity
            ?? initiallyEndedContinuity

        guard generation == key.generation,
              activeSessionID == key.logicalSessionID,
              rendererTransferCoordinator.activeDriverSessionID
                == sourceTechnicalSessionID,
              rendererTransferCoordinator.isPrepared(prepared.resource.driver) else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }

        let activation: RendererTransferCoordinator.Activation
        do {
            activation = try rendererTransferCoordinator.activateTechnicalSession(
                key: key,
                cutoverTime: cutoverTime,
                endedContinuity: endedContinuity,
                sourcePresentation: sourcePresentation,
                naturalEndNotificationWasPublished:
                    naturalEndNotificationWasPublished,
                beforeCutover: { detach() }
            )
        } catch let error as RendererTransferCoordinator.TransferError {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw runtimeError(for: error)
        }
        bindDriverCallbacks(to: activation.activeResource.driver)
        activeSourceReadFailureSequence = currentLaunchRequest?.source.byteStreamHandle?
            .latestReadFailure()?.sequence ?? 0
        activeTechnicalSessionID = activation.activeResource.sessionID
        beginOpeningForActiveTechnicalSession()
        videoRendererIsPublished = true
        publishRendererTransferObservation()
        clearVideoComponentBindingObservation()
        presentationState = .placeholder
        startsWhenAttached = true
        firstAttachedPresentationForActiveTechnicalSession = nil
        videoComponentRevision &+= 1
        effectiveVideoFormatRevision = nil
        technicalSessionMediaFormatInterpretation = effectiveMediaFormatInterpretation
        technicalSessionFormatReplacementIsPending = false
        currentPlaybackSpeed = prepared.speed
        availableAudioTracks = prepared.resource.driver.availableAudioTracks.map {
            Self.audioTrack(
                $0,
                isDefault: String($0.streamIndex) == prepared.selectedAudioTrackID
            )
        }
        currentAudioTrackID = prepared.resource.driver.selectedAudioStreamIndex
            .map(String.init)
        availableSubtitleTracks = prepared.resource.driver.availableSubtitleTracks
            .map(Self.subtitleTrack)
        currentSubtitleTrackID = prepared.resource.driver.selectedSubtitleTrackID
        activeSubtitleCues = prepared.resource.driver.activeSubtitleCues
        activeSubtitleFrame = prepared.resource.driver.activeSubtitleFrame
        if case .ended(let continuity) = activation.continuity,
           let snapshot = currentCutoverSnapshot() {
            adoptEndedContinuity(continuity, cutover: snapshot)
        }
        receive(prepared.resource.driver.status, from: prepared.resource.driver)
        receive(prepared.resource.driver.diagnostics)
        logger.info(
            "prepared technical session activated logical=\(key.logicalSessionID, privacy: .public) technical=\(activation.activeResource.sessionID, privacy: .public)"
        )
    }

    private func activateReplacementRendererGraph() async throws {
        guard let key = rendererTransferCoordinator.preparedTransferKey else {
            throw RuntimeError.noSession
        }
        guard let sourceTechnicalSessionID =
                rendererTransferCoordinator.activeDriverSessionID,
              let logicalSessionID = activeSessionID else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }
        guard generation == key.generation,
              logicalSessionID == key.logicalSessionID,
              sourceTechnicalSessionID == key.sourceTechnicalSessionID else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }
        let initiallyEndedContinuity = rendererTransferCoordinator.endedContinuity
        let naturalEndNotificationWasPublished =
            productLifecycle == .ended && didEndNaturally
        do {
            if productLifecycle == .playing {
                try rendererTransferCoordinator.pause()
            }
        } catch {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw error
        }
        guard let cutoverTime = rendererTransferCoordinator.currentTime() else {
            _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }
        let sourcePresentation = attachedPresentation
        let endedContinuity = rendererTransferCoordinator.endedContinuity
            ?? initiallyEndedContinuity

        let replacement = try await rendererTransferCoordinator
            .replaceActiveVideoRendererGraph()
        guard generation == key.generation,
              activeSessionID == logicalSessionID,
              rendererTransferCoordinator.activeDriverSessionID
                == sourceTechnicalSessionID else {
            if await rendererTransferCoordinator.abandonInstalledRendererGraph(
                key: key,
                replacement: replacement
            ) == false {
                await rendererTransferCoordinator
                    .retireActiveDepartingVideoRendererGraph()
                _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            }
            videoRendererIsPublished = mediaKind == .video
            videoComponentRevision &+= 1
            effectiveVideoFormatRevision = nil
            publishRendererTransferObservation()
            clearVideoComponentBindingObservation()
            technicalSessionReplacementStage = .failed
            throw RuntimeError.mediaSessionChanged
        }

        let activation: RendererTransferCoordinator.Activation
        do {
            activation = try rendererTransferCoordinator.activateRendererGraph(
                key: key,
                replacement: replacement,
                cutoverTime: cutoverTime,
                endedContinuity: endedContinuity,
                sourcePresentation: sourcePresentation,
                naturalEndNotificationWasPublished:
                    naturalEndNotificationWasPublished,
                beforeCutover: { detach() }
            )
        } catch let error as RendererTransferCoordinator.TransferError {
            if await rendererTransferCoordinator.abandonInstalledRendererGraph(
                key: key,
                replacement: replacement
            ) == false {
                await rendererTransferCoordinator
                    .retireActiveDepartingVideoRendererGraph()
                _ = await rendererTransferCoordinator.cancelPreparedTransfer()
            }
            videoRendererIsPublished = mediaKind == .video
            videoComponentRevision &+= 1
            effectiveVideoFormatRevision = nil
            publishRendererTransferObservation()
            clearVideoComponentBindingObservation()
            technicalSessionReplacementStage = .failed
            throw runtimeError(for: error)
        }
        videoRendererIsPublished = true
        beginOpeningForActiveTechnicalSession()
        publishRendererTransferObservation()
        clearVideoComponentBindingObservation()
        presentationState = .placeholder
        startsWhenAttached = true
        firstAttachedPresentationForActiveTechnicalSession = nil
        videoComponentRevision &+= 1
        effectiveVideoFormatRevision = nil
        if case .ended(let continuity) = activation.continuity,
           let snapshot = currentCutoverSnapshot() {
            adoptEndedContinuity(continuity, cutover: snapshot)
        }
        logger.info(
            "replacement renderer graph activated logical=\(logicalSessionID, privacy: .public) technical=\(sourceTechnicalSessionID, privacy: .public)"
        )
    }

    public func rebaseActivatedTechnicalSessionReplacement(
        to presentation: PlaybackPresentation
    ) async throws {
        guard let cutover = currentCutoverSnapshot() else {
            throw RuntimeError.noSession
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        while replacementRendererTargetIsCurrent(for: presentation) == false {
            guard cutoverIsCurrent(cutover) else {
                throw RuntimeError.mediaSessionChanged
            }
            guard clock.now - startedAt < Self.presentationSettlementDeadline else {
                throw RuntimeError.presentationDidNotSettle(presentation)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard cutoverIsCurrent(cutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        observeEndedContinuityIfAvailable(for: cutover)
        if Self.shouldRetireDepartingTechnicalSessionBeforeDelivery(
            from: cutover.sourcePresentation,
            to: presentation
        ) {
            do {
                if try await rendererTransferCoordinator.retireDepartingBeforeDelivery(
                    for: cutover.token
                ) == .technicalSession {
                    logger.info(
                        "departing technical session retired before replacement delivery"
                    )
                }
            } catch let error as RendererTransferCoordinator.TransferError {
                throw runtimeError(for: error)
            }
        }
        try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded(
            cutover: cutover
        )
        guard cutoverIsCurrent(cutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        technicalSessionReplacementStage = .completed
    }

    public func retireDepartingTechnicalSessionAfterSceneDisappearance() async {
        let cutover = currentCutoverSnapshot()
        let departure = await rendererTransferCoordinator
            .retireDepartingAfterSceneDisappearance()
        if let cutover, departure != nil {
            completeTechnicalSessionReplacementAfterSettlement(cutover: cutover)
        }
        switch departure {
        case .rendererGraph:
            logger.info("departing renderer graph retired after source Scene disappeared")
        case .technicalSession:
            logger.info("departing technical session retired after source Scene disappeared")
        case nil:
            break
        }
    }

    static func shouldRetireDepartingTechnicalSessionBeforeDelivery(
        from sourcePresentation: PlaybackPresentation?,
        to targetPresentation: PlaybackPresentation
    ) -> Bool {
        sourcePresentation == .portal && targetPresentation == .panorama
    }

    public func cancelPreparedTechnicalSessionReplacement() async {
        if await rendererTransferCoordinator.cancelPreparedTransfer() {
            technicalSessionReplacementStage = .failed
        }
    }

    public func rebuildTechnicalSessionForCurrentPresentation() async throws {
        guard technicalSessionFormatReplacementIsPending else { return }
        guard let presentation = attachedPresentation,
              let logicalSessionID = activeSessionID else {
            throw RuntimeError.noSession
        }
        let restoresPlayingIntent = productLifecycle == .playing

        try await prepareTechnicalSessionForPresentationConversion()
        try await activatePreparedTechnicalSessionReplacement()
        try await rebaseActivatedTechnicalSessionReplacement(to: presentation)
        if restoresPlayingIntent, productLifecycle != .ended {
            try await performSpatialPlaybackTransport(
                .resume(mediaSessionID: logicalSessionID)
            )
        }
        guard await waitUntilPresentationSettled(to: presentation) else {
            throw RuntimeError.presentationDidNotSettle(presentation)
        }
        await retireDepartingTechnicalSessionAfterSceneDisappearance()
    }

    private func publishFormat(
        projection: MediaFormatInterpreter.Projection,
        horizontalFieldOfViewDegrees: Int?,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool
    ) {
        selectedProjectionType = projection
        selectedHorizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        selectedStereoLayout = stereo
        self.usesDolbyVisionFallback = usesDolbyVisionFallback
        usesSourceFormat = false
        mediaFormatIsKnown = true
    }

    func publishEffectiveFormatAfterSourceDiscovery(
        _ initialFormat: MediaFormat?
    ) {
        guard let initialFormat else {
            publishSourceFormat()
            return
        }
        publishFormat(
            projection: MediaFormatInterpreter.playbackProjection(
                from: initialFormat.projection
            ),
            horizontalFieldOfViewDegrees: initialFormat.horizontalFieldOfViewDegrees,
            stereo: MediaFormatInterpreter.playbackStereoLayout(
                from: initialFormat.stereoLayout
            ),
            usesDolbyVisionFallback: initialFormat.usesDolbyVisionFallback
        )
    }

    private func publishSourceFormat() {
        selectedProjectionType = MediaFormatInterpreter.sourceFormat(
            contentKind: sourceVideoContentKind,
            stereoLayout: sourceStereoLayout
        ).projection
        selectedHorizontalFieldOfViewDegrees = nil
        selectedStereoLayout = sourceStereoLayout
        usesDolbyVisionFallback = false
        usesSourceFormat = true
        mediaFormatIsKnown = sourceMediaFormatIsCaptured
    }

    private func publishSourceMediaFormat(
        _ sourceFormat: SourceMediaFormatFact,
        isCaptured: Bool
    ) {
        sourceVideoContentKind = sourceFormat.contentKind
        sourceStereoLayout = sourceFormat.stereoLayout
        sourceMediaFormatIsCaptured = isCaptured
        if usesSourceFormat {
            publishSourceFormat()
        }
    }

    public func videoRendererTargetDidBind(
        revision: UInt64,
        entityID: String
    ) {
        guard let binding = rendererTransferCoordinator.recordRendererTargetBinding(
            revision: revision,
            currentRevision: videoComponentRevision,
            entityID: entityID
        ) else { return }
        publishRendererTransferObservation()
        if let previousEntityID = binding.previousEntityID,
           previousEntityID != entityID {
            logger.error(
                "video renderer target identity changed within one playback session previous=\(previousEntityID, privacy: .public) current=\(entityID, privacy: .public)"
            )
        }
    }

    public func stop(releasingSourceAccess: Bool = true) {
        beginStop(releasingSourceAccess: releasingSourceAccess)
    }

    public func stopAndWait(releasingSourceAccess: Bool = true) async {
        let closeTask = beginStop(releasingSourceAccess: releasingSourceAccess)
        await closeTask?.value
    }

    public func displayedArtworkImage() -> CGImage? {
        guard activeSessionID != nil else { return nil }
        return rendererTransferCoordinator.displayedArtworkImage()
    }

    @discardableResult
    private func beginStop(releasingSourceAccess: Bool) -> Task<Void, Never>? {
        SurfaceInputProbes.record(
            "rendererOwnership.stop"
                + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                + "/\(Self.probeEntity(rendererConsumerEntityID))"
                + " renderer=\(renderer == nil ? "none" : "present")"
        )
        if currentLaunchRequest != nil {
            emitPlaybackObservation(.stopped)
        }
        generation += 1
        startsWhenAttached = false
        resetFrameStepping()
        detach()
        let sourceAccess = releasingSourceAccess
            ? currentLaunchRequest?.sourceAccess
            : nil
        let externalSubtitleAccesses = Array(externalSubtitleAccessBySourceID.values)
        externalSubtitleAccessBySourceID = [:]
        externalSubtitleSourceIDByURL = [:]
        let hadActiveDriver = rendererTransferCoordinator.hasActiveDriver
        let rendererCloseTask = rendererTransferCoordinator.beginClose()
        let openingDriver = openingTechnicalSessionDriver
        openingTechnicalSessionDriver = nil
        openingDriver?.hush()
        let previousClosingTask = closingTask
        let audioSessionLifecycle = audioSessionLifecycle
        let closeTask = Task { @MainActor in
            await previousClosingTask?.value
            await rendererCloseTask?.value
            await openingDriver?.close(clearSource: hadActiveDriver == false)
            await audioSessionLifecycle.deactivate()
            sourceAccess?.release()
            for subtitleAccess in externalSubtitleAccesses {
                subtitleAccess.release()
            }
        }
        closingTask = closeTask
        clearPresentation()
        logger.info("session stopped")
        return closeTask
    }

    private func clearPresentation() {
        presentationState = .hidden
        updateLoadingState { $0.clear() }
        videoRendererIsPublished = false
        rendererTransferCoordinator.invalidatePresentationState()
        publishRendererTransferObservation()
        activeTechnicalSessionID = nil
        updateActiveSessionID(nil)
        currentLaunchRequest = nil
        prefetchedMetadata = nil
        availableAudioTracks = []
        currentAudioTrackID = nil
        availableSubtitleTracks = []
        currentSubtitleTrackID = nil
        activeSubtitleCues = []
        activeSubtitleFrame = nil
        mediaKind = .video
        audioSpectrumFrame = .silent
        playbackPosition = .init(seconds: 0, duration: 0)
        selectedProjectionType = .flat
        selectedHorizontalFieldOfViewDegrees = nil
        selectedStereoLayout = .mono
        usesDolbyVisionFallback = false
        sourceVideoContentKind = .rectilinear
        sourceStereoLayout = .mono
        sourceMediaFormatIsCaptured = false
        usesSourceFormat = true
        mediaFormatIsKnown = false
        effectiveVideoFormatRevision = nil
        technicalSessionFormatReplacementIsPending = false
        technicalSessionMediaFormatInterpretation = nil
        activeSourceReadFailureSequence = 0
        clearVideoComponentBindingObservation()
        lastResolvedProfile = nil
    }

    private func updateActiveSessionID(_ newSessionID: String?) {
        let previousSessionID = activeSessionID
        guard previousSessionID != newSessionID else { return }
        activeSessionID = newSessionID

        switch (previousSessionID, newSessionID) {
        case (nil, let currentID?):
            sessionLifecycleHandler?(.activated(id: currentID))
        case (let previousID?, let currentID?):
            sessionLifecycleHandler?(
                .replaced(
                    previousID: previousID,
                    currentID: currentID
                )
            )
        case (let previousID?, nil):
            sessionLifecycleHandler?(.ended(id: previousID))
        case (nil, nil):
            break
        }
    }

    public static let presentationSettlementDeadline = Duration.seconds(30)

    public func waitUntilPresentationSettled(
        to presentation: PlaybackPresentation,
        allowsPendingSessionStart: Bool = false,
        deadline: Duration = PlaybackRuntime.presentationSettlementDeadline,
        clock: ContinuousClock = ContinuousClock()
    ) async -> Bool {
        #if DEBUG
        if debugConsumePresentationSettlementFault() == .timeout {
            SurfaceInputProbes.record(
                "presentationSettlement fault=settlement-timeout"
                    + " target=\(presentation.rawValue)",
                retention: .evidence
            )
            return false
        }
        #endif
        if let cutover = currentCutoverSnapshot() {
            do {
                try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded(
                    cutover: cutover
                )
            } catch {
                fail(error)
                return false
            }
        }
        if presentationIsSettled(presentation) {
            if let cutover = currentCutoverSnapshot() {
                completeTechnicalSessionReplacementAfterSettlement(
                    cutover: cutover
                )
            }
            return true
        }
        let startedAt = clock.now
        while true {
            guard Task.isCancelled == false else { return false }
            guard productLifecycle != .failed else { return false }
            if productLifecycle == .ended {
                guard currentCutoverSnapshot() != nil else {
                    return false
                }
            }
            let sessionIsAvailable = currentLaunchRequest != nil
                && activeSessionID != nil
                && activeTechnicalSessionID != nil
            guard sessionIsAvailable || allowsPendingSessionStart else {
                return false
            }
            guard clock.now - startedAt < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
            if let cutover = currentCutoverSnapshot() {
                do {
                    try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded(
                        cutover: cutover
                    )
                } catch {
                    fail(error)
                    return false
                }
            }
            if presentationIsSettled(presentation) {
                if let cutover = currentCutoverSnapshot() {
                    completeTechnicalSessionReplacementAfterSettlement(
                        cutover: cutover
                    )
                }
                return true
            }
        }
    }

    private func presentationIsSettled(_ presentation: PlaybackPresentation) -> Bool {
        guard activeSessionID != nil,
              attachedPresentation == presentation,
              let snapshot = rendererTransferCoordinator.debugSnapshot(),
              let record = snapshot.presentationState,
              rendererPixelVideoComponentRevision == videoComponentRevision,
              rendererPixelStreamEpoch == snapshot.streamEpoch else {
            return false
        }
        return Self.presentationTransitionCanCommit(
            record: record,
            presentation: presentation,
            activeTechnicalSessionID: activeTechnicalSessionID,
            lifecycle: productLifecycle
        )
    }

    static func presentationTransitionCanCommit(
        record: PresentationStateRecord,
        presentation: PlaybackPresentation,
        activeTechnicalSessionID: String?,
        lifecycle: ProductPlaybackLifecycle
    ) -> Bool {
        guard record.mediaSessionID == activeTechnicalSessionID,
              record.requestedMode == presentation.rawValue,
              record.displayedPixelBuffer == true,
              lifecycle != .failed,
              let phase = PlaybackPresentationSettlementPhase(rawValue: record.phase) else {
            return false
        }
        switch phase {
        case .settled:
            return true
        case .surfaceAttached:
            return false
        }
    }

    @discardableResult
    func recordPresentationState(
        presentation: PlaybackPresentation,
        phase: PlaybackPresentationSettlementPhase,
        entityID: String,
        technicalSessionID: String?,
        videoComponentRevision: UInt64,
        streamEpoch: UInt64?,
        realityViewID: String,
        entityParentID: String? = nil,
        desiredImmersiveViewingMode: String? = nil,
        actualImmersiveViewingMode: String? = nil,
        desiredViewingMode: String? = nil,
        actualViewingMode: String? = nil,
        desiredSpatialVideoMode: String? = nil,
        actualSpatialVideoMode: String? = nil,
        componentRenderingStatus: String? = nil,
        displayedPixelBuffer: Bool? = nil
    ) -> Bool {
        guard activeSessionID != nil,
              let mediaSessionID = rendererTransferCoordinator.activeDriverSessionID,
              let snapshot = rendererTransferCoordinator.debugSnapshot() else { return false }
        let record = PresentationStateRecord(
            mediaSessionID: mediaSessionID,
            requestedMode: presentation.rawValue,
            phase: phase.rawValue,
            platform: platformName,
            sceneContainer: .init(known: presentation.sceneContainer),
            realityViewIdentity: .init(known: realityViewID),
            entityParentIdentity: Self.observedFact(entityParentID),
            desiredImmersiveViewingMode: Self.observedFact(desiredImmersiveViewingMode),
            actualImmersiveViewingMode: Self.observedFact(actualImmersiveViewingMode),
            desiredViewingMode: Self.observedFact(desiredViewingMode),
            actualViewingMode: Self.observedFact(actualViewingMode),
            desiredSpatialVideoMode: Self.observedFact(desiredSpatialVideoMode),
            actualSpatialVideoMode: Self.observedFact(actualSpatialVideoMode),
            componentRenderingStatus: componentRenderingStatus.map { .init(known: $0) },
            displayedPixelBuffer: displayedPixelBuffer,
            audioSessionActive: audioSessionLifecycle.isActive,
            transitionResult: .init(known: "succeeded")
        )
        let outputIsPresentable = phase == .settled && displayedPixelBuffer == true
        let reportedPixelIdentity = PlaybackPresentationSurfacePixelIdentity(
            technicalSessionID: technicalSessionID,
            videoComponentRevision: videoComponentRevision,
            streamEpoch: streamEpoch
        )
        let currentPixelIdentity = PlaybackPresentationSurfacePixelIdentity(
            technicalSessionID: activeTechnicalSessionID,
            videoComponentRevision: self.videoComponentRevision,
            streamEpoch: snapshot.streamEpoch
        )
        let pixelIdentityIsCurrent = boundVideoComponentRevision
            == reportedPixelIdentity.videoComponentRevision
            && Self.presentationSurfacePixelIdentityIsCurrent(
                record: record,
                presentation: presentation,
                reported: reportedPixelIdentity,
                current: currentPixelIdentity,
                lifecycle: productLifecycle
            )
        if displayedPixelBuffer == true,
           rendererConsumerEntityID == entityID,
           pixelIdentityIsCurrent {
            rendererPixelVideoComponentRevision = videoComponentRevision
            rendererPixelStreamEpoch = streamEpoch
        }
        if outputIsPresentable {
            if presentationState != .videoVisible {
                presentationState = .videoVisible
                markActivePresentationUsable()
            }
        }
        if snapshot.presentationState != record {
            rendererTransferCoordinator.recordPresentationState(record)
        }
        return attachedPresentation == presentation
            && rendererConsumerEntityID == entityID
            && outputIsPresentable
            && pixelIdentityIsCurrent
    }

    static func presentationSurfacePixelIdentityIsCurrent(
        record: PresentationStateRecord,
        presentation: PlaybackPresentation,
        reported: PlaybackPresentationSurfacePixelIdentity,
        current: PlaybackPresentationSurfacePixelIdentity,
        lifecycle: ProductPlaybackLifecycle
    ) -> Bool {
        guard reported == current,
              reported.technicalSessionID != nil,
              reported.streamEpoch != nil,
              record.mediaSessionID == reported.technicalSessionID else {
            return false
        }
        return presentationTransitionCanCommit(
            record: record,
            presentation: presentation,
            activeTechnicalSessionID: current.technicalSessionID,
            lifecycle: lifecycle
        )
    }

    private func clearVideoComponentBindingObservation(
        for entityID: String? = nil
    ) {
        if let entityID,
           rendererConsumerEntityID != entityID {
            return
        }
        boundVideoComponentRevision = nil
        rendererPixelVideoComponentRevision = nil
        rendererPixelStreamEpoch = nil
    }

    private func currentCutoverSnapshot()
        -> RendererTransferCoordinator.CutoverSnapshot? {
        rendererTransferCoordinator.cutoverSnapshot(
            generation: generation,
            logicalSessionID: activeSessionID,
            activeTechnicalSessionID: activeTechnicalSessionID
        )
    }

    private func cutoverIsCurrent(
        _ cutover: RendererTransferCoordinator.CutoverSnapshot
    ) -> Bool {
        rendererTransferCoordinator.cutoverIsCurrent(
            cutover.token,
            generation: generation,
            logicalSessionID: activeSessionID,
            activeTechnicalSessionID: activeTechnicalSessionID
        )
    }

    private func observeEndedContinuityIfAvailable(
        for cutover: RendererTransferCoordinator.CutoverSnapshot
    ) {
        guard cutoverIsCurrent(cutover),
              let continuity = rendererTransferCoordinator
                .observeEndedContinuity(for: cutover.token) else { return }
        adoptEndedContinuity(continuity, cutover: cutover)
    }

    private func adoptEndedContinuity(
        _ continuity: PlaybackEndedContinuity,
        cutover: RendererTransferCoordinator.CutoverSnapshot
    ) {
        guard cutoverIsCurrent(cutover) else { return }
        invalidatePendingDisplayedImageClear()
        lifecycle = .ended(continuity.reason)
        didEndNaturally = continuity.reason == .naturalCompletion
        playbackPosition = .init(
            seconds: continuity.logicalPosition.seconds,
            duration: max(
                playbackPosition.duration,
                continuity.logicalPosition.seconds
            )
        )
        diagnostics.currentSeconds = continuity.logicalPosition.seconds
        let endedSessionID = activeSessionID
        Task { @MainActor [weak self] in
            guard let self,
                  activeSessionID == endedSessionID else { return }
            await audioSessionLifecycle.deactivate()
            guard activeSessionID == endedSessionID else { return }
            recordAudioSessionFact()
        }
        if rendererTransferCoordinator.recordNaturalEndNotification(
            for: cutover.token,
            continuity: continuity
        ) {
            onPlaybackEnded?()
        }
    }

    private func receiveReplacementStatus(_ status: PlaybackStatus) -> Bool {
        guard let cutover = currentCutoverSnapshot() else { return false }
        if case .failed = status { return false }
        observeEndedContinuityIfAvailable(for: cutover)
        guard let currentCutover = currentCutoverSnapshot(),
              case .ended = currentCutover.delivery.continuity else {
            return false
        }
        return true
    }

    private func reconcileAndDeliverTechnicalSessionReplacementIfNeeded(
        cutover: RendererTransferCoordinator.CutoverSnapshot
    ) async throws {
        observeEndedContinuityIfAvailable(for: cutover)
        guard let snapshot = currentCutoverSnapshot(),
              snapshot.token == cutover.token else {
            throw RuntimeError.mediaSessionChanged
        }
        guard case .pending = snapshot.delivery else { return }
        rendererPixelVideoComponentRevision = nil
        rendererPixelStreamEpoch = nil
        do {
            try await rendererTransferCoordinator.restartPendingDelivery(
                for: cutover.token
            )
        } catch let error as RendererTransferCoordinator.TransferError {
            throw runtimeError(for: error)
        }
        observeEndedContinuityIfAvailable(for: cutover)
    }

    private func completeTechnicalSessionReplacementAfterSettlement(
        cutover: RendererTransferCoordinator.CutoverSnapshot
    ) {
        guard cutoverIsCurrent(cutover),
              rendererTransferCoordinator.completeCutover(cutover.token) else { return }
        technicalSessionReplacementStage = .completed
    }

    private func replacementRendererTargetIsCurrent(
        for presentation: PlaybackPresentation
    ) -> Bool {
        guard attachedPresentation == presentation,
              attachment?.presentation == presentation,
              let entityID = attachment?.entityID else { return false }
        return rendererTransferCoordinator.rendererTargetIsCurrent(
            presentation: presentation,
            entityID: entityID,
            videoComponentRevision: videoComponentRevision
        )
    }

    private func publishRendererTransferObservation() {
        let snapshot = rendererTransferCoordinator.consumerSnapshot
        rendererConsumerPresentation = snapshot.presentation
        rendererConsumerEntityID = snapshot.entityID
        boundVideoComponentRevision = snapshot.boundVideoComponentRevision
    }

    private func runtimeError(
        for error: RendererTransferCoordinator.TransferError
    ) -> RuntimeError {
        switch error {
        case .noActiveRenderer:
            .noSession
        case .transferPending:
            .rendererTransferPending
        case .staleTransfer:
            .mediaSessionChanged
        }
    }

    public func outputObservation() -> PlaybackOutputObservation {
        let publishedSnapshot = rendererTransferCoordinator.debugSnapshot()
        let snapshot = activeSessionID == nil ? nil : publishedSnapshot
        let sourceReadObservation = openingTechnicalSessionDriver?.debugSnapshot()?
            .sourceReadObservation
            ?? rendererTransferCoordinator.preparedDebugSnapshot()?
                .sourceReadObservation
            ?? publishedSnapshot?.sourceReadObservation
        let presentation = snapshot?.presentationState
        let audioSession = audioSessionLifecycle.observation
        return PlaybackOutputObservation(
            capturedAt: snapshot?.generatedAt ?? Date(),
            mediaSessionID: snapshot?.mediaSession?.mediaSessionID,
            streamEpoch: snapshot?.streamEpoch ?? 0,
            lifecycle: productLifecycle,
            positionSeconds: snapshot?.rendererState?.currentTimeSeconds
                ?? playbackPosition.seconds,
            videoSampleCount: snapshot?.sampleCount ?? 0,
            acceptedRendererInputCount: snapshot?.acceptedRendererInputCount ?? 0,
            decoderBootstrapComplete: snapshot?.decoderBootstrap?.complete ?? false,
            requestedPlaybackRate: snapshot?.rendererState?.rate
                ?? snapshot?.decoderBootstrap?.targetRate
                ?? snapshot?.mediaSession?.initialRate
                ?? 0,
            actualTimebaseRate: snapshot?.rendererState?.actualTimebaseRate ?? 0,
            realityKitRendererBound: snapshot?.realityKitBinding?.active == true
                && snapshot?.realityKitBinding?.componentAttached == true,
            videoComponentReady: presentation?.componentRenderingStatus?.value?
                .localizedCaseInsensitiveContains("ready") == true,
            displayedPixelBuffer: presentation?.displayedPixelBuffer
                ?? snapshot?.rendererState?.displayedPixelBuffer
                ?? false,
            desiredImmersiveViewingMode: presentation?.desiredImmersiveViewingMode.value,
            actualImmersiveViewingMode: presentation?.actualImmersiveViewingMode.value,
            desiredViewingMode: presentation?.desiredViewingMode.value,
            actualViewingMode: presentation?.actualViewingMode.value,
            desiredSpatialVideoMode: presentation?.desiredSpatialVideoMode.value,
            actualSpatialVideoMode: presentation?.actualSpatialVideoMode.value,
            hasAudio: availableAudioTracks.isEmpty == false,
            audioSampleBufferCount: snapshot?.audioSampleBufferCount ?? 0,
            audioRendererSampleBufferCount: snapshot?.audioRendererState?
                .enqueuedSampleBufferCount ?? 0,
            audioRendererStreamEpoch: snapshot?.audioRendererState?.streamEpoch ?? 0,
            audioRendererStatus: snapshot?.audioRendererState?.status ?? "unknown",
            audioRendererVolume: snapshot?.audioRendererState?.volume ?? 1,
            audioRendererMuted: snapshot?.audioRendererState?.muted ?? false,
            audioRendererError: snapshot?.audioRendererState?.error,
            audioSessionActive: audioSessionLifecycle.isActive,
            audioSessionCategory: audioSession.category,
            audioSessionMode: audioSession.mode,
            audioSessionOutputPortTypes: audioSession.outputPortTypes,
            systemOutputVolume: audioSession.outputVolume,
            sourceReadBytesPerSecond: sourceReadObservation?.bytesPerSecond ?? 0,
            loadingVisibility: loadingState.visibility,
            loadingStage: loadingState.stage,
            loadingCausalEvidence: loadingState.causalEvidence
        )
    }

    public func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        guard activeSessionID != nil else { return nil }
        return rendererTransferCoordinator.debugSnapshot()
    }

    #if DEBUG
    public func debugEvidenceJSON() -> String {
        rendererTransferCoordinator.debugEvidenceJSON()
            ?? openingTechnicalSessionDriver?.debugEvidenceJSON()
            ?? ""
    }
    #endif

    func activeSessionForVerification() -> SampleBufferPlaybackSession? {
        guard activeSessionID != nil else { return nil }
        return rendererTransferCoordinator.sessionForVerification()
    }

    private var platformName: String {
        "visionOS"
    }

    private static func observedFact(_ value: String?) -> ObservedStringFact {
        value.map { .init(known: $0) } ?? .init(.notExposed)
    }

    private static func subtitleTrack(
        _ track: PlaybackSubtitleTrack
    ) -> PlaybackModel.SubtitleTrack {
        PlaybackModel.SubtitleTrack(
            id: track.id,
            languageCode: track.language,
            displayName: track.label
        )
    }

    private func frameStep(direction: Double) {
        pendingFrameStepDelta += direction > 0 ? 1 : -1
        guard frameStepTask == nil else { return }
        updateLoadingState { $0.clearStarvation() }
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let playbackObservationGeneration = observationGeneration
        frameStepGeneration &+= 1
        let generation = frameStepGeneration
        frameStepTask = Task { [weak self] in
            defer { self?.finishFrameStepping(generation: generation) }
            guard let self else { return }
            while self.frameStepGeneration == generation, self.pendingFrameStepDelta != 0 {
                let delta = self.pendingFrameStepDelta
                self.pendingFrameStepDelta = 0
                do {
                    let landing = try await self.rendererTransferCoordinator.stepFrames(
                        by: delta
                    )
                    self.emitPlaybackObservation(
                        .seekCompleted(positionSeconds: landing.seconds),
                        generation: playbackObservationGeneration
                    )
                } catch let error as RendererTransferCoordinator.TransferError {
                    self.fail(self.runtimeError(for: error))
                    return
                } catch let error as PlaybackControlError {
                    if case .seekSuperseded = error { return }
                    self.fail(error)
                    return
                } catch {
                    self.fail(error)
                    return
                }
            }
        }
    }

    private func finishFrameStepping(generation: UInt64) {
        guard frameStepGeneration == generation else { return }
        frameStepTask = nil
        pendingFrameStepDelta = 0
    }

    private func resetFrameStepping() {
        frameStepGeneration &+= 1
        frameStepTask?.cancel()
        frameStepTask = nil
        pendingFrameStepDelta = 0
    }

    private func updateLoadingState(
        _ update: (inout PlaybackLoadingStateMachine) -> Void
    ) {
        update(&loadingStateMachine)
        loadingState = loadingStateMachine.state
    }

    private func beginOpeningForActiveTechnicalSession() {
        guard let request = currentLaunchRequest,
              let activeTechnicalSessionID else { return }
        updateLoadingState { stateMachine in
            stateMachine.beginOpening(
                runtimeGeneration: observationGeneration,
                requestID: String(describing: request.id),
                technicalSessionID: activeTechnicalSessionID
            )
        }
    }

    private func markActivePresentationUsable() {
        guard let activeTechnicalSessionID else { return }
        updateLoadingState { stateMachine in
            stateMachine.presentationBecameUsable(
                technicalSessionID: activeTechnicalSessionID,
                runtimeGeneration: observationGeneration
            )
        }
    }

    private func receive(
        _ observation: PlaybackDeliveryContinuityObservation,
        from driver: PlaybackMediaSessionDriver
    ) {
        guard rendererTransferCoordinator.isActive(driver),
              let activeTechnicalSessionID,
              driver.sessionID == activeTechnicalSessionID else { return }
        updateLoadingState { stateMachine in
            stateMachine.receive(
                observation,
                technicalSessionID: activeTechnicalSessionID,
                runtimeGeneration: observationGeneration,
                lifecycle: productLifecycle
            )
        }
    }

    private func receive(
        _ status: PlaybackStatus,
        from driver: PlaybackMediaSessionDriver
    ) {
        guard openingTechnicalSessionDriver === driver
                || rendererTransferCoordinator.isActive(driver) else { return }
        if receiveReplacementStatus(status) { return }
        let previousLifecycle = lifecycle
        lifecycle = status
        emitPlaybackObservation(.lifecycle(productLifecycle))
        switch status {
        case .idle, .loading:
            break
        case .ready, .playing:
            didEndNaturally = false
        case .paused:
            didEndNaturally = false
            updateLoadingState { $0.clearStarvation() }
        case .ended(let reason):
            updateLoadingState { $0.clear() }
            didEndNaturally = reason == .naturalCompletion
            let endedSessionID = activeSessionID
            Task { @MainActor [weak self] in
                guard let self,
                      activeSessionID == endedSessionID else { return }
                await audioSessionLifecycle.deactivate()
                guard activeSessionID == endedSessionID else { return }
                recordAudioSessionFact()
            }
            displayedImageGeneration += 1
            let clearGeneration = displayedImageGeneration
            Task { [weak self] in
                guard let self, let endedSessionID else { return }
                await Task.yield()
                guard case .ended = lifecycle,
                      activeSessionID == endedSessionID,
                      displayedImageGeneration == clearGeneration else { return }
                await rendererTransferCoordinator.clearDisplayedVideoImage(
                    forMediaSessionID: endedSessionID
                )
            }
            if reason == .naturalCompletion {
                onPlaybackEnded?()
            }
        case .failed(let message):
            updateLoadingState { $0.clear() }
            let failedSessionID = activeSessionID
            Task { @MainActor [weak self] in
                guard let self,
                      activeSessionID == failedSessionID else { return }
                await audioSessionLifecycle.deactivate()
                guard activeSessionID == failedSessionID else { return }
                recordAudioSessionFact()
            }
            if unmetCapabilities.contains(where: \.preventsPlayback) {
                setUserVisibleIssue(.capabilityUnavailable(.videoDecoderUnavailable))
            } else if let failure = activePlaybackFailure(
                from: driver,
                previousLifecycle: previousLifecycle
            ) {
                setUserVisibleIssue(.activePlaybackFailure(failure))
                emitPlaybackObservation(.activeFailure(failure))
            } else if userVisibleIssue?.interruptsPlayback != true {
                setUserVisibleIssue(.playbackFailed)
            }
            logger.error("playback failed message=\(message, privacy: .public)")
        }
    }

    private func activePlaybackFailure(
        from driver: PlaybackMediaSessionDriver,
        previousLifecycle: PlaybackStatus
    ) -> PlaybackActiveFailure? {
        switch previousLifecycle {
        case .ready, .playing, .paused:
            break
        case .idle, .loading, .ended, .failed:
            return nil
        }
        guard rendererTransferCoordinator.isActive(driver),
              driver.sessionID == activeTechnicalSessionID,
              let request = currentLaunchRequest,
              let mediaSessionID = activeSessionID else { return nil }
        if let operation = driver.debugSnapshot()?.lastCompletedOperation,
           operation.kind == .seek,
           operation.state == .failed {
            return nil
        }

        guard let coreContext = driver.activeFailureContext else { return nil }
        let sourceFailure: MediaSourceReadFailure?
        if case .sourceRead = coreContext {
            let sourceObservation = request.source.byteStreamHandle?.latestReadFailure()
            if let sourceObservation,
               sourceObservation.sequence > activeSourceReadFailureSequence {
                activeSourceReadFailureSequence = sourceObservation.sequence
                sourceFailure = sourceObservation.failure
            } else {
                sourceFailure = nil
            }
        } else {
            sourceFailure = nil
        }
        guard let cause = Self.activeFailureCause(
            sourceFailure: sourceFailure,
            coreContext: coreContext
        ) else { return nil }
        let causalSeconds = driver.currentTime()?.seconds
        let causalPosition = PlaybackModel.PlaybackPosition(
            seconds: causalSeconds?.isFinite == true
                ? max(0, causalSeconds ?? playbackPosition.seconds)
                : playbackPosition.seconds,
            duration: playbackPosition.duration
        )
        return PlaybackActiveFailure(
            cause: cause,
            causalPosition: causalPosition,
            runtimeGeneration: observationGeneration,
            requestID: request.id,
            mediaSessionID: mediaSessionID
        )
    }

    static func activeFailureCause(
        sourceFailure: MediaSourceReadFailure?,
        coreContext: PlaybackCoreActiveFailureContext?
    ) -> PlaybackActiveFailure.Cause? {
        PlaybackMediaSessionDriver.activeFailureCause(
            sourceFailure: sourceFailure,
            coreContext: coreContext
        )
    }

    static func capabilityFacts(from diagnostics: PlaybackDiagnostics) -> PlaybackCapabilityFacts {
        PlaybackMediaSessionDriver.capabilityFacts(from: diagnostics)
    }

    private func recordAudioSessionFact() {
        guard activeSessionID != nil else { return }
        rendererTransferCoordinator.updateAudioSessionActive(
            audioSessionLifecycle.isActive
        )
    }

    private func receive(_ diagnostics: PlaybackDiagnostics) {
        recordActualPlayback(until: diagnostics.currentSeconds)
        self.diagnostics = diagnostics
        if let cutover = currentCutoverSnapshot(),
           case .ended(let continuity) = cutover.delivery.continuity {
            self.diagnostics.currentSeconds = continuity.logicalPosition.seconds
            playbackPosition = .init(
                seconds: continuity.logicalPosition.seconds,
                duration: max(
                    diagnostics.durationSeconds,
                    continuity.logicalPosition.seconds
                )
            )
        } else {
            playbackPosition = .init(
                seconds: diagnostics.currentSeconds,
                duration: diagnostics.durationSeconds
            )
        }
        emitPlaybackObservation(
            .diagnostics(
                position: playbackPosition,
                actualPlaybackSeconds: actualPlaybackSeconds
            )
        )
        guard let request = currentLaunchRequest,
              let profile = profile(from: diagnostics) else { return }
        guard profile != lastResolvedProfile else { return }
        lastResolvedProfile = profile
        onMediaProfileResolved?(request, profile)
    }

    private func recordActualPlayback(until position: Double, at date: Date = Date()) {
        actualPlaybackSeconds = actualPlaybackAccumulator.record(
            positionSeconds: position,
            at: date,
            isPlaying: lifecycle == .playing,
            playbackRate: currentPlaybackSpeed.value
        )
    }

    private func resetActualPlaybackSampling() {
        actualPlaybackAccumulator.markDiscontinuity()
    }

    private func emitPlaybackObservation(
        _ event: PlaybackRuntimeObservation.Event,
        generation: UInt64? = nil
    ) {
        onPlaybackObservation?(
            PlaybackRuntimeObservation(
                generation: generation ?? observationGeneration,
                event: event
            )
        )
    }

    private func invalidatePendingDisplayedImageClear() {
        displayedImageGeneration += 1
    }

    private func profile(from diagnostics: PlaybackDiagnostics) -> PlaybackModel.MediaProfile? {
        MediaFormatInterpreter.mediaProfile(
            projectionKind: diagnostics.projectionKind,
            viewPackingKind: diagnostics.viewPackingKind,
            isMVHEVC: diagnostics.isMVHEVC,
            dimensions: diagnostics.dimensions,
            encodedGeometry: diagnostics.videoGeometry.map {
                MediaFormatInterpreter.EncodedVideoGeometry(
                    width: $0.encodedDimensions.width,
                    height: $0.encodedDimensions.height,
                    horizontalSpacing: $0.sampleAspectRatio.horizontalSpacing,
                    verticalSpacing: $0.sampleAspectRatio.verticalSpacing
                )
            },
            transferFunction: diagnostics.transferFunction,
            dolbyVisionProfile: diagnostics.dolbyVisionProfile,
            formatHasDvcC: diagnostics.formatHasDvcC,
            formatHasDvvC: diagnostics.formatHasDvvC,
            dolbyVisionCrossCompatibilityID: diagnostics.dolbyVisionCrossCompatibilityID,
            dolbyVisionHasEnhancementLayer: diagnostics.dolbyVisionHasEnhancementLayer,
            codecName: diagnostics.codecName,
            nominalFrameRate: diagnostics.nominalFrameRate,
            durationSeconds: diagnostics.durationSeconds,
            fallback: prefetchedMetadata?.mediaProfile
        )
    }

    func fail(
        _ error: Error,
        issue: PlaybackUserVisibleIssue = .playbackControlFailed
    ) {
        if case PlaybackControlError.timelineNotReady = error {
            switch lifecycle {
            case .ready, .playing, .paused:
                logger.notice(
                    "stale timeline control failure ignored lifecycle=\(self.lifecycle.label, privacy: .public)"
                )
                return
            case .idle, .loading, .ended, .failed:
                break
            }
        }
        setUserVisibleIssue(issue)
        logger.error("runtime operation failed error=\(error.localizedDescription, privacy: .public)")
    }

    public func setUserVisibleIssue(_ issue: PlaybackUserVisibleIssue?) {
        userVisibleIssue = issue
    }

    private func releaseSourceAccessIfUnowned(_ sourceAccess: MediaAccessLease?) {
        guard let sourceAccess,
              currentLaunchRequest?.sourceAccess !== sourceAccess else { return }
        sourceAccess.release()
    }

    static func parseResolution(_ dimensions: String) -> PlaybackModel.MediaProfile.Resolution? {
        MediaFormatInterpreter.parseResolution(dimensions)
    }

    private static func audioTrack(
        _ track: PlaybackAudioTrack,
        isDefault: Bool
    ) -> PlaybackModel.AudioTrack {
        PlaybackModel.AudioTrack(
            id: String(track.streamIndex),
            languageCode: track.language,
            displayName: track.label,
            isDefault: isDefault
        )
    }
}

private extension PlaybackDebugSnapshotV1 {
    var mediaFormatSignaling: MediaFormatInterpreter.SourceSignaling {
        MediaFormatInterpreter.SourceSignaling(
            providerProjectionKind: providerOpen?.formatSignaling.projectionKind.value,
            sampleProjectionKind: lastVideoSample?.formatSignaling.projectionKind.value,
            providerViewPackingKind: providerOpen?.formatSignaling.viewPackingKind.value,
            sampleViewPackingKind: lastVideoSample?.formatSignaling.viewPackingKind.value,
            isMVHEVC: providerOpen?.isMVHEVC == true
        )
    }
}

private extension PlaybackPresentation {
    var sceneContainer: String {
        switch self {
        case .window: "WindowGroup"
        case .portal: "WindowGroup.Portal"
        case .docked: "ImmersiveSpace.Docked"
        case .panorama: "ImmersiveSpace.Panorama"
        }
    }
}

private extension PlaybackAddress {
    var playbackCoreTransport: PlaybackSourceTransport {
        guard isRemote else { return .localFile }
        let preference: PlaybackDemuxBufferPreference = switch preferredBufferDepth {
        case .none:
            .none
        case .automatic:
            .automatic
        case .bytes(let byteLimit):
            .bytes(byteLimit)
        }
        return .remoteByteStream(buffering: preference)
    }
}
