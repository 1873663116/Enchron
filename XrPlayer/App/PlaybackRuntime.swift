import AVFoundation
import CoreMedia
import Foundation
import Observation
import OSLog
import PlaybackCore

@MainActor
@Observable
public final class PlaybackRuntime {
    public enum PresentationState: Sendable {
        case hidden
        case placeholder
        case videoVisible
    }

    public enum RuntimeError: LocalizedError {
        case noSession
        case sourceAccessUnavailable
        case unsupportedProjection(PlaybackModel.ProjectionType)
        case rendererConsumerBusy(PlaybackPresentation)

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
    public private(set) var renderer: AVSampleBufferVideoRenderer?
    public private(set) var attachedPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerPresentation: PlaybackPresentation?
    public private(set) var rendererConsumerEntityID: String?
    public var lastErrorMessage: String?

    public var onPlaybackEnded: (() -> Void)?
    public var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?

    public var hasActivePlaybackRequest: Bool { currentLaunchRequest != nil }
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
        if isUITestFixture, let fixtureProjectionOverride { return fixtureProjectionOverride }
        return Self.projectionType(from: session?.effectiveProjectionKind ?? "")
            ?? displayMediaProfile?.projectionType
            ?? .flat
    }
    public var effectiveStereoLayout: PlaybackModel.StereoLayout {
        if isUITestFixture, let fixtureStereoOverride { return fixtureStereoOverride }
        switch controller.selectedStereoLayout {
        case .sideBySide: return .sideBySide
        case .overUnder: return .topBottom
        case .mono: return .mono
        case nil: return displayMediaProfile?.stereoLayout ?? .mono
        }
    }
    public var displayMediaProfile: PlaybackModel.MediaProfile? {
        profile(from: diagnostics) ?? prefetchedMetadata?.mediaProfile
    }
    public var displayFileSizeInBytes: Int64? { prefetchedMetadata?.fileSizeInBytes }
    public var isHDRContent: Bool { displayMediaProfile?.hdrType != .sdr }

    private let controller: PlaybackCoreController
    private let isUITestFixture: Bool
    private let audioSessionLifecycle: PlaybackAudioSessionLifecycle
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackRuntime")
    private let signposter: OSSignposter
    private var session: SampleBufferPlaybackSession?
    private var attachment: Attachment?
    private var generation = 0
    private var fixtureProjectionOverride: PlaybackModel.ProjectionType?
    private var fixtureStereoOverride: PlaybackModel.StereoLayout?
    private var lastResolvedProfile: PlaybackModel.MediaProfile?
    private var closingTask: Task<Void, Never>?
    private var startsWhenAttached = false

    private struct Attachment {
        let entityID: String
        let realityViewID: String
        let presentation: PlaybackPresentation
    }

    public convenience init(
        controller: PlaybackCoreController = PlaybackCoreController(),
        isUITestFixture: Bool = false
    ) {
        self.init(
            controller: controller,
            isUITestFixture: isUITestFixture,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
    }

    init(
        controller: PlaybackCoreController,
        isUITestFixture: Bool,
        audioSessionLifecycle: PlaybackAudioSessionLifecycle
    ) {
        self.controller = controller
        self.isUITestFixture = isUITestFixture
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
        presentationState = .placeholder
        lastErrorMessage = nil
        lastResolvedProfile = nil
        startsWhenAttached = true
    }

    public func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = prefetchedMetadata?.merging(with: metadata) ?? metadata
    }

