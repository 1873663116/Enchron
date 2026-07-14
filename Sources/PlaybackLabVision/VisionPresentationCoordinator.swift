import Foundation
import Observation

struct VisionPresentationWaitPolicy: Sendable {
  let windowOpen: Duration
  let windowClose: Duration
  let sceneOpen: Duration
  let sceneClose: Duration

  static let production = VisionPresentationWaitPolicy(
    windowOpen: .seconds(3),
    windowClose: .seconds(3),
    sceneOpen: .seconds(3),
    sceneClose: .seconds(3)
  )
}

@MainActor
@Observable
final class VisionPresentationCoordinator {
  private let waitPolicy: VisionPresentationWaitPolicy
  private(set) var state = VisionPresentationState.stable
  private(set) var facts = VisionPresentationFacts(
    projection: .flat,
    placement: .window,
    sceneLifecycle: .closed,
    sceneContent: nil,
    stereoLayout: .mono
  )
  private(set) var windowLifecycle = VisionSceneLifecycle.closed
  private(set) var windowAttached = false
  private(set) var sceneAttached = false
  private var expectedWindowRequest: VisionSurfaceRequest?
  private var expectedSceneRequest: VisionSurfaceRequest?
  private var activeWindowAttachment: VisionSurfaceAttachment?
  private var activeSceneAttachment: VisionSurfaceAttachment?
  private(set) var immersiveOpenResult = "notRequested"
  private(set) var operationError: String?

  var isTransitioning: Bool { state.isTransitioning }
  var transitionError: String? { state.error ?? operationError }
  var productShape: VisionProductShape { facts.productShape }
  var isWindowOpen: Bool { windowAttached }
  var isSceneOpen: Bool { sceneAttached }

  init(waitPolicy: VisionPresentationWaitPolicy = .production) {
    self.waitPolicy = waitPolicy
  }

  @discardableResult
  func surfaceDidAttach(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    switch surface {
    case .playbackWindow:
      if activeWindowAttachment == attachment { return true }
      guard activeWindowAttachment == nil,
        expectedWindowRequest == attachment.request
      else {
        operationError = activeWindowAttachment == nil
          ? "unexpectedPlaybackWindowAttach" : "duplicatePlaybackWindowAttach"
        if activeWindowAttachment == nil, expectedWindowRequest == nil {
          windowLifecycle = .failed("unexpectedPlaybackWindowAttach")
        }
        return false
      }
      operationError = nil
      activeWindowAttachment = attachment
      windowAttached = true
      expectedWindowRequest = nil
      windowLifecycle = .open
    case .scene:
      if activeSceneAttachment == attachment { return true }
      guard activeSceneAttachment == nil,
        expectedSceneRequest == attachment.request
      else {
        operationError = activeSceneAttachment == nil
          ? "unexpectedSceneAttach" : "duplicateSceneAttach"
        if activeSceneAttachment == nil, expectedSceneRequest == nil {
          facts.sceneLifecycle = .failed("unexpectedSceneAttach")
        }
        return false
      }
      operationError = nil
      activeSceneAttachment = attachment
      sceneAttached = true
      expectedSceneRequest = nil
      facts.sceneLifecycle = .open
      if facts.sceneContent == nil { facts.sceneContent = .customScene }
    }
    return true
  }

  @discardableResult
  func surfaceDidDetach(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    switch surface {
    case .playbackWindow:
      guard activeWindowAttachment == attachment else { return false }
      activeWindowAttachment = nil
      windowAttached = false
      windowLifecycle = .closed
    case .scene:
      guard activeSceneAttachment == attachment else { return false }
      activeSceneAttachment = nil
      sceneAttached = false
      facts.sceneLifecycle = .closed
      facts.sceneContent = nil
    }
    return true
  }

  func surfaceIsActive(
    _ surface: VisionSurface,
    attachment: VisionSurfaceAttachment
  ) -> Bool {
    activeAttachment(for: surface) == attachment
  }

  func activeAttachment(for surface: VisionSurface) -> VisionSurfaceAttachment? {
    switch surface {
    case .playbackWindow: activeWindowAttachment
    case .scene: activeSceneAttachment
    }
  }

  func openPlaybackWindow(actions: VisionPresentationActions) async {
    guard !isWindowOpen else {
      guard windowLifecycle == .open else {
        operationError = "playbackWindowDismissalInFlight"
        return
      }
      windowLifecycle = .open
      return
    }
    operationError = nil
    windowLifecycle = .opening
    let request = VisionSurfaceRequest()
    expectedWindowRequest = request
    actions.openWindow(VisionSceneID.playbackWindow, request)
    guard await waitUntil(timeout: waitPolicy.windowOpen, condition: { self.isWindowOpen }) else {
      if expectedWindowRequest == request { expectedWindowRequest = nil }
      actions.dismissWindow(VisionSceneID.playbackWindow, request)
      windowLifecycle = .failed("playbackWindowDidNotAttach")
      operationError = "playbackWindowDidNotAttach"
      return
    }
  }

  func closePlaybackWindow(actions: VisionPresentationActions) async {
    guard isWindowOpen else {
      windowLifecycle = .closed
      return
    }
    guard let attachment = activeWindowAttachment else {
      windowLifecycle = .failed("playbackWindowAttachmentMissing")
      operationError = "playbackWindowAttachmentMissing"
      return
    }
    operationError = nil
    windowLifecycle = .closing
    expectedWindowRequest = nil
    actions.dismissWindow(VisionSceneID.playbackWindow, attachment.request)
    guard
      await waitUntil(timeout: waitPolicy.windowClose, condition: { !self.windowAttached })
    else {
      windowLifecycle = .failed("playbackWindowDidNotDetach")
      operationError = "playbackWindowDidNotDetach"
      return
    }
  }

