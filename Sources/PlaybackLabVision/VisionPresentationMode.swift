import Foundation

enum VisionSceneID {
  static let controlWindow = "PlaybackControlWindow"
  static let playbackWindow = "PlaybackWindow"
  static let playbackSpace = "PlaybackImmersiveSpace"
}

enum VisionImmersiveOpenResult {
  case opened
  case userCancelled
  case failed(String)
}

struct VisionSurfaceRequest: Codable, Hashable, Sendable {
  let id: UUID

  init(id: UUID = UUID()) {
    self.id = id
  }
}

struct VisionSurfaceAttachment: Hashable, Sendable {
  let request: VisionSurfaceRequest
  let instanceID: UUID

  init(request: VisionSurfaceRequest, instanceID: UUID = UUID()) {
    self.request = request
    self.instanceID = instanceID
  }

  var identity: String {
    "\(request.id.uuidString).\(instanceID.uuidString)"
  }
}

struct VisionPresentationActions {
  var openWindow: @MainActor (String, VisionSurfaceRequest) -> Void
  var dismissWindow: @MainActor (String, VisionSurfaceRequest) -> Void
  var openImmersiveSpace: @MainActor (String, VisionSurfaceRequest) async
    -> VisionImmersiveOpenResult
  var dismissImmersiveSpace: @MainActor () async -> Void
}

enum VisionProjection: String, CaseIterable, Sendable {
  case flat
  case sourcePanoramic

  var isPanoramic: Bool { self == .sourcePanoramic }
}

enum VisionStereoLayout: String, CaseIterable, Sendable {
  case mono
  case sideBySide
  case overUnder

  var isStereo: Bool { self != .mono }
}

enum VisionPlaybackPlacement: String, Sendable {
  case window
  case docked
  case panorama
}

enum VisionSceneContent: String, Sendable {
  case customScene
  case blackPanorama
}

enum VisionProductShape: String, CaseIterable, Identifiable, Sendable {
  case flatWindow
  case portalWindow
  case docked
  case panorama

  var id: Self { self }

  var label: String {
    switch self {
    case .flatWindow: "Flat Window"
    case .portalWindow: "Portal Window"
    case .docked: "Docked"
    case .panorama: "Panorama"
    }
  }
}

enum VisionSurface: String, CaseIterable, Sendable {
  case playbackWindow
  case scene
}

enum VisionSceneLifecycle: Equatable, Sendable {
  case closed
  case opening
  case open
  case closing
  case failed(String)

  var stateName: String {
    switch self {
    case .closed: "closed"
    case .opening: "opening"
    case .open: "open"
    case .closing: "closing"
    case .failed: "failed"
    }
  }

  var error: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }
}

struct VisionPresentationFacts: Equatable, Sendable {
  var projection: VisionProjection
  var placement: VisionPlaybackPlacement
  var sceneLifecycle: VisionSceneLifecycle
  var sceneContent: VisionSceneContent?
  var stereoLayout: VisionStereoLayout
  var customSceneRequestedOpen = false

  var productShape: VisionProductShape {
    switch placement {
    case .window:
      projection.isPanoramic ? .portalWindow : .flatWindow
    case .docked:
      .docked
    case .panorama:
      .panorama
    }
  }

  var canDock: Bool {
    productShape == .flatWindow
      && sceneLifecycle == .open
      && sceneContent == .customScene
  }

  var shouldRestoreCustomSceneAfterPanorama: Bool {
    customSceneRequestedOpen
  }

  var sceneLifecycleCommand: PresentationCommand? {
    guard productShape == .flatWindow || productShape == .portalWindow else { return nil }
    switch sceneLifecycle {
    case .closed, .failed:
      return .openScene
    case .open:
      return .closeScene
    case .opening, .closing:
      return nil
    }
  }

  var primaryPresentationCommands: [PresentationCommand] {
    switch productShape {
    case .flatWindow:
      canDock ? [.dock] : []
    case .portalWindow:
      [.showPanorama]
    case .docked, .panorama:
      [.showWindow]
    }
  }
}

enum PresentationCommand: Equatable, Sendable {
  case openPlaybackWindow
  case closePlaybackWindow
  case openScene
  case closeScene
  case showWindow
  case dock
  case showPanorama
  case setProjection(VisionProjection)
  case setStereo(VisionStereoLayout)
}

struct PresentationCommandResult: Equatable, Sendable {
  let command: PresentationCommand
  let succeeded: Bool
  let facts: VisionPresentationFacts
  let error: String?
}

enum VisionPresentationTransitionPhase: String, Equatable, Sendable {
  case preparing
  case waitingForModeChange
  case openingTarget
  case migratingBinding
  case waitingForRenderer
  case restoringScene
  case rollingBack
}

enum VisionPresentationState: Equatable, Sendable {
  case stable
  case transitioning(command: PresentationCommand, phase: VisionPresentationTransitionPhase)
  case failed(command: PresentationCommand, error: String)

  var phase: String {
    switch self {
    case .stable: "stable"
    case .transitioning(_, let phase): phase.rawValue
    case .failed: "failed"
    }
  }

  var error: String? {
    guard case .failed(_, let error) = self else { return nil }
    return error
  }

  var isTransitioning: Bool {
    if case .transitioning = self { return true }
    return false
  }
}
