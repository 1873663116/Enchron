import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import MediaSource
import PlaybackCore

@MainActor
class PlaybackMediaSessionDriver {
    struct OpenRequest {
        let url: URL
        let startTime: CMTime
        let startsPaused: Bool
        let initialRate: Float?
        let sourceTransport: PlaybackSourceTransport
        let stereoOverride: PlaybackModel.StereoLayout?
        let projectionOverride: MediaFormatInterpreter.Projection?
        let horizontalFieldOfViewDegrees: Int?
        let usesDolbyVisionFallback: Bool
        let provenance: String
        let accessRequirement: String

        init(
            url: URL,
            startTime: CMTime = .zero,
            startsPaused: Bool = false,
            initialRate: Float? = nil,
            sourceTransport: PlaybackSourceTransport = .localFile,
            stereoOverride: PlaybackModel.StereoLayout? = nil,
            projectionOverride: MediaFormatInterpreter.Projection? = nil,
            horizontalFieldOfViewDegrees: Int? = nil,
            usesDolbyVisionFallback: Bool = false,
            provenance: String = "appOpen",
            accessRequirement: String = "appAdapterManaged"
        ) {
            self.url = url
            self.startTime = startTime
            self.startsPaused = startsPaused
            self.initialRate = initialRate
            self.sourceTransport = sourceTransport
            self.stereoOverride = stereoOverride
            self.projectionOverride = projectionOverride
            self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
            self.usesDolbyVisionFallback = usesDolbyVisionFallback
            self.provenance = provenance
            self.accessRequirement = accessRequirement
        }
    }

    struct SessionResource {
        let driver: PlaybackMediaSessionDriver
        let sessionID: String
        let renderer: AVSampleBufferVideoRenderer

        fileprivate init(
            driver: PlaybackMediaSessionDriver,
            session: SampleBufferPlaybackSession
        ) {
            self.driver = driver
            self.sessionID = session.traceID
            self.renderer = session.renderer
        }
    }

    struct OpenResult {
        let resource: SessionResource
        let mediaKind: PlaybackMediaKind
        let selectedAudioStreamIndex: Int?
        let debugSnapshot: PlaybackDebugSnapshotV1
    }

    struct Callbacks {
        var onStatusChange: ((PlaybackStatus) -> Void)?
        var onDiagnosticsChange: ((PlaybackDiagnostics) -> Void)?
        var onDeliveryContinuityChange: ((
            PlaybackDeliveryContinuityObservation
        ) -> Void)?
        var onAcceptedVideoFormatRevisionChange: ((UInt64) -> Void)?
        var onSubtitleCuesChange: (([PlaybackSubtitleCue]) -> Void)?
        var onSubtitleFrameChange: ((PlaybackSubtitleFrame?) -> Void)?
        var onAudioSpectrumFrameChange: ((AudioSpectrumFrame) -> Void)?
    }

    private let controller: PlaybackCoreController
    private var session: SampleBufferPlaybackSession?
    private var callbacks = Callbacks()
    private var closeTask: Task<Void, Never>?

    init(controller: PlaybackCoreController = PlaybackCoreController()) {
        self.controller = controller
        session = controller.activeSession
        bindControllerCallbacks()
    }

    var acceptedVideoFormatDescription: CMFormatDescription? {
        attachedSession?.acceptedVideoFormatDescription
    }

    var sessionID: String? {
        attachedSession?.traceID
    }

    var selectedAudioStreamIndex: Int? {
        attachedSession?.selectedAudioStreamIndex
    }

    var availableAudioTracks: [PlaybackAudioTrack] {
        controller.availableAudioTracks
    }

    var availableSubtitleTracks: [PlaybackSubtitleTrack] {
        controller.availableSubtitleTracks
    }

    var selectedSubtitleTrackID: PlaybackSubtitleTrack.ID? {
        controller.selectedSubtitleTrackID
    }

    var activeSubtitleCues: [PlaybackSubtitleCue] {
        controller.activeSubtitleCues
    }

    var activeSubtitleFrame: PlaybackSubtitleFrame? {
        controller.activeSubtitleFrame
    }

    var status: PlaybackStatus {
        controller.status
    }

    var diagnostics: PlaybackDiagnostics {
        controller.diagnostics
    }

    var activeFailureContext: PlaybackCoreActiveFailureContext? {
        controller.activeFailureContext
    }

    var deliveryContinuity: PlaybackDeliveryContinuityObservation? {
        controller.deliveryContinuity
    }

