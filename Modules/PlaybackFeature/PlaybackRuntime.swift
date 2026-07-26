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
    public enum PresentationState: Sendable {
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
        case mediaSessionChanged
        case spatialPlaybackTransportUnavailable(ProductPlaybackLifecycle)
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
            case .mediaSessionChanged:
                "The media session changed before the operation completed."
            case .spatialPlaybackTransportUnavailable(let lifecycle):
                "Playback cannot be paused or resumed while it is \(String(describing: lifecycle))."
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
    public private(set) var activeSessionID: String?
    public private(set) var actualPlaybackSeconds: Double = 0
    public private(set) var didEndNaturally = false
    public private(set) var mediaFormatIsKnown = false
    public private(set) var renderer: AVSampleBufferVideoRenderer?
    public private(set) var attachedPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerEntityID: String?
    public var lastErrorMessage: String?

    public var onPlaybackEnded: (() -> Void)?
    public var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    @ObservationIgnored
    private var sessionLifecycleHandler: ((SessionLifecycleEvent) -> Void)?

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

    private struct Attachment {
        let entityID: String
        let realityViewID: String
        let presentation: PlaybackPresentation
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
        lastResolvedProfile = nil
        startsWhenAttached = true
        actualPlaybackSeconds = 0
        didEndNaturally = false
        actualPlaybackAccumulator.reset()
        selectedProjectionType = .flat
        selectedStereoLayout = .mono
        mediaFormatIsKnown = false
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
            renderer = newSession.renderer
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
                try audioSessionLifecycle.activateIfNeeded(hasAudio: !availableAudioTracks.isEmpty)
                try controller.start()
                startsWhenAttached = false
            }
        } catch {
            audioSessionLifecycle.deactivate()
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
        presentationState = .videoVisible
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

    func claimRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String
    ) throws {
        if let rendererConsumerEntityID, rendererConsumerEntityID != entityID {
            throw RuntimeError.rendererConsumerBusy(rendererConsumerPresentation ?? presentation)
        }
        rendererConsumerPresentation = presentation
        rendererConsumerEntityID = entityID
    }

    func releaseRendererConsumer(
        presentation: PlaybackPresentation,
        entityID: String
    ) {
        guard rendererConsumerPresentation == presentation,
              rendererConsumerEntityID == entityID else { return }
        rendererConsumerPresentation = nil
        rendererConsumerEntityID = nil
        logger.notice(
            "renderer consumer released presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
        )
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
        do {
            guard let activeSessionID else { throw RuntimeError.noSession }
            try performSpatialPlaybackTransport(.pause(mediaSessionID: activeSessionID))
        } catch {
            fail(error)
        }
    }

    public func resume() {
        PlaybackTrace.event("runtime.resume.request lifecycle=\(lifecycle.label)")
        do {
            guard let activeSessionID else { throw RuntimeError.noSession }
            try performSpatialPlaybackTransport(.resume(mediaSessionID: activeSessionID))
        } catch {
            fail(error)
        }
    }

    public func performSpatialPlaybackTransport(
        _ intent: SpatialPlaybackTransportIntent
    ) throws {
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
            try controller.play()
            PlaybackTrace.event("runtime.resume.completed")
        }

        guard activeSessionID == intent.mediaSessionID else {
            throw RuntimeError.mediaSessionChanged
        }
    }

    public func seek(to seconds: Double, startsPaused: Bool? = nil) {
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        let nonnegativeTarget = max(0, seconds)
        let target = playbackPosition.duration > 0
            ? min(playbackPosition.duration, nonnegativeTarget)
            : nonnegativeTarget
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    startsPaused: startsPaused
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
        let startsPaused = lifecycle == .ended ? true : nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    by: CMTime(seconds: delta, preferredTimescale: 600),
                    startsPaused: startsPaused
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

    public func selectAudioTrack(_ track: PlaybackModel.AudioTrack) {
        guard let streamIndex = Int(track.id) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.selectAudioTrack(streamIndex: streamIndex)
                currentAudioTrackID = track.id
            } catch {
                fail(error)
            }
        }
    }

    public func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.selectSubtitleTrack(id: track?.id)
                currentSubtitleTrackID = controller.selectedSubtitleTrackID
                activeSubtitleCues = controller.activeSubtitleCues
            } catch {
                fail(error)
            }
        }
    }

    public func replay() {
        resetActualPlaybackSampling()
        invalidatePendingDisplayedImageClear()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(to: .zero, startsPaused: false)
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
            selectedProjectionType = projection
            selectedStereoLayout = stereo
            mediaFormatIsKnown = true
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
            } catch RuntimeError.mediaSessionChanged {
                throw RuntimeError.mediaSessionChanged
            } catch {
                mediaFormatIsKnown = false
                lastErrorMessage = RuntimeError.formatRollbackFailed.localizedDescription
                throw RuntimeError.formatRollbackFailed
            }
            throw error
        }
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
        let controller = controller
        let previousClosingTask = closingTask
        let audioSessionLifecycle = audioSessionLifecycle
        let closeTask = Task { @MainActor in
            await previousClosingTask?.value
            await controller.closeAndWait()
            audioSessionLifecycle.deactivate()
            sourceAccess?.release()
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
        playbackPosition = .init(seconds: 0, duration: 0)
        selectedProjectionType = .flat
        selectedStereoLayout = .mono
        mediaFormatIsKnown = false
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
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            guard Task.isCancelled == false else { return false }
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
              record.requestedMode == presentation.rawValue else { return false }
        if record.phase == "settled" { return true }
        #if targetEnvironment(simulator)
        if record.phase == "simulatorConfigured" {
            return presentation == .panorama
        }
        #endif
        guard record.phase == "surfaceAttached" else { return false }
        guard presentation != .panorama else { return false }
        switch lifecycle {
        case .ready, .paused, .ended:
            return true
        case .idle, .loading, .playing, .failed:
            return false
        }
    }

    func recordPresentationState(
        presentation: PlaybackPresentation,
        phase: String,
        realityViewID: String,
        entityParentID: String? = nil,
        desiredImmersiveViewingMode: String? = nil,
        actualImmersiveViewingMode: String? = nil,
        desiredViewingMode: String? = nil,
        actualViewingMode: String? = nil,
        desiredSpatialVideoMode: String? = nil,
        actualSpatialVideoMode: String? = nil
    ) {
        guard let session else { return }
        let record = PresentationStateRecord(
            mediaSessionID: session.traceID,
            requestedMode: presentation.rawValue,
            phase: phase,
            platform: platformName,
            sceneContainer: .init(.known, value: presentation.sceneContainer),
            realityViewIdentity: .init(.known, value: realityViewID),
            entityParentIdentity: Self.observedFact(entityParentID),
            desiredImmersiveViewingMode: Self.observedFact(desiredImmersiveViewingMode),
            actualImmersiveViewingMode: Self.observedFact(actualImmersiveViewingMode),
            desiredViewingMode: Self.observedFact(desiredViewingMode),
            actualViewingMode: Self.observedFact(actualViewingMode),
            desiredSpatialVideoMode: Self.observedFact(desiredSpatialVideoMode),
            actualSpatialVideoMode: Self.observedFact(actualSpatialVideoMode),
            transitionResult: .init(.known, value: "succeeded")
        )
        guard session.debugSnapshot().presentationState != record else { return }
        session.recordPresentationState(record)
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        session?.debugSnapshot()
    }

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
        value.map { .init(.known, value: $0) } ?? .init(.notExposed)
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
                    startsPaused: true
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
            clearFailureIfPlaybackIsUsable()
        case .ended:
            didEndNaturally = true
            audioSessionLifecycle.deactivate()
            let endedSessionID = activeSessionID
            displayedImageGeneration += 1
            let clearGeneration = displayedImageGeneration
            Task { [weak self] in
                guard let self, let endedSessionID else { return }
                await Task.yield()
                guard lifecycle == .ended,
                      activeSessionID == endedSessionID,
                      displayedImageGeneration == clearGeneration else { return }
                await controller.clearDisplayedVideoImage(forMediaSessionID: endedSessionID)
            }
            onPlaybackEnded?()
        case .failed(let message):
            audioSessionLifecycle.deactivate()
            lastErrorMessage = message
            logger.error("playback failed message=\(message, privacy: .public)")
        }
    }

    private func clearFailureIfPlaybackIsUsable() {
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