    public func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double = 0
    ) async throws {
        let interval = signposter.beginInterval("OpenPlayback")
        defer { signposter.endInterval("OpenPlayback", interval) }
        generation += 1
        let openGeneration = generation
        let startTimeSeconds = max(0, startTimeSeconds)
        prepareForPlayback(request)
        logger.info("open requested source=\(request.displayName, privacy: .public)")

        if isUITestFixture {
            renderer = AVSampleBufferVideoRenderer()
            activeSessionID = "ui-test-fixture"
            playbackPosition = .init(seconds: startTimeSeconds, duration: 7_200)
            lifecycle = .ready
            presentationState = .videoVisible
            return
        }

        do {
            await closingTask?.value
            closingTask = nil
            guard request.sourceAccess?.ensureActive() != false else {
                throw RuntimeError.sourceAccessUnavailable
            }
            let newSession = try await controller.open(
                request.url,
                startTime: CMTime(seconds: startTimeSeconds, preferredTimescale: 60_000),
                initialRate: Float(currentPlaybackSpeed.value),
                provenance: "Enchron",
                accessRequirement: request.url.isFileURL ? "securityScopedFile" : "networkSource"
            )
            guard generation == openGeneration else {
                await controller.closeAndWait()
                releaseSourceAccessIfUnowned(request.sourceAccess)
                return
            }
            session = newSession
            activeSessionID = newSession.traceID
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
        if isUITestFixture {
            attachment = Attachment(entityID: entityID, realityViewID: realityViewID, presentation: presentation)
            attachedPresentation = presentation
            presentationState = .videoVisible
            if startsWhenAttached {
                lifecycle = .playing
                startsWhenAttached = false
            }
            clearFailureIfPlaybackIsUsable()
            logger.notice(
                "fixture surface attached presentation=\(String(describing: presentation), privacy: .public) entity=\(entityID, privacy: .public)"
            )
            return
        }
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
        if isUITestFixture {
            logger.notice(
                "fixture surface detached presentation=\(String(describing: self.attachedPresentation), privacy: .public)"
            )
            attachment = nil
            attachedPresentation = nil
            return
        }
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
        if isUITestFixture {
            lifecycle = .paused
            PlaybackTrace.event("runtime.pause.completed fixture=true")
            return
        }
        do {
            try controller.pause()
            PlaybackTrace.event("runtime.pause.completed fixture=false")
        } catch {
            fail(error)
        }
    }

    public func resume() {
        PlaybackTrace.event("runtime.resume.request lifecycle=\(lifecycle.label)")
        if isUITestFixture {
            lifecycle = .playing
            PlaybackTrace.event("runtime.resume.completed fixture=true")
            return
        }
        do {
            try controller.play()
            PlaybackTrace.event("runtime.resume.completed fixture=false")
        } catch {
            fail(error)
        }
    }

    public func seek(to seconds: Double) {
        let nonnegativeTarget = max(0, seconds)
        let target = playbackPosition.duration > 0
            ? min(playbackPosition.duration, nonnegativeTarget)
            : nonnegativeTarget
        if isUITestFixture {
            playbackPosition = .init(seconds: target, duration: playbackPosition.duration)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            } catch let error as PlaybackControlError {
                if case .seekSuperseded = error { return }
                fail(error)
            } catch {
                fail(error)
            }
        }
    }

    public func skip(by delta: Double) {
        if isUITestFixture {
            seek(to: playbackPosition.seconds + delta)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await controller.seek(
                    by: CMTime(seconds: delta, preferredTimescale: 600)
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
        if isUITestFixture { currentPlaybackSpeed = speed; return }
        do {
            try controller.setRate(Float(speed.value))
            currentPlaybackSpeed = speed
        } catch {
            fail(error)
        }
    }

    public func setVolume(_ volume: Float) {
        if isUITestFixture { return }
        do {
            try controller.setVolume(volume)
        } catch {
            fail(error)
        }
    }

    public func setMuted(_ muted: Bool) {
        if isUITestFixture { return }
        do {
            try controller.setMuted(muted)
        } catch {
            fail(error)
        }
    }

    public func selectAudioTrack(_ track: PlaybackModel.AudioTrack) {
        if isUITestFixture { currentAudioTrackID = track.id; return }
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
        if isUITestFixture {
            currentSubtitleTrackID = track?.id
            activeSubtitleCues = []
            activeSubtitleFrame = nil
            return
        }
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
        if isUITestFixture {
            playbackPosition = .init(seconds: 0, duration: playbackPosition.duration)
            lifecycle = .playing
            return
        }
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
        if projection == .fisheye,
           displayMediaProfile?.projectionType != .fisheye {
            throw RuntimeError.unsupportedProjection(.fisheye)
        }
        if isUITestFixture {
            fixtureProjectionOverride = projection
            fixtureStereoOverride = stereo
            return
        }
        switch stereo {
        case .mono: _ = try await controller.setStereoLayout(.mono)
        case .sideBySide: _ = try await controller.setStereoLayout(.sideBySide)
        case .topBottom: _ = try await controller.setStereoLayout(.overUnder)
        }
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

    public func stop(releasingSourceAccess: Bool = true) {
        generation += 1
        startsWhenAttached = false
        detach()
        let sourceAccess = releasingSourceAccess
            ? currentLaunchRequest?.sourceAccess
            : nil
        if isUITestFixture == false {
            let controller = controller
            let previousClosingTask = closingTask
            let audioSessionLifecycle = audioSessionLifecycle
            closingTask = Task { @MainActor in
                await previousClosingTask?.value
                await controller.closeAndWait()
                audioSessionLifecycle.deactivate()
                sourceAccess?.release()
            }
        } else {
            audioSessionLifecycle.deactivate()
            sourceAccess?.release()
        }
        clearPresentation()
        if isUITestFixture { lifecycle = .idle }
        logger.info("session stopped")
    }

    public func clearPresentationForTeardown() {
        presentationState = .hidden
        lastErrorMessage = nil
    }

    public func clearPresentation() {
        clearPresentationForTeardown()
        session = nil
        renderer = nil
        activeSessionID = nil
        currentLaunchRequest = nil
        prefetchedMetadata = nil
        availableAudioTracks = []
        currentAudioTrackID = nil
        availableSubtitleTracks = []
        currentSubtitleTrackID = nil
        activeSubtitleCues = []
        activeSubtitleFrame = nil
        playbackPosition = .init(seconds: 0, duration: 0)
        fixtureProjectionOverride = nil
        fixtureStereoOverride = nil
        lastResolvedProfile = nil
    }

    public func waitUntilAttached(
        to presentation: PlaybackPresentation,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        if attachedPresentation == presentation { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            guard Task.isCancelled == false else { return false }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
            if attachedPresentation == presentation { return true }
        }
        logger.error(
            "surface attachment timed out expected=\(String(describing: presentation), privacy: .public) actual=\(String(describing: self.attachedPresentation), privacy: .public)"
        )
        return false
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
            route: session.route,
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
        let rate = diagnostics.nominalFrameRate > 0 ? diagnostics.nominalFrameRate : 30
        skip(by: direction / rate)
    }

    private func receive(_ status: PlaybackStatus) {
        lifecycle = status
        switch status {
        case .idle, .loading:
            break
        case .ready, .playing, .paused:
            clearFailureIfPlaybackIsUsable()
        case .ended:
            audioSessionLifecycle.deactivate()
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

    private func fail(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        logger.error("runtime operation failed error=\(error.localizedDescription, privacy: .public)")
    }

    private func releaseSourceAccessIfUnowned(_ sourceAccess: PlaybackSourceAccess?) {
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
