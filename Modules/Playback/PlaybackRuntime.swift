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
        case unsupportedProjection(PlaybackModel.ProjectionType)
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
            case .unsupportedProjection(let projection):
                "PlaybackCore cannot currently represent the \(projection.rawValue) projection."
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
    public private(set) var renderer: AVSampleBufferVideoRenderer?
    public private(set) var attachedPresentation: PlaybackPresentation?
    public var attachedRealityViewID: String? { attachment?.realityViewID }
    /// The first RealityView presentation that received the active technical
    /// playback instance. This resets whenever that instance is replaced.
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
        controller.liveTechnicalSessionCount
            + (departingTechnicalSessionController?.liveTechnicalSessionCount ?? 0)
            + (preparedTechnicalSessionReplacement?.controller.liveTechnicalSessionCount ?? 0)
    }
    public var retiringTechnicalSessionCount: Int {
        controller.retiringTechnicalSessionCount
            + (departingTechnicalSessionController?.retiringTechnicalSessionCount ?? 0)
            + (preparedTechnicalSessionReplacement?.controller.retiringTechnicalSessionCount ?? 0)
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
    public var effectiveProjectionType: PlaybackModel.ProjectionType {
        return selectedProjectionType
    }
    public var effectiveHorizontalFieldOfViewDegrees: Int {
        Self.effectiveHorizontalFieldOfViewDegrees(
            for: selectedProjectionType,
            explicitDegrees: selectedHorizontalFieldOfViewDegrees
        )
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
    /// The projection description accepted by the current renderer input.
    /// User overrides must prove this boundary before RealityKit mode changes
    /// can be treated as adoption of the override.
    public var acceptedRendererProjectionKind: String? {
        session?.debugSnapshot().lastAcceptedRendererInput?
            .formatSignaling?.projectionKind.value
    }
    public var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation {
        let sourceProjection = Self.projectionType(for: sourceVideoContentKind)
        let source = SourceMediaFormatFact(
            contentKind: sourceVideoContentKind,
            projection: sourceProjection,
            horizontalFieldOfViewDegrees: Self.sourceHorizontalFieldOfViewDegrees(
                for: sourceProjection
            ),
            stereoLayout: sourceStereoLayout
        )
        let formatOverride: MediaFormat? = usesSourceFormat
            ? nil
            : MediaFormat(
                projection: Self.mediaProjection(from: selectedProjectionType),
                horizontalFieldOfViewDegrees: selectedHorizontalFieldOfViewDegrees,
                stereoLayout: Self.mediaStereoLayout(from: selectedStereoLayout),
                usesDolbyVisionFallback: usesDolbyVisionFallback
            )
        return MediaFormatInterpretationResolver.resolve(
            source: source,
            override: formatOverride
        )
    }
    public private(set) var sourceVideoContentKind: PlaybackModel.SourceVideoContentKind = .rectilinear
    public var sourceMediaFormatSummary: String {
        "\(sourceVideoContentKind.displayName) · \(Self.stereoLayoutDisplayName(sourceStereoLayout))"
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

    private var controller: PlaybackCoreController
    private let audioSessionLifecycle: PlaybackAudioSessionLifecycle
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackRuntime")
    private let signposter: OSSignposter
    private var session: SampleBufferPlaybackSession?
    @ObservationIgnored
    private var openingTechnicalSessionReplacementController: PlaybackCoreController?
    private var attachment: Attachment?
    private var generation = 0
    private var selectedProjectionType: PlaybackModel.ProjectionType = .flat
    private var selectedHorizontalFieldOfViewDegrees: Int?
    private var selectedStereoLayout: PlaybackModel.StereoLayout = .mono
    private var usesDolbyVisionFallback = false
    private var sourceStereoLayout: PlaybackModel.StereoLayout = .mono
    private var sourceMediaFormatIsCaptured = false
    private var usesSourceFormat = true
    private var displayedImageGeneration = 0
    private var lastResolvedProfile: PlaybackModel.MediaProfile?
    private var closingTask: Task<Void, Never>?
    private var startsWhenAttached = false
    private var presentationConversionReusesMediaSession = false
    private var playbackVolume: Float = 1
    private var playbackMuted = false
    private var technicalSessionMediaFormatInterpretation: EffectiveMediaFormatInterpretation?
    private var actualPlaybackAccumulator = ActualPlaybackAccumulator()
    private var lastBoundVideoRendererEntityID: String?
    private var releasedRendererConsumer: ReleasedRendererConsumer?
    /// Counts renderer replacements. It advances only where `renderer` itself
    /// changes, never on a media-request generation bump, because a replacement
    /// is prepared long before its renderer is installed and the consumer that
    /// still holds the old renderer is legitimate for that whole window.
    private var rendererEpoch = 0
    /// The renderer epoch the consumer record describes. The record names an
    /// Entity that consumes one specific renderer, and the entity store mints a
    /// new Entity whenever that renderer is replaced, so a record from an
    /// earlier epoch names an Entity nothing can present again. Carrying the
    /// epoch lets such a record be recognised as spent instead of outliving its
    /// renderer and refusing every later claim.
    private var rendererConsumerEpoch: Int?
    private var technicalSessionReplacementIsInFlight = false
    private var preparedTechnicalSessionReplacement: PreparedTechnicalSessionReplacement?
    private var activatedTechnicalSessionCutover: ActivatedTechnicalSessionCutover?
    private var departingTechnicalSessionController: PlaybackCoreController?
    private var seekIntentGeneration: UInt64 = 0

    private struct PreparedTechnicalSessionReplacement {
        let controller: PlaybackCoreController
        let session: SampleBufferPlaybackSession
        let generation: Int
        let logicalSessionID: String
        let speed: PlaybackModel.PlaybackSpeed
        let selectedAudioTrackID: String?
        let selectedSubtitleTrackID: String?
    }

    private enum TechnicalSessionRebuildContinuity: Equatable {
        case timeline(CMTime)
        case ended(PlaybackEndedContinuity)
    }

    private enum TechnicalSessionReplacementDelivery: Equatable {
        case pending(TechnicalSessionRebuildContinuity)
        case applied(TechnicalSessionRebuildContinuity)

        var continuity: TechnicalSessionRebuildContinuity {
            switch self {
            case .pending(let continuity), .applied(let continuity):
                continuity
            }
        }
    }

    private struct ActivatedTechnicalSessionCutover: Equatable {
        let generation: Int
        let logicalSessionID: String
        let activeReplacementSessionID: String
        let sourcePresentation: PlaybackPresentation?
        var delivery: TechnicalSessionReplacementDelivery
        var naturalEndNotificationWasPublished: Bool
    }

    private struct Attachment {
        let entityID: String
        let realityViewID: String
        let presentation: PlaybackPresentation
    }

    /// Carries the serial handoff boundary after the source RealityView has
    /// removed its VideoPlayerComponent. A cross-RealityView handoff must use
    /// a new Entity because RealityKit does not reliably reactivate the same
    /// Entity and renderer graph after it moves between Window and Immersive
    /// roots. Transfers within one RealityView ownership class keep identity.
    private struct ReleasedRendererConsumer {
        let presentation: PlaybackPresentation
        let entityID: String

        func permitsClaim(
            presentation targetPresentation: PlaybackPresentation,
            entityID targetEntityID: String
        ) -> Bool {
            entityID == targetEntityID
                || presentation.usesImmersiveSpace
                    != targetPresentation.usesImmersiveSpace
        }
    }

    public convenience init(controller: PlaybackCoreController = PlaybackCoreController()) {
        self.init(
            controller: controller,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
    }

    init(
        controller: PlaybackCoreController,
        audioSessionLifecycle: PlaybackAudioSessionLifecycle
    ) {
        self.controller = controller
        self.audioSessionLifecycle = audioSessionLifecycle
        self.signposter = OSSignposter(logger: logger)
        bindControllerCallbacks(to: controller)
    }

    private func bindControllerCallbacks(to controller: PlaybackCoreController) {
        controller.onStatusChange = { [weak self] status in
            self?.receive(status)
        }
        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.receive(diagnostics)
        }
        controller.onAcceptedVideoFormatRevisionChange = { [weak self] revision in
            // Accepted input can publish newly observed source signaling, but
            // never triggers renderer, component, or Entity replacement.
            guard let self,
                  effectiveVideoFormatRevision.map({ revision >= $0 }) ?? true else {
                return
            }
            if usesSourceFormat, let session {
                publishSourceMediaFormat(from: session.debugSnapshot())
            }
            effectiveVideoFormatRevision = revision
        }
        controller.onSubtitleCuesChange = { [weak self] cues in
            self?.activeSubtitleCues = cues
        }
        controller.onSubtitleFrameChange = { [weak self] frame in
            self?.activeSubtitleFrame = frame
        }
        controller.onAudioSpectrumFrameChange = { [weak self] frame in
            guard let self, self.mediaKind == .audioOnly else { return }
            audioSpectrumFrame = frame
        }
    }

    private func unbindControllerCallbacks(from controller: PlaybackCoreController) {
        controller.onStatusChange = nil
        controller.onDiagnosticsChange = nil
        controller.onAcceptedVideoFormatRevisionChange = nil
        controller.onSubtitleCuesChange = nil
        controller.onSubtitleFrameChange = nil
        controller.onAudioSpectrumFrameChange = nil
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
        prefetchedMetadata = request.initialMetadata
        diagnostics = PlaybackDiagnostics()
        playbackPosition = .init(seconds: 0, duration: 0)
        currentPlaybackSpeed = .default
        presentationState = .placeholder
        setUserVisibleIssue(
            request.externalSubtitleResolutionFailed ? .externalSubtitleFailed : nil
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
        videoComponentRevision = 0
        boundVideoComponentRevision = nil
        rendererPixelVideoComponentRevision = nil
        rendererPixelStreamEpoch = nil
        effectiveVideoFormatRevision = nil
        technicalSessionFormatReplacementIsPending = false
        technicalSessionMediaFormatInterpretation = nil
        activeTechnicalSessionID = nil
        firstAttachedPresentationForActiveTechnicalSession = nil
        lastBoundVideoRendererEntityID = nil
        releasedRendererConsumer = nil
        activatedTechnicalSessionCutover = nil
        invalidatePendingDisplayedImageClear()
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
            installPlaybackSwitchSampleHandler(
                on: session,
                byteStreamHandle: currentLaunchRequest?.source.byteStreamHandle
            )
            installPlaybackSwitchSampleHandler(
                on: preparedTechnicalSessionReplacement?.session,
                byteStreamHandle: currentLaunchRequest?.source.byteStreamHandle
            )
        }

        public func debugSetPlaybackFormatSwitchHandler(_ handler: (() -> Void)?) {
            playbackFormatSwitchHandler = handler
        }

        public func debugCurrentByteStreamCounters() -> MediaByteStreamDebugCounters? {
            currentLaunchRequest?.source.byteStreamHandle?.debugCounters()
        }

        public func debugCapturePlaybackSwitchRendererState() {
            session?.capturePlaybackSwitchRendererState()
        }

        private func installPlaybackSwitchSampleHandler(
            on session: SampleBufferPlaybackSession?,
            byteStreamHandle: MediaByteStreamHandle?
        ) {
            guard let session else { return }
            guard let playbackSwitchSampleHandler else {
                session.setPlaybackSwitchRendererSampleSink(nil)
                return
            }
            session.setPlaybackSwitchRendererSampleSink(
                PlaybackSwitchRendererSampleForwarder(
                    byteStreamHandle: byteStreamHandle,
                    handler: playbackSwitchSampleHandler
                )
            )
            session.capturePlaybackSwitchRendererState()
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
                projection: Self.playbackProjection(from: initialFormat.projection),
                horizontalFieldOfViewDegrees: initialFormat.horizontalFieldOfViewDegrees,
                stereo: Self.playbackStereoLayout(from: initialFormat.stereoLayout),
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
            let newSession: SampleBufferPlaybackSession
            do {
                newSession = try await controller.open(
                    request.url,
                    startTime: CMTime(seconds: startTimeSeconds, preferredTimescale: 60_000),
                    initialRate: Float(initialSpeed.value),
                    sourceTransport: request.source.playbackCoreTransport,
                    initialStereoLayout: initialFormat.flatMap {
                        Self.coreStereoLayout(
                            for: Self.playbackStereoLayout(from: $0.stereoLayout)
                        )
                    },
                    initialProjectionOverride: initialFormat.map {
                        Self.coreProjectionOverride(
                            for: Self.playbackProjection(from: $0.projection),
                            horizontalFieldOfViewDegrees: $0.horizontalFieldOfViewDegrees
                        )
                    },
                    initialDynamicRangeOverride: initialFormat?.usesDolbyVisionFallback == true
                        ? .dolbyVisionFallback
                        : nil,
                    provenance: "Enchron",
                    accessRequirement: request.source.isRemote ? "networkSource" : "securityScopedFile"
                )
                request.source.byteStreamHandle?.finishContainerIndex()
            } catch {
                request.source.byteStreamHandle?.discardContainerIndex()
                throw error
            }
            let sourceSnapshot = newSession.debugSnapshot()
            #if DEBUG
                installPlaybackSwitchSampleHandler(
                    on: newSession,
                    byteStreamHandle: request.source.byteStreamHandle
                )
            #endif
            let sourceFormat = Self.sourceMediaFormat(from: sourceSnapshot)
            if sourceFormat.contentKind == .appleImmersiveVideo {
                await controller.closeAndWait()
                throw RuntimeError.unableToOpenFile
            }
            guard generation == openGeneration else {
                await controller.closeAndWait()
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            session = newSession
            mediaKind = newSession.mediaKind
            updateActiveSessionID(newSession.traceID)
            activeTechnicalSessionID = newSession.traceID
            publishSourceMediaFormat(from: sourceSnapshot)
            publishEffectiveFormatAfterSourceDiscovery(initialFormat)
            technicalSessionMediaFormatInterpretation = effectiveMediaFormatInterpretation
            let selectedAudioStreamIndex = newSession.selectedAudioStreamIndex
            availableAudioTracks = controller.availableAudioTracks.map {
                Self.audioTrack(
                    $0,
                    isDefault: $0.streamIndex == selectedAudioStreamIndex
                )
            }
            currentAudioTrackID = selectedAudioStreamIndex.map(String.init)
            availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
            currentSubtitleTrackID = controller.selectedSubtitleTrackID
            activeSubtitleCues = controller.activeSubtitleCues
            activeSubtitleFrame = controller.activeSubtitleFrame
            await addAutomaticExternalSubtitleSources(
                request.externalSubtitleSources,
                mediaSessionID: newSession.traceID,
                openGeneration: openGeneration
            )
            guard generation == openGeneration,
                  activeSessionID == newSession.traceID else {
                await controller.closeAndWait()
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            try await audioSessionLifecycle.activateIfNeeded(
                hasAudio: !availableAudioTracks.isEmpty
            )
            guard generation == openGeneration,
                  activeSessionID == newSession.traceID else {
                await controller.closeAndWait()
                if activeSessionID == nil {
                    await audioSessionLifecycle.deactivate()
                }
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            recordAudioSessionFact()
            renderer = mediaKind == .video ? newSession.renderer : nil
            rendererEpoch &+= 1
            SurfaceInputProbes.record(
                "rendererOwnership.open stage=rendererPublished"
                    + " technical=\(newSession.traceID)"
                    + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                    + "/\(Self.probeEntity(rendererConsumerEntityID))"
            )
            logger.info("session prepared id=\(newSession.traceID, privacy: .public)")
            if mediaKind == .audioOnly {
                try controller.audioOnlyPresentationDidBecomeReady(session: newSession)
                try controller.start()
                startsWhenAttached = false
                presentationState = .audioVisible
            }
        } catch {
            guard generation == openGeneration else {
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            let issue: PlaybackUserVisibleIssue
            if let runtimeError = error as? RuntimeError,
               case .sourceAccessUnavailable = runtimeError {
                issue = .sourceAccessUnavailable
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
        guard let session else { throw RuntimeError.noSession }
        if attachment?.entityID == entityID,
           attachment?.realityViewID == realityViewID,
           attachment?.presentation == presentation { return }
        detach()
        let shouldStart = startsWhenAttached
        session.recordRealityKitBinding(entityIdentity: entityID, active: true)
        session.recordPresentationBinding(
            realityViewIdentity: realityViewID,
            platform: platformName,
            attached: true,
            sceneContainer: presentation.sceneContainer,
            sceneLifecycle: "activeRealityView"
        )
        try controller.presentationDidAttach(session: session)
        do {
            if shouldStart {
                try controller.start()
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
            session.recordPresentationBinding(
                realityViewIdentity: realityViewID,
                platform: platformName,
                attached: false,
                sceneContainer: presentation.sceneContainer,
                sceneLifecycle: "attachFailed"
            )
            session.recordRealityKitBinding(entityIdentity: entityID, active: false)
            throw error
        }
        attachment = Attachment(entityID: entityID, realityViewID: realityViewID, presentation: presentation)
        attachedPresentation = presentation
        if firstAttachedPresentationForActiveTechnicalSession == nil {
            firstAttachedPresentationForActiveTechnicalSession = presentation
        }
        presentationState = .placeholder
        clearFailureIfPlaybackIsUsable()
        logger.info("surface attached presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)")
    }

    public func detach() {
        guard let session, let attachment else { return }
        session.recordPresentationBinding(
            realityViewIdentity: attachment.realityViewID,
            platform: platformName,
            attached: false,
            sceneContainer: attachment.presentation.sceneContainer,
            sceneLifecycle: "detachedRealityView"
        )
        session.recordRealityKitBinding(entityIdentity: attachment.entityID, active: false)
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
        discardRendererConsumerRecordFromASpentEpoch()
        if rendererConsumerPresentation == presentation,
           rendererConsumerEntityID == entityID {
            return
        }
        let releasedFacts = releasedRendererConsumer.map {
            "\($0.presentation.rawValue)/\(Self.probeEntity($0.entityID))"
        } ?? "none"
        let ownershipFacts = "target=\(presentation.rawValue)/\(Self.probeEntity(entityID))"
            + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
            + "/\(Self.probeEntity(rendererConsumerEntityID))"
            + " released=\(releasedFacts)"
        if let rendererConsumerEntityID, rendererConsumerEntityID != entityID {
            SurfaceInputProbes.record(
                "rendererOwnership.claim outcome=busy \(ownershipFacts)"
            )
            throw RuntimeError.rendererConsumerBusy(rendererConsumerPresentation ?? presentation)
        }
        if let releasedRendererConsumer {
            guard releasedRendererConsumer.permitsClaim(
                presentation: presentation,
                entityID: entityID
            ) else {
                SurfaceInputProbes.record(
                    "rendererOwnership.claim outcome=transferPending \(ownershipFacts)"
                )
                throw RuntimeError.rendererTransferPending
            }
            self.releasedRendererConsumer = nil
        }
        rendererConsumerPresentation = presentation
        rendererConsumerEntityID = entityID
        rendererConsumerEpoch = rendererEpoch
        SurfaceInputProbes.record(
            "rendererOwnership.claim outcome=granted \(ownershipFacts)"
        )
    }

    /// Drops a consumer record left by an earlier media request. Ownership is
    /// serialised between RealityViews that share one renderer; once the
    /// renderer has been replaced there is nothing left to serialise, and the
    /// Entity identity the record is keyed by can no longer be presented by
    /// anyone. Without this the record refuses every claim on the new renderer
    /// and the surface retries forever, because the only code that could clear
    /// it is guarded by the identity the entity store has already replaced.
    private func discardRendererConsumerRecordFromASpentEpoch() {
        guard let rendererConsumerEpoch,
              rendererConsumerEpoch != rendererEpoch else { return }
        if let rendererConsumerEntityID {
            SurfaceInputProbes.record(
                "rendererOwnership.discardSpent"
                    + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                    + "/\(Self.probeEntity(rendererConsumerEntityID))"
                    + " recordEpoch=\(rendererConsumerEpoch)"
                    + " currentEpoch=\(rendererEpoch)"
            )
        }
        rendererConsumerPresentation = nil
        rendererConsumerEntityID = nil
        self.rendererConsumerEpoch = nil
        releasedRendererConsumer = nil
        lastBoundVideoRendererEntityID = nil
        clearVideoComponentBindingObservation()
    }

    /// Shortens an Entity identity for the ownership probe. Only the object
    /// address distinguishes two `EnchronVideo#ObjectIdentifier(...)` values.
    static func probeEntity(_ entityID: String?) -> String {
        guard let entityID else { return "none" }
        return String(entityID.suffix(10))
    }

    public func releaseRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String,
        preservingVideoComponent: Bool = false
    ) {
        guard rendererConsumerPresentation == presentation,
              rendererConsumerEntityID == entityID else {
            SurfaceInputProbes.record(
                "rendererOwnership.release outcome=guardRejected"
                    + " requested=\(presentation.rawValue)/\(Self.probeEntity(entityID))"
                    + " holder=\(rendererConsumerPresentation?.rawValue ?? "none")"
                    + "/\(Self.probeEntity(rendererConsumerEntityID))"
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
        releasedRendererConsumer = ReleasedRendererConsumer(
            presentation: presentation,
            entityID: entityID
        )
        rendererConsumerPresentation = nil
        rendererConsumerEntityID = nil
        rendererConsumerEpoch = nil
        logger.notice(
            "renderer consumer released presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
        )
    }

    func waitUntilRendererConsumerIsReleased(
        from sourcePresentation: PlaybackPresentation? = nil,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        if rendererConsumerIsReleased(from: sourcePresentation) { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if rendererConsumerIsReleased(from: sourcePresentation) { return true }
        }
        logger.error(
            "renderer consumer release timed out presentation=\(String(describing: self.rendererConsumerPresentation), privacy: .public)"
        )
        return false
    }

    private func rendererConsumerIsReleased(
        from sourcePresentation: PlaybackPresentation?
    ) -> Bool {
        guard let sourcePresentation else {
            return rendererConsumerEntityID == nil
        }
        return rendererConsumerPresentation != sourcePresentation
    }

    public func pause() {
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
        guard activeSessionID == intent.mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }

        switch intent {
        case .pause:
            if productLifecycle == .paused { return }
            guard productLifecycle == .playing else {
                throw RuntimeError.spatialPlaybackTransportUnavailable(productLifecycle)
            }
            PlaybackTrace.event("runtime.pause.request lifecycle=\(lifecycle.label)")
            try controller.pause()
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
            guard activeSessionID == intent.mediaSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            recordAudioSessionFact()
            if mediaKind == .audioOnly {
                try controller.play()
                PlaybackTrace.event("runtime.resume.completed kind=audioOnly")
                return
            }
            let continuity = try await controller.playAndVerifyRendererGraphContinuity()
            guard continuity.explicitPlayMayContinue else {
                try? controller.pause()
                throw RuntimeError.rendererGraphPlaybackDidNotAdvance(continuity)
            }
            if continuity == .awaitingDisplayedFrameAdvance {
                logger.notice(
                    "explicit Play kept running while displayed-frame identity awaits visual evidence"
                )
            }
            PlaybackTrace.event("runtime.resume.completed")
        }

        guard activeSessionID == intent.mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
    }

    /// Starts a playing replacement session while its target Entity is still
    /// attaching. The presentation settlement gate supplies the displayed-
    /// pixel proof, so this path must not require that proof before Play can
    /// begin.
    public func beginPlaybackForPresentationSettlement(
        mediaSessionID: String
    ) async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        guard activeSessionID == mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
        if productLifecycle == .playing { return }
        guard productLifecycle == .paused || productLifecycle == .ready else {
            throw RuntimeError.spatialPlaybackTransportUnavailable(productLifecycle)
        }
        try await audioSessionLifecycle.activateIfNeeded(
            hasAudio: !availableAudioTracks.isEmpty
        )
        guard activeSessionID == mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
        recordAudioSessionFact()
        try await controller.waitUntilTimelineReadyForControl()
        guard activeSessionID == mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
        try controller.playWithExternallyManagedFirstVideoFrameDeadline()
    }

    public func seek(
        to seconds: Double,
        event: PlaybackSeekEvent = .progressBar
    ) {
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
        let behavior = Self.coreAfterSeekBehavior(for: intent)
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
                try await controller.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    after: behavior
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
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let intent = PlaybackSeekPolicy.intent(
            for: .skip,
            lifecycle: productLifecycle,
            targetBoundary: .beforeEnd
        )
        let behavior = Self.coreAfterSeekBehavior(for: intent)
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
                try await controller.seek(
                    by: CMTime(seconds: delta, preferredTimescale: 600),
                    after: behavior
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
            try controller.setRate(Float(speed.value))
            currentPlaybackSpeed = speed
        } catch {
            fail(error)
        }
    }

    func setVolume(_ volume: Float) {
        do {
            try controller.setVolume(volume)
            playbackVolume = volume
        } catch {
            fail(error)
        }
    }

    func setMuted(_ muted: Bool) {
        do {
            try controller.setMuted(muted)
            playbackMuted = muted
        } catch {
            fail(error)
        }
    }

    public func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws {
        guard let streamIndex = Int(track.id) else { return }
        try await controller.selectAudioTrack(streamIndex: streamIndex)
        currentAudioTrackID = track.id
    }

    public func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws {
        try await controller.selectSubtitleTrack(id: track?.id)
        currentSubtitleTrackID = controller.selectedSubtitleTrackID
        activeSubtitleCues = controller.activeSubtitleCues
    }

    private func addAutomaticExternalSubtitleSources(
        _ sources: [ResolvedExternalSubtitleSource],
        mediaSessionID: String,
        openGeneration: Int
    ) async {
        var encounteredFailure = false
        for source in sources {
            guard generation == openGeneration,
                  activeSessionID == mediaSessionID else {
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
                _ = try await controller.addExternalSubtitleSource(
                    PlaybackExternalSubtitleSource(
                        id: source.id,
                        url: source.url,
                        displayName: source.displayName
                    )
                )
                guard generation == openGeneration,
                      activeSessionID == mediaSessionID else {
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
              activeSessionID == mediaSessionID else { return }
        availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
        currentSubtitleTrackID = controller.selectedSubtitleTrackID
        activeSubtitleCues = controller.activeSubtitleCues
        activeSubtitleFrame = controller.activeSubtitleFrame
        if encounteredFailure {
            setUserVisibleIssue(.externalSubtitleFailed)
        }
    }

    /// Adds the already-owned sidecar sources to a prepared controller without
    /// transferring their access leases away from the active logical session.
    private func prepareExternalSubtitleSources(
        _ sources: [ResolvedExternalSubtitleSource],
        on replacementController: PlaybackCoreController
    ) async {
        for source in sources {
            guard source.accessLease?.ensureActive() != false else { continue }
            _ = try? await replacementController.addExternalSubtitleSource(
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
                try await controller.seek(to: .zero, after: .play)
                emitPlaybackObservation(
                    .seekCompleted(positionSeconds: 0),
                    generation: playbackObservationGeneration
                )
                try controller.play()
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

    public func setFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int? = nil,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool = false
    ) async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        let resolvedHorizontalFieldOfViewDegrees = projection == .customAngle
            ? PanoramaHorizontalCoverage.normalized(
                horizontalFieldOfViewDegrees
                    ?? PanoramaHorizontalCoverage.defaultCustomAngle
            )
            : nil
        publishFormat(
            projection: projection,
            horizontalFieldOfViewDegrees: resolvedHorizontalFieldOfViewDegrees,
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
        // The override becomes renderer input only when a fresh technical
        // session is assembled. Mutating the live renderer would allow
        // RealityKit to retain its previous projection classification.
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
        guard technicalSessionReplacementIsInFlight == false else {
            throw RuntimeError.rendererTransferPending
        }
        guard let request = currentLaunchRequest,
              let logicalSessionID = activeSessionID else {
            throw RuntimeError.noSession
        }
        technicalSessionReplacementIsInFlight = true

        // A conversion that keeps the format needs only a renderer the target
        // Entity has never bound, and the live session can hand one out. Opening
        // the source again would repeat its track enumeration, its demuxer and,
        // on a network source, every one of those as a fresh connection.
        if technicalSessionFormatReplacementIsPending == false, session != nil {
            presentationConversionReusesMediaSession = true
            technicalSessionReplacementStage = .installingRenderer
            return
        }
        presentationConversionReusesMediaSession = false
        technicalSessionReplacementStage = .openingReplacement

        generation += 1
        let replacementGeneration = generation
        let startTimeSeconds = max(0, playbackPosition.seconds)
        let speed = currentPlaybackSpeed
        let selectedAudioTrackID = currentAudioTrackID
        let selectedSubtitleTrackID = currentSubtitleTrackID
        let initialStereoLayout = usesSourceFormat
            ? nil
            : Self.coreStereoLayout(for: selectedStereoLayout)
        let initialProjectionOverride = usesSourceFormat
            ? nil
            : Self.coreProjectionOverride(
                for: selectedProjectionType,
                horizontalFieldOfViewDegrees: selectedHorizontalFieldOfViewDegrees
            )
        let initialDynamicRangeOverride = usesDolbyVisionFallback
            ? VideoDynamicRangeOverride.dolbyVisionFallback
            : nil

        let replacementController = PlaybackCoreController()
        openingTechnicalSessionReplacementController = replacementController
        defer {
            if openingTechnicalSessionReplacementController === replacementController {
                openingTechnicalSessionReplacementController = nil
            }
        }
        do {
            let replacement = try await replacementController.open(
                request.url,
                startTime: CMTime(
                    seconds: startTimeSeconds,
                    preferredTimescale: 60_000
                ),
                startsPaused: true,
                initialRate: Float(speed.value),
                sourceTransport: request.source.playbackCoreTransport,
                initialStereoLayout: initialStereoLayout,
                initialProjectionOverride: initialProjectionOverride,
                initialDynamicRangeOverride: initialDynamicRangeOverride,
                provenance: "presentationConversionPrepared",
                accessRequirement: request.url.isFileURL
                    ? "securityScopedFile"
                    : "networkSource"
            )
            #if DEBUG
                installPlaybackSwitchSampleHandler(
                    on: replacement,
                    byteStreamHandle: request.source.byteStreamHandle
                )
            #endif
            guard generation == replacementGeneration,
                  activeSessionID == logicalSessionID else {
                await replacementController.closeAndWait(clearSource: false)
                throw RuntimeError.mediaSessionChanged
            }

            technicalSessionReplacementStage = .restoringExternalSubtitles
            await prepareExternalSubtitleSources(
                request.externalSubtitleSources,
                on: replacementController
            )

            if let selectedAudioTrackID,
               let streamIndex = Int(selectedAudioTrackID),
               replacementController.availableAudioTracks.contains(where: {
                   $0.streamIndex == streamIndex
               }) {
                technicalSessionReplacementStage = .restoringAudioTrack
                try await replacementController.selectAudioTrack(streamIndex: streamIndex)
            }
            if let selectedSubtitleTrackID,
               replacementController.availableSubtitleTracks.contains(where: {
                   $0.id == selectedSubtitleTrackID
               }) {
                technicalSessionReplacementStage = .restoringSubtitleTrack
                try await replacementController.selectSubtitleTrack(id: selectedSubtitleTrackID)
            }
            try replacementController.setVolume(playbackVolume)
            try replacementController.setMuted(playbackMuted)
            preparedTechnicalSessionReplacement = PreparedTechnicalSessionReplacement(
                controller: replacementController,
                session: replacement,
                generation: replacementGeneration,
                logicalSessionID: logicalSessionID,
                speed: speed,
                selectedAudioTrackID: selectedAudioTrackID,
                selectedSubtitleTrackID: selectedSubtitleTrackID
            )
            technicalSessionReplacementStage = .installingRenderer
            logger.info(
                "replacement technical session prepared logical=\(logicalSessionID, privacy: .public) technical=\(replacement.traceID, privacy: .public)"
            )
        } catch {
            await replacementController.closeAndWait(clearSource: false)
            technicalSessionReplacementIsInFlight = false
            technicalSessionReplacementStage = .failed
            throw error
        }
    }

    public func activatePreparedTechnicalSessionReplacement() async throws {
        if presentationConversionReusesMediaSession {
            try await activateReplacementRendererGraph()
            return
        }
        guard let prepared = preparedTechnicalSessionReplacement else {
            throw RuntimeError.noSession
        }
        guard generation == prepared.generation,
              activeSessionID == prepared.logicalSessionID,
              let sourceSession = session,
              preparedTechnicalSessionReplacement?.session === prepared.session else {
            throw RuntimeError.mediaSessionChanged
        }

        let sourceController = controller
        let initiallyEndedContinuity = sourceController.endedContinuity
        let naturalEndNotificationWasPublished =
            productLifecycle == .ended && didEndNaturally
        try await prepared.controller.suspendVideoSampleDelivery()
        if productLifecycle == .playing {
            try sourceController.pause()
        }
        let cutoverTime = sourceSession.currentTime()
        let sourcePresentation = attachedPresentation
        let endedContinuity = sourceController.endedContinuity
            ?? initiallyEndedContinuity

        guard generation == prepared.generation,
              activeSessionID == prepared.logicalSessionID,
              session === sourceSession,
              preparedTechnicalSessionReplacement?.session === prepared.session else {
            throw RuntimeError.mediaSessionChanged
        }

        detach()
        releaseRendererConsumerForVideoComponentReplacement()
        unbindControllerCallbacks(from: sourceController)
        departingTechnicalSessionController = sourceController

        controller = prepared.controller
        bindControllerCallbacks(to: controller)
        session = prepared.session
        activeTechnicalSessionID = prepared.session.traceID
        renderer = prepared.session.renderer
        rendererEpoch &+= 1
        presentationState = .placeholder
        startsWhenAttached = true
        firstAttachedPresentationForActiveTechnicalSession = nil
        videoComponentRevision &+= 1
        effectiveVideoFormatRevision = nil
        technicalSessionMediaFormatInterpretation = effectiveMediaFormatInterpretation
        technicalSessionFormatReplacementIsPending = false
        currentPlaybackSpeed = prepared.speed
        availableAudioTracks = controller.availableAudioTracks.map {
            Self.audioTrack(
                $0,
                isDefault: String($0.streamIndex) == prepared.selectedAudioTrackID
            )
        }
        currentAudioTrackID = prepared.session.selectedAudioStreamIndex.map(String.init)
        availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
        currentSubtitleTrackID = controller.selectedSubtitleTrackID
        activeSubtitleCues = controller.activeSubtitleCues
        activeSubtitleFrame = controller.activeSubtitleFrame
        preparedTechnicalSessionReplacement = nil
        activatedTechnicalSessionCutover = ActivatedTechnicalSessionCutover(
            generation: prepared.generation,
            logicalSessionID: prepared.logicalSessionID,
            activeReplacementSessionID: prepared.session.traceID,
            sourcePresentation: sourcePresentation,
            delivery: .pending(
                endedContinuity.map(TechnicalSessionRebuildContinuity.ended)
                    ?? .timeline(cutoverTime)
            ),
            naturalEndNotificationWasPublished: naturalEndNotificationWasPublished
        )
        if let endedContinuity {
            adoptEndedContinuity(endedContinuity)
        }
        receive(controller.status)
        receive(controller.diagnostics)
        logger.info(
            "prepared technical session activated logical=\(prepared.logicalSessionID, privacy: .public) technical=\(prepared.session.traceID, privacy: .public)"
        )
    }

    private func activateReplacementRendererGraph() async throws {
        guard let sourceSession = session,
              let logicalSessionID = activeSessionID else {
            throw RuntimeError.noSession
        }
        let conversionGeneration = generation
        let initiallyEndedContinuity = controller.endedContinuity
        let naturalEndNotificationWasPublished =
            productLifecycle == .ended && didEndNaturally
        if productLifecycle == .playing {
            try controller.pause()
        }
        let cutoverTime = sourceSession.currentTime()
        let sourcePresentation = attachedPresentation
        let endedContinuity = controller.endedContinuity ?? initiallyEndedContinuity

        let replacement: AVSampleBufferVideoRenderer
        do {
            replacement = try await controller.replaceVideoRendererGraph()
        } catch {
            presentationConversionReusesMediaSession = false
            technicalSessionReplacementIsInFlight = false
            technicalSessionReplacementStage = .failed
            throw error
        }
        guard generation == conversionGeneration,
              activeSessionID == logicalSessionID,
              session === sourceSession else {
            throw RuntimeError.mediaSessionChanged
        }

        detach()
        releaseRendererConsumerForVideoComponentReplacement()
        renderer = replacement
        rendererEpoch &+= 1
        presentationState = .placeholder
        startsWhenAttached = true
        firstAttachedPresentationForActiveTechnicalSession = nil
        videoComponentRevision &+= 1
        effectiveVideoFormatRevision = nil
        activatedTechnicalSessionCutover = ActivatedTechnicalSessionCutover(
            generation: conversionGeneration,
            logicalSessionID: logicalSessionID,
            activeReplacementSessionID: sourceSession.traceID,
            sourcePresentation: sourcePresentation,
            delivery: .pending(
                endedContinuity.map(TechnicalSessionRebuildContinuity.ended)
                    ?? .timeline(cutoverTime)
            ),
            naturalEndNotificationWasPublished: naturalEndNotificationWasPublished
        )
        if let endedContinuity {
            adoptEndedContinuity(endedContinuity)
        }
        logger.info(
            "replacement renderer graph activated logical=\(logicalSessionID, privacy: .public) technical=\(sourceSession.traceID, privacy: .public)"
        )
    }

    public func rebaseActivatedTechnicalSessionReplacement(
        to presentation: PlaybackPresentation
    ) async throws {
        guard let cutover = activatedTechnicalSessionCutover else {
            throw RuntimeError.noSession
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        while replacementRendererTargetIsCurrent(for: presentation) == false {
            guard activatedTechnicalSessionCutoverIsCurrent(cutover) else {
                throw RuntimeError.mediaSessionChanged
            }
            guard clock.now - startedAt < Self.presentationSettlementDeadline else {
                throw RuntimeError.presentationDidNotSettle(presentation)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        observeEndedContinuityIfAvailable()
        if Self.shouldRetireDepartingTechnicalSessionBeforeDelivery(
            from: cutover.sourcePresentation,
            to: presentation
        ) {
            await retireDepartingTechnicalSessionBeforeReplacementDelivery()
        }
        try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded()
        guard activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        technicalSessionReplacementStage = .completed
    }

    public func retireDepartingTechnicalSessionAfterSceneDisappearance() async {
        if presentationConversionReusesMediaSession {
            presentationConversionReusesMediaSession = false
            await controller.retireDepartingVideoRendererGraph()
            completeTechnicalSessionReplacementAfterSettlement()
            logger.info("departing renderer graph retired after source Scene disappeared")
            return
        }
        guard let departingTechnicalSessionController else { return }
        self.departingTechnicalSessionController = nil
        await departingTechnicalSessionController.closeAndWait(clearSource: false)
        completeTechnicalSessionReplacementAfterSettlement()
        logger.info("departing technical session retired after source Scene disappeared")
    }

    static func shouldRetireDepartingTechnicalSessionBeforeDelivery(
        from sourcePresentation: PlaybackPresentation?,
        to targetPresentation: PlaybackPresentation
    ) -> Bool {
        sourcePresentation == .portal && targetPresentation == .panorama
    }

    private func retireDepartingTechnicalSessionBeforeReplacementDelivery() async {
        guard let departingTechnicalSessionController else { return }
        self.departingTechnicalSessionController = nil
        await departingTechnicalSessionController.closeAndWait(clearSource: false)
        logger.info("departing technical session retired before replacement delivery")
    }

    public func cancelPreparedTechnicalSessionReplacement() async {
        if presentationConversionReusesMediaSession {
            presentationConversionReusesMediaSession = false
            technicalSessionReplacementIsInFlight = false
            technicalSessionReplacementStage = .failed
            await controller.retireDepartingVideoRendererGraph()
            return
        }
        guard let preparedTechnicalSessionReplacement else { return }
        self.preparedTechnicalSessionReplacement = nil
        technicalSessionReplacementIsInFlight = false
        technicalSessionReplacementStage = .failed
        await preparedTechnicalSessionReplacement.controller.closeAndWait(clearSource: false)
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
        projection: PlaybackModel.ProjectionType,
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

    /// Source discovery records the file's facts without taking precedence
    /// over a persisted user override supplied to this technical session.
    func publishEffectiveFormatAfterSourceDiscovery(
        _ initialFormat: MediaFormat?
    ) {
        guard let initialFormat else {
            publishSourceFormat()
            return
        }
        publishFormat(
            projection: Self.playbackProjection(from: initialFormat.projection),
            horizontalFieldOfViewDegrees: initialFormat.horizontalFieldOfViewDegrees,
            stereo: Self.playbackStereoLayout(from: initialFormat.stereoLayout),
            usesDolbyVisionFallback: initialFormat.usesDolbyVisionFallback
        )
    }

    private func publishSourceFormat() {
        selectedProjectionType = Self.projectionType(for: sourceVideoContentKind)
        selectedHorizontalFieldOfViewDegrees = nil
        selectedStereoLayout = sourceStereoLayout
        usesDolbyVisionFallback = false
        usesSourceFormat = true
        mediaFormatIsKnown = sourceMediaFormatIsCaptured
    }

    func publishSourceMediaFormat(from snapshot: PlaybackDebugSnapshotV1) {
        let sourceFormat = Self.sourceMediaFormat(from: snapshot)
        sourceVideoContentKind = sourceFormat.contentKind
        sourceStereoLayout = sourceFormat.stereoLayout
        sourceMediaFormatIsCaptured = snapshot.providerOpen != nil
            || snapshot.lastVideoSample != nil
        if usesSourceFormat {
            publishSourceFormat()
        }
    }

    public func videoRendererTargetDidBind(
        revision: UInt64,
        entityID: String
    ) {
        guard revision == videoComponentRevision,
              rendererConsumerEntityID == entityID else { return }
        let previousEntityID = lastBoundVideoRendererEntityID
        lastBoundVideoRendererEntityID = entityID
        boundVideoComponentRevision = revision
        if let previousEntityID, previousEntityID != entityID {
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
        session?.displayedArtworkImage()
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
        detach()
        let sourceAccess = releasingSourceAccess
            ? currentLaunchRequest?.sourceAccess
            : nil
        let externalSubtitleAccesses = Array(externalSubtitleAccessBySourceID.values)
        externalSubtitleAccessBySourceID = [:]
        externalSubtitleSourceIDByURL = [:]
        let controller = controller
        let departingController = departingTechnicalSessionController
        departingTechnicalSessionController = nil
        let preparedController = preparedTechnicalSessionReplacement?.controller
        preparedTechnicalSessionReplacement = nil
        controller.hush()
        departingController?.hush()
        preparedController?.hush()
        activatedTechnicalSessionCutover = nil
        technicalSessionReplacementIsInFlight = false
        presentationConversionReusesMediaSession = false
        let previousClosingTask = closingTask
        let audioSessionLifecycle = audioSessionLifecycle
        let closeTask = Task { @MainActor in
            await previousClosingTask?.value
            await controller.closeAndWait()
            await departingController?.closeAndWait(clearSource: false)
            await preparedController?.closeAndWait(clearSource: false)
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

    public func clearPresentationForTeardown() {
        presentationState = .hidden
    }

    public func clearPresentation() {
        clearPresentationForTeardown()
        session = nil
        renderer = nil
        rendererEpoch &+= 1
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
        activatedTechnicalSessionCutover = nil
        lastBoundVideoRendererEntityID = nil
        releasedRendererConsumer = nil
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

    /// Waits for RealityKit to adopt the replacement session instead of
    /// converting device speed into a presentation failure. A presentation
    /// transfer ends only when its requested surface settles, the media
    /// pipeline reports a real failure, or the operation is cancelled.
    /// A surface that has not settled within this window is not merely slow to
    /// start; it is stuck. The caller holds a platform execution lease for the
    /// whole wait, and an unbounded wait leaves that lease claimed forever, so
    /// every later spatial request is refused until the app is relaunched.
    /// High-resolution panoramic startup is the reason the bound is generous.
    public static let presentationSettlementDeadline = Duration.seconds(30)

    public func waitUntilPresentationSettled(
        to presentation: PlaybackPresentation,
        allowsPendingSessionStart: Bool = false,
        deadline: Duration = PlaybackRuntime.presentationSettlementDeadline,
        clock: ContinuousClock = ContinuousClock()
    ) async -> Bool {
        if activatedTechnicalSessionCutover != nil {
            do {
                try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded()
            } catch {
                fail(error)
                return false
            }
        }
        if presentationIsSettled(presentation) {
            completeTechnicalSessionReplacementAfterSettlement()
            return true
        }
        let startedAt = clock.now
        while true {
            guard Task.isCancelled == false else { return false }
            guard productLifecycle != .failed else { return false }
            if productLifecycle == .ended {
                guard let cutover = activatedTechnicalSessionCutover,
                      activatedTechnicalSessionCutoverIsCurrent(cutover) else {
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
            if activatedTechnicalSessionCutover != nil {
                do {
                    try await reconcileAndDeliverTechnicalSessionReplacementIfNeeded()
                } catch {
                    fail(error)
                    return false
                }
            }
            if presentationIsSettled(presentation) {
                completeTechnicalSessionReplacementAfterSettlement()
                return true
            }
        }
    }

    private func presentationIsSettled(_ presentation: PlaybackPresentation) -> Bool {
        guard attachedPresentation == presentation,
              let snapshot = session?.debugSnapshot(),
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
        guard let session else { return false }
        let snapshot = session.debugSnapshot()
        let record = PresentationStateRecord(
            // Presentation observations describe the Entity owned by this
            // technical playback instance. The logical media identity remains
            // stable across handoff, but PlaybackCore must reject observations
            // from a retired renderer graph.
            mediaSessionID: session.traceID,
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
            }
            clearFailureIfPlaybackIsUsable()
        }
        if snapshot.presentationState != record {
            session.recordPresentationState(record)
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

    private func activatedTechnicalSessionCutoverIsCurrent(
        _ cutover: ActivatedTechnicalSessionCutover
    ) -> Bool {
        generation == cutover.generation
            && activeSessionID == cutover.logicalSessionID
            && activeTechnicalSessionID == cutover.activeReplacementSessionID
            && session?.traceID == cutover.activeReplacementSessionID
            && activatedTechnicalSessionCutover?.generation == cutover.generation
            && activatedTechnicalSessionCutover?.logicalSessionID == cutover.logicalSessionID
            && activatedTechnicalSessionCutover?.activeReplacementSessionID
                == cutover.activeReplacementSessionID
    }

    private func observeEndedContinuityIfAvailable() {
        guard var cutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            return
        }
        let departingContinuity = departingTechnicalSessionController?.endedContinuity
        guard let continuity = departingContinuity ?? controller.endedContinuity else {
            return
        }
        switch cutover.delivery.continuity {
        case .timeline:
            break
        case .ended(let currentContinuity):
            guard let departingContinuity,
                  currentContinuity != departingContinuity else {
                return
            }
        }
        cutover.delivery = .pending(.ended(continuity))
        activatedTechnicalSessionCutover = cutover
        adoptEndedContinuity(continuity)
    }

    private func adoptEndedContinuity(_ continuity: PlaybackEndedContinuity) {
        guard var cutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            return
        }
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
        if continuity.reason == .naturalCompletion,
           cutover.naturalEndNotificationWasPublished == false {
            cutover.naturalEndNotificationWasPublished = true
            activatedTechnicalSessionCutover = cutover
            onPlaybackEnded?()
        }
    }

    private func receiveReplacementStatus(_ status: PlaybackStatus) -> Bool {
        guard let cutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            return false
        }
        if case .failed = status { return false }
        observeEndedContinuityIfAvailable()
        guard let currentCutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(currentCutover),
              case .ended = currentCutover.delivery.continuity else {
            return false
        }
        return true
    }

    private func reconcileAndDeliverTechnicalSessionReplacementIfNeeded()
        async throws {
        observeEndedContinuityIfAvailable()
        guard let cutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        guard case .pending(let continuity) = cutover.delivery else { return }
        rendererPixelVideoComponentRevision = nil
        rendererPixelStreamEpoch = nil
        switch continuity {
        case .timeline(let time):
            try await controller.restartVideoSampleDelivery(
                at: time,
                after: .pause
            )
        case .ended(let endedContinuity):
            try await controller.restartVideoSampleDelivery(
                preserving: endedContinuity
            )
        }
        guard var currentCutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(currentCutover) else {
            throw RuntimeError.mediaSessionChanged
        }
        if currentCutover.delivery == .pending(continuity) {
            currentCutover.delivery = .applied(continuity)
            activatedTechnicalSessionCutover = currentCutover
        }
        observeEndedContinuityIfAvailable()
    }

    private func completeTechnicalSessionReplacementAfterSettlement() {
        guard let cutover = activatedTechnicalSessionCutover,
              activatedTechnicalSessionCutoverIsCurrent(cutover) else {
            return
        }
        activatedTechnicalSessionCutover = nil
        technicalSessionReplacementIsInFlight = false
        technicalSessionReplacementStage = .completed
    }

    private func replacementRendererTargetIsCurrent(
        for presentation: PlaybackPresentation
    ) -> Bool {
        guard boundVideoComponentRevision == videoComponentRevision,
              attachedPresentation == presentation,
              attachment?.presentation == presentation,
              rendererConsumerPresentation == presentation,
              let entityID = attachment?.entityID,
              rendererConsumerEntityID == entityID,
              lastBoundVideoRendererEntityID == entityID else {
            return false
        }
        return true
    }

    /// Releases Runtime's record of RealityKit's old VideoPlayerComponent
    /// consumer before the presentation layer installs the replacement graph.
    private func releaseRendererConsumerForVideoComponentReplacement() {
        if let rendererConsumerEntityID {
            session?.recordRealityKitBinding(
                entityIdentity: rendererConsumerEntityID,
                active: false
            )
        }
        rendererConsumerPresentation = nil
        rendererConsumerEntityID = nil
        rendererConsumerEpoch = nil
        releasedRendererConsumer = nil
        lastBoundVideoRendererEntityID = nil
        clearVideoComponentBindingObservation()
    }

    public func outputObservation() -> PlaybackOutputObservation {
        let snapshot = session?.debugSnapshot()
        let sourceReadSession = openingTechnicalSessionReplacementController?.activeSession
            ?? preparedTechnicalSessionReplacement?.session
            ?? controller.activeSession
            ?? session
        let sourceReadObservation = sourceReadSession === session
            ? snapshot?.sourceReadObservation
            : sourceReadSession?.debugSnapshot().sourceReadObservation
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
            sourceReadBytesPerSecond: sourceReadObservation?.bytesPerSecond ?? 0
        )
    }

    public func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        session?.debugSnapshot()
    }

    #if DEBUG
    public func debugEvidenceJSON() -> String {
        controller.debugEvidenceJSON() ?? ""
    }
    #endif

    func activeSessionForVerification() -> SampleBufferPlaybackSession? {
        session
    }

    func waitForPendingClose() async {
        await closingTask?.value
        closingTask = nil
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
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let playbackObservationGeneration = observationGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let landing = try await controller.stepFrame(
                    direction > 0 ? .forward : .backward
                )
                emitPlaybackObservation(
                    .seekCompleted(positionSeconds: landing.seconds),
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

    private func receive(_ status: PlaybackStatus) {
        if receiveReplacementStatus(status) { return }
        lifecycle = status
        emitPlaybackObservation(.lifecycle(productLifecycle))
        switch status {
        case .idle, .loading:
            break
        case .ready, .playing, .paused:
            didEndNaturally = false
            clearFailureIfPlaybackIsUsable()
        case .ended(let reason):
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
                await controller.clearDisplayedVideoImage(forMediaSessionID: endedSessionID)
            }
            if reason == .naturalCompletion {
                onPlaybackEnded?()
            }
        case .failed(let message):
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
            } else {
                setUserVisibleIssue(.playbackFailed)
            }
            logger.error("playback failed message=\(message, privacy: .public)")
        }
    }

    /// Every fact here is published by PlaybackCore. Reading the debug snapshot
    /// instead would cost a struct copy and several timebase queries on a value
    /// the playback deck recomputes on every redraw, and it would give two
    /// sources for one fact that can disagree.
    static func capabilityFacts(from diagnostics: PlaybackDiagnostics) -> PlaybackCapabilityFacts {
        PlaybackCapabilityFacts(
            codecName: diagnostics.codecName,
            // A title is only reported as flattened once a renderer input has said
            // what it carried. Before that the answer is unknown, not "one view".
            sourceIsMultiview: diagnostics.isMVHEVC
                && diagnostics.rendererInputIsMultiview != nil,
            deliveredIsMultiview: diagnostics.rendererInputIsMultiview == true,
            audioRetired: diagnostics.audioRetired,
            audioRetirementReason: diagnostics.audioRetirementReason,
            rendererFailedToDecode: diagnostics.rendererFailedToDecode
        )
    }

    private static func coreAfterSeekBehavior(
        for intent: PlaybackAfterSeekIntent
    ) -> PlaybackAfterSeekBehavior {
        switch intent {
        case .preserveCurrentPlaybackIntent:
            .preserveCurrentPauseState
        case .pause, .ended:
            .pause
        }
    }

    private func recordAudioSessionFact() {
        guard let session,
              var record = session.debugSnapshot().presentationState else { return }
        record.audioSessionActive = audioSessionLifecycle.isActive
        session.recordPresentationState(record)
    }

    private func clearFailureIfPlaybackIsUsable() {
        guard userVisibleIssue?.category == .playbackFailed else { return }
        switch lifecycle {
        case .ready, .playing, .paused:
            setUserVisibleIssue(nil)
        case .idle, .loading, .ended, .failed:
            break
        }
    }

    private func receive(_ diagnostics: PlaybackDiagnostics) {
        recordActualPlayback(until: diagnostics.currentSeconds)
        self.diagnostics = diagnostics
        if let cutover = activatedTechnicalSessionCutover,
           activatedTechnicalSessionCutoverIsCurrent(cutover),
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

    private static func coreStereoLayout(
        for stereo: PlaybackModel.StereoLayout
    ) -> VideoStereoLayout? {
        switch stereo {
        case .mono: .mono
        case .multiview: nil
        case .sideBySide: .sideBySide
        case .topBottom: .overUnder
        }
    }

    private static func coreProjectionOverride(
        for projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int? = nil
    ) -> VideoProjectionOverride {
        switch projection {
        case .flat: .rectilinear
        case .equirectangular180: .halfEquirectangular
        case .equirectangular360: .equirectangular
        case .customAngle:
            .customEquirectangular(
                horizontalFieldOfViewDegrees: PanoramaHorizontalCoverage.normalized(
                    horizontalFieldOfViewDegrees
                        ?? PanoramaHorizontalCoverage.defaultCustomAngle
                )
            )
        }
    }

    private static func projectionType(
        for contentKind: PlaybackModel.SourceVideoContentKind
    ) -> PlaybackModel.ProjectionType {
        switch contentKind {
        case .halfEquirectangular: .equirectangular180
        case .equirectangular: .equirectangular360
        case .rectilinear, .spatialVideo, .parametricImmersive, .appleImmersiveVideo:
            .flat
        }
    }

    static func effectiveHorizontalFieldOfViewDegrees(
        for projection: PlaybackModel.ProjectionType,
        explicitDegrees: Int?
    ) -> Int {
        switch projection {
        case .flat:
            PanoramaHorizontalCoverage.defaultCustomAngle
        case .equirectangular180:
            180
        case .equirectangular360:
            360
        case .customAngle:
            PanoramaHorizontalCoverage.normalized(
                explicitDegrees ?? PanoramaHorizontalCoverage.defaultCustomAngle
            )
        }
    }

    private static func sourceHorizontalFieldOfViewDegrees(
        for projection: PlaybackModel.ProjectionType
    ) -> Int? {
        switch projection {
        case .flat:
            nil
        case .equirectangular180:
            180
        case .equirectangular360:
            360
        case .customAngle:
            PanoramaHorizontalCoverage.defaultCustomAngle
        }
    }

    private static func mediaProjection(
        from projection: PlaybackModel.ProjectionType
    ) -> MediaProjection {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func mediaStereoLayout(
        from stereoLayout: PlaybackModel.StereoLayout
    ) -> MediaStereoLayout {
        switch stereoLayout {
        case .mono, .multiview: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    private static func playbackProjection(
        from projection: MediaProjection
    ) -> PlaybackModel.ProjectionType {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func playbackStereoLayout(
        from stereoLayout: MediaStereoLayout
    ) -> PlaybackModel.StereoLayout {
        switch stereoLayout {
        case .mono: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    private static func sourceMediaFormat(
        from snapshot: PlaybackDebugSnapshotV1
    ) -> (
        contentKind: PlaybackModel.SourceVideoContentKind,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        let providerOpen = snapshot.providerOpen
        let sampleSignaling = snapshot.lastVideoSample?.formatSignaling
        let contentKind = recognizedSourceVideoContentKind(
            from: providerOpen?.formatSignaling.projectionKind.value
        ) ?? recognizedSourceVideoContentKind(
            from: sampleSignaling?.projectionKind.value
        ) ?? (providerOpen?.isMVHEVC == true ? .spatialVideo : .rectilinear)

        let stereoLayout: PlaybackModel.StereoLayout
        if providerOpen?.isMVHEVC == true {
            stereoLayout = .multiview
        } else {
            stereoLayout = Self.stereoLayout(
                from: providerOpen?.formatSignaling.viewPackingKind.value ?? ""
            ) ?? Self.stereoLayout(
                from: sampleSignaling?.viewPackingKind.value ?? ""
            ) ?? .mono
        }
        return (contentKind, stereoLayout)
    }

    static func sourceVideoContentKind(
        from projectionKind: String,
        isMVHEVC: Bool
    ) -> PlaybackModel.SourceVideoContentKind {
        recognizedSourceVideoContentKind(from: projectionKind)
            ?? (isMVHEVC ? .spatialVideo : .rectilinear)
    }

    private static func recognizedSourceVideoContentKind(
        from projectionKind: String?
    ) -> PlaybackModel.SourceVideoContentKind? {
        let normalizedProjection = (projectionKind ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if normalizedProjection.contains("appleimmersivevideo") {
            return .appleImmersiveVideo
        }
        if normalizedProjection.contains("parametricimmersive")
                    || normalizedProjection.contains("fisheye") {
            return .parametricImmersive
        }
        if normalizedProjection.contains("halfequirectangular") {
            return .halfEquirectangular
        }
        if normalizedProjection.contains("equirectangular") {
            return .equirectangular
        }
        if normalizedProjection.contains("rectilinear") {
            return .rectilinear
        }
        return nil
    }

    private static func stereoLayoutDisplayName(
        _ stereoLayout: PlaybackModel.StereoLayout
    ) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .multiview: "Native Stereo"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }

    private func profile(from diagnostics: PlaybackDiagnostics) -> PlaybackModel.MediaProfile? {
        let resolution: PlaybackModel.MediaProfile.Resolution?
        let pixelAspectRatio: PlaybackModel.MediaProfile.PixelAspectRatio
        if let geometry = diagnostics.videoGeometry {
            resolution = .init(
                width: geometry.encodedDimensions.width,
                height: geometry.encodedDimensions.height
            )
            pixelAspectRatio = .init(
                horizontalSpacing: geometry.sampleAspectRatio.horizontalSpacing,
                verticalSpacing: geometry.sampleAspectRatio.verticalSpacing
            )
        } else {
            resolution = Self.parseResolution(diagnostics.dimensions)
            pixelAspectRatio = .square
        }
        guard let resolution else {
            return prefetchedMetadata?.mediaProfile
        }
        let transfer = diagnostics.transferFunction.lowercased()
        // The base layer's own signalling, which is the picture the wearer receives
        // whenever the Dolby Vision is stored across two layers.
        let baseLayer: PlaybackModel.HDRType
        if transfer.contains("2084") || transfer.contains("pq") {
            baseLayer = .hdr10
        } else if transfer.contains("hlg") || transfer.contains("arib") {
            baseLayer = .hlg
        } else {
            baseLayer = .sdr
        }
        let claimsDolbyVision = diagnostics.dolbyVisionProfile > 0
            || diagnostics.formatHasDvcC
            || diagnostics.formatHasDvvC
        let dolbyVision: PlaybackModel.DolbyVision? = claimsDolbyVision
            ? PlaybackModel.DolbyVision(
                profile: diagnostics.dolbyVisionProfile,
                crossCompatibilityID: diagnostics.dolbyVisionCrossCompatibilityID,
                fallbackTo: diagnostics.dolbyVisionHasEnhancementLayer ? baseLayer : nil
            )
            : nil
        let hdr: PlaybackModel.HDRType = claimsDolbyVision
            && diagnostics.dolbyVisionHasEnhancementLayer == false
            ? .dolbyVision
            : baseLayer
        return PlaybackModel.MediaProfile(
            projectionType: Self.projectionType(from: diagnostics.projectionKind)
                ?? prefetchedMetadata?.mediaProfile?.projectionType
                ?? .flat,
            stereoLayout: Self.stereoLayout(
                from: diagnostics.viewPackingKind,
                isMVHEVC: diagnostics.isMVHEVC
            )
                ?? prefetchedMetadata?.mediaProfile?.stereoLayout
                ?? .mono,
            hdrType: hdr,
            dolbyVision: dolbyVision,
            resolution: resolution,
            pixelAspectRatio: pixelAspectRatio,
            frameRate: diagnostics.nominalFrameRate,
            videoCodec: diagnostics.codecName,
            durationSeconds: diagnostics.durationSeconds
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
        let values = dimensions
            .split(whereSeparator: { $0 == "x" || $0 == "×" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 2 else { return nil }
        return .init(width: values[0], height: values[1])
    }

    static func projectionType(from value: String) -> PlaybackModel.ProjectionType? {
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if normalized.contains("halfequirectangular") { return .equirectangular180 }
        if normalized.contains("equirectangular") { return .equirectangular360 }
        if normalized.contains("fisheye")
            || normalized.contains("parametricimmersive")
            || normalized.contains("appleimmersivevideo") {
            return .flat
        }
        if normalized.contains("rectilinear") { return .flat }
        return nil
    }

    static func projectionType(from value: VideoProjectionOverride?) -> PlaybackModel.ProjectionType? {
        switch value {
        case .rectilinear: .flat
        case .equirectangular: .equirectangular360
        case .halfEquirectangular: .equirectangular180
        case .customEquirectangular: .customAngle
        case nil: nil
        }
    }

    static func stereoLayout(from value: String) -> PlaybackModel.StereoLayout? {
        stereoLayout(from: value, isMVHEVC: false)
    }

    static func stereoLayout(
        from value: String,
        isMVHEVC: Bool
    ) -> PlaybackModel.StereoLayout? {
        if isMVHEVC { return .multiview }
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if normalized.contains("sidebyside") || normalized.contains("leftright") {
            return .sideBySide
        }
        if normalized.contains("overunder") || normalized.contains("topbottom") {
            return .topBottom
        }
        return nil
    }

    static func hasAIME(from projectionKind: String) -> Bool {
        let normalized = projectionKind.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized == "parametricimmersive"
            || normalized == "appleimmersivevideo"
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
