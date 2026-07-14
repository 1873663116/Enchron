import AVFoundation
import Foundation
import Observation
import PlaybackCore
import RealityKit
import SwiftUI

private struct VisionPresentationCommandError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

struct VisionPresentationObservation {
  let state: [String: Any]
  let displayedPixelBuffer: CVPixelBuffer?
  let renderer: AnyObject?
  let videoEntity: AnyObject?
}

@MainActor
@Observable
final class VisionPlaybackModel {
  let windowPresentationRoot = Entity()
  let dockedPresentationRoot = Entity()
  let panoramaPresentationRoot = Entity()
  let presentation = VisionPresentationCoordinator()

  private(set) var status: PlaybackStatus = .idle
  private(set) var selectedURL: URL?
  private(set) var selectedRoute = PlaybackRoute.appleCompressed
  private(set) var diagnostics = PlaybackDiagnostics()
  private(set) var videoEntity: Entity?
  private(set) var currentSeconds = 0.0
  private(set) var durationSeconds = 0.0
  private(set) var playbackRate: Float = 1
  private(set) var volume: Float = 1
  private(set) var isMuted = false
  private(set) var audioTracks: [PlaybackAudioTrack] = []
  private(set) var selectedAudioStreamIndex: Int?
  private(set) var isMediaTransitioning = false
  private(set) var controlError: String?
  private(set) var videoEntityGeneration: UInt64 = 0
  private(set) var audioSessionConfigured = false
  private(set) var audioSessionActive = false
  private(set) var audioSessionError: String?
  private(set) var audioSessionLastAction = "notConfigured"
  private(set) var immersiveSceneError: String?

  private let core = PlaybackCoreController()
  private let audioSession = AVAudioSession.sharedInstance()
  private var securityScopedURL: URL?
  private var presentationTraceTask: Task<Void, Never>?
  private var progressTask: Task<Void, Never>?
  private var videoEventSubscriptions: [String: [EventSubscription]] = [:]
  private var surfaceUpdateSubscriptions: [String: EventSubscription] = [:]
  private var surfaceUpdateGeneration: [String: UInt64] = [:]
  private var surfaceStableUpdateCount: [String: Int] = [:]
  private var surfaceReadyGeneration: [String: UInt64] = [:]
  private var mediaOperationGeneration: UInt64 = 0
  private var immersiveScene: Entity?
  private var dockingAnchor: Entity?
  private var authoredDockingTransform: Transform?
  private var lastCleanupSnapshot: PlaybackDebugSnapshotV1?
  private var immersiveModeChangeSequence: UInt64 = 0
  private var lastAcknowledgedImmersiveMode: VideoPlayerComponent.ImmersiveViewingMode?
  private var lastAcknowledgedImmersiveModeSurface: VisionSurface?
  private var viewingModeChangeSequence: UInt64 = 0
  private var lastAcknowledgedViewingMode: VideoPlaybackController.ViewingMode?
  private var lastAcknowledgedViewingModeSurface: VisionSurface?
  private var contentTypeChangeSequence: UInt64 = 0
  private var lastAcknowledgedContentType = "none"
  private(set) var lastPresentationRollbackState = "none"
  private(set) var lastPresentationRollbackError: String?

  var presentationFacts: VisionPresentationFacts { presentation.facts }
  var productShape: VisionProductShape { presentation.productShape }
  var isPresentationTransitioning: Bool { presentation.isTransitioning }
  var presentationTransitionError: String? { presentation.transitionError }
  var canIssuePresentationCommand: Bool {
    presentedProductShape != nil && !isMediaTransitioning && !presentation.isTransitioning
  }

  var presentedProductShape: VisionProductShape? {
    guard videoEntity != nil, presentationIsSettled() else { return nil }
    return presentation.productShape
  }

  init() {
    core.onStatusChange = { [weak self] status in
      guard let self else { return }
      self.status = status
      switch status {
      case .ended:
        self.deactivateAudioSession(reason: "ended")
      case .failed:
        self.deactivateAudioSession(reason: "failed")
      default:
        break
      }
    }
    core.onDiagnosticsChange = { [weak self] diagnostics in
      self?.diagnostics = diagnostics
    }
  }

  func openImportedVideo(_ url: URL) async {
    let generation = beginMediaTransition()
    defer { finishMediaTransition(generation) }
    PlaybackTrace.event(
      "model.open.request route=\(selectedRoute.rawValue) file=\(url.lastPathComponent)"
    )
    await closeSessionAndWait()
    guard ownsMediaTransition(generation) else { return }
    if Task.isCancelled {
      releaseSecurityScopedURL()
      selectedURL = nil
      diagnostics = PlaybackDiagnostics()
      resetPlaybackFacts()
      status = .idle
      return
    }
    releaseSecurityScopedURL()
    selectedURL = nil
    diagnostics = PlaybackDiagnostics()
    resetPlaybackFacts()
    let gainedSecurityScope = url.startAccessingSecurityScopedResource()
    if gainedSecurityScope {
      securityScopedURL = url
    }
    PlaybackTrace.event("model.securityScope acquired=\(gainedSecurityScope)")

    status = .loading
    selectedURL = url

    var openedSession: SampleBufferPlaybackSession?
    do {
      let session = try await core.open(
        url,
        route: selectedRoute,
        initialStereoLayout: coreStereoLayout(presentation.facts.stereoLayout),
        initialProjectionOverride: nil,
        provenance: "systemFileImporter",
        accessRequirement: gainedSecurityScope ? "securityScoped" : "notRequired"
      )
      openedSession = session
      guard ownsMediaTransition(generation), !Task.isCancelled,
        core.activeSession === session
      else {
        if core.activeSession === session {
          detachVideoEntity(traceID: session.traceID)
          core.close(clearSource: false)
        }
        if ownsMediaTransition(generation) {
          releaseSecurityScopedURL()
        }
        return
      }

      attachVideoEntity(for: session)
      audioTracks = core.availableAudioTracks
      selectedAudioStreamIndex = session.selectedAudioStreamIndex
      playbackRate = session.preferredPlaybackRate
      volume = session.currentVolume
      isMuted = session.isMuted
      startPresentationTrace(for: session)
    } catch {
      guard ownsMediaTransition(generation) else { return }
      PlaybackTrace.event(
        "model.open.failed error=\(error.localizedDescription)"
      )
      if let openedSession, core.activeSession === openedSession {
        detachVideoEntity(traceID: openedSession.traceID)
        core.close(clearSource: false)
      }
      deactivateAudioSession(reason: "openFailed")
      releaseSecurityScopedURL()
      resetPlaybackFacts()
      status = .failed(error.localizedDescription)
    }
  }

  func selectRoute(_ route: PlaybackRoute) async {
    do {
      try await switchRoute(route)
    } catch {
      if case PlaybackControlError.openTerminatedByCleanup = error { return }
      if !isMediaTransitioning {
        controlError = error.localizedDescription
      }
    }
  }

  private func switchRoute(_ route: PlaybackRoute) async throws {
    guard route != selectedRoute else { return }
    guard let url = selectedURL else {
      selectedRoute = route
      diagnostics.requestedRoute = route.rawValue
      diagnostics.selectedRoute = route.rawValue
      diagnostics.rendererInputKind = route.rendererInputKind.rawValue
      return
    }
    let generation = beginMediaTransition()
    defer { finishMediaTransition(generation) }

    let time = core.activeSession?.currentTime() ?? .zero
    let paused = status == .paused
    PlaybackTrace.event(
      "model.routeSwitch.request from=\(selectedRoute.rawValue) to=\(route.rawValue) "
        + "time=\(time.seconds) paused=\(paused)"
    )
    presentationTraceTask?.cancel()
    presentationTraceTask = nil
    progressTask?.cancel()
    progressTask = nil
    let oldSession = core.activeSession
    if let oldSession {
      traceComponent(event: "component.beforeRouteSwitch", session: oldSession)
      detachVideoEntity(traceID: oldSession.traceID)
    }
    selectedRoute = route
    status = .loading
    selectedURL = url

    var switchedSession: SampleBufferPlaybackSession?
    do {
      let session = try await core.switchRoute(to: route)
      switchedSession = session
      if let oldSession {
        lastCleanupSnapshot = oldSession.debugSnapshot()
      }
      guard ownsMediaTransition(generation), !Task.isCancelled,
        core.activeSession === session
      else {
        if core.activeSession === session {
          detachVideoEntity(traceID: session.traceID)
          core.close(clearSource: false)
        }
        throw PlaybackControlError.openTerminatedByCleanup
      }
      attachVideoEntity(for: session)
      audioTracks = core.availableAudioTracks
      selectedAudioStreamIndex = session.selectedAudioStreamIndex
      playbackRate = session.preferredPlaybackRate
      volume = session.currentVolume
      isMuted = session.isMuted
      startPresentationTrace(for: session)
    } catch {
      guard ownsMediaTransition(generation) else {
        throw PlaybackControlError.openTerminatedByCleanup
      }
      PlaybackTrace.event(
        "model.routeSwitch.failed error=\(error.localizedDescription)"
      )
      if let switchedSession, core.activeSession === switchedSession {
        detachVideoEntity(traceID: switchedSession.traceID)
        core.close(clearSource: false)
      }
      deactivateAudioSession(reason: "routeSwitchFailed")
      resetPlaybackFacts()
      status = .failed(error.localizedDescription)
      throw error
    }
  }

