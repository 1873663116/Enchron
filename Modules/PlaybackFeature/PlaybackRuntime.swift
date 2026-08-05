import AVFoundation
import CoreMedia
import Foundation
import MediaSource
import Observation
import OSLog
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation

@MainActor
@Observable
public final class PlaybackRuntime: PlaybackRuntimeControlling {
    public enum PresentationState: Sendable, Equatable {
        case hidden
        case placeholder
        case videoVisible
    }

    public enum SessionLifecycleEvent: Equatable, Sendable {
        case activated(id: String)
        case replaced(previousID: String, currentID: String)
        case ended(id: String)
    }

    public enum RuntimeError: LocalizedError {
        case noSession
        case sourceAccessUnavailable
        case unsupportedProjection(PlaybackModel.ProjectionType)
        case rendererConsumerBusy(PlaybackPresentation)
        case rendererTransferPending
        case mediaSessionChanged
        case spatialPlaybackTransportUnavailable(ProductPlaybackLifecycle)
        case videoComponentReplacementTimedOut
        case videoSampleDeliveryRestartFailed
        case rendererGraphPlaybackDidNotAdvance(RendererGraphPlaybackContinuity)
        case formatRollbackFailed

        public var errorDescription: String? {
            switch self {
            case .noSession:
                "No PlaybackCore media session is active."
            case .sourceAccessUnavailable:
                "The original media source is no longer available. Choose it again to restore access."
            case .unsupportedProjection(let projection):
                "PlaybackCore cannot currently represent the \(projection.rawValue) projection."
            case .rendererConsumerBusy(let presentation):
                "The \(presentation.rawValue) RealityView still owns the active video renderer."
            case .rendererTransferPending:
                "The video renderer is being prepared for another RealityView."
            case .mediaSessionChanged:
                "The media session changed before the operation completed."
            case .spatialPlaybackTransportUnavailable(let lifecycle):
                "Playback cannot be paused or resumed while it is \(String(describing: lifecycle))."
            case .videoComponentReplacementTimedOut:
                "The video surface did not accept the updated media format in time."
            case .videoSampleDeliveryRestartFailed:
                "Video delivery could not restart after the media format changed."
            case .rendererGraphPlaybackDidNotAdvance(let condition):
                "The replacement video renderer did not prove continuous playback: \(condition.rawValue)."
            case .formatRollbackFailed:
                "The media format could not be restored after a failed update. Reopen the media before changing its format again."
            }
        }
    }

    public private(set) var lifecycle: PlaybackStatus = .idle
    public private(set) var playbackPosition = PlaybackModel.PlaybackPosition(seconds: 0, duration: 0)
    public private(set) var currentPlaybackSpeed = PlaybackModel.PlaybackSpeed.default
    public private(set) var currentLaunchRequest: PlaybackLaunchRequest?
    public var currentPlaybackURL: URL? { currentLaunchRequest?.url }
    public private(set) var prefetchedMetadata: PlaybackMediaMetadata?
    public private(set) var presentationState: PresentationState = .hidden
    public private(set) var diagnostics = PlaybackDiagnostics()
    public private(set) var availableAudioTracks: [PlaybackModel.AudioTrack] = []
    public private(set) var currentAudioTrackID: String?
    public private(set) var availableSubtitleTracks: [PlaybackModel.SubtitleTrack] = []
    public private(set) var currentSubtitleTrackID: String?
    public private(set) var activeSubtitleCues: [PlaybackSubtitleCue] = []
    public private(set) var activeSubtitleFrame: PlaybackSubtitleFrame?
    public var subtitleErrorMessage: String?
    public private(set) var activeSessionID: String?
    public private(set) var actualPlaybackSeconds: Double = 0
    public private(set) var didEndNaturally = false
    public private(set) var mediaFormatIsKnown = false
    public private(set) var renderer: AVSampleBufferVideoRenderer?
    public private(set) var attachedPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerEntityID: String?
    public private(set) var videoComponentRevision: UInt64 = 0
    public private(set) var boundVideoComponentRevision: UInt64?
    public private(set) var rendererPixelVideoComponentRevision: UInt64?
    public private(set) var rendererPixelStreamEpoch: UInt64?
    public private(set) var sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds: TimeInterval?
    public var lastErrorMessage: String?

    public var onPlaybackEnded: (() -> Void)?
    public var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    @ObservationIgnored
    private var sessionLifecycleHandler: ((SessionLifecycleEvent) -> Void)?
    @ObservationIgnored
    private var externalSubtitleSourceIDByURL: [URL: String] = [:]
    @ObservationIgnored
    private var externalSubtitleAccessBySourceID: [String: MediaAccessLease] = [:]

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
              renderer != nil,
              attachedPresentation != nil,
              presentationState == .videoVisible,
              lastErrorMessage == nil else { return false }
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
    public var effectiveStereoLayout: PlaybackModel.StereoLayout {
        return selectedStereoLayout
    }
    public var displayMediaProfile: PlaybackModel.MediaProfile? {
        profile(from: diagnostics) ?? prefetchedMetadata?.mediaProfile
    }
    public var displayFileSizeInBytes: Int64? { prefetchedMetadata?.fileSizeInBytes }
    public var isHDRContent: Bool { displayMediaProfile?.hdrType != .sdr }