    var endedContinuity: PlaybackEndedContinuity? {
        controller.endedContinuity
    }

    var liveTechnicalSessionCount: Int {
        controller.liveTechnicalSessionCount
    }

    var retiringTechnicalSessionCount: Int {
        controller.retiringTechnicalSessionCount
    }

    private var attachedSession: SampleBufferPlaybackSession? {
        guard let session, controller.activeSession === session else { return nil }
        return session
    }

    func bindCallbacks(_ callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    func unbindCallbacks() {
        callbacks = Callbacks()
    }

    func open(_ request: OpenRequest) async throws -> OpenResult {
        guard closeTask == nil else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        let openedSession = try await controller.open(
            request.url,
            startTime: request.startTime,
            startsPaused: request.startsPaused,
            initialRate: request.initialRate,
            sourceTransport: request.sourceTransport,
            initialStereoLayout: Self.engineStereoLayout(for: request.stereoOverride),
            initialProjectionOverride: request.projectionOverride.map {
                Self.engineProjectionOverride(
                    for: $0,
                    horizontalFieldOfViewDegrees: request.horizontalFieldOfViewDegrees
                )
            },
            initialDynamicRangeOverride: request.usesDolbyVisionFallback
                ? .dolbyVisionFallback
                : nil,
            provenance: request.provenance,
            accessRequirement: request.accessRequirement
        )
        guard controller.activeSession === openedSession else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        session = openedSession
        return OpenResult(
            resource: SessionResource(driver: self, session: openedSession),
            mediaKind: openedSession.mediaKind,
            selectedAudioStreamIndex: openedSession.selectedAudioStreamIndex,
            debugSnapshot: openedSession.debugSnapshot()
        )
    }

    func start() throws {
        try controller.start()
    }

    func presentationDidAttach() throws {
        guard let session = attachedSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try controller.presentationDidAttach(session: session)
    }

    func audioOnlyPresentationDidBecomeReady() throws {
        guard let session = attachedSession else {
            throw PlaybackControlError.noActiveMediaSession
        }
        try controller.audioOnlyPresentationDidBecomeReady(session: session)
    }

    func play() throws {
        try controller.play()
    }

    func playWithExternallyManagedFirstVideoFrameDeadline() throws {
        try controller.playWithExternallyManagedFirstVideoFrameDeadline()
    }

    func playAndVerifyRendererGraphContinuity(
        timeout: Duration = .seconds(3)
    ) async throws -> RendererGraphPlaybackContinuity {
        try await controller.playAndVerifyRendererGraphContinuity(timeout: timeout)
    }

    func pause() throws {
        try controller.pause()
    }

    func waitUntilTimelineReadyForControl() async throws {
        try await controller.waitUntilTimelineReadyForControl()
    }

    func seek(
        to time: CMTime,
        after intent: PlaybackAfterSeekIntent
    ) async throws {
        try await seek(to: time, after: Self.engineAfterSeekBehavior(for: intent))
    }

    func seek(
        by offset: CMTime,
        after intent: PlaybackAfterSeekIntent
    ) async throws {
        try await seek(by: offset, after: Self.engineAfterSeekBehavior(for: intent))
    }

    func seek(
        to time: CMTime,
        after behavior: PlaybackAfterSeekBehavior = .preserveCurrentPauseState
    ) async throws {
        try await controller.seek(to: time, after: behavior)
    }

    func seek(
        by offset: CMTime,
        after behavior: PlaybackAfterSeekBehavior = .preserveCurrentPauseState
    ) async throws {
        try await controller.seek(by: offset, after: behavior)
    }

    func stepFrames(by delta: Int) async throws -> CMTime {
        try await controller.stepFrames(by: delta)
    }

    func setRate(_ rate: Float) throws {
        try controller.setRate(rate)
    }

    func setVolume(_ volume: Float) throws {
        try controller.setVolume(volume)
    }

    func setMuted(_ muted: Bool) throws {
        try controller.setMuted(muted)
    }

    func selectAudioTrack(streamIndex: Int) async throws {
        try await controller.selectAudioTrack(streamIndex: streamIndex)
    }

    func selectSubtitleTrack(id: PlaybackSubtitleTrack.ID?) async throws {
        try await controller.selectSubtitleTrack(id: id)
    }

    func addExternalSubtitleSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> [PlaybackSubtitleTrack] {
        try await controller.addExternalSubtitleSource(source)
    }

    func suspendVideoSampleDelivery() async throws {
        try await controller.suspendVideoSampleDelivery()
    }

    func replaceVideoRendererGraph() async throws -> SessionResource {
        let renderer = try await controller.replaceVideoRendererGraph()
        guard let session = attachedSession,
              session.renderer === renderer else {
            throw PlaybackControlError.openTerminatedByCleanup
        }
        return SessionResource(driver: self, session: session)
    }

    func retireDepartingVideoRendererGraph() async {
        await controller.retireDepartingVideoRendererGraph()
    }

    func restartVideoSampleDelivery(
        at time: CMTime,
        after behavior: PlaybackAfterSeekBehavior
    ) async throws {
        try await controller.restartVideoSampleDelivery(at: time, after: behavior)
    }

    func restartVideoSampleDelivery(
        preserving continuity: PlaybackEndedContinuity
    ) async throws {
        try await controller.restartVideoSampleDelivery(preserving: continuity)
    }

    func clearDisplayedVideoImage(forMediaSessionID mediaSessionID: String) async {
        await controller.clearDisplayedVideoImage(forMediaSessionID: mediaSessionID)
    }

    func hush() {
        controller.hush()
    }

    func interruptInFlightOpen() {
        controller.interruptActiveSessionSourceReads()
    }

    func close(clearSource: Bool = true) async {
        if let closeTask {
            await closeTask.value
            return
        }
        let controller = controller
        let task = Task { @MainActor [weak self] in
            await controller.closeAndWait(clearSource: clearSource)
            self?.session = nil
            self?.callbacks = Callbacks()
            self?.unbindControllerCallbacks()
        }
        closeTask = task
        await task.value
    }

    func abandon() {
        controller.abandonActiveSession()
        closeTask = nil
        session = nil
        callbacks = Callbacks()
        unbindControllerCallbacks()
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        attachedSession?.debugSnapshot()
    }

    func displayedArtworkImage() -> CGImage? {
        attachedSession?.displayedArtworkImage()
    }

    func currentTime() -> CMTime? {
        attachedSession?.currentTime()
    }

    func recordRealityKitBinding(entityIdentity: String, active: Bool) {
        attachedSession?.recordRealityKitBinding(
            entityIdentity: entityIdentity,
            active: active
        )
    }

    func recordPresentationBinding(
        realityViewIdentity: String,
        platform: String,
        attached: Bool,
        sceneContainer: String,
        sceneLifecycle: String
    ) {
        attachedSession?.recordPresentationBinding(
            realityViewIdentity: realityViewIdentity,
            platform: platform,
            attached: attached,
            sceneContainer: sceneContainer,
            sceneLifecycle: sceneLifecycle
        )
    }

    func recordPresentationState(_ record: PresentationStateRecord) {
        attachedSession?.recordPresentationState(record)
    }

    #if DEBUG
        func setPlaybackSwitchRendererSampleSink(
            _ sink: PlaybackSwitchRendererSampleSink?
        ) {
            attachedSession?.setPlaybackSwitchRendererSampleSink(sink)
        }

        func capturePlaybackSwitchRendererState() {
            attachedSession?.capturePlaybackSwitchRendererState()
        }

        func debugEvidenceJSON() -> String? {
            controller.debugEvidenceJSON()
        }
    #endif

    func sessionForVerification() -> SampleBufferPlaybackSession? {
        attachedSession
    }

    func attachedResource() -> SessionResource? {
        guard let session = attachedSession else { return nil }
        return SessionResource(driver: self, session: session)
    }

    func owns(_ resource: SessionResource) -> Bool {
        guard resource.driver === self,
              let session = attachedSession else { return false }
        return session.traceID == resource.sessionID
            && session.renderer === resource.renderer
    }

    private func bindControllerCallbacks() {
        controller.onStatusChange = { [weak self] status in
            self?.callbacks.onStatusChange?(status)
        }
        controller.onDiagnosticsChange = { [weak self] diagnostics in
            self?.callbacks.onDiagnosticsChange?(diagnostics)
        }
        controller.onDeliveryContinuityChange = { [weak self] observation in
            self?.callbacks.onDeliveryContinuityChange?(observation)
        }
        controller.onAcceptedVideoFormatRevisionChange = { [weak self] revision in
            self?.callbacks.onAcceptedVideoFormatRevisionChange?(revision)
        }
        controller.onSessionChange = { [weak self] session in
            self?.session = session
        }
        controller.onSubtitleCuesChange = { [weak self] cues in
            self?.callbacks.onSubtitleCuesChange?(cues)
        }
        controller.onSubtitleFrameChange = { [weak self] frame in
            self?.callbacks.onSubtitleFrameChange?(frame)
        }
        controller.onAudioSpectrumFrameChange = { [weak self] frame in
            self?.callbacks.onAudioSpectrumFrameChange?(frame)
        }
    }

    private func unbindControllerCallbacks() {
        controller.onStatusChange = nil
        controller.onDiagnosticsChange = nil
        controller.onDeliveryContinuityChange = nil
        controller.onAcceptedVideoFormatRevisionChange = nil
        controller.onSessionChange = nil
        controller.onSubtitleCuesChange = nil
        controller.onSubtitleFrameChange = nil
        controller.onAudioSpectrumFrameChange = nil
    }

    static func capabilityFacts(from diagnostics: PlaybackDiagnostics) -> PlaybackCapabilityFacts {
        PlaybackCapabilityFacts(
            codecName: diagnostics.codecName,
            sourceIsMultiview: diagnostics.isMVHEVC
                && diagnostics.rendererInputIsMultiview != nil,
            deliveredIsMultiview: diagnostics.rendererInputIsMultiview == true,
            audioRetired: diagnostics.audioRetired,
            audioRetirementReason: diagnostics.audioRetirementReason,
            rendererFailedToDecode: diagnostics.rendererFailedToDecode
        )
    }

    static func activeFailureCause(
        sourceFailure: MediaSourceReadFailure?,
        coreContext: PlaybackCoreActiveFailureContext?
    ) -> PlaybackActiveFailure.Cause? {
        switch coreContext {
        case .sourceRead(let coreFailure):
            if let sourceFailure {
                return switch sourceFailure {
                case .transportInterrupted: .connectionInterrupted
                case .resourceMissing: .sourceFileMissing
                case .accessDenied: .sourceAccessDenied
                case .invalidData: .mediaDataCorrupt
                }
            }
            guard let coreFailure else { return nil }
            return engineFailureCause(coreFailure)
        case .decoder(let coreFailure):
            return engineFailureCause(coreFailure)
        case nil:
            return nil
        }
    }

    private static func engineFailureCause(
        _ coreFailure: PlaybackCoreActiveFailureCause
    ) -> PlaybackActiveFailure.Cause {
        switch coreFailure {
        case .connectionInterrupted: .connectionInterrupted
        case .sourceFileMissing: .sourceFileMissing
        case .sourceAccessDenied: .sourceAccessDenied
        case .mediaDataCorrupt: .mediaDataCorrupt
        case .rendererRequiresFlush: .rendererRequiresFlush
        case .mediaServicesReset: .mediaServicesReset
        case .rendererFailed: .rendererFailed
        }
    }

    private static func engineStereoLayout(
        for stereo: PlaybackModel.StereoLayout?
    ) -> VideoStereoLayout? {
        switch stereo {
        case .mono: .mono
        case .multiview, nil: nil
        case .sideBySide: .sideBySide
        case .topBottom: .overUnder
        }
    }

    private static func engineProjectionOverride(
        for projection: MediaFormatInterpreter.Projection,
        horizontalFieldOfViewDegrees: Int?
    ) -> VideoProjectionOverride {
        switch projection {
        case .flat: .rectilinear
        case .equirectangular180: .halfEquirectangular
        case .equirectangular360: .equirectangular
        case .customAngle:
            .customEquirectangular(
                horizontalFieldOfViewDegrees:
                    MediaFormatInterpreter.effectiveHorizontalFieldOfViewDegrees(
                        for: projection,
                        explicitDegrees: horizontalFieldOfViewDegrees
                    )
            )
        }
    }

    private static func engineAfterSeekBehavior(
        for intent: PlaybackAfterSeekIntent
    ) -> PlaybackAfterSeekBehavior {
        switch intent {
        case .preserveCurrentPlaybackIntent:
            .preserveCurrentPauseState
        case .pause:
            .pause
        case .ended:
            .end
        }
    }
}

extension PlaybackRuntime {
    public convenience init(controller: PlaybackCoreController = PlaybackCoreController()) {
        self.init(
            openingDriver: PlaybackMediaSessionDriver(controller: controller),
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
    }

    convenience init(
        controller: PlaybackCoreController,
        audioSessionLifecycle: PlaybackAudioSessionLifecycle
    ) {
        self.init(
            openingDriver: PlaybackMediaSessionDriver(controller: controller),
            audioSessionLifecycle: audioSessionLifecycle
        )
    }
}