  func openScene(actions: VisionPresentationActions) async {
    facts.customSceneRequestedOpen = true
    await ensureSceneOpen(content: .customScene, actions: actions)
  }

  func openPanoramaSpace(actions: VisionPresentationActions) async {
    await ensureSceneOpen(content: .blackPanorama, actions: actions)
  }

  private func ensureSceneOpen(
    content: VisionSceneContent,
    actions: VisionPresentationActions
  ) async {
    if isSceneOpen {
      guard facts.sceneLifecycle == .open else {
        operationError = "sceneDismissalInFlight"
        return
      }
      facts.sceneLifecycle = .open
      facts.sceneContent = content
      return
    }
    operationError = nil
    facts.sceneLifecycle = .opening
    facts.sceneContent = content
    let request = VisionSurfaceRequest()
    expectedSceneRequest = request
    switch await actions.openImmersiveSpace(VisionSceneID.playbackSpace, request) {
    case .opened:
      immersiveOpenResult = "opened"
    case .userCancelled:
      if activeSceneAttachment?.request == request {
        immersiveOpenResult = "attachedDespiteUserCancelled"
        break
      }
      failSceneOpen("userCancelled", request: request)
      return
    case .failed(let message):
      if activeSceneAttachment?.request == request {
        immersiveOpenResult = "attachedDespiteFailure.\(message)"
        break
      }
      failSceneOpen(message, request: request)
      return
    }
    guard await waitUntil(timeout: waitPolicy.sceneOpen, condition: { self.isSceneOpen }) else {
      if expectedSceneRequest == request { expectedSceneRequest = nil }
      await actions.dismissImmersiveSpace()
      failSceneOpen("sceneDidNotAttach", request: request)
      return
    }
  }

  func closeScene(actions: VisionPresentationActions) async {
    guard isSceneOpen else {
      facts.customSceneRequestedOpen = false
      facts.sceneLifecycle = .closed
      facts.sceneContent = nil
      return
    }
    operationError = nil
    facts.customSceneRequestedOpen = false
    facts.sceneLifecycle = .closing
    expectedSceneRequest = nil
    await actions.dismissImmersiveSpace()
    guard
      await waitUntil(timeout: waitPolicy.sceneClose, condition: { !self.sceneAttached })
    else {
      facts.sceneLifecycle = .failed("sceneDidNotDetach")
      operationError = "sceneDidNotDetach"
      return
    }
  }

  func closePanoramaSpaceIfSceneWasNotRequested(actions: VisionPresentationActions) async {
    guard !facts.customSceneRequestedOpen else {
      facts.sceneContent = .customScene
      return
    }
    await closeScene(actions: actions)
  }

  func begin(_ command: PresentationCommand) -> Bool {
    guard !isTransitioning else { return false }
    operationError = nil
    state = .transitioning(command: command, phase: .preparing)
    return true
  }

  func setPhase(_ phase: VisionPresentationTransitionPhase) {
    guard case .transitioning(let command, _) = state else { return }
    state = .transitioning(command: command, phase: phase)
  }

  func finish() {
    operationError = nil
    state = .stable
  }

  func fail(_ command: PresentationCommand, error: String) {
    operationError = error
    state = .failed(command: command, error: error)
  }

  func clearVideoBinding() {
    facts.placement = .window
    state = .stable
  }

  func setProjection(_ projection: VisionProjection) {
    facts.projection = projection
  }

  func setStereo(_ stereo: VisionStereoLayout) {
    facts.stereoLayout = stereo
  }

  func setPlacement(_ placement: VisionPlaybackPlacement) {
    facts.placement = placement
  }

  func setSceneContent(_ content: VisionSceneContent?) {
    facts.sceneContent = content
  }

  func restoreIntent(_ snapshot: VisionPresentationFacts) {
    facts.projection = snapshot.projection
    facts.placement = snapshot.placement
    facts.stereoLayout = snapshot.stereoLayout
    facts.customSceneRequestedOpen = snapshot.customSceneRequestedOpen
    if isSceneOpen {
      facts.sceneContent = snapshot.sceneContent ?? facts.sceneContent ?? .customScene
    } else {
      facts.sceneContent = nil
    }
  }

  private func failSceneOpen(_ message: String, request: VisionSurfaceRequest) {
    if expectedSceneRequest == request { expectedSceneRequest = nil }
    facts.sceneLifecycle = .failed(message)
    facts.sceneContent = nil
    facts.customSceneRequestedOpen = false
    immersiveOpenResult = message
    operationError = message
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
}

enum VisionPresentationTransaction {
  @MainActor
  static func presentTarget(
    prepareTarget: () async throws -> Void,
    migrateAndBind: () async throws -> Void,
    requestAndAwaitMode: () async throws -> Void,
    awaitTargetSettled: () async throws -> Void,
    closeSource: () async throws -> Void
  ) async throws {
    try await prepareTarget()
    try await migrateAndBind()
    try await requestAndAwaitMode()
    try await awaitTargetSettled()
    try await closeSource()
  }

  @MainActor
  static func restoreSource(
    ensureSourceContainers: () async throws -> Void,
    restoreIntentAndBinding: () async throws -> Void,
    requestAndAwaitMode: () async throws -> Void,
    awaitSourceSettled: () async throws -> Void,
    closeFailedTarget: () async throws -> Void
  ) async throws {
    try await ensureSourceContainers()
    try await restoreIntentAndBinding()
    try await requestAndAwaitMode()
    try await awaitSourceSettled()
    try await closeFailedTarget()
  }
}