    private let controller: PlaybackCoreController
    private let audioSessionLifecycle: PlaybackAudioSessionLifecycle
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackRuntime")
    private let signposter: OSSignposter
    private var session: SampleBufferPlaybackSession?
    private var attachment: Attachment?
    private var generation = 0
    private var selectedProjectionType: PlaybackModel.ProjectionType = .flat
    private var selectedStereoLayout: PlaybackModel.StereoLayout = .mono
    private var displayedImageGeneration = 0
    private var lastResolvedProfile: PlaybackModel.MediaProfile?
    private var closingTask: Task<Void, Never>?
    private var startsWhenAttached = false
    private var actualPlaybackAccumulator = ActualPlaybackAccumulator()
    private var pendingVideoComponentRevision: UInt64?
    private var restartingVideoComponentRevision: UInt64?
    private var lastBoundVideoRendererEntityID: String?
    private var videoSampleDeliveryRestartFailed = false
    private var rendererGraphRecoveryInProgress = false
    private var releasedRendererConsumerEntityID: String?
    private var existingRendererGraphTransfer: ExistingRendererGraphTransfer?
    private var sourceVideoPlayerComponentRemovedAt: Date?

    private static let videoComponentReplacementTimeout = Duration.seconds(7)

    private struct Attachment {
        let entityID: String
        let realityViewID: String
        let presentation: PlaybackPresentation
    }