  func play() {
    do {
      try core.play()
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func pause() {
    do {
      try core.pause()
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func seek(to seconds: Double) async {
    let generation = mediaOperationGeneration
    do {
      try await core.seek(to: CMTime(seconds: seconds, preferredTimescale: 60_000))
      guard ownsMediaTransition(generation) else { return }
      currentSeconds = seconds
      controlError = nil
    } catch {
      guard ownsMediaTransition(generation) else { return }
      if case PlaybackControlError.seekSuperseded = error { return }
      controlError = error.localizedDescription
    }
  }

  func setRate(_ rate: Float) {
    do {
      try core.setRate(rate)
      playbackRate = rate
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func setVolume(_ value: Float) {
    do {
      try core.setVolume(value)
      volume = value
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func setMuted(_ muted: Bool) {
    do {
      try core.setMuted(muted)
      isMuted = muted
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func reopen() async {
    guard selectedURL != nil else { return }
    let generation = beginMediaTransition()
    defer { finishMediaTransition(generation) }
    PlaybackTrace.event("model.reopen.request route=\(selectedRoute.rawValue)")
    presentationTraceTask?.cancel()
    presentationTraceTask = nil
    progressTask?.cancel()
    progressTask = nil
    let oldSession = core.activeSession
    if let oldSession {
      traceComponent(event: "component.beforeReopen", session: oldSession)
      detachVideoEntity(traceID: oldSession.traceID)
    }
    status = .loading

    var reopenedSession: SampleBufferPlaybackSession?
    do {
      let session = try await core.reopen()
      reopenedSession = session
      if let oldSession {
        lastCleanupSnapshot = oldSession.debugSnapshot()
      }
      guard ownsMediaTransition(generation), !Task.isCancelled,
        core.activeSession === session
      else {
        if core.activeSession === session {
          detachVideoEntity(traceID: session.traceID)
          core.close(clearSource: false)
        }
        return
      }
      attachVideoEntity(for: session)
      audioTracks = core.availableAudioTracks
      selectedAudioStreamIndex = session.selectedAudioStreamIndex
      playbackRate = session.preferredPlaybackRate
      volume = session.currentVolume
      isMuted = session.isMuted
      startPresentationTrace(for: session)
      PlaybackTrace.event("model.reopen.opened id=\(session.traceID)")
    } catch {
      guard ownsMediaTransition(generation) else { return }
      if let reopenedSession, core.activeSession === reopenedSession {
        detachVideoEntity(traceID: reopenedSession.traceID)
        core.close(clearSource: false)
      }
      deactivateAudioSession(reason: "reopenFailed")
      resetPlaybackFacts()
      controlError = error.localizedDescription
      status = .failed(error.localizedDescription)
      PlaybackTrace.event("model.reopen.failed error=\(error.localizedDescription)")
    }
  }

  func selectAudioTrack(_ streamIndex: Int) {
    do {
      try core.selectAudioTrack(streamIndex: streamIndex)
      selectedAudioStreamIndex = streamIndex
      controlError = nil
    } catch {
      controlError = error.localizedDescription
    }
  }

  func closeAndWait() async {
    PlaybackTrace.event("model.closeAndWait.request")
    invalidateMediaTransitions()
    await closeSessionAndWait()
    presentation.clearVideoBinding()
    releaseSecurityScopedURL()
    status = .idle
    selectedURL = nil
    diagnostics = PlaybackDiagnostics()
    resetPlaybackFacts()
    PlaybackTrace.event("model.closeAndWait.end")
  }

  func closeMedia(actions: VisionPresentationActions) async {
    let wasPanorama = presentation.facts.sceneContent == .blackPanorama
    await closeAndWait()
    if wasPanorama {
      await presentation.closePanoramaSpaceIfSceneWasNotRequested(actions: actions)
      updateImmersiveSceneVisibility()
    }
    recordPresentationState(phase: "mediaClosed")
  }

  @discardableResult
  func performPresentationCommand(
    _ command: PresentationCommand,
    actions: VisionPresentationActions
  ) async -> PresentationCommandResult {
    guard presentation.begin(command) else {
      return PresentationCommandResult(
        command: command,
        succeeded: false,
        facts: presentation.facts,
        error: "presentationBusy"
      )
    }
    lastPresentationRollbackState = "notNeeded"
    lastPresentationRollbackError = nil
    let snapshot = presentation.facts
    let windowWasOpen = presentation.isWindowOpen
    let sceneWasOpen = presentation.isSceneOpen
    do {
      switch command {
      case .openPlaybackWindow:
        await presentation.openPlaybackWindow(actions: actions)
        try require(presentation.isWindowOpen, fallback: "playbackWindowDidNotOpen")
        if videoEntity != nil, presentation.facts.placement == .window {
          if videoEntity?.parent !== windowPresentationRoot {
            moveVideoEntity(to: windowPresentationRoot)
          }
          try await awaitPresentationBinding()
          try await awaitPresentationSettled()
        }
      case .closePlaybackWindow:
        await presentation.closePlaybackWindow(actions: actions)
        try require(
          presentation.windowLifecycle == .closed,
          fallback: "playbackWindowDidNotClose"
        )
      case .openScene:
        await presentation.openScene(actions: actions)
        updateImmersiveSceneVisibility()
        try await awaitCustomSceneVisible()
      case .closeScene:
        await presentation.closeScene(actions: actions)
        updateImmersiveSceneVisibility()
        try require(
          presentation.facts.sceneLifecycle == .closed,
          fallback: "customSceneDidNotClose"
        )
      case .showWindow:
        try await showWindow(actions: actions)
      case .dock:
        try await showDocked(actions: actions)
      case .showPanorama:
        try await showPanorama(actions: actions)
      case .setProjection(let projection):
        try await setProjection(projection, actions: actions)
      case .setStereo(let layout):
        try await setStereo(layout)
      }
      presentation.finish()
      recordPresentationState(phase: "active", transitionResult: presentation.productShape.rawValue)
      return PresentationCommandResult(
        command: command,
        succeeded: true,
        facts: presentation.facts,
        error: nil
      )
    } catch {
      let finalError = await rollbackPresentation(
        command: command,
        snapshot: snapshot,
        windowWasOpen: windowWasOpen,
        sceneWasOpen: sceneWasOpen,
        actions: actions,
        error: error.localizedDescription
      )
      return PresentationCommandResult(
        command: command,
        succeeded: false,
        facts: presentation.facts,
        error: finalError
      )
    }
  }

  @discardableResult
  func presentationSurfaceDidAttach(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    guard presentation.surfaceDidAttach(surface, attachment: attachment) else {
      recordPresentationState(
        phase: "unexpectedSurfaceAttach",
        transitionError: presentation.transitionError
      )
      PlaybackTrace.event("presentation.surface.reject surface=\(surface.rawValue)")
      return false
    }
    updateImmersiveSceneVisibility()
    if surface == activeSurface,
      videoEntity != nil,
      videoEntity?.parent !== activePresentationRoot
    {
      moveVideoEntity(to: activePresentationRoot)
    }
    recordPresentationState(phase: "surfaceAttached")
    PlaybackTrace.event("presentation.surface.attach surface=\(surface.rawValue)")
    return true
  }

  func presentationSurfaceContentDidAttach(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) async {
    guard presentation.surfaceIsActive(surface, attachment: attachment),
      surface == activeSurface
    else { return }
    if let session = core.activeSession,
      let binding = session.debugSnapshot().presentationBinding,
      binding.entityAttached,
      binding.realityViewIdentity == surface.rawValue,
      binding.mediaSessionID == session.traceID
    {
      return
    }
    do {
      _ = try configurePresentationBindingIfAvailable()
      recordPresentationState(phase: "surfaceContentAttached")
      PlaybackTrace.event("presentation.surface.contentReady surface=\(surface.rawValue)")
    } catch {
      controlError = error.localizedDescription
    }
  }

  func subscribeToSurfaceUpdates(
    in content: RealityViewContent,
    surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) {
    let key = "\(surface.rawValue)|\(attachment.identity)"
    guard surfaceUpdateSubscriptions[key] == nil else { return }
    surfaceUpdateSubscriptions[key] = content.subscribe(to: SceneEvents.Update.self) {
      [weak self] _ in
      Task { @MainActor in
        await self?.presentationSurfaceDidUpdate(
          surface,
          attachment: attachment,
          key: key
        )
      }
    }
  }

  private func presentationSurfaceDidUpdate(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment,
    key: String
  ) async {
    let generation = videoEntityGeneration
    if surfaceUpdateGeneration[key] != generation {
      surfaceUpdateGeneration[key] = generation
      surfaceStableUpdateCount[key] = 1
      surfaceReadyGeneration.removeValue(forKey: key)
      return
    }
    surfaceStableUpdateCount[key, default: 0] += 1
    guard surfaceStableUpdateCount[key, default: 0] >= 4,
      surfaceReadyGeneration[key] != generation
    else { return }
    surfaceReadyGeneration[key] = generation
    await presentationSurfaceContentDidAttach(surface, attachment: attachment)
  }

  func presentationSurfaceDidDetach(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) {
    guard presentation.surfaceDidDetach(surface, attachment: attachment) else {
      PlaybackTrace.event(
        "presentation.surface.ignoreDetach surface=\(surface.rawValue) attachment=\(attachment.identity)"
      )
      return
    }
    cancelVideoPlayerSubscriptions(surface: surface, attachment: attachment)
    surfaceUpdateSubscriptions.removeValue(
      forKey: "\(surface.rawValue)|\(attachment.identity)"
    )
    let surfaceKey = "\(surface.rawValue)|\(attachment.identity)"
    surfaceUpdateGeneration.removeValue(forKey: surfaceKey)
    surfaceStableUpdateCount.removeValue(forKey: surfaceKey)
    surfaceReadyGeneration.removeValue(forKey: surfaceKey)
    if activeSurface == surface {
      detachCurrentPresentationBinding()
    }
    updateImmersiveSceneVisibility()
    recordPresentationState(phase: "surfaceDetached")
    PlaybackTrace.event("presentation.surface.detach surface=\(surface.rawValue)")
  }

  func presentationSurfaceIsActive(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    presentation.surfaceIsActive(surface, attachment: attachment)
  }

  private func showWindow(
    actions: VisionPresentationActions,
    targetProjection: VisionProjection? = nil
  ) async throws {
    guard videoEntity != nil else { throw VisionPresentationCommandError("videoEntityMissing") }
    let sourceWasPanorama = presentation.facts.sceneContent == .blackPanorama
    try await VisionPresentationTransaction.presentTarget(
      prepareTarget: {
        self.presentation.setPhase(.openingTarget)
        await self.presentation.openPlaybackWindow(actions: actions)
        try self.require(
          self.presentation.windowLifecycle == .open,
          fallback: "playbackWindowDidNotOpen"
        )
      },
      migrateAndBind: {
        self.presentation.setPhase(.migratingBinding)
        self.presentation.setPlacement(.window)
        if self.videoEntity?.parent !== self.windowPresentationRoot {
          self.moveVideoEntity(to: self.windowPresentationRoot, configureComponent: false)
        }
        try await self.awaitPresentationBinding()
      },
      requestAndAwaitMode: {
        if let targetProjection {
          self.presentation.setProjection(targetProjection)
          self.configurePresenter(for: targetProjection)
        }
        self.presentation.setPhase(.waitingForModeChange)
        if self.presentation.facts.projection.isPanoramic {
          try await self.requestImmersiveViewingMode(.portal)
        }
      },
      awaitTargetSettled: {
        try await self.awaitPresentationSettled()
      },
      closeSource: {
        guard sourceWasPanorama else { return }
        self.presentation.setPhase(.restoringScene)
        await self.presentation.closePanoramaSpaceIfSceneWasNotRequested(actions: actions)
        self.updateImmersiveSceneVisibility()
        if self.presentation.facts.customSceneRequestedOpen {
          try self.require(
            self.presentation.isSceneOpen
              && self.presentation.facts.sceneContent == .customScene,
            fallback: "customSceneDidNotRestore"
          )
          try await self.awaitCustomSceneVisible()
        } else {
          try self.require(
            self.presentation.facts.sceneLifecycle == .closed,
            fallback: "panoramaSpaceDidNotClose"
          )
        }
      }
    )
  }

  private func showDocked(actions: VisionPresentationActions) async throws {
    guard videoEntity != nil else { throw VisionPresentationCommandError("videoEntityMissing") }
    try require(
      presentation.facts.sceneLifecycle == .open
        && presentation.facts.sceneContent == .customScene,
      fallback: "customSceneNotReadyForDock"
    )
    try await awaitDockingTargetReady()
    try await VisionPresentationTransaction.presentTarget(
      prepareTarget: {},
      migrateAndBind: {
        self.presentation.setPhase(.migratingBinding)
        self.presentation.setProjection(.flat)
        self.presentation.setPlacement(.docked)
        self.configurePresenter(for: .flat)
        self.moveVideoEntity(to: self.dockedPresentationRoot, configureComponent: false)
        try await self.awaitPresentationBinding()
      },
      requestAndAwaitMode: {
        self.presentation.setPhase(.waitingForModeChange)
      },
      awaitTargetSettled: {
        try await self.awaitPresentationSettled()
      },
      closeSource: {
        await self.presentation.closePlaybackWindow(actions: actions)
        try self.require(
          self.presentation.windowLifecycle == .closed,
          fallback: "sourcePlaybackWindowDidNotClose"
        )
      }
    )
  }

  private func showPanorama(
    actions: VisionPresentationActions,
    targetProjection: VisionProjection? = nil
  ) async throws {
    guard videoEntity != nil else { throw VisionPresentationCommandError("videoEntityMissing") }
    try require(
      effectiveProjectionIsPanoramic,
      fallback: "immersiveProjectionMetadataMissing"
    )
    try require(
      presentation.facts.projection.isPanoramic || targetProjection?.isPanoramic == true,
      fallback: "panoramicProjectionNotSelected"
    )
    try await VisionPresentationTransaction.presentTarget(
      prepareTarget: {
        self.presentation.setPhase(.openingTarget)
        await self.presentation.openPanoramaSpace(actions: actions)
        self.updateImmersiveSceneVisibility()
        try self.require(
          self.presentation.isSceneOpen
            && self.presentation.facts.sceneContent == .blackPanorama,
          fallback: "panoramaSpaceDidNotOpen"
        )
      },
      migrateAndBind: {
        self.presentation.setPhase(.migratingBinding)
        self.presentation.setPlacement(.panorama)
        self.moveVideoEntity(to: self.panoramaPresentationRoot, configureComponent: false)
        try await self.awaitPresentationBinding()
      },
      requestAndAwaitMode: {
        if let targetProjection {
          self.presentation.setProjection(targetProjection)
          self.configurePresenter(for: targetProjection)
        }
        self.presentation.setPhase(.waitingForModeChange)
        try await self.requestImmersiveViewingMode(.progressive)
      },
      awaitTargetSettled: {
        try await self.awaitPresentationSettled()
      },
      closeSource: {
        await self.presentation.closePlaybackWindow(actions: actions)
        try self.require(
          self.presentation.windowLifecycle == .closed,
          fallback: "sourcePlaybackWindowDidNotClose"
        )
      }
    )
  }

  private func setProjection(
    _ projection: VisionProjection,
    actions: VisionPresentationActions
  ) async throws {
    guard let session = core.activeSession else {
      throw VisionPresentationCommandError("mediaSessionMissing")
    }
    let previousProjection = presentation.facts.projection
    let previousProjectionOverride = core.selectedProjectionOverride
    do {
      try await applyProjectionMetadata(for: projection)
      switch (projection, presentation.facts.placement) {
      case (.sourcePanoramic, .docked):
        try await showPanorama(actions: actions, targetProjection: projection)
      case (.flat, .panorama):
        try await showWindow(actions: actions, targetProjection: projection)
      case (_, .window):
        presentation.setProjection(projection)
        configurePresenter(for: projection)
        try await showWindow(actions: actions)
      case (.flat, .docked):
        presentation.setProjection(.flat)
        configurePresenter(for: .flat)
        try await awaitPresentationSettled()
      case (.sourcePanoramic, .panorama):
        presentation.setProjection(.sourcePanoramic)
        configurePresenter(for: .sourcePanoramic)
        try await requestImmersiveViewingMode(.progressive)
        try await awaitPresentationSettled()
      }
    } catch let commandError {
      if core.activeSession === session {
        do {
          try await restoreProjectionOverride(previousProjectionOverride)
          presentation.setProjection(previousProjection)
          configurePresenter(for: previousProjection)
        } catch let rollbackError {
          throw VisionPresentationCommandError(
            "projectionRollbackFailed.\(rollbackError.localizedDescription); "
              + "command=\(commandError.localizedDescription)"
          )
        }
      }
      throw commandError
    }
  }

  private func applyProjectionMetadata(for projection: VisionProjection) async throws {
    switch projection {
    case .flat:
      if core.selectedProjectionOverride != nil {
        _ = try await core.clearProjectionOverride()
      }
    case .sourcePanoramic:
      if sourceHasEquirectangularProjection {
        if core.selectedProjectionOverride != nil {
          _ = try await core.clearProjectionOverride()
        }
      } else if core.selectedProjectionOverride != .equirectangular {
        _ = try await core.setProjectionOverride(.equirectangular)
      }
    }
  }

  private func restoreProjectionOverride(
    _ projection: VideoProjectionOverride?
  ) async throws {
    if let projection {
      if core.selectedProjectionOverride != projection {
        _ = try await core.setProjectionOverride(projection)
      }
    } else if core.selectedProjectionOverride != nil {
      _ = try await core.clearProjectionOverride()
    }
  }

  private func setStereo(_ layout: VisionStereoLayout) async throws {
    guard videoEntity != nil, let session = core.activeSession else {
      throw VisionPresentationCommandError("videoEntityMissing")
    }
    let previousOverride = core.selectedStereoLayout
    let previousPresentationLayout = presentation.facts.stereoLayout
    let targetLayout = coreStereoLayout(layout)
    let expectedViewingMode: VideoPlaybackController.ViewingMode =
      layout.isStereo ? .stereo : .mono

    do {
      let revision = try await core.setStereoLayout(targetLayout)
      try requireEffectiveStereoLayout(targetLayout, revision: revision)
      try await requestViewingMode(expectedViewingMode)
      presentation.setStereo(layout)
      try await awaitPresentationSettled()
    } catch let commandError {
      if core.activeSession === session {
        do {
          if let previousOverride {
            _ = try await core.setStereoLayout(previousOverride)
          } else {
            _ = try await core.clearStereoLayoutOverride()
          }
          try await requestViewingMode(
            previousPresentationLayout.isStereo ? .stereo : .mono
          )
        } catch let rollbackError {
          throw VisionPresentationCommandError(
            "stereoRollbackFailed.\(rollbackError.localizedDescription); "
              + "command=\(commandError.localizedDescription)"
          )
        }
      }
      throw commandError
    }
  }

  private func coreStereoLayout(_ layout: VisionStereoLayout) -> VideoStereoLayout {
    switch layout {
    case .mono: .mono
    case .sideBySide: .sideBySide
    case .overUnder: .overUnder
    }
  }

  private func requireEffectiveStereoLayout(
    _ layout: VideoStereoLayout,
    revision: UInt64
  ) throws {
    guard let sample = core.activeSession?.debugSnapshot().lastVideoSample,
      sample.formatRevision == revision
    else {
      throw VisionPresentationCommandError("stereoSampleRevisionMissing")
    }
    let packing = sample.formatSignaling.viewPackingKind.value?.lowercased() ?? ""
    switch layout {
    case .mono:
      try require(packing.isEmpty, fallback: "stereoMonoPackingStillPresent")
      try require(
        sample.formatSignaling.hasLeftStereoEyeView.value == false
          && sample.formatSignaling.hasRightStereoEyeView.value == false,
        fallback: "stereoMonoEyeFlagsMismatch"
      )
    case .sideBySide:
      try require(
        packing.contains("side")
          && sample.formatSignaling.hasLeftStereoEyeView.value == true
          && sample.formatSignaling.hasRightStereoEyeView.value == true,
        fallback: "stereoSideBySideSignalingMismatch"
      )
    case .overUnder:
      try require(
        (packing.contains("over") || packing.contains("top"))
          && sample.formatSignaling.hasLeftStereoEyeView.value == true
          && sample.formatSignaling.hasRightStereoEyeView.value == true,
        fallback: "stereoOverUnderSignalingMismatch"
      )
    }
  }

  func immersiveSceneEntity() async -> Entity? {
    if let immersiveScene { return immersiveScene }

    immersiveSceneError = nil
    do {
      let scene = try await Entity(named: "world")
      guard let authoredScreen = scene.findEntity(named: "screen"),
        let parent = authoredScreen.parent
      else {
        throw VisionPresentationCommandError("immersiveScene.screenAnchorMissing")
      }
      let screenAnchor = Entity()
      screenAnchor.name = "screen"
      screenAnchor.transform = authoredScreen.transform
      authoredDockingTransform = authoredScreen.transform
      authoredScreen.removeFromParent()
      parent.addChild(screenAnchor)
      screenAnchor.addChild(dockedPresentationRoot)
      dockingAnchor = screenAnchor
      immersiveScene = scene
      updateImmersiveSceneVisibility()
      PlaybackTrace.event(
        "immersiveScene.loaded name=world entity=\(PlaybackTrace.identity(scene))"
      )
      return scene
    } catch {
      immersiveSceneError = error.localizedDescription
      PlaybackTrace.event(
        "immersiveScene.failed name=world error=\(error.localizedDescription)"
      )
      return nil
    }
  }

  func updateImmersiveSceneVisibility() {
    immersiveScene?.isEnabled = presentation.facts.sceneContent == .customScene
    panoramaPresentationRoot.isEnabled = presentation.facts.sceneContent == .blackPanorama
  }

  func subscribeToVideoPlayerEvents(
    in content: RealityViewContent,
    surface: VisionSurface,
    attachment: VisionSurfaceAttachment,
    root: Entity
  ) {
    guard let entity = videoEntity,
      entity.parent === root,
      let session = core.activeSession
    else { return }
    let entityIdentity = PlaybackTrace.identity(entity)
    let sessionID = session.traceID
    let subscriptionKey =
      "\(surface.rawValue)|\(attachment.identity)|\(sessionID)|\(entityIdentity)"
    guard videoEventSubscriptions[subscriptionKey] == nil else { return }
    var subscriptions = [EventSubscription]()

    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.ImmersiveViewingModeWillTransition.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.recordPresentationState(
            phase: "componentWillTransition",
            transitionResult:
              "\(String(describing: event.previousMode))->\(String(describing: event.currentMode))"
          )
        }
      })
    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.ImmersiveViewingModeDidChange.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.immersiveModeChangeSequence &+= 1
          self?.lastAcknowledgedImmersiveMode = event.currentMode
          self?.lastAcknowledgedImmersiveModeSurface = surface
          self?.recordPresentationState(
            phase: "componentModeChanged",
            transitionResult:
              "\(String(describing: event.previousMode))->\(String(describing: event.currentMode))"
          )
        }
      })
    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.ImmersiveViewingModeDidTransition.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.recordPresentationState(
            phase: "componentDidTransition",
            transitionResult:
              "\(String(describing: event.previousMode))->\(String(describing: event.currentMode))"
          )
        }
      })
    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.ViewingModeDidChange.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.viewingModeChangeSequence &+= 1
          self?.lastAcknowledgedViewingMode = event.currentViewingMode
          self?.lastAcknowledgedViewingModeSurface = surface
          self?.recordPresentationState(
            phase: "viewingModeChanged",
            transitionResult:
              "\(String(describing: event.previousViewingMode))->\(String(describing: event.currentViewingMode))"
          )
        }
      })
    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.RenderingStatusDidChange.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.recordPresentationState(
            phase: "renderingStatusChanged",
            transitionResult:
              "\(String(describing: event.previousStatus))->\(String(describing: event.currentStatus))"
          )
        }
      })
    subscriptions.append(
      content.subscribe(
        to: VideoPlayerEvents.ContentTypeDidChange.self,
        on: entity
      ) { [weak self] event in
        Task { @MainActor in
          guard
            self?.eventBelongsToCurrentEntity(
              entityIdentity: entityIdentity,
              sessionID: sessionID,
              surface: surface,
              attachment: attachment
            ) == true
          else { return }
          self?.contentTypeChangeSequence &+= 1
          self?.lastAcknowledgedContentType = String(describing: event.contentType)
          self?.recordPresentationState(
            phase: "contentTypeChanged",
            transitionResult: String(describing: event.contentType)
          )
        }
      })
    videoEventSubscriptions[subscriptionKey] = subscriptions
  }

  private func cancelVideoPlayerSubscriptions(
    surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) {
    let prefix = "\(surface.rawValue)|\(attachment.identity)|"
    let keys = videoEventSubscriptions.keys.filter {
      $0.hasPrefix(prefix)
    }
    for key in keys {
      videoEventSubscriptions.removeValue(forKey: key)?.forEach { $0.cancel() }
    }
  }

  private func cancelAllVideoPlayerSubscriptions() {
    for subscriptions in videoEventSubscriptions.values {
      subscriptions.forEach { $0.cancel() }
    }
    videoEventSubscriptions.removeAll()
  }

  private func hasVideoPlayerSubscription(on surface: VisionSurface) -> Bool {
    guard let session = core.activeSession, let videoEntity,
      let attachment = presentation.activeAttachment(for: surface)
    else { return false }
    let prefix = "\(surface.rawValue)|\(attachment.identity)|"
    let suffix = "|\(session.traceID)|\(PlaybackTrace.identity(videoEntity))"
    return videoEventSubscriptions.keys.contains {
      $0.hasPrefix(prefix) && $0.hasSuffix(suffix)
    }
  }

  private func eventBelongsToCurrentEntity(
    entityIdentity: String,
    sessionID: String,
    surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    guard core.activeSession?.traceID == sessionID,
      PlaybackTrace.identity(videoEntity) == entityIdentity,
      activeSurface == surface,
      presentation.surfaceIsActive(surface, attachment: attachment)
    else { return false }
    return true
  }

  func presentationIsSettled() -> Bool {
    switch presentation.facts.placement {
    case .window:
      guard presentation.isWindowOpen else { return false }
    case .docked:
      guard presentation.isSceneOpen,
        presentation.facts.sceneContent == .customScene,
        immersiveScene != nil,
        immersiveScene?.isEnabled == true,
        panoramaPresentationRoot.isEnabled == false,
        dockingAnchor != nil,
        dockingAnchor?.components[ModelComponent.self] == nil,
        dockedPresentationRoot.parent === dockingAnchor,
        dockingAnchor?.transform == authoredDockingTransform
      else { return false }
    case .panorama:
      guard presentation.isSceneOpen,
        presentation.facts.sceneContent == .blackPanorama,
        panoramaPresentationRoot.isEnabled,
        immersiveScene?.isEnabled != true
      else { return false }
    }
    guard selectedURL != nil else { return true }
    guard let entity = videoEntity,
      entity.parent === activePresentationRoot,
      rendererIsBoundToActivePresenter,
      let binding = core.activeSession?.debugSnapshot().presentationBinding,
      binding.entityAttached,
      binding.mediaSessionID == core.activeSession?.traceID,
      binding.realityViewIdentity == activeSurface.rawValue,
      binding.sceneContainer.value
        == (activeSurface == .playbackWindow
          ? VisionSceneID.playbackWindow : VisionSceneID.playbackSpace)
    else { return false }

    if presentation.facts.projection.isPanoramic {
      guard let component = entity.components[VideoPlayerComponent.self],
        entity.components[ModelComponent.self] == nil,
        component.currentRenderingStatus == .ready,
        hasVideoPlayerSubscription(on: activeSurface)
      else { return false }
      let expectedImmersiveMode = immersiveViewingMode(for: presentation.facts.placement)
      let expectedViewingMode: VideoPlaybackController.ViewingMode =
        presentation.facts.stereoLayout.isStereo ? .stereo : .mono
      guard effectiveProjectionIsPanoramic else { return false }
      guard component.desiredImmersiveViewingMode == expectedImmersiveMode,
        component.immersiveViewingMode == expectedImmersiveMode,
        component.desiredViewingMode == expectedViewingMode,
        component.viewingMode == expectedViewingMode
      else { return false }
    } else {
      guard entity.components[VideoPlayerComponent.self] == nil,
        entity.components[ModelComponent.self] != nil,
        let material = planarVideoMaterial,
        material.controller.currentViewingMode
          == (presentation.facts.stereoLayout.isStereo ? .stereo : .mono)
      else { return false }
    }
    return true
  }

  private var activePresentationRoot: Entity {
    presentationRoot(for: presentation.facts.placement)
  }

  private func presentationRoot(for placement: VisionPlaybackPlacement) -> Entity {
    switch placement {
    case .window:
      windowPresentationRoot
    case .docked:
      dockedPresentationRoot
    case .panorama:
      panoramaPresentationRoot
    }
  }

  private var activeSurface: VisionSurface {
    presentationSurface(for: presentation.facts.placement)
  }

  private func presentationSurface(for placement: VisionPlaybackPlacement) -> VisionSurface {
    placement == .window ? .playbackWindow : .scene
  }

  private func waitUntil(
    timeout: Duration,
    condition: @escaping @MainActor () -> Bool
  ) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return condition()
  }

  func presentationStateSnapshot() -> [String: Any] {
    makePresentationStateSnapshot(
      displayedPixelBuffer: core.activeSession?.renderer.displayedPixelBuffer()
    )
  }

  func presentationObservation() -> VisionPresentationObservation {
    let session = core.activeSession
    let displayedPixelBuffer = session?.renderer.displayedPixelBuffer()
    return VisionPresentationObservation(
      state: makePresentationStateSnapshot(displayedPixelBuffer: displayedPixelBuffer),
      displayedPixelBuffer: displayedPixelBuffer,
      renderer: session?.renderer,
      videoEntity: videoEntity
    )
  }

  private func makePresentationStateSnapshot(
    displayedPixelBuffer: CVPixelBuffer?
  ) -> [String: Any] {
    let component = videoEntity?.components[VideoPlayerComponent.self]
    let planarMaterial = planarVideoMaterial
    let parent = videoEntity?.parent
    let session = core.activeSession
    let debug = session?.debugSnapshot()
    let projection =
      debug?.lastVideoSample?.formatSignaling.projectionKind.value
      ?? debug?.providerOpen?.formatSignaling.projectionKind.value
    let binding = debug?.presentationBinding
    let presentationState = debug?.presentationState
    let rendererState = debug?.rendererState
    let audioRendererState = debug?.audioRendererState
    let effectiveSignaling = debug?.lastVideoSample?.formatSignaling
    let detectedSignaling = debug?.providerOpen?.formatSignaling
    let cleanup = lastCleanupSnapshot
    return [
      "route": session?.route.rawValue ?? "none",
      "selectedRoute": selectedRoute.rawValue,
      "source": debug?.mediaSession?.sourceSummary ?? "none",
      "projectionKind": projection ?? "none",
      "detectedProjectionKind": detectedSignaling?.projectionKind.value ?? "none",
      "effectiveProjectionKind": effectiveSignaling?.projectionKind.value ?? "none",
      "productShape": presentedProductShape?.rawValue ?? "none",
      "candidateProductShape": presentation.productShape.rawValue,
      "projection": presentation.facts.projection.rawValue,
      "placement": presentation.facts.placement.rawValue,
      "stereoLayout": presentation.facts.stereoLayout.rawValue,
      "sceneContent": presentation.facts.sceneContent?.rawValue ?? "none",
      "customSceneRequestedOpen": presentation.facts.customSceneRequestedOpen,
      "usesSystemDocking": false,
      "immersiveSpaceResult": presentation.immersiveOpenResult,
      "parentIsWindowRoot": parent === windowPresentationRoot,
      "parentIsDockedRoot": parent === dockedPresentationRoot,
      "parentIsPanoramaRoot": parent === panoramaPresentationRoot,
      "windowLifecycle": presentation.windowLifecycle.stateName,
      "sceneLifecycle": presentation.facts.sceneLifecycle.stateName,
      "presentationPhase": presentation.state.phase,
      "immersiveSceneLoaded": immersiveScene != nil,
      "immersiveSceneEnabled": immersiveScene?.isEnabled ?? false,
      "panoramaRootEnabled": panoramaPresentationRoot.isEnabled,
      "immersiveSceneError": immersiveSceneError ?? "none",
      "immersiveSceneEntityIdentity": PlaybackTrace.identity(immersiveScene),
      "presentationSettled": presentationIsSettled(),
      "presentationBindingAttached": binding?.entityAttached ?? false,
      "realityKitBindingActive": debug?.realityKitBinding?.active ?? false,
      "presentationGeometry": component != nil ? "immersive" : (planarMaterial != nil ? "planar" : "none"),
      "planarMeshActive": videoEntity?.components[ModelComponent.self] != nil,
      "desiredImmersiveViewingMode": component.map {
        String(describing: $0.desiredImmersiveViewingMode)
      } ?? "missing",
      "actualImmersiveViewingMode": component?.immersiveViewingMode.map {
        String(describing: $0)
      } ?? "none",
      "immersiveModeChangeSequence": immersiveModeChangeSequence,
      "lastAcknowledgedImmersiveMode": lastAcknowledgedImmersiveMode.map {
        String(describing: $0)
      } ?? "none",
      "lastAcknowledgedImmersiveModeSurface": lastAcknowledgedImmersiveModeSurface?.rawValue
        ?? "none",
      "desiredViewingMode": component.map { String(describing: $0.desiredViewingMode) }
        ?? planarMaterial.map { String(describing: $0.controller.preferredViewingMode) }
        ?? "missing",
      "actualViewingMode": component?.viewingMode.map { String(describing: $0) }
        ?? planarMaterial?.controller.currentViewingMode.map { String(describing: $0) }
        ?? "none",
      "viewingModeChangeSequence": viewingModeChangeSequence,
      "lastAcknowledgedViewingMode": lastAcknowledgedViewingMode.map {
        String(describing: $0)
      } ?? "none",
      "lastAcknowledgedViewingModeSurface": lastAcknowledgedViewingModeSurface?.rawValue
        ?? "none",
      "entityScale": Double(videoEntity?.scale.x ?? -1),
      "entityPosition": videoEntity.map {
        "\($0.position.x),\($0.position.y),\($0.position.z)"
      } ?? "none",
      "videoEntityIdentity": PlaybackTrace.identity(videoEntity),
      "rendererIdentity": PlaybackTrace.identity(session?.renderer),
      "rendererGraphID": rendererState?.graphID ?? "none",
      "rendererSynchronizerIdentity": rendererState?.synchronizerIdentity ?? "none",
      "rendererMatchesSession": rendererIsBoundToActivePresenter,
      "rendererStatus": String(describing: session?.renderer.status),
      "rendererError": session?.renderer.error?.localizedDescription ?? "none",
      "componentRenderingStatus": component.map {
        String(describing: $0.currentRenderingStatus)
      } ?? (planarMaterial != nil ? "ready" : "missing"),
      "displayedPixelBuffer": displayedPixelBuffer != nil,
      "displayedPixelBufferIdentity": PlaybackTrace.identity(displayedPixelBuffer),
      "sampleCount": debug?.sampleCount ?? 0,
      "streamEpoch": debug?.streamEpoch ?? 0,
      "rendererFlushCount": rendererState?.flushCount ?? 0,
      "effectiveFormatRevision": debug?.lastVideoSample?.formatRevision ?? 0,
      "detectedViewPackingKind": detectedSignaling?.viewPackingKind.value ?? "none",
      "effectiveViewPackingKind": effectiveSignaling?.viewPackingKind.value ?? "none",
      "effectiveHasLeftStereoEyeView": effectiveSignaling?.hasLeftStereoEyeView.value ?? false,
      "effectiveHasRightStereoEyeView": effectiveSignaling?.hasRightStereoEyeView.value ?? false,
      "coreEffectiveStereoLayout": session?.effectiveStereoLayout.rawValue ?? "none",
      "audioSampleBufferCount": debug?.audioSampleBufferCount ?? 0,
      "audioTrackIndices": audioTracks.map(\.streamIndex),
      "selectedAudioStreamIndex": selectedAudioStreamIndex ?? -1,
      "audioRendererSampleBufferCount": audioRendererState?.enqueuedSampleBufferCount ?? 0,
      "audioRendererMediaSessionID": audioRendererState?.mediaSessionID ?? "none",
      "audioRendererGraphID": audioRendererState?.graphID ?? "none",
      "audioRendererIdentity": audioRendererState?.rendererIdentity ?? "none",
      "audioRendererVideoRendererIdentity": audioRendererState?.videoRendererIdentity ?? "none",
      "audioRendererSynchronizerIdentity": audioRendererState?.synchronizerIdentity ?? "none",
      "audioRendererStreamEpoch": audioRendererState?.streamEpoch ?? 0,
      "audioRendererFrameCount": audioRendererState?.enqueuedAudioFrameCount ?? 0,
      "audioRendererVolume": Double(audioRendererState?.volume ?? volume),
      "audioRendererMuted": audioRendererState?.muted ?? isMuted,
      "audioRendererError": audioRendererState?.error ?? "none",
      "rendererTimelineRate": Double(rendererState?.rate ?? 0),
      "mediaSessionID": core.activeSession?.traceID ?? "none",
      "routeSwitchOperationState": debug?.lastRouteSwitchOperation?.state.rawValue ?? "none",
      "lastCompletedOperationKind": debug?.lastCompletedOperation?.kind.rawValue ?? "none",
      "lastCompletedOperationState": debug?.lastCompletedOperation?.state.rawValue ?? "none",
      "lastCompletedOperationTargetTime": debug?.lastCompletedOperation?.targetTimeSeconds ?? -1,
      "hasActiveMediaSession": session != nil,
      "hasVideoEntity": videoEntity != nil,
      "sourceAccessRequirement": debug?.mediaSession?.accessRequirement ?? "none",
      "securityScopeHeld": securityScopedURL != nil,
      "audioSessionConfigured": audioSessionConfigured,
      "audioSessionActive": audioSessionActive,
      "audioSessionCategory": audioSession.category.rawValue,
      "audioSessionMode": audioSession.mode.rawValue,
      "audioSessionLastAction": audioSessionLastAction,
      "audioSessionError": audioSessionError ?? "none",
      "presentationBinding": binding?.realityViewIdentity ?? "none",
      "sceneContainer": binding?.sceneContainer.value ?? "none",
      "presentationStatePhase": presentationState?.phase ?? "none",
      "currentSeconds": currentSeconds,
      "dockingAnchorReady": dockingAnchor != nil,
      "dockingAnchorHasModel": dockingAnchor?.components[ModelComponent.self] != nil,
      "dockingAnchorComponentCount": dockingAnchor?.components.count ?? -1,
      "dockedRootBoundToAnchor": dockedPresentationRoot.parent === dockingAnchor,
      "dockingAnchorPreservesAuthoredTransform": dockingAnchor?.transform
        == authoredDockingTransform,
      "dockingAnchorPosition": dockingAnchor.map {
        "\($0.position.x),\($0.position.y),\($0.position.z)"
      } ?? "none",
      "dockingAnchorScale": dockingAnchor.map {
        "\($0.scale.x),\($0.scale.y),\($0.scale.z)"
      } ?? "none",
      "lastCleanupMediaSessionID": cleanup?.lastMediaSession?.mediaSessionID ?? "none",
      "lastCleanupOperationKind": cleanup?.lastCompletedOperation?.kind.rawValue ?? "none",
      "lastCleanupOperationState": cleanup?.lastCompletedOperation?.state.rawValue ?? "none",
      "lastCleanupRendererFlushCount": cleanup?.rendererState?.flushCount ?? 0,
      "lastCleanupVideoProviderCancelled": cleanup?.cleanupState?.videoProviderCancelled ?? false,
      "lastCleanupAudioProviderCancelled": cleanup?.cleanupState?.audioProviderCancelled ?? false,
      "lastCleanupAudioRendererFlushed": cleanup?.cleanupState?.audioRendererFlushed ?? false,
      "lastCleanupVideoRendererFlushed": cleanup?.cleanupState?.videoRendererFlushed ?? false,
      "lastCleanupRealityKitBindingActive": cleanup?.realityKitBinding?.active ?? true,
      "lastCleanupPresentationBindingAttached": cleanup?.presentationBinding?.entityAttached ?? true,
      "status": status.label,
      "mediaTransitioning": isMediaTransitioning,
      "controlError": controlError ?? "none",
      "transitioning": isPresentationTransitioning,
      "transitionError": presentationTransitionError ?? "none",
      "presentationRollbackState": lastPresentationRollbackState,
      "presentationRollbackError": lastPresentationRollbackError ?? "none",
    ]
  }

  func scenePhaseDidChange(_ phase: String) {
    PlaybackTrace.event("scene.phase value=\(phase)")
    recordPresentationState(phase: "scenePhase.\(phase)")
  }

  var canPlay: Bool {
    !isMediaTransitioning && (status == .ready || status == .paused)
  }

  var canPause: Bool {
    !isMediaTransitioning && status == .playing
  }

  var canSeek: Bool {
    !isMediaTransitioning && durationSeconds > 0
      && (status == .ready || status == .playing || status == .paused)
  }

  var canAdjustPlayback: Bool {
    !isMediaTransitioning && (status == .ready || status == .playing || status == .paused)
  }

  private func closeSessionAndWait() async {
    progressTask?.cancel()
    progressTask = nil
    presentationTraceTask?.cancel()
    presentationTraceTask = nil
    guard let session = core.activeSession else {
      deactivateAudioSession(reason: "close")
      detachVideoEntity(traceID: "none")
      return
    }
    traceComponent(event: "component.beforeClose", session: session)
    detachVideoEntity(traceID: session.traceID)
    await core.closeAndWait(clearSource: false)
    lastCleanupSnapshot = session.debugSnapshot()
    deactivateAudioSession(reason: "close")
  }

  private func releaseSecurityScopedURL() {
    securityScopedURL?.stopAccessingSecurityScopedResource()
    securityScopedURL = nil
  }

  private func resetPlaybackFacts() {
    currentSeconds = 0
    durationSeconds = 0
    playbackRate = 1
    volume = 1
    isMuted = false
    audioTracks = []
    selectedAudioStreamIndex = nil
    controlError = nil
  }

  private func beginMediaTransition() -> UInt64 {
    mediaOperationGeneration &+= 1
    isMediaTransitioning = true
    controlError = nil
    return mediaOperationGeneration
  }

  private func ownsMediaTransition(_ generation: UInt64) -> Bool {
    mediaOperationGeneration == generation
  }

  private func finishMediaTransition(_ generation: UInt64) {
    guard ownsMediaTransition(generation) else { return }
    isMediaTransitioning = false
  }

  private func invalidateMediaTransitions() {
    mediaOperationGeneration &+= 1
    isMediaTransitioning = false
  }

  private func startPresentationTrace(for session: SampleBufferPlaybackSession) {
    presentationTraceTask?.cancel()
    presentationTraceTask = Task { [weak self, weak session] in
      for tick in 1...24 {
        try? await Task.sleep(for: .milliseconds(tick <= 8 ? 250 : 1_000))
        guard !Task.isCancelled, let self, let session else { return }
        guard self.core.activeSession === session else {
          PlaybackTrace.event("presentation.monitor.stale id=\(session.traceID)")
          return
        }
        self.traceComponent(event: "presentation.heartbeat.\(tick)", session: session)
      }
    }
  }

  private func attachVideoEntity(for session: SampleBufferPlaybackSession) {
    let entity = Entity()
    entity.scale = .one
    videoEntity = entity
    configurePlanarPresenter(for: session)
    videoEntityGeneration &+= 1
    session.recordRealityKitBinding(
      entityIdentity: PlaybackTrace.identity(entity),
      active: true
    )
    traceComponent(event: "component.set.beforeAttach", session: session)
    if activePresentationContainerIsOpen {
      moveVideoEntity(to: activePresentationRoot)
    }
    recordPresentationState(phase: "entityAttached")
    traceComponent(event: "entity.attached", session: session)
  }

  private func detachVideoEntity(traceID: String) {
    guard let videoEntity else { return }
    cancelAllVideoPlayerSubscriptions()
    let entityID = PlaybackTrace.identity(videoEntity)
    let parentID = PlaybackTrace.identity(videoEntity.parent)
    detachCurrentPresentationBinding()
    core.activeSession?.recordRealityKitBinding(entityIdentity: entityID, active: false)
    videoEntity.removeFromParent()
    self.videoEntity = nil
    videoEntityGeneration &+= 1
    PlaybackTrace.event(
      "entity.detached id=\(traceID) entity=\(entityID) root=\(parentID)"
    )
  }

  private var activePresentationContainerIsOpen: Bool {
    switch presentation.facts.placement {
    case .window:
      presentation.isWindowOpen
    case .docked, .panorama:
      presentation.isSceneOpen
    }
  }

  private func moveVideoEntity(
    to root: Entity,
    configureComponent: Bool = true
  ) {
    guard let videoEntity else { return }
    cancelAllVideoPlayerSubscriptions()
    detachCurrentPresentationBinding()
    root.addChild(videoEntity, preservingWorldTransform: false)
    videoEntity.position = .zero
    videoEntity.orientation = .init()
    videoEntity.scale = .one
    if configureComponent {
      configurePresenterForCurrentProjection()
    }
    videoEntityGeneration &+= 1
    updateImmersiveSceneVisibility()
  }

  private func configurePresenterForCurrentProjection() {
    configurePresenter(for: presentation.facts.projection)
  }

  private func configurePresenter(for projection: VisionProjection) {
    guard let session = core.activeSession else { return }
    if projection.isPanoramic {
      configureImmersivePresenter(for: session)
    } else {
      configurePlanarPresenter(for: session)
    }
  }

  private func configurePlanarPresenter(for session: SampleBufferPlaybackSession) {
    guard let videoEntity else { return }
    videoEntity.components.remove(VideoPlayerComponent.self)
    let material = VideoMaterial(videoRenderer: session.renderer)
    material.controller.preferredViewingMode = presentation.facts.stereoLayout.isStereo
      ? .stereo : .mono
    let mesh = MeshResource.generatePlane(width: 1.6, height: 0.9)
    videoEntity.components.set(ModelComponent(mesh: mesh, materials: [material]))
    videoEntityGeneration &+= 1
    PlaybackTrace.event(
      "presentation.presenter.configured kind=planar shape=\(presentation.productShape.rawValue)"
    )
  }

  private func configureImmersivePresenter(for session: SampleBufferPlaybackSession) {
    guard let videoEntity else { return }
    videoEntity.components.remove(ModelComponent.self)
    var component = VideoPlayerComponent(videoRenderer: session.renderer)
    component.desiredViewingMode = presentation.facts.stereoLayout.isStereo ? .stereo : .mono
    component.desiredImmersiveViewingMode = immersiveViewingMode(for: presentation.facts.placement)
    videoEntity.components.set(component)
    videoEntityGeneration &+= 1
    PlaybackTrace.event(
      "presentation.presenter.configured kind=immersive shape=\(presentation.productShape.rawValue) "
        + "desiredImmersive=\(String(describing: component.desiredImmersiveViewingMode))"
    )
  }

  private var planarVideoMaterial: VideoMaterial? {
    guard let model = videoEntity?.components[ModelComponent.self] else { return nil }
    return model.materials.lazy.compactMap { $0 as? VideoMaterial }.first
  }

  private var rendererIsBoundToActivePresenter: Bool {
    guard let renderer = core.activeSession?.renderer else { return false }
    if let component = videoEntity?.components[VideoPlayerComponent.self] {
      return component.videoRenderer === renderer
    }
    return planarVideoMaterial?.videoRenderer === renderer
  }

  private func immersiveViewingMode(
    for placement: VisionPlaybackPlacement
  ) -> VideoPlayerComponent.ImmersiveViewingMode {
    placement == .panorama ? .progressive : .portal
  }

  private func requestImmersiveViewingMode(
    _ expected: VideoPlayerComponent.ImmersiveViewingMode
  ) async throws {
    guard let videoEntity,
      var component = videoEntity.components[VideoPlayerComponent.self]
    else {
      throw VisionPresentationCommandError("videoPlayerComponentMissing")
    }
    if expected == .progressive && !effectiveProjectionIsPanoramic {
      throw VisionPresentationCommandError("immersiveProjectionMetadataMissing")
    }
    if component.immersiveViewingMode == expected {
      component.desiredImmersiveViewingMode = expected
      videoEntity.components.set(component)
      return
    }

    let baseline = immersiveModeChangeSequence
    let expectedSurface = activeSurface
    component.desiredImmersiveViewingMode = expected
    videoEntity.components.set(component)
    recordPresentationState(
      phase: "waitingForModeChange",
      transitionResult: "desired=\(String(describing: expected))"
    )

    if !effectiveProjectionIsPanoramic && expected == .portal { return }
    guard
      await waitUntil(
        timeout: .seconds(3),
        condition: {
          self.immersiveModeChangeSequence > baseline
            && self.lastAcknowledgedImmersiveMode == expected
            && self.lastAcknowledgedImmersiveModeSurface == expectedSurface
        })
    else {
      let current = videoEntity.components[VideoPlayerComponent.self]
      throw VisionPresentationCommandError(
        "immersiveViewingModeDidChangeTimeout.\(String(describing: expected))"
          + ".actual=\(String(describing: current?.immersiveViewingMode))"
          + ".desired=\(String(describing: current?.desiredImmersiveViewingMode))"
          + ".contentType=\(lastAcknowledgedContentType)"
          + ".contentTypeSequence=\(contentTypeChangeSequence)"
      )
    }
  }

  private func requestViewingMode(
    _ expected: VideoPlaybackController.ViewingMode
  ) async throws {
    guard let videoEntity else { throw VisionPresentationCommandError("videoEntityMissing") }
    if var model = videoEntity.components[ModelComponent.self],
      let material = model.materials.lazy.compactMap({ $0 as? VideoMaterial }).first
    {
      let baselineMode = material.controller.currentViewingMode
      material.controller.preferredViewingMode = expected
      model.materials = [material]
      videoEntity.components.set(model)
      guard
        await waitUntil(
          timeout: .seconds(3),
          condition: {
            self.planarVideoMaterial?.controller.currentViewingMode == expected
          })
      else {
        throw VisionPresentationCommandError(
          "planarViewingModeDidChangeTimeout.\(String(describing: expected))"
        )
      }
      if baselineMode != expected {
        viewingModeChangeSequence &+= 1
        lastAcknowledgedViewingMode = expected
        lastAcknowledgedViewingModeSurface = activeSurface
      }
      return
    }
    guard var component = videoEntity.components[VideoPlayerComponent.self] else {
      throw VisionPresentationCommandError("videoPresenterMissing")
    }
    if component.viewingMode == expected {
      component.desiredViewingMode = expected
      videoEntity.components.set(component)
      return
    }

    let baseline = viewingModeChangeSequence
    let expectedSurface = activeSurface
    component.desiredViewingMode = expected
    videoEntity.components.set(component)
    guard
      await waitUntil(
        timeout: .seconds(3),
        condition: {
          self.viewingModeChangeSequence > baseline
            && self.lastAcknowledgedViewingMode == expected
            && self.lastAcknowledgedViewingModeSurface == expectedSurface
        })
    else {
      throw VisionPresentationCommandError(
        "viewingModeDidChangeTimeout.\(String(describing: expected))"
      )
    }
  }

  private func awaitPresentationBinding() async throws {
    let expectedSurface = activeSurface
    if videoEntity?.components[VideoPlayerComponent.self] != nil {
      guard
        await waitUntil(
          timeout: .seconds(3),
          condition: { self.hasVideoPlayerSubscription(on: expectedSurface) })
      else {
        throw VisionPresentationCommandError("videoPlayerEventsNotConnected")
      }
    }
    guard
      await waitUntil(
        timeout: .seconds(3),
        condition: {
          guard let session = self.core.activeSession,
            let binding = session.debugSnapshot().presentationBinding
          else { return false }
          return binding.entityAttached
            && binding.mediaSessionID == session.traceID
            && binding.realityViewIdentity == expectedSurface.rawValue
        })
    else {
      throw VisionPresentationCommandError("presentationBindingDidNotAttach")
    }
  }

  private func awaitCustomSceneVisible() async throws {
    guard
      await waitUntil(
        timeout: .seconds(10),
        condition: {
          self.presentation.isSceneOpen
            && self.presentation.facts.sceneContent == .customScene
            && self.immersiveScene != nil
            && self.immersiveScene?.isEnabled == true
        })
    else {
      if let immersiveSceneError {
        throw VisionPresentationCommandError("customSceneLoadFailed.\(immersiveSceneError)")
      }
      var failures = [String]()
      if !presentation.isSceneOpen { failures.append("sceneNotOpen") }
      if presentation.facts.sceneContent != .customScene {
        failures.append("sceneContent=\(presentation.facts.sceneContent?.rawValue ?? "none")")
      }
      if immersiveScene == nil { failures.append("assetNotLoaded") }
      if immersiveScene?.isEnabled != true { failures.append("assetNotEnabled") }
      throw VisionPresentationCommandError(
        "customSceneDidNotBecomeVisible.\(failures.joined(separator: ","))"
      )
    }
  }

  private func awaitDockingTargetReady() async throws {
    guard
      await waitUntil(
        timeout: .seconds(10),
        condition: {
          self.dockingAnchor != nil
            && self.dockingAnchor?.components[ModelComponent.self] == nil
            && self.dockedPresentationRoot.parent === self.dockingAnchor
            && self.dockingAnchor?.transform == self.authoredDockingTransform
        })
    else {
      var failures = [String]()
      if dockingAnchor == nil { failures.append("anchorMissing") }
      if dockingAnchor?.components[ModelComponent.self] != nil {
        failures.append("anchorHasModel")
      }
      if dockedPresentationRoot.parent !== dockingAnchor {
        failures.append("dockedRootNotBound")
      }
      if dockingAnchor?.transform != authoredDockingTransform {
        failures.append("authoredTransformChanged")
      }
      throw VisionPresentationCommandError(
        "dockingTargetDidNotBecomeReady.\(failures.joined(separator: ","))"
      )
    }
  }

  private func awaitPresentationSettled() async throws {
    presentation.setPhase(.waitingForRenderer)
    guard
      await waitUntil(
        timeout: .seconds(3),
        condition: { self.presentationIsSettled() })
    else {
      throw VisionPresentationCommandError("presentationDidNotSettle")
    }
  }

  private func require(
    _ condition: @autoclosure () -> Bool,
    fallback: String
  ) throws {
    if !condition() { throw VisionPresentationCommandError(fallback) }
  }

  private func rollbackPresentation(
    command: PresentationCommand,
    snapshot: VisionPresentationFacts,
    windowWasOpen: Bool,
    sceneWasOpen: Bool,
    actions: VisionPresentationActions,
    error: String
  ) async -> String {
    presentation.setPhase(.rollingBack)
    var rollbackFailures = [String]()
    let sourceBindingWasIntact = sourcePresentationBindingIsIntact(snapshot: snapshot)
    do {
      try await VisionPresentationTransaction.restoreSource(
        ensureSourceContainers: {
          if windowWasOpen {
            await self.presentation.openPlaybackWindow(actions: actions)
            try self.require(
              self.presentation.windowLifecycle == .open,
              fallback: "rollbackWindowDidNotOpen"
            )
          }
          if sceneWasOpen {
            if snapshot.sceneContent == .blackPanorama {
              await self.presentation.openPanoramaSpace(actions: actions)
            } else {
              await self.presentation.openScene(actions: actions)
            }
            self.updateImmersiveSceneVisibility()
            try self.require(
              self.presentation.facts.sceneLifecycle == .open
                && self.presentation.facts.sceneContent == snapshot.sceneContent,
              fallback: "rollbackSceneDidNotOpen"
            )
            if snapshot.sceneContent == .customScene {
              try await self.awaitCustomSceneVisible()
            }
          }
        },
        restoreIntentAndBinding: {
          self.presentation.restoreIntent(snapshot)
          self.updateImmersiveSceneVisibility()
          guard self.videoEntity != nil else { return }
          self.configurePresenter(for: snapshot.projection)
          try self.require(
            self.activePresentationContainerIsOpen,
            fallback: "rollbackSourceContainerNotOpen"
          )
          if !sourceBindingWasIntact {
            self.moveVideoEntity(to: self.activePresentationRoot, configureComponent: false)
            try await self.awaitPresentationBinding()
          }
        },
        requestAndAwaitMode: {
          guard self.videoEntity != nil else { return }
          if snapshot.projection.isPanoramic {
            try await self.requestImmersiveViewingMode(
              self.immersiveViewingMode(for: snapshot.placement)
            )
          }
          try await self.requestViewingMode(
            snapshot.stereoLayout.isStereo ? .stereo : .mono
          )
        },
        awaitSourceSettled: {
          guard self.videoEntity != nil else { return }
          try await self.awaitPresentationSettled()
        },
        closeFailedTarget: {
          if !windowWasOpen {
            await self.presentation.closePlaybackWindow(actions: actions)
            try self.require(
              self.presentation.windowLifecycle == .closed,
              fallback: "rollbackWindowDidNotClose"
            )
          }
          if !sceneWasOpen {
            await self.presentation.closeScene(actions: actions)
            self.updateImmersiveSceneVisibility()
            try self.require(
              self.presentation.facts.sceneLifecycle == .closed,
              fallback: "rollbackSceneDidNotClose"
            )
          }
        }
      )
    } catch let rollbackError {
      rollbackFailures.append(rollbackError.localizedDescription)
    }

    if presentation.isWindowOpen != windowWasOpen
      || presentation.windowLifecycle != (windowWasOpen ? .open : .closed)
    {
      rollbackFailures.append("windowLifecycle")
    }
    if presentation.isSceneOpen != sceneWasOpen
      || presentation.facts.sceneLifecycle != (sceneWasOpen ? .open : .closed)
    {
      rollbackFailures.append("sceneLifecycle")
    }
    if presentation.facts.projection != snapshot.projection
      || presentation.facts.placement != snapshot.placement
      || presentation.facts.stereoLayout != snapshot.stereoLayout
      || presentation.facts.customSceneRequestedOpen != snapshot.customSceneRequestedOpen
      || presentation.facts.sceneContent != (sceneWasOpen ? snapshot.sceneContent : nil)
    {
      rollbackFailures.append("presentationFacts")
    }

    let finalError: String
    if rollbackFailures.isEmpty {
      lastPresentationRollbackState = "succeeded"
      lastPresentationRollbackError = nil
      finalError = error
    } else {
      let rollbackError = rollbackFailures.joined(separator: ",")
      lastPresentationRollbackState = "failed"
      lastPresentationRollbackError = rollbackError
      finalError = "\(error);rollbackFailed.\(rollbackError)"
    }
    presentation.fail(command, error: finalError)
    recordPresentationState(phase: "failed", transitionError: finalError)
    PlaybackTrace.event(
      "presentation.command.failed command=\(String(describing: command)) "
        + "rollback=\(lastPresentationRollbackState) error=\(finalError)"
    )
    return finalError
  }

  private func sourcePresentationBindingIsIntact(
    snapshot: VisionPresentationFacts
  ) -> Bool {
    guard let session = core.activeSession,
      let videoEntity,
      videoEntity.parent === presentationRoot(for: snapshot.placement),
      let binding = session.debugSnapshot().presentationBinding
    else { return false }
    let presenterMatches: Bool
    if snapshot.projection.isPanoramic {
      guard let component = videoEntity.components[VideoPlayerComponent.self] else { return false }
      presenterMatches = component.videoRenderer === session.renderer
        && component.currentRenderingStatus == .ready
        && hasVideoPlayerSubscription(on: presentationSurface(for: snapshot.placement))
    } else {
      presenterMatches = rendererIsBoundToActivePresenter
        && videoEntity.components[VideoPlayerComponent.self] == nil
        && videoEntity.components[ModelComponent.self] != nil
    }
    guard presenterMatches else { return false }
    let surface = presentationSurface(for: snapshot.placement)
    return binding.entityAttached
      && binding.mediaSessionID == session.traceID
      && binding.realityViewIdentity == surface.rawValue
      && binding.sceneContainer.value
        == (surface == .playbackWindow
          ? VisionSceneID.playbackWindow : VisionSceneID.playbackSpace)
  }

  private var sourceHasEquirectangularProjection: Bool {
    let snapshot = core.activeSession?.debugSnapshot()
    let projection = snapshot?.providerOpen?.formatSignaling.projectionKind.value
    let normalized = projection?.lowercased() ?? ""
    return normalized.contains("equirectangular")
  }

  private var effectiveProjectionIsPanoramic: Bool {
    let projection = core.activeSession?.debugSnapshot().lastVideoSample?
      .formatSignaling.projectionKind.value
    return projection?.lowercased().contains("equirectangular") == true
  }

  var contentSupportsPanorama: Bool {
    core.activeSession != nil
  }

  @discardableResult
  private func configurePresentationBindingIfAvailable() throws -> Bool {
    guard let session = core.activeSession,
      let videoEntity,
      activePresentationContainerIsOpen,
      videoEntity.parent === activePresentationRoot,
      rendererIsBoundToActivePresenter
    else { return false }
    session.recordPresentationBinding(
      realityViewIdentity: activeSurface.rawValue,
      platform: "visionOS",
      attached: true,
      sceneContainer:
        activeSurface == .playbackWindow ? VisionSceneID.playbackWindow : VisionSceneID.playbackSpace,
      sceneLifecycle: "active"
    )

    do {
      try core.presentationDidAttach(session: session)
      try startIfPresentationAttached(session)
      return true
    } catch {
      PlaybackTrace.event(
        "presentation.binding.failed id=\(session.traceID) " + "error=\(error.localizedDescription)"
      )
      controlError = error.localizedDescription
      throw error
    }
  }

  private func startIfPresentationAttached(
    _ session: SampleBufferPlaybackSession
  ) throws {
    guard core.activeSession === session,
      session.debugSnapshot().presentationBinding?.entityAttached == true,
      status == .loading || status == .ready
    else { return }
    currentSeconds = session.currentTime().seconds
    durationSeconds = diagnostics.durationSeconds
    do {
      try activateAudioSessionIfNeeded(for: session)
      try core.start()
    } catch {
      deactivateAudioSession(reason: "startFailed")
      throw error
    }
    startProgressUpdates()
  }

  private func activateAudioSessionIfNeeded(
    for session: SampleBufferPlaybackSession
  ) throws {
    guard session.selectedAudioStreamIndex != nil else {
      deactivateAudioSession(reason: "noAudioTrack")
      return
    }
    do {
      try audioSession.setCategory(.playback, mode: .moviePlayback)
      audioSessionConfigured = true
      audioSessionLastAction = "configured"
      try audioSession.setActive(true)
      audioSessionActive = true
      audioSessionError = nil
      audioSessionLastAction = "activated"
      PlaybackTrace.event(
        "audioSession.activated category=\(audioSession.category.rawValue) "
          + "mode=\(audioSession.mode.rawValue)"
      )
    } catch {
      audioSessionActive = false
      audioSessionError = error.localizedDescription
      audioSessionLastAction = "activationFailed"
      PlaybackTrace.event(
        "audioSession.activationFailed error=\(error.localizedDescription)"
      )
      throw error
    }
  }

  private func deactivateAudioSession(reason: String) {
    guard audioSessionActive else { return }
    do {
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
      audioSessionActive = false
      audioSessionError = nil
      audioSessionLastAction = "deactivated.\(reason)"
      PlaybackTrace.event("audioSession.deactivated reason=\(reason)")
    } catch {
      audioSessionError = error.localizedDescription
      audioSessionLastAction = "deactivationFailed.\(reason)"
      PlaybackTrace.event(
        "audioSession.deactivationFailed reason=\(reason) " + "error=\(error.localizedDescription)"
      )
    }
  }

  private func detachCurrentPresentationBinding() {
    guard let session = core.activeSession,
      let binding = session.debugSnapshot().presentationBinding
    else { return }
    session.recordPresentationBinding(
      realityViewIdentity: binding.realityViewIdentity,
      platform: binding.platform,
      attached: false,
      sceneContainer: binding.sceneContainer.value ?? "unknown",
      sceneLifecycle: "inactive"
    )
  }

  private func recordPresentationState(
    phase: String,
    transitionResult: String? = nil,
    transitionError: String? = nil
  ) {
    guard let session = core.activeSession else { return }
    let component = videoEntity?.components[VideoPlayerComponent.self]
    let planarMaterial = planarVideoMaterial
    let activeView = activePresentationContainerIsOpen ? activeSurface.rawValue : nil
    let activeSceneContainer: String? = activePresentationContainerIsOpen
      ? (activeSurface == .playbackWindow
        ? VisionSceneID.playbackWindow : VisionSceneID.playbackSpace)
      : nil
    session.recordPresentationState(
      PresentationStateRecord(
        mediaSessionID: session.traceID,
        route: session.route,
        requestedMode: presentation.productShape.rawValue,
        phase: phase,
        platform: "visionOS",
        sceneContainer: presentationFact(activeSceneContainer, unresolved: .unknown),
        realityViewIdentity: presentationFact(activeView, unresolved: .unknown),
        entityParentIdentity: presentationFact(
          videoEntity?.parent.map(PlaybackTrace.identity), unresolved: .unknown),
        desiredImmersiveViewingMode: presentationFact(
          component.map {
            String(describing: $0.desiredImmersiveViewingMode)
          }),
        actualImmersiveViewingMode: presentationFact(
          component?.immersiveViewingMode.map {
            String(describing: $0)
          }, unresolved: .unknown),
        desiredViewingMode: presentationFact(
          component.map {
            String(describing: $0.desiredViewingMode)
          } ?? planarMaterial.map {
            String(describing: $0.controller.preferredViewingMode)
          }),
        actualViewingMode: presentationFact(
          component?.viewingMode.map {
            String(describing: $0)
          } ?? planarMaterial?.controller.currentViewingMode.map {
            String(describing: $0)
          }, unresolved: .unknown),
        desiredSpatialVideoMode: presentationFact(nil),
        actualSpatialVideoMode: presentationFact(nil),
        transitionResult: presentationFact(transitionResult),
        transitionError: presentationFact(transitionError, unresolved: .none)
      ))
  }

  private func presentationFact(
    _ value: String?,
    unresolved: FactAvailability = .notExposed
  ) -> ObservedStringFact {
    value.map { .init(.known, value: $0) } ?? .init(unresolved)
  }

  private func traceComponent(event: String, session: SampleBufferPlaybackSession) {
    let entity = videoEntity
    let component = entity?.components[VideoPlayerComponent.self]
    let material = planarVideoMaterial
    PlaybackTrace.event(
      "\(event) id=\(session.traceID) entity=\(PlaybackTrace.identity(entity)) "
        + "parent=\(PlaybackTrace.identity(entity?.parent)) "
        + "componentPresent=\(component != nil) "
        + "planarPresent=\(material != nil) "
        + "componentRenderer=\(PlaybackTrace.identity(component?.videoRenderer)) "
        + "sessionRenderer=\(PlaybackTrace.identity(session.renderer)) "
        + "rendererMatches=\(rendererIsBoundToActivePresenter) "
        + "realityStatus=\(component.map { String(describing: $0.currentRenderingStatus) } ?? "missing") "
        + "rendererStatus=\(session.renderer.status) "
        + "rendererError=\(session.renderer.error?.localizedDescription ?? "none") "
        + "displayed=\(session.renderer.displayedPixelBuffer() != nil) "
        + "time=\(session.currentTime().seconds) samples=\(diagnostics.enqueuedSampleCount) "
        + "entityEnabled=\(entity?.isEnabled ?? false)"
    )
  }

  private func startProgressUpdates() {
    progressTask?.cancel()
    progressTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        currentSeconds = core.activeSession?.currentTime().seconds ?? 0
        durationSeconds = diagnostics.durationSeconds
        try? await Task.sleep(for: .milliseconds(200))
      }
    }
  }
}