    private struct ExistingRendererGraphTransfer {
        let sourcePresentation: PlaybackPresentation
        let sourceEntityID: String
        let targetPresentation: PlaybackPresentation
        var sourceVideoPlayerComponentWasRemoved = false
        var targetEntityID: String?
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
        controller.onStatusChange = { [weak self] status in
            self?.receive(status)
        }
        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.receive(diagnostics)
        }
        controller.onSubtitleCuesChange = { [weak self] cues in
            self?.activeSubtitleCues = cues
        }
        controller.onSubtitleFrameChange = { [weak self] frame in
            self?.activeSubtitleFrame = frame
        }
    }

    public func prepareForPlayback(_ request: PlaybackLaunchRequest) {
        currentLaunchRequest = request
        prefetchedMetadata = request.initialMetadata
        playbackPosition = .init(seconds: 0, duration: 0)
        currentPlaybackSpeed = .default
        presentationState = .placeholder
        lastErrorMessage = nil
        subtitleErrorMessage = request.externalSubtitleErrorMessage
        lastResolvedProfile = nil
        startsWhenAttached = true
        actualPlaybackSeconds = 0
        didEndNaturally = false
        actualPlaybackAccumulator.reset()
        selectedProjectionType = .flat
        selectedStereoLayout = .mono
        mediaFormatIsKnown = false
        pendingVideoComponentRevision = nil
        lastBoundVideoRendererEntityID = nil
        releasedRendererConsumerEntityID = nil
        existingRendererGraphTransfer = nil
        sourceVideoPlayerComponentRemovedAt = nil
        sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds = nil
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

    public func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double = 0,
        initialSpeed: PlaybackModel.PlaybackSpeed = .default
    ) async throws {
        let interval = signposter.beginInterval("OpenPlayback")
        defer { signposter.endInterval("OpenPlayback", interval) }
        generation += 1
        let openGeneration = generation
        let startTimeSeconds = max(0, startTimeSeconds)
        prepareForPlayback(request)
        currentPlaybackSpeed = initialSpeed
        logger.info("open requested source=\(request.displayName, privacy: .public)")

        do {
            await closingTask?.value
            closingTask = nil
            guard request.sourceAccess?.ensureActive() != false else {
                throw RuntimeError.sourceAccessUnavailable
            }
            let newSession = try await controller.open(
                request.url,
                startTime: CMTime(seconds: startTimeSeconds, preferredTimescale: 60_000),
                initialRate: Float(initialSpeed.value),
                provenance: "Enchron",
                accessRequirement: request.url.isFileURL ? "securityScopedFile" : "networkSource"
            )
            guard generation == openGeneration else {
                await controller.closeAndWait()
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            session = newSession
            updateActiveSessionID(newSession.traceID)
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
            renderer = newSession.renderer
            logger.info("session prepared id=\(newSession.traceID, privacy: .public)")
        } catch {
            guard generation == openGeneration else {
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            fail(error)
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
        guard rendererGraphRecoveryInProgress == false else {
            throw RuntimeError.rendererTransferPending
        }
        if rendererConsumerPresentation == presentation,
           rendererConsumerEntityID == entityID {
            return
        }
        if let rendererConsumerEntityID, rendererConsumerEntityID != entityID {
            throw RuntimeError.rendererConsumerBusy(rendererConsumerPresentation ?? presentation)
        }
        if let existingRendererGraphTransfer {
            let isTargetClaim = presentation == existingRendererGraphTransfer.targetPresentation
            let isSourceRollback = presentation == existingRendererGraphTransfer.sourcePresentation
                && entityID == existingRendererGraphTransfer.sourceEntityID
            guard isTargetClaim || isSourceRollback else {
                throw RuntimeError.rendererTransferPending
            }
            if isTargetClaim {
                guard existingRendererGraphTransfer.sourceVideoPlayerComponentWasRemoved,
                      existingRendererGraphTransfer.targetEntityID == nil
                        || existingRendererGraphTransfer.targetEntityID == entityID else {
                    throw RuntimeError.rendererTransferPending
                }
                var transfer = existingRendererGraphTransfer
                transfer.targetEntityID = entityID
                self.existingRendererGraphTransfer = transfer
            } else {
                guard existingRendererGraphTransfer.targetEntityID == nil else {
                    throw RuntimeError.rendererTransferPending
                }
                self.existingRendererGraphTransfer = nil
            }
        } else if let releasedRendererConsumerEntityID {
            guard releasedRendererConsumerEntityID == entityID else {
                throw RuntimeError.rendererTransferPending
            }
            self.releasedRendererConsumerEntityID = nil
        }
        rendererConsumerPresentation = presentation
        rendererConsumerEntityID = entityID
    }

    public func releaseRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String,
        retainingCurrentRendererGraphFor targetPresentation: PlaybackPresentation? = nil
    ) {
        guard rendererConsumerPresentation == presentation,
              rendererConsumerEntityID == entityID else { return }
        clearVideoComponentBindingObservation(for: entityID)
        if var existingRendererGraphTransfer,
           presentation == existingRendererGraphTransfer.targetPresentation,
           entityID == existingRendererGraphTransfer.targetEntityID {
            existingRendererGraphTransfer.targetEntityID = nil
            self.existingRendererGraphTransfer = existingRendererGraphTransfer
            releasedRendererConsumerEntityID = nil
        } else if pendingVideoComponentRevision == nil {
            if presentation == .window,
               targetPresentation == .panorama {
                existingRendererGraphTransfer = ExistingRendererGraphTransfer(
                    sourcePresentation: presentation,
                    sourceEntityID: entityID,
                    targetPresentation: .panorama
                )
                releasedRendererConsumerEntityID = nil
                sourceVideoPlayerComponentRemovedAt = nil
                sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds = nil
            } else {
                existingRendererGraphTransfer = nil
                releasedRendererConsumerEntityID = entityID
            }
        }
        rendererConsumerPresentation = nil
        rendererConsumerEntityID = nil
        logger.notice(
            "renderer consumer released presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
        )
    }

    /// The App reports this only after RealityKit no longer exposes the source
    /// VideoPlayerComponent. A renderer graph is never attached to a second
    /// RealityKit video component. Window-to-Panorama therefore replaces the
    /// graph only after that removal is observable.
    public func sourceVideoPlayerComponentDidRemove(
        presentation: PlaybackPresentation,
        entityID: String
    ) async throws {
        guard var existingRendererGraphTransfer,
              existingRendererGraphTransfer.sourcePresentation == presentation,
              existingRendererGraphTransfer.sourceEntityID == entityID,
              existingRendererGraphTransfer.targetEntityID == nil else {
            return
        }
        existingRendererGraphTransfer.sourceVideoPlayerComponentWasRemoved = true
        self.existingRendererGraphTransfer = existingRendererGraphTransfer
        sourceVideoPlayerComponentRemovedAt = Date()
        logger.notice(
            "source video component removed presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
        )
        _ = try await beginRendererGraphReplacement()
    }

    /// Once the target surface has settled, later releases are ordinary
    /// presentation changes rather than a rollback to the Window source.
    public func rendererGraphTransferDidSettle(
        for presentation: PlaybackPresentation
    ) {
        guard let existingRendererGraphTransfer,
              existingRendererGraphTransfer.targetPresentation == presentation,
              existingRendererGraphTransfer.targetEntityID
                == rendererConsumerEntityID,
              rendererConsumerPresentation == presentation else {
            return
        }
        self.existingRendererGraphTransfer = nil
    }

    public func waitUntilPanoramaRendererGraphIsPrepared(
        timeout: Duration = .seconds(7)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            guard let existingRendererGraphTransfer,
                  existingRendererGraphTransfer.targetPresentation == .panorama else {
                return false
            }
            if existingRendererGraphTransfer.sourceVideoPlayerComponentWasRemoved,
               rendererGraphRecoveryInProgress == false,
               pendingVideoComponentRevision != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func waitUntilRendererConsumerIsReleased(
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        if rendererConsumerEntityID == nil { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if rendererConsumerEntityID == nil { return true }
        }
        logger.error(
            "renderer consumer release timed out presentation=\(String(describing: self.rendererConsumerPresentation), privacy: .public)"
        )
        return false
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
            let continuity = try await controller.playAndVerifyRendererGraphContinuity()
            guard continuity == .ready else {
                try? controller.pause()
                throw RuntimeError.rendererGraphPlaybackDidNotAdvance(continuity)
            }
            PlaybackTrace.event("runtime.resume.completed")
        }

        guard activeSessionID == intent.mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
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
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    after: behavior
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
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    by: CMTime(seconds: delta, preferredTimescale: 600),
                    after: behavior
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
        } catch {
            fail(error)
        }
    }

    func setMuted(_ muted: Bool) {
        do {
            try controller.setMuted(muted)
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

    public func addExternalSubtitleFile(_ url: URL) async throws -> PlaybackModel.SubtitleTrack? {
        guard let activeSessionID else {
            throw RuntimeError.noSession
        }
        let normalizedURL = url.standardizedFileURL
        let sourceAccess = MediaAccessLease.retaining(
            normalizedURL as NSURL,
            securityScoped: normalizedURL
        )
        let sourceID = externalSubtitleSourceIDByURL[normalizedURL]
            ?? VersionedMediaIdentity.local(normalizedURL)?.mediaIdentity.storageKey
            ?? MediaIdentity.localPathFallback(canonicalPath: normalizedURL.path).storageKey
        logger.info(
            "external subtitle addition requested extension=\(normalizedURL.pathExtension, privacy: .public)"
        )
        do {
            return try await finishAddingExternalSubtitleFile(
                normalizedURL,
                sourceID: sourceID,
                sourceAccess: sourceAccess,
                activeSessionID: activeSessionID
            )
        } catch {
            subtitleErrorMessage = error.localizedDescription
            logger.error(
                "external subtitle addition failed error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func finishAddingExternalSubtitleFile(
        _ normalizedURL: URL,
        sourceID: String,
        sourceAccess: MediaAccessLease,
        activeSessionID: String
    ) async throws -> PlaybackModel.SubtitleTrack? {
        var sourceWasAdded = false
        do {
            let tracks = try await controller.addExternalSubtitleSource(
                PlaybackExternalSubtitleSource(
                    id: sourceID,
                    url: normalizedURL,
                    displayName: normalizedURL.lastPathComponent
                )
            )
            sourceWasAdded = true
            guard self.activeSessionID == activeSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            if let firstTrack = tracks.first {
                try await controller.selectSubtitleTrack(id: firstTrack.id)
            }
            guard self.activeSessionID == activeSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            let previousAccess = externalSubtitleAccessBySourceID.updateValue(
                sourceAccess,
                forKey: sourceID
            )
            externalSubtitleSourceIDByURL[normalizedURL] = sourceID
            previousAccess?.release()
            availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
            currentSubtitleTrackID = controller.selectedSubtitleTrackID
            activeSubtitleCues = controller.activeSubtitleCues
            activeSubtitleFrame = controller.activeSubtitleFrame
            subtitleErrorMessage = nil
            logger.info("external subtitle addition completed")
            return availableSubtitleTracks.first { $0.id == currentSubtitleTrackID }
        } catch {
            if sourceWasAdded, self.activeSessionID == activeSessionID {
                try? await controller.removeExternalSubtitleSource(id: sourceID)
                availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
                currentSubtitleTrackID = controller.selectedSubtitleTrackID
                activeSubtitleCues = controller.activeSubtitleCues
                activeSubtitleFrame = controller.activeSubtitleFrame
            }
            externalSubtitleSourceIDByURL.removeValue(forKey: normalizedURL)
            externalSubtitleAccessBySourceID.removeValue(forKey: sourceID)?.release()
            sourceAccess.release()
            throw error
        }
    }

    private func addAutomaticExternalSubtitleSources(
        _ sources: [ResolvedExternalSubtitleSource],
        mediaSessionID: String,
        openGeneration: Int
    ) async {
        var failures: [String] = []
        for source in sources {
            guard generation == openGeneration,
                  activeSessionID == mediaSessionID else {
                source.accessLease?.release()
                continue
            }
            guard source.accessLease?.ensureActive() != false else {
                failures.append("\(source.displayName): source access is unavailable")
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
                    externalSubtitleAccessBySourceID.updateValue(
                        accessLease,
                        forKey: source.id
                    )?.release()
                }
                let normalizedURL = source.url.isFileURL
                    ? source.url.standardizedFileURL
                    : source.url
                externalSubtitleSourceIDByURL[normalizedURL] = source.id
            } catch {
                source.accessLease?.release()
                failures.append("\(source.displayName): \(error.localizedDescription)")
            }
        }
        guard generation == openGeneration,
              activeSessionID == mediaSessionID else { return }
        availableSubtitleTracks = controller.availableSubtitleTracks.map(Self.subtitleTrack)
        currentSubtitleTrackID = controller.selectedSubtitleTrackID
        activeSubtitleCues = controller.activeSubtitleCues
        activeSubtitleFrame = controller.activeSubtitleFrame
        if !failures.isEmpty {
            subtitleErrorMessage = ([subtitleErrorMessage].compactMap { $0 } + failures)
                .joined(separator: "\n")
        }
    }

    public func replay() {
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await audioSessionLifecycle.activateIfNeeded(
                    hasAudio: !availableAudioTracks.isEmpty
                )
                recordAudioSessionFact()
                try await controller.seek(to: .zero, after: .play)
                try controller.play()
            } catch {
                fail(error)
            }
        }
    }

    public func frameStepForward() { frameStep(direction: 1) }
    public func frameStepBackward() { frameStep(direction: -1) }

    public func setFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout
    ) async throws {
        if projection == .fisheye, supportsFisheyePresentation == false {
            throw RuntimeError.unsupportedProjection(.fisheye)
        }
        let formatGeneration = generation
        let formatSessionID = activeSessionID
        let previousProjection = selectedProjectionType
        let previousStereo = selectedStereoLayout
        let changesFormat = projection != previousProjection || stereo != previousStereo
        do {
            try await applyStereoLayout(stereo)
            guard generation == formatGeneration,
                  activeSessionID == formatSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            try await applyProjection(projection)
            guard generation == formatGeneration,
                  activeSessionID == formatSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            try await publishFormat(
                projection: projection,
                stereo: stereo,
                replacingVideoComponent: changesFormat,
                expectedGeneration: formatGeneration,
                expectedSessionID: formatSessionID
            )
        } catch {
            guard generation == formatGeneration,
                  activeSessionID == formatSessionID else { throw error }
            do {
                try await applyStereoLayout(previousStereo)
                guard generation == formatGeneration,
                      activeSessionID == formatSessionID else {
                    throw RuntimeError.mediaSessionChanged
                }
                try await applyProjection(previousProjection)
                guard generation == formatGeneration,
                      activeSessionID == formatSessionID else {
                    throw RuntimeError.mediaSessionChanged
                }
                try await publishFormat(
                    projection: previousProjection,
                    stereo: previousStereo,
                    replacingVideoComponent: changesFormat,
                    expectedGeneration: formatGeneration,
                    expectedSessionID: formatSessionID
                )
            } catch RuntimeError.mediaSessionChanged {
                throw RuntimeError.mediaSessionChanged
            } catch {
                abandonPendingVideoComponentReplacement()
                mediaFormatIsKnown = false
                lastErrorMessage = RuntimeError.formatRollbackFailed.localizedDescription
                throw RuntimeError.formatRollbackFailed
            }
            throw error
        }
    }

    private func publishFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout,
        replacingVideoComponent: Bool,
        expectedGeneration: Int,
        expectedSessionID: String?
    ) async throws {
        let requiresRendererReplacement = replacingVideoComponent
            && (rendererConsumerEntityID != nil || pendingVideoComponentRevision != nil)
        let replacementRenderer: AVSampleBufferVideoRenderer?
        if requiresRendererReplacement {
            replacementRenderer = try await controller.replaceRendererGraphForPresentation()
            guard generation == expectedGeneration,
                  activeSessionID == expectedSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
        } else {
            replacementRenderer = nil
        }

        if replacingVideoComponent {
            videoComponentRevision &+= 1
            clearVideoComponentBindingObservation()
        }
        let revision = videoComponentRevision
        if requiresRendererReplacement {
            pendingVideoComponentRevision = revision
            restartingVideoComponentRevision = nil
            videoSampleDeliveryRestartFailed = false
        }
        selectedProjectionType = projection
        selectedStereoLayout = stereo
        mediaFormatIsKnown = true
        if let replacementRenderer {
            releaseCurrentRendererConsumerForReplacement()
            renderer = replacementRenderer
        }

        guard requiresRendererReplacement else { return }
        let deadline = ContinuousClock.now + Self.videoComponentReplacementTimeout
        do {
            while pendingVideoComponentRevision == revision,
                  ContinuousClock.now < deadline {
                try Task.checkCancellation()
                guard generation == expectedGeneration,
                      activeSessionID == expectedSessionID else {
                    throw RuntimeError.mediaSessionChanged
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        } catch {
            throw error
        }
        guard pendingVideoComponentRevision != revision else {
            throw RuntimeError.videoComponentReplacementTimedOut
        }
        if videoSampleDeliveryRestartFailed {
            throw RuntimeError.videoSampleDeliveryRestartFailed
        }
    }

    public func videoRendererTargetDidBind(
        revision: UInt64,
        entityID: String
    ) {
        guard revision == videoComponentRevision,
              rendererConsumerEntityID == entityID else { return }
        if let existingRendererGraphTransfer,
           existingRendererGraphTransfer.targetEntityID == entityID,
           let sourceVideoPlayerComponentRemovedAt {
            sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds =
                Date().timeIntervalSince(sourceVideoPlayerComponentRemovedAt)
        }
        let previousEntityID = lastBoundVideoRendererEntityID
        lastBoundVideoRendererEntityID = entityID
        boundVideoComponentRevision = revision
        let rendererReplacementIsPending = pendingVideoComponentRevision == revision
        let videoRendererTargetChanged = previousEntityID != nil
            && previousEntityID != entityID
        guard rendererReplacementIsPending || videoRendererTargetChanged,
              restartingVideoComponentRevision != revision else { return }
        restartingVideoComponentRevision = revision
        let expectedGeneration = generation
        let expectedSessionID = activeSessionID
        let restartTime = CMTime(
            seconds: max(0, diagnostics.currentSeconds),
            preferredTimescale: 60_000
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await controller.restartVideoSampleDeliveryForPresentationTransfer(
                    at: restartTime
                )
                guard generation == expectedGeneration,
                      activeSessionID == expectedSessionID,
                      restartingVideoComponentRevision == revision else { return }
                restartingVideoComponentRevision = nil
                if rendererConsumerEntityID == entityID,
                   lastBoundVideoRendererEntityID == entityID,
                   pendingVideoComponentRevision == revision {
                    pendingVideoComponentRevision = nil
                }
            } catch {
                guard restartingVideoComponentRevision == revision else { return }
                restartingVideoComponentRevision = nil
                if rendererConsumerEntityID == entityID,
                   lastBoundVideoRendererEntityID == entityID {
                    videoSampleDeliveryRestartFailed = true
                    lastErrorMessage = error.localizedDescription
                    if pendingVideoComponentRevision == revision {
                        pendingVideoComponentRevision = nil
                    }
                }
            }
        }
    }

    func recoverRendererGraphAfterPresentationTransfer() async throws {
        guard rendererGraphRecoveryInProgress == false,
              pendingVideoComponentRevision == nil else { return }
        let revision = try await beginRendererGraphReplacement()
        try await waitForRendererGraphReplacementToBind(revision: revision)
    }

    private func beginRendererGraphReplacement() async throws -> UInt64 {
        guard activeSessionID != nil else { throw RuntimeError.noSession }
        guard rendererGraphRecoveryInProgress == false else {
            throw RuntimeError.rendererTransferPending
        }
        let expectedGeneration = generation
        let expectedSessionID = activeSessionID
        rendererGraphRecoveryInProgress = true
        let replacementRenderer: AVSampleBufferVideoRenderer
        do {
            replacementRenderer = try await controller.replaceRendererGraphForPresentation()
            guard generation == expectedGeneration,
                  activeSessionID == expectedSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
        } catch {
            rendererGraphRecoveryInProgress = false
            throw error
        }
        rendererGraphRecoveryInProgress = false

        videoComponentRevision &+= 1
        clearVideoComponentBindingObservation()
        let revision = videoComponentRevision
        pendingVideoComponentRevision = revision
        restartingVideoComponentRevision = nil
        videoSampleDeliveryRestartFailed = false
        releaseCurrentRendererConsumerForReplacement()
        renderer = replacementRenderer
        return revision
    }

    private func waitForRendererGraphReplacementToBind(revision: UInt64) async throws {
        let expectedGeneration = generation
        let expectedSessionID = activeSessionID
        let deadline = ContinuousClock.now + Self.videoComponentReplacementTimeout
        while pendingVideoComponentRevision == revision,
              ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard generation == expectedGeneration,
                  activeSessionID == expectedSessionID else {
                throw RuntimeError.mediaSessionChanged
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard pendingVideoComponentRevision != revision else {
            throw RuntimeError.videoComponentReplacementTimedOut
        }
        if videoSampleDeliveryRestartFailed {
            throw RuntimeError.videoSampleDeliveryRestartFailed
        }
    }

    func prepareRendererGraphForPresentationTransfer() async throws {
        guard releasedRendererConsumerEntityID != nil else { return }
        guard rendererConsumerEntityID == nil,
              rendererGraphRecoveryInProgress == false,
              pendingVideoComponentRevision == nil else {
            throw RuntimeError.rendererTransferPending
        }
        guard activeSessionID != nil else { throw RuntimeError.noSession }
        releasedRendererConsumerEntityID = nil
        _ = try await beginRendererGraphReplacement()
    }

    private func releaseCurrentRendererConsumerForReplacement() {
        guard let presentation = rendererConsumerPresentation,
              let entityID = rendererConsumerEntityID else { return }
        releaseRendererConsumer(presentation: presentation, entityID: entityID)
    }

    private func abandonPendingVideoComponentReplacement() {
        pendingVideoComponentRevision = nil
        restartingVideoComponentRevision = nil
        videoSampleDeliveryRestartFailed = false
    }

    public var supportsFisheyePresentation: Bool {
        Self.hasAIME(from: diagnostics.projectionKind)
    }

    public func stop(releasingSourceAccess: Bool = true) {
        beginStop(releasingSourceAccess: releasingSourceAccess)
    }

    public func stopAndWait(releasingSourceAccess: Bool = true) async {
        let closeTask = beginStop(releasingSourceAccess: releasingSourceAccess)
        await closeTask?.value
    }

    @discardableResult
    private func beginStop(releasingSourceAccess: Bool) -> Task<Void, Never>? {
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
        let previousClosingTask = closingTask
        let audioSessionLifecycle = audioSessionLifecycle
        let closeTask = Task { @MainActor in
            await previousClosingTask?.value
            await controller.closeAndWait()
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
        lastErrorMessage = nil
    }

    public func clearPresentation() {
        clearPresentationForTeardown()
        session = nil
        renderer = nil
        updateActiveSessionID(nil)
        currentLaunchRequest = nil
        prefetchedMetadata = nil
        availableAudioTracks = []
        currentAudioTrackID = nil
        availableSubtitleTracks = []
        currentSubtitleTrackID = nil
        activeSubtitleCues = []
        activeSubtitleFrame = nil
        subtitleErrorMessage = nil
        playbackPosition = .init(seconds: 0, duration: 0)
        selectedProjectionType = .flat
        selectedStereoLayout = .mono
        mediaFormatIsKnown = false
        pendingVideoComponentRevision = nil
        lastBoundVideoRendererEntityID = nil
        releasedRendererConsumerEntityID = nil
        existingRendererGraphTransfer = nil
        sourceVideoPlayerComponentRemovedAt = nil
        sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds = nil
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

    public func waitUntilPresentationSettled(
        to presentation: PlaybackPresentation,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        if presentationIsSettled(presentation) { return true }
        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: timeout)
        var allowedComponentReplacement = false
        while clock.now < deadline {
            guard Task.isCancelled == false else { return false }
            if allowedComponentReplacement == false,
               rendererGraphRecoveryInProgress || pendingVideoComponentRevision != nil {
                allowedComponentReplacement = true
                // A cross-RealityView transfer can require a bounded renderer
                // replacement before the ordinary surface-settlement interval
                // can begin. Give that operation its own documented bound and
                // then the full settlement interval; do not make the two
                // independently bounded operations race the same deadline.
                deadline = clock.now.advanced(
                    by: Self.videoComponentReplacementTimeout + timeout
                )
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
            if presentationIsSettled(presentation) { return true }
        }
        logger.error(
            "presentation settlement timed out expected=\(String(describing: presentation), privacy: .public) actual=\(String(describing: self.attachedPresentation), privacy: .public)"
        )
        return false
    }

    private func presentationIsSettled(_ presentation: PlaybackPresentation) -> Bool {
        guard attachedPresentation == presentation,
              let record = session?.debugSnapshot().presentationState else { return false }
        return Self.presentationTransitionCanCommit(
            record: record,
            presentation: presentation,
            activeSessionID: activeSessionID,
            lifecycle: productLifecycle
        )
    }

    static func presentationTransitionCanCommit(
        record: PresentationStateRecord,
        presentation: PlaybackPresentation,
        activeSessionID: String?,
        lifecycle: ProductPlaybackLifecycle
    ) -> Bool {
        guard record.mediaSessionID == activeSessionID,
              record.requestedMode == presentation.rawValue,
              let phase = PlaybackPresentationSettlementPhase(rawValue: record.phase) else {
            return false
        }
        switch phase {
        case .settled:
            return true
        case .surfaceAttached:
            return lifecycle == .ended
        }
    }

    func recordPresentationState(
        presentation: PlaybackPresentation,
        phase: PlaybackPresentationSettlementPhase,
        entityID: String,
        videoComponentRevision: UInt64,
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
    ) {
        guard let session else { return }
        let record = PresentationStateRecord(
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
        let endedSurfaceIsPresentable = phase == .surfaceAttached
            && productLifecycle == .ended
        if displayedPixelBuffer == true,
           rendererConsumerEntityID == entityID,
           boundVideoComponentRevision == videoComponentRevision,
           self.videoComponentRevision == videoComponentRevision {
            rendererPixelVideoComponentRevision = videoComponentRevision
            rendererPixelStreamEpoch = session.debugSnapshot().streamEpoch
        }
        if outputIsPresentable || endedSurfaceIsPresentable {
            if presentationState != .videoVisible {
                presentationState = .videoVisible
            }
            clearFailureIfPlaybackIsUsable()
        }
        guard session.debugSnapshot().presentationState != record else { return }
        session.recordPresentationState(record)
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

    func outputObservation() -> PlaybackOutputObservation {
        let snapshot = session?.debugSnapshot()
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
            systemOutputVolume: audioSession.outputVolume
        )
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        session?.debugSnapshot()
    }

    #if DEBUG
    func debugEvidenceJSON() -> String {
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
#if os(macOS)
        "macOS"
#else
        "visionOS"
#endif
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
        let rate = diagnostics.nominalFrameRate > 0 ? diagnostics.nominalFrameRate : 30
        let offset = direction / rate
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    by: CMTime(seconds: offset, preferredTimescale: 60_000),
                    after: .pause
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
        lifecycle = status
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
            lastErrorMessage = message
            logger.error("playback failed message=\(message, privacy: .public)")
        }
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
        guard lastErrorMessage != nil else { return }
        switch lifecycle {
        case .ready, .playing, .paused:
            lastErrorMessage = nil
        case .idle, .loading, .ended, .failed:
            break
        }
    }

    private func receive(_ diagnostics: PlaybackDiagnostics) {
        recordActualPlayback(until: diagnostics.currentSeconds)
        self.diagnostics = diagnostics
        playbackPosition = .init(
            seconds: diagnostics.currentSeconds,
            duration: diagnostics.durationSeconds
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

    private func invalidatePendingDisplayedImageClear() {
        displayedImageGeneration += 1
    }

    private func applyStereoLayout(_ stereo: PlaybackModel.StereoLayout) async throws {
        switch stereo {
        case .mono: _ = try await controller.setStereoLayout(.mono)
        case .sideBySide: _ = try await controller.setStereoLayout(.sideBySide)
        case .topBottom: _ = try await controller.setStereoLayout(.overUnder)
        }
    }

    private func applyProjection(_ projection: PlaybackModel.ProjectionType) async throws {
        switch projection {
        case .flat: _ = try await controller.setProjectionOverride(.rectilinear)
        case .equirectangular180: _ = try await controller.setProjectionOverride(.halfEquirectangular)
        case .equirectangular360: _ = try await controller.setProjectionOverride(.equirectangular)
        case .fisheye:
            // Apple fisheye playback requires source AIME metadata; retaining it
            // means removing any app-supplied projection override.
            _ = try await controller.clearProjectionOverride()
        }
    }

    private func profile(from diagnostics: PlaybackDiagnostics) -> PlaybackModel.MediaProfile? {
        guard let resolution = Self.parseResolution(diagnostics.dimensions) else {
            return prefetchedMetadata?.mediaProfile
        }
        let transfer = diagnostics.transferFunction.lowercased()
        let hdr: PlaybackModel.HDRType
        if diagnostics.formatHasDvcC || diagnostics.formatHasDvvC {
            hdr = .dolbyVision
        } else if transfer.contains("2084") || transfer.contains("pq") {
            hdr = .hdr10
        } else if transfer.contains("hlg") || transfer.contains("arib") {
            hdr = .hlg
        } else {
            hdr = .sdr
        }
        return PlaybackModel.MediaProfile(
            projectionType: Self.projectionType(from: diagnostics.projectionKind)
                ?? prefetchedMetadata?.mediaProfile?.projectionType
                ?? .flat,
            stereoLayout: Self.stereoLayout(from: diagnostics.viewPackingKind)
                ?? prefetchedMetadata?.mediaProfile?.stereoLayout
                ?? .mono,
            hdrType: hdr,
            resolution: resolution,
            frameRate: diagnostics.nominalFrameRate,
            videoCodec: diagnostics.codecName,
            durationSeconds: diagnostics.durationSeconds
        )
    }

    func fail(_ error: Error) {
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
        lastErrorMessage = error.localizedDescription
        logger.error("runtime operation failed error=\(error.localizedDescription, privacy: .public)")
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
            return .fisheye
        }
        if normalized.contains("rectilinear") { return .flat }
        return nil
    }

    static func projectionType(from value: VideoProjectionOverride?) -> PlaybackModel.ProjectionType? {
        switch value {
        case .rectilinear: .flat
        case .equirectangular: .equirectangular360
        case .halfEquirectangular: .equirectangular180
        case nil: nil
        }
    }

    static func stereoLayout(from value: String) -> PlaybackModel.StereoLayout? {
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
        case .docked: "ImmersiveSpace.Docked"
        case .panorama: "ImmersiveSpace.Panorama"
        }
    }
}
