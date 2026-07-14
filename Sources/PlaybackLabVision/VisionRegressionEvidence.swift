import Foundation

struct VisionRegressionEvidenceSnapshot {
  let missingRequiredKeys: [String]
  let invalidRequiredKeys: [String]
  let route: String
  let source: String
  let sourceAccessRequirement: String
  let securityScopeHeld: Bool
  let productShape: String
  let candidateProductShape: String
  let projection: String
  let detectedProjectionKind: String
  let effectiveProjectionKind: String
  let placement: String
  let stereoLayout: String
  let sceneContent: String
  let customSceneRequestedOpen: Bool
  let windowLifecycle: String
  let sceneLifecycle: String
  let immersiveSceneLoaded: Bool
  let immersiveSceneEnabled: Bool
  let panoramaRootEnabled: Bool
  let presentationSettled: Bool
  let presentationBindingAttached: Bool
  let realityKitBindingActive: Bool
  let presentationGeometry: String
  let planarMeshActive: Bool
  let presentationBinding: String
  let sceneContainer: String
  let parentIsWindowRoot: Bool
  let parentIsDockedRoot: Bool
  let parentIsPanoramaRoot: Bool
  let actualImmersiveViewingMode: String
  let immersiveModeChangeSequence: UInt64
  let lastAcknowledgedImmersiveModeSurface: String
  let actualViewingMode: String
  let viewingModeChangeSequence: UInt64
  let lastAcknowledgedViewingModeSurface: String
  let videoEntityIdentity: String
  let rendererIdentity: String
  let rendererGraphID: String
  let rendererSynchronizerIdentity: String
  let rendererMatchesSession: Bool
  let rendererError: String
  let componentRenderingStatus: String
  let displayedPixelBuffer: Bool
  let displayedPixelBufferIdentity: String
  let sampleCount: UInt64
  let streamEpoch: UInt64
  let rendererFlushCount: UInt64
  let formatRevision: UInt64
  let currentSeconds: Double
  let status: String
  let rendererTimelineRate: Double
  let audioRendererSampleBufferCount: UInt64
  let audioRendererMediaSessionID: String
  let audioRendererGraphID: String
  let audioRendererIdentity: String
  let audioRendererVideoRendererIdentity: String
  let audioRendererSynchronizerIdentity: String
  let audioRendererStreamEpoch: UInt64
  let audioRendererError: String
  let audioRendererVolume: Double
  let audioRendererMuted: Bool
  let selectedAudioStreamIndex: Int
  let lastCompletedOperationKind: String
  let lastCompletedOperationState: String
  let lastCompletedOperationTargetTime: Double
  let mediaSessionID: String
  let effectiveViewPackingKind: String
  let effectiveHasLeftStereoEyeView: Bool
  let effectiveHasRightStereoEyeView: Bool
  let coreEffectiveStereoLayout: String
  let routeSwitchOperationState: String
  let dockingAnchorReady: Bool
  let dockingAnchorHasModel: Bool
  let dockingAnchorComponentCount: Int
  let dockedRootBoundToAnchor: Bool
  let dockingAnchorPreservesAuthoredTransform: Bool
  let hasActiveMediaSession: Bool
  let hasVideoEntity: Bool
  let lastCleanupMediaSessionID: String
  let lastCleanupOperationKind: String
  let lastCleanupOperationState: String
  let lastCleanupRendererFlushCount: UInt64
  let lastCleanupVideoProviderCancelled: Bool
  let lastCleanupAudioProviderCancelled: Bool
  let lastCleanupAudioRendererFlushed: Bool
  let lastCleanupVideoRendererFlushed: Bool
  let lastCleanupRealityKitBindingActive: Bool
  let lastCleanupPresentationBindingAttached: Bool
  let presentationRollbackState: String
  let presentationRollbackError: String

  init(_ values: [String: Any]) {
    missingRequiredKeys = Self.requiredKeys.filter { values[$0] == nil }
    invalidRequiredKeys = Self.requiredKeys.compactMap { key in
      guard let value = values[key] else { return nil }
      return Self.hasExpectedType(value, for: key) ? nil : key
    }
    route = values.string("route")
    source = values.string("source")
    sourceAccessRequirement = values.string("sourceAccessRequirement")
    securityScopeHeld = values.bool("securityScopeHeld")
    productShape = values.string("productShape")
    candidateProductShape = values.string("candidateProductShape")
    projection = values.string("projection")
    detectedProjectionKind = values.string("detectedProjectionKind")
    effectiveProjectionKind = values.string("effectiveProjectionKind")
    placement = values.string("placement")
    stereoLayout = values.string("stereoLayout")
    sceneContent = values.string("sceneContent")
    customSceneRequestedOpen = values.bool("customSceneRequestedOpen")
    windowLifecycle = values.string("windowLifecycle")
    sceneLifecycle = values.string("sceneLifecycle")
    immersiveSceneLoaded = values.bool("immersiveSceneLoaded")
    immersiveSceneEnabled = values.bool("immersiveSceneEnabled")
    panoramaRootEnabled = values.bool("panoramaRootEnabled")
    presentationSettled = values.bool("presentationSettled")
    presentationBindingAttached = values.bool("presentationBindingAttached")
    realityKitBindingActive = values.bool("realityKitBindingActive")
    presentationGeometry = values.string("presentationGeometry")
    planarMeshActive = values.bool("planarMeshActive")
    presentationBinding = values.string("presentationBinding")
    sceneContainer = values.string("sceneContainer")
    parentIsWindowRoot = values.bool("parentIsWindowRoot")
    parentIsDockedRoot = values.bool("parentIsDockedRoot")
    parentIsPanoramaRoot = values.bool("parentIsPanoramaRoot")
    actualImmersiveViewingMode = values.string("actualImmersiveViewingMode")
    immersiveModeChangeSequence = values.uint64("immersiveModeChangeSequence")
    lastAcknowledgedImmersiveModeSurface = values.string(
      "lastAcknowledgedImmersiveModeSurface")
    actualViewingMode = values.string("actualViewingMode")
    viewingModeChangeSequence = values.uint64("viewingModeChangeSequence")
    lastAcknowledgedViewingModeSurface = values.string("lastAcknowledgedViewingModeSurface")
    videoEntityIdentity = values.string("videoEntityIdentity")
    rendererIdentity = values.string("rendererIdentity")
    rendererGraphID = values.string("rendererGraphID")
    rendererSynchronizerIdentity = values.string("rendererSynchronizerIdentity")
    rendererMatchesSession = values.bool("rendererMatchesSession")
    rendererError = values.string("rendererError")
    componentRenderingStatus = values.string("componentRenderingStatus")
    displayedPixelBuffer = values.bool("displayedPixelBuffer")
    displayedPixelBufferIdentity = values.string("displayedPixelBufferIdentity")
    sampleCount = values.uint64("sampleCount")
    streamEpoch = values.uint64("streamEpoch")
    rendererFlushCount = values.uint64("rendererFlushCount")
    formatRevision = values.uint64("effectiveFormatRevision")
    currentSeconds = values.double("currentSeconds")
    status = values.string("status")
    rendererTimelineRate = values.double("rendererTimelineRate")
    audioRendererSampleBufferCount = values.uint64("audioRendererSampleBufferCount")
    audioRendererMediaSessionID = values.string("audioRendererMediaSessionID")
    audioRendererGraphID = values.string("audioRendererGraphID")
    audioRendererIdentity = values.string("audioRendererIdentity")
    audioRendererVideoRendererIdentity = values.string("audioRendererVideoRendererIdentity")
    audioRendererSynchronizerIdentity = values.string("audioRendererSynchronizerIdentity")
    audioRendererStreamEpoch = values.uint64("audioRendererStreamEpoch")
    audioRendererError = values.string("audioRendererError")
    audioRendererVolume = values.double("audioRendererVolume")
    audioRendererMuted = values.bool("audioRendererMuted")
    selectedAudioStreamIndex = values.int("selectedAudioStreamIndex")
    lastCompletedOperationKind = values.string("lastCompletedOperationKind")
    lastCompletedOperationState = values.string("lastCompletedOperationState")
    lastCompletedOperationTargetTime = values.double("lastCompletedOperationTargetTime")
    mediaSessionID = values.string("mediaSessionID")
    effectiveViewPackingKind = values.string("effectiveViewPackingKind")
    effectiveHasLeftStereoEyeView = values.bool("effectiveHasLeftStereoEyeView")
    effectiveHasRightStereoEyeView = values.bool("effectiveHasRightStereoEyeView")
    coreEffectiveStereoLayout = values.string("coreEffectiveStereoLayout")
    routeSwitchOperationState = values.string("routeSwitchOperationState")
    dockingAnchorReady = values.bool("dockingAnchorReady")
    dockingAnchorHasModel = values.bool("dockingAnchorHasModel")
    dockingAnchorComponentCount = values.int("dockingAnchorComponentCount")
    dockedRootBoundToAnchor = values.bool("dockedRootBoundToAnchor")
    dockingAnchorPreservesAuthoredTransform = values.bool(
      "dockingAnchorPreservesAuthoredTransform")
    hasActiveMediaSession = values.bool("hasActiveMediaSession")
    hasVideoEntity = values.bool("hasVideoEntity")
    lastCleanupMediaSessionID = values.string("lastCleanupMediaSessionID")
    lastCleanupOperationKind = values.string("lastCleanupOperationKind")
    lastCleanupOperationState = values.string("lastCleanupOperationState")
    lastCleanupRendererFlushCount = values.uint64("lastCleanupRendererFlushCount")
    lastCleanupVideoProviderCancelled = values.bool("lastCleanupVideoProviderCancelled")
    lastCleanupAudioProviderCancelled = values.bool("lastCleanupAudioProviderCancelled")
    lastCleanupAudioRendererFlushed = values.bool("lastCleanupAudioRendererFlushed")
    lastCleanupVideoRendererFlushed = values.bool("lastCleanupVideoRendererFlushed")
    lastCleanupRealityKitBindingActive = values.bool("lastCleanupRealityKitBindingActive")
    lastCleanupPresentationBindingAttached = values.bool(
      "lastCleanupPresentationBindingAttached")
    presentationRollbackState = values.string("presentationRollbackState")
    presentationRollbackError = values.string("presentationRollbackError")
  }

  private static let requiredKeys = [
    "route", "source", "sourceAccessRequirement", "securityScopeHeld", "productShape",
    "candidateProductShape", "projection",
    "detectedProjectionKind", "effectiveProjectionKind", "placement", "stereoLayout",
    "sceneContent", "customSceneRequestedOpen", "windowLifecycle", "sceneLifecycle",
    "immersiveSceneLoaded", "immersiveSceneEnabled", "panoramaRootEnabled",
    "presentationSettled", "presentationBindingAttached", "realityKitBindingActive",
    "presentationGeometry", "planarMeshActive",
    "presentationBinding", "sceneContainer", "parentIsWindowRoot", "parentIsDockedRoot",
    "parentIsPanoramaRoot", "actualImmersiveViewingMode", "immersiveModeChangeSequence",
    "lastAcknowledgedImmersiveModeSurface", "actualViewingMode",
    "viewingModeChangeSequence", "lastAcknowledgedViewingModeSurface",
    "videoEntityIdentity", "rendererIdentity", "rendererGraphID",
    "rendererSynchronizerIdentity", "rendererMatchesSession", "rendererError",
    "componentRenderingStatus", "displayedPixelBuffer", "displayedPixelBufferIdentity",
    "sampleCount", "streamEpoch", "rendererFlushCount", "effectiveFormatRevision",
    "currentSeconds", "status", "rendererTimelineRate", "audioRendererSampleBufferCount",
    "audioRendererMediaSessionID", "audioRendererGraphID", "audioRendererIdentity",
    "audioRendererVideoRendererIdentity", "audioRendererSynchronizerIdentity",
    "audioRendererStreamEpoch", "audioRendererError", "audioRendererVolume",
    "audioRendererMuted",
    "selectedAudioStreamIndex",
    "lastCompletedOperationKind", "lastCompletedOperationState",
    "lastCompletedOperationTargetTime", "mediaSessionID", "effectiveViewPackingKind",
    "effectiveHasLeftStereoEyeView", "effectiveHasRightStereoEyeView",
    "coreEffectiveStereoLayout", "routeSwitchOperationState", "dockingAnchorReady",
    "dockingAnchorHasModel", "dockingAnchorComponentCount", "dockedRootBoundToAnchor",
    "dockingAnchorPreservesAuthoredTransform", "hasActiveMediaSession", "hasVideoEntity",
    "lastCleanupMediaSessionID", "lastCleanupOperationKind", "lastCleanupOperationState",
    "lastCleanupRendererFlushCount", "lastCleanupVideoProviderCancelled",
    "lastCleanupAudioProviderCancelled", "lastCleanupAudioRendererFlushed",
    "lastCleanupVideoRendererFlushed", "lastCleanupRealityKitBindingActive",
    "lastCleanupPresentationBindingAttached", "presentationRollbackState",
    "presentationRollbackError",
  ]

  private static let boolKeys: Set<String> = [
    "securityScopeHeld", "customSceneRequestedOpen", "immersiveSceneLoaded",
    "immersiveSceneEnabled",
    "panoramaRootEnabled", "presentationSettled", "presentationBindingAttached",
    "realityKitBindingActive", "planarMeshActive", "parentIsWindowRoot", "parentIsDockedRoot",
    "parentIsPanoramaRoot", "rendererMatchesSession", "displayedPixelBuffer",
    "audioRendererMuted", "effectiveHasLeftStereoEyeView", "effectiveHasRightStereoEyeView",
    "dockingAnchorReady", "dockingAnchorHasModel", "dockedRootBoundToAnchor",
    "dockingAnchorPreservesAuthoredTransform", "hasActiveMediaSession", "hasVideoEntity",
    "lastCleanupVideoProviderCancelled", "lastCleanupAudioProviderCancelled",
    "lastCleanupAudioRendererFlushed", "lastCleanupVideoRendererFlushed",
    "lastCleanupRealityKitBindingActive", "lastCleanupPresentationBindingAttached",
  ]

  private static let uint64Keys: Set<String> = [
    "immersiveModeChangeSequence", "viewingModeChangeSequence", "sampleCount", "streamEpoch",
    "rendererFlushCount", "effectiveFormatRevision", "audioRendererSampleBufferCount",
    "audioRendererStreamEpoch", "lastCleanupRendererFlushCount",
  ]

  private static let doubleKeys: Set<String> = [
    "currentSeconds", "rendererTimelineRate", "audioRendererVolume",
    "lastCompletedOperationTargetTime",
  ]

  private static let intKeys: Set<String> = [
    "selectedAudioStreamIndex", "dockingAnchorComponentCount",
  ]

  private static func hasExpectedType(_ value: Any, for key: String) -> Bool {
    if boolKeys.contains(key) { return value is Bool }
    if uint64Keys.contains(key) {
      if value is UInt64 { return true }
      if let value = value as? Int { return value >= 0 }
      return false
    }
    if doubleKeys.contains(key) { return value is Double || value is Float }
    if intKeys.contains(key) { return value is Int }
    return value is String
  }
}

enum VisionRegressionEvidenceContract {
  static func controlAudioBaselineFailures(
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    requireHealthySharedAudioGraph(target, failures: &failures)
    return failures
  }

  static func presentationFailures(
    expectedRoute: VisionRegressionRoute,
    expectedShape: VisionProductShape,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = activePlaybackFailures(baseline: baseline, target: target)
    require(baseline.route == expectedRoute.rawValue, "route.baselineMismatch", into: &failures)
    require(target.route == expectedRoute.rawValue, "route.targetMismatch", into: &failures)
    require(target.productShape == expectedShape.rawValue, "shape.notReached", into: &failures)
    require(
      target.formatRevision == baseline.formatRevision,
      "projection.unexpectedRevisionChange",
      into: &failures
    )

    switch expectedShape {
    case .flatWindow:
      require(target.projection == VisionProjection.flat.rawValue, "flat.projection", into: &failures)
      requirePlanarPresentation(target, failures: &failures)
      requireWindowBinding(target, failures: &failures)
    case .portalWindow:
      require(target.projection == VisionProjection.sourcePanoramic.rawValue, "portal.projection", into: &failures)
      requirePanoramicProjection(target, failures: &failures)
      requireImmersivePresentation(target, failures: &failures)
      requireWindowBinding(target, failures: &failures)
      require(
        normalized(target.actualImmersiveViewingMode).contains("portal"),
        "portal.actualMode",
        into: &failures
      )
      requireModeAcknowledgementIfChanged(
        baseline: baseline,
        target: target,
        expectedSurface: VisionSurface.playbackWindow,
        failures: &failures
      )
    case .docked:
      require(target.projection == VisionProjection.flat.rawValue, "docked.projection", into: &failures)
      requirePlanarPresentation(target, failures: &failures)
      requireSceneBinding(target, failures: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "docked.scene", into: &failures)
      require(target.parentIsDockedRoot, "docked.parent", into: &failures)
      require(target.dockingAnchorReady, "docked.anchorMissing", into: &failures)
      require(!target.dockingAnchorHasModel, "docked.anchorIsNotPure", into: &failures)
      require(target.dockedRootBoundToAnchor, "docked.rootNotBound", into: &failures)
      require(
        target.dockingAnchorPreservesAuthoredTransform,
        "docked.authoredTransformNotPreserved",
        into: &failures
      )
      require(target.immersiveSceneLoaded, "docked.sceneAssetNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "docked.sceneAssetNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "docked.panoramaRootVisible", into: &failures)
    case .panorama:
      require(target.projection == VisionProjection.sourcePanoramic.rawValue, "panorama.projection", into: &failures)
      requirePanoramicProjection(target, failures: &failures)
      requireImmersivePresentation(target, failures: &failures)
      requireSceneBinding(target, failures: &failures)
      require(target.sceneContent == VisionSceneContent.blackPanorama.rawValue, "panorama.scene", into: &failures)
      require(target.parentIsPanoramaRoot, "panorama.parent", into: &failures)
      require(target.panoramaRootEnabled, "panorama.rootNotVisible", into: &failures)
      require(!target.immersiveSceneEnabled, "panorama.customSceneVisible", into: &failures)
      require(
        normalized(target.actualImmersiveViewingMode).contains("progressive"),
        "panorama.actualMode",
        into: &failures
      )
      requireModeAcknowledgementIfChanged(
        baseline: baseline,
        target: target,
        expectedSurface: VisionSurface.scene,
        failures: &failures
      )
    }
    return failures
  }

  static func stereoFailures(
    expectedLayout: VisionStereoLayout,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = activePlaybackFailures(baseline: baseline, target: target)
    require(target.productShape == baseline.productShape, "stereo.shapeChanged", into: &failures)
    require(target.projection == baseline.projection, "stereo.projectionChanged", into: &failures)
    require(
      target.detectedProjectionKind == baseline.detectedProjectionKind,
      "stereo.detectedProjectionChanged",
      into: &failures
    )
    require(
      target.effectiveProjectionKind == baseline.effectiveProjectionKind,
      "stereo.effectiveProjectionChanged",
      into: &failures
    )
    require(target.placement == baseline.placement, "stereo.placementChanged", into: &failures)
    require(target.sceneLifecycle == baseline.sceneLifecycle, "stereo.sceneLifecycleChanged", into: &failures)
    require(target.sceneContent == baseline.sceneContent, "stereo.sceneContentChanged", into: &failures)
    require(
      target.customSceneRequestedOpen == baseline.customSceneRequestedOpen,
      "stereo.sceneIntentChanged",
      into: &failures
    )
    require(target.stereoLayout == expectedLayout.rawValue, "stereo.layout", into: &failures)
    require(target.coreEffectiveStereoLayout == expectedLayout.rawValue, "stereo.coreLayout", into: &failures)
    require(target.formatRevision > baseline.formatRevision, "stereo.revisionDidNotAdvance", into: &failures)
    require(
      target.viewingModeChangeSequence > baseline.viewingModeChangeSequence,
      "stereo.viewingModeAcknowledgementMissing",
      into: &failures
    )
    require(
      target.lastAcknowledgedViewingModeSurface == target.presentationBinding,
      "stereo.viewingModeAcknowledgedOnWrongSurface",
      into: &failures
    )

    switch expectedLayout {
    case .mono:
      require(target.effectiveViewPackingKind == "none", "stereo.monoPacking", into: &failures)
      require(!target.effectiveHasLeftStereoEyeView, "stereo.monoLeftEye", into: &failures)
      require(!target.effectiveHasRightStereoEyeView, "stereo.monoRightEye", into: &failures)
      require(normalized(target.actualViewingMode).contains("mono"), "stereo.actualMono", into: &failures)
    case .sideBySide:
      require(normalized(target.effectiveViewPackingKind).contains("sidebyside"), "stereo.sideBySidePacking", into: &failures)
      requireStereoEyes(target, failures: &failures)
      require(normalized(target.actualViewingMode).contains("stereo"), "stereo.actualStereo", into: &failures)
    case .overUnder:
      let packing = normalized(target.effectiveViewPackingKind)
      require(packing.contains("overunder") || packing.contains("topbottom"), "stereo.overUnderPacking", into: &failures)
      requireStereoEyes(target, failures: &failures)
      require(normalized(target.actualViewingMode).contains("stereo"), "stereo.actualStereo", into: &failures)
    }
    return failures
  }

  static func preparedSessionFailures(
    expectedRoute: VisionRegressionRoute,
    sceneBaseline: VisionRegressionSceneBaseline = .closed,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    require(target.route == expectedRoute.rawValue, "prepare.route", into: &failures)
    require(target.source != "none", "prepare.source", into: &failures)
    require(target.sourceAccessRequirement != "none", "prepare.sourceAccess", into: &failures)
    requireSourceAccessActive(target, failures: &failures)
    require(target.mediaSessionID != "none", "prepare.session", into: &failures)
    require(target.rendererIdentity != "none", "prepare.renderer", into: &failures)
    require(target.rendererGraphID != "none", "prepare.rendererGraph", into: &failures)
    require(
      target.rendererSynchronizerIdentity != "none",
      "prepare.synchronizer",
      into: &failures
    )
    require(target.videoEntityIdentity != "none", "prepare.entity", into: &failures)
    require(target.hasActiveMediaSession, "prepare.sessionSlot", into: &failures)
    require(target.hasVideoEntity, "prepare.videoEntity", into: &failures)
    require(target.productShape == VisionProductShape.flatWindow.rawValue, "prepare.shape", into: &failures)
    require(target.projection == VisionProjection.flat.rawValue, "prepare.projection", into: &failures)
    requirePlanarPresentation(target, failures: &failures)
    require(target.stereoLayout == VisionStereoLayout.mono.rawValue, "prepare.stereo", into: &failures)
    require(target.coreEffectiveStereoLayout == VisionStereoLayout.mono.rawValue, "prepare.coreStereo", into: &failures)
    require(target.status == "Playing", "prepare.status", into: &failures)
    require(target.rendererTimelineRate > 0, "prepare.rate", into: &failures)
    require(target.sampleCount > 0, "prepare.sample", into: &failures)
    require(target.windowLifecycle == "open", "prepare.window", into: &failures)
    requireWindowBinding(target, failures: &failures)
    switch sceneBaseline {
    case .closed:
      require(target.sceneLifecycle == "closed", "prepare.scene", into: &failures)
      require(target.sceneContent == "none", "prepare.sceneContent", into: &failures)
      require(!target.customSceneRequestedOpen, "prepare.sceneIntent", into: &failures)
      require(!target.immersiveSceneEnabled, "prepare.sceneAssetVisible", into: &failures)
      require(!target.panoramaRootEnabled, "prepare.panoramaRootVisible", into: &failures)
    case .customSceneOpen:
      require(target.sceneLifecycle == "open", "prepare.scene", into: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "prepare.sceneContent", into: &failures)
      require(target.customSceneRequestedOpen, "prepare.sceneIntent", into: &failures)
      require(target.immersiveSceneLoaded, "prepare.sceneAssetNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "prepare.sceneAssetNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "prepare.panoramaRootVisible", into: &failures)
    }
    requireActiveOutput(target, failures: &failures)
    return failures
  }

  static func lifecycleFailures(
    expected: VisionRegressionLifecycle,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    require(!target.hasActiveMediaSession, "lifecycle.mediaSessionCreated", into: &failures)
    require(!target.hasVideoEntity, "lifecycle.videoEntityCreated", into: &failures)
    require(target.productShape == "none", "lifecycle.productShapeClaimed", into: &failures)
    switch expected {
    case .playbackWindowOpenWithoutMedia:
      require(target.windowLifecycle == "open", "lifecycle.windowNotOpen", into: &failures)
      require(target.sceneLifecycle == "closed", "lifecycle.sceneUnexpectedlyOpen", into: &failures)
    case .playbackWindowCloseWithoutMedia:
      require(target.windowLifecycle == "closed", "lifecycle.windowNotClosed", into: &failures)
      require(target.sceneLifecycle == "closed", "lifecycle.sceneUnexpectedlyOpen", into: &failures)
    case .customSceneOpenWithoutMedia:
      require(target.windowLifecycle == "closed", "lifecycle.windowUnexpectedlyOpen", into: &failures)
      require(target.sceneLifecycle == "open", "lifecycle.sceneNotOpen", into: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "lifecycle.sceneContent", into: &failures)
      require(target.customSceneRequestedOpen, "lifecycle.sceneIntent", into: &failures)
      require(target.immersiveSceneLoaded, "lifecycle.sceneAssetNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "lifecycle.sceneAssetNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "lifecycle.panoramaRootVisible", into: &failures)
    case .customSceneCloseWithoutMedia:
      require(target.windowLifecycle == "closed", "lifecycle.windowUnexpectedlyOpen", into: &failures)
      require(target.sceneLifecycle == "closed", "lifecycle.sceneNotClosed", into: &failures)
      require(target.sceneContent == "none", "lifecycle.sceneContentRetained", into: &failures)
      require(!target.customSceneRequestedOpen, "lifecycle.sceneIntentRetained", into: &failures)
      require(!target.immersiveSceneEnabled, "lifecycle.sceneAssetVisible", into: &failures)
      require(!target.panoramaRootEnabled, "lifecycle.panoramaRootVisible", into: &failures)
    }
    return failures
  }

  static func sceneOpenWithoutMigrationFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = activePlaybackFailures(baseline: baseline, target: target)
    requireSameAudioGraph(baseline: baseline, target: target, failures: &failures)
    require(target.route == expectedRoute.rawValue, "sceneOpen.route", into: &failures)
    require(target.productShape == baseline.productShape, "sceneOpen.shapeChanged", into: &failures)
    require(target.placement == baseline.placement, "sceneOpen.placementChanged", into: &failures)
    requireWindowBinding(target, failures: &failures)
    require(target.sceneLifecycle == "open", "sceneOpen.sceneNotOpen", into: &failures)
    require(target.sceneContent == VisionSceneContent.customScene.rawValue, "sceneOpen.content", into: &failures)
    require(target.customSceneRequestedOpen, "sceneOpen.intent", into: &failures)
    requireUnchangedProjectionAndStereo(
      baseline: baseline,
      target: target,
      prefix: "sceneOpen",
      failures: &failures
    )
    require(target.immersiveSceneLoaded, "sceneOpen.assetNotLoaded", into: &failures)
    require(target.immersiveSceneEnabled, "sceneOpen.assetNotVisible", into: &failures)
    require(!target.panoramaRootEnabled, "sceneOpen.panoramaRootVisible", into: &failures)
    return failures
  }

  static func sceneCloseWithoutMigrationFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = activePlaybackFailures(baseline: baseline, target: target)
    requireSameAudioGraph(baseline: baseline, target: target, failures: &failures)
    require(target.route == expectedRoute.rawValue, "sceneClose.route", into: &failures)
    require(target.productShape == baseline.productShape, "sceneClose.shapeChanged", into: &failures)
    require(target.placement == baseline.placement, "sceneClose.placementChanged", into: &failures)
    requireWindowBinding(target, failures: &failures)
    require(target.sceneLifecycle == "closed", "sceneClose.sceneNotClosed", into: &failures)
    require(target.sceneContent == "none", "sceneClose.contentRetained", into: &failures)
    require(!target.customSceneRequestedOpen, "sceneClose.intentRetained", into: &failures)
    requireUnchangedProjectionAndStereo(
      baseline: baseline,
      target: target,
      prefix: "sceneClose",
      failures: &failures
    )
    require(!target.immersiveSceneEnabled, "sceneClose.sceneAssetVisible", into: &failures)
    require(!target.panoramaRootEnabled, "sceneClose.panoramaRootVisible", into: &failures)
    return failures
  }

  static func pauseFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(target.status == "Paused", "control.pause.status", into: &failures)
    require(abs(target.rendererTimelineRate) < 0.001, "control.pause.rate", into: &failures)
    require(baseline.status == "Playing", "control.pause.baselineStatus", into: &failures)
    require(baseline.rendererTimelineRate > 0, "control.pause.baselineRate", into: &failures)
    require(target.lastCompletedOperationKind == "pause", "control.pause.operationKind", into: &failures)
    require(target.lastCompletedOperationState == "completed", "control.pause.operationState", into: &failures)
    requireUnchangedVideoStream(baseline: baseline, target: target, failures: &failures)
    require(
      target.audioRendererStreamEpoch == baseline.audioRendererStreamEpoch,
      "control.pause.audioEpochChanged",
      into: &failures
    )
    return failures
  }

  static func playFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(baseline.status == "Paused", "control.play.baselineStatus", into: &failures)
    require(abs(baseline.rendererTimelineRate) < 0.001, "control.play.baselineRate", into: &failures)
    require(target.status == "Playing", "control.play.status", into: &failures)
    require(target.rendererTimelineRate > 0, "control.play.rate", into: &failures)
    require(target.lastCompletedOperationKind == "play", "control.play.operationKind", into: &failures)
    require(target.lastCompletedOperationState == "completed", "control.play.operationState", into: &failures)
    requireFreshOutput(baseline: baseline, target: target, failures: &failures)
    requireFreshAudio(baseline: baseline, target: target, failures: &failures)
    requireUnchangedVideoStream(baseline: baseline, target: target, failures: &failures)
    require(
      target.audioRendererStreamEpoch == baseline.audioRendererStreamEpoch,
      "control.play.audioEpochChanged",
      into: &failures
    )
    return failures
  }

  static func rateFailures(
    expectedRoute: VisionRegressionRoute,
    expectedRate: Double,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(baseline.status == "Playing", "control.rate.baselineStatus", into: &failures)
    require(target.status == "Playing", "control.rate.status", into: &failures)
    require(abs(target.rendererTimelineRate - expectedRate) < 0.001, "control.rate.synchronizer", into: &failures)
    require(target.lastCompletedOperationKind == "setRate", "control.rate.operationKind", into: &failures)
    require(target.lastCompletedOperationState == "completed", "control.rate.operationState", into: &failures)
    requireFreshOutput(baseline: baseline, target: target, failures: &failures)
    requireFreshAudio(baseline: baseline, target: target, failures: &failures)
    require(target.streamEpoch == baseline.streamEpoch, "control.rate.streamEpoch", into: &failures)
    require(target.rendererFlushCount == baseline.rendererFlushCount, "control.rate.flush", into: &failures)
    require(
      target.audioRendererStreamEpoch == baseline.audioRendererStreamEpoch,
      "control.rate.audioEpochChanged",
      into: &failures
    )
    return failures
  }

  static func seekFailures(
    expectedRoute: VisionRegressionRoute,
    expectedSeconds: Double,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(target.status == baseline.status, "control.seek.statusChanged", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "control.seek.rateChanged",
      into: &failures
    )
    require(abs(target.currentSeconds - expectedSeconds) < 0.35, "control.seek.target", into: &failures)
    require(target.streamEpoch > baseline.streamEpoch, "control.seek.streamEpoch", into: &failures)
    require(target.rendererFlushCount > baseline.rendererFlushCount, "control.seek.flush", into: &failures)
    require(target.lastCompletedOperationKind == "seek", "control.seek.operationKind", into: &failures)
    require(target.lastCompletedOperationState == "completed", "control.seek.operationState", into: &failures)
    require(
      abs(target.lastCompletedOperationTargetTime - expectedSeconds) < 0.001,
      "control.seek.operationTarget",
      into: &failures
    )
    require(target.sampleCount > baseline.sampleCount, "control.seek.freshSample", into: &failures)
    require(target.displayedPixelBufferIdentity != baseline.displayedPixelBufferIdentity, "control.seek.freshPixel", into: &failures)
    requireFreshAudio(baseline: baseline, target: target, failures: &failures)
    require(
      target.audioRendererStreamEpoch > baseline.audioRendererStreamEpoch,
      "control.seek.audioEpoch",
      into: &failures
    )
    return failures
  }

  static func audioTrackFailures(
    expectedRoute: VisionRegressionRoute,
    expectedStreamIndex: Int,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(expectedStreamIndex != baseline.selectedAudioStreamIndex, "control.audioTrack.notAlternate", into: &failures)
    require(target.selectedAudioStreamIndex == expectedStreamIndex, "control.audioTrack.selection", into: &failures)
    require(target.audioRendererSampleBufferCount > baseline.audioRendererSampleBufferCount, "control.audioTrack.freshPCM", into: &failures)
    require(
      target.audioRendererStreamEpoch > baseline.audioRendererStreamEpoch,
      "control.audioTrack.audioEpoch",
      into: &failures
    )
    require(target.status == baseline.status, "control.audioTrack.statusChanged", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "control.audioTrack.rateChanged",
      into: &failures
    )
    requireUnchangedVideoStream(baseline: baseline, target: target, failures: &failures)
    requireHealthySharedAudioGraph(target, failures: &failures)
    return failures
  }

  static func volumeFailures(
    expectedRoute: VisionRegressionRoute,
    expectedVolume: Double,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(abs(expectedVolume - baseline.audioRendererVolume) > 0.001, "control.volume.notChanged", into: &failures)
    require(abs(target.audioRendererVolume - expectedVolume) < 0.001, "control.volume.renderer", into: &failures)
    require(target.audioRendererSampleBufferCount > 0, "control.volume.audioRendererMissing", into: &failures)
    require(target.status == baseline.status, "control.volume.statusChanged", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "control.volume.rateChanged",
      into: &failures
    )
    requireUnchangedVideoStream(baseline: baseline, target: target, failures: &failures)
    require(
      target.audioRendererStreamEpoch == baseline.audioRendererStreamEpoch,
      "control.volume.audioEpochChanged",
      into: &failures
    )
    requireHealthySharedAudioGraph(target, failures: &failures)
    return failures
  }

  static func muteFailures(
    expectedRoute: VisionRegressionRoute,
    expectedMuted: Bool,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = samePlaybackGraphFailures(expectedRoute: expectedRoute, baseline: baseline, target: target)
    require(expectedMuted != baseline.audioRendererMuted, "control.mute.notChanged", into: &failures)
    require(target.audioRendererMuted == expectedMuted, "control.mute.renderer", into: &failures)
    require(target.audioRendererSampleBufferCount > 0, "control.mute.audioRendererMissing", into: &failures)
    require(target.status == baseline.status, "control.mute.statusChanged", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "control.mute.rateChanged",
      into: &failures
    )
    requireUnchangedVideoStream(baseline: baseline, target: target, failures: &failures)
    require(
      target.audioRendererStreamEpoch == baseline.audioRendererStreamEpoch,
      "control.mute.audioEpochChanged",
      into: &failures
    )
    requireHealthySharedAudioGraph(target, failures: &failures)
    return failures
  }

  static func reopenFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(baseline, role: "baseline")
    failures.append(contentsOf: schemaFailures(target, role: "target"))
    require(target.route == expectedRoute.rawValue, "control.reopen.route", into: &failures)
    require(target.source == baseline.source, "control.reopen.source", into: &failures)
    require(
      baseline.sourceAccessRequirement != "none"
        && target.sourceAccessRequirement == baseline.sourceAccessRequirement,
      "control.reopen.sourceAccessRequirement",
      into: &failures
    )
    require(target.mediaSessionID != baseline.mediaSessionID, "control.reopen.session", into: &failures)
    require(target.rendererIdentity != baseline.rendererIdentity, "control.reopen.renderer", into: &failures)
    require(
      target.rendererGraphID != baseline.rendererGraphID && target.rendererGraphID != "none",
      "control.reopen.rendererGraph",
      into: &failures
    )
    require(
      target.rendererSynchronizerIdentity != baseline.rendererSynchronizerIdentity
        && target.rendererSynchronizerIdentity != "none",
      "control.reopen.synchronizer",
      into: &failures
    )
    require(target.videoEntityIdentity != baseline.videoEntityIdentity, "control.reopen.entity", into: &failures)
    require(
      target.audioRendererIdentity != baseline.audioRendererIdentity,
      "control.reopen.audioRenderer",
      into: &failures
    )
    require(target.productShape == baseline.productShape, "control.reopen.shape", into: &failures)
    require(target.placement == baseline.placement, "control.reopen.placement", into: &failures)
    require(target.sceneLifecycle == baseline.sceneLifecycle, "control.reopen.scene", into: &failures)
    requireUnchangedProjectionAndStereo(
      baseline: baseline,
      target: target,
      prefix: "control.reopen",
      failures: &failures
    )
    require(target.sampleCount > 0, "control.reopen.freshSample", into: &failures)
    require(
      target.displayedPixelBufferIdentity != baseline.displayedPixelBufferIdentity,
      "control.reopen.freshPixel",
      into: &failures
    )
    requireActiveOutput(target, failures: &failures)
    requireSourceAccessActive(target, failures: &failures)
    requireHealthySharedAudioGraph(target, failures: &failures)
    require(target.lastCleanupMediaSessionID == baseline.mediaSessionID, "control.reopen.oldSessionCleanup", into: &failures)
    require(target.lastCleanupOperationKind == "close", "control.reopen.oldCloseKind", into: &failures)
    require(target.lastCleanupOperationState == "completed", "control.reopen.oldCloseState", into: &failures)
    require(target.lastCleanupRendererFlushCount > 0, "control.reopen.oldRendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoProviderCancelled, "control.reopen.oldVideoProviderActive", into: &failures)
    require(target.lastCleanupAudioProviderCancelled, "control.reopen.oldAudioProviderActive", into: &failures)
    require(target.lastCleanupAudioRendererFlushed, "control.reopen.oldAudioRendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoRendererFlushed, "control.reopen.oldVideoRendererNotFlushed", into: &failures)
    require(!target.lastCleanupRealityKitBindingActive, "control.reopen.oldRealityBindingActive", into: &failures)
    require(!target.lastCleanupPresentationBindingAttached, "control.reopen.oldPresentationBindingAttached", into: &failures)
    return failures
  }

  static func mediaCloseSceneRestorationFailures(
    mediaSessionID: String,
    baseline: VisionRegressionSceneBaseline,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = cleanupFailures(
      mediaSessionID: mediaSessionID,
      target: target,
      requirePresentationClosed: false
    )
    require(target.windowLifecycle == "closed", "mediaClose.windowOpen", into: &failures)
    switch baseline {
    case .closed:
      require(target.sceneLifecycle == "closed", "mediaClose.sceneNotClosed", into: &failures)
      require(target.sceneContent == "none", "mediaClose.sceneContent", into: &failures)
      require(!target.customSceneRequestedOpen, "mediaClose.sceneIntent", into: &failures)
      require(!target.immersiveSceneEnabled, "mediaClose.customSceneVisible", into: &failures)
      require(!target.panoramaRootEnabled, "mediaClose.panoramaRootVisible", into: &failures)
    case .customSceneOpen:
      require(target.sceneLifecycle == "open", "mediaClose.sceneNotOpen", into: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "mediaClose.customScene", into: &failures)
      require(target.customSceneRequestedOpen, "mediaClose.sceneIntent", into: &failures)
      require(target.immersiveSceneLoaded, "mediaClose.customSceneNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "mediaClose.customSceneNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "mediaClose.panoramaRootVisible", into: &failures)
    }
    return failures
  }

  static func activeMediaSceneRestorationFailures(
    baseline: VisionRegressionSceneBaseline,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    switch baseline {
    case .closed:
      require(target.sceneLifecycle == "closed", "sceneRestore.sceneNotClosed", into: &failures)
      require(target.sceneContent == "none", "sceneRestore.sceneContent", into: &failures)
      require(!target.customSceneRequestedOpen, "sceneRestore.sceneIntent", into: &failures)
      require(!target.immersiveSceneEnabled, "sceneRestore.customSceneVisible", into: &failures)
      require(!target.panoramaRootEnabled, "sceneRestore.panoramaRootVisible", into: &failures)
    case .customSceneOpen:
      require(target.sceneLifecycle == "open", "sceneRestore.sceneNotOpen", into: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "sceneRestore.customScene", into: &failures)
      require(target.customSceneRequestedOpen, "sceneRestore.sceneIntent", into: &failures)
      require(target.immersiveSceneLoaded, "sceneRestore.customSceneNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "sceneRestore.customSceneNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "sceneRestore.panoramaRootVisible", into: &failures)
    }
    return failures
  }

  static func presentationEdgeFailures(
    edge: VisionRegressionEdge,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    switch edge {
    case .dockedToFlatWindow:
      require(target.productShape == VisionProductShape.flatWindow.rawValue, "edge.flat.shape", into: &failures)
      require(target.sceneLifecycle == "open", "edge.flat.sceneNotOpen", into: &failures)
      require(target.sceneContent == VisionSceneContent.customScene.rawValue, "edge.flat.customScene", into: &failures)
      require(target.customSceneRequestedOpen, "edge.flat.sceneIntent", into: &failures)
      require(target.immersiveSceneLoaded, "edge.flat.customSceneNotLoaded", into: &failures)
      require(target.immersiveSceneEnabled, "edge.flat.customSceneNotVisible", into: &failures)
      require(!target.panoramaRootEnabled, "edge.flat.panoramaRootVisible", into: &failures)
      require(target.dockingAnchorReady, "edge.flat.anchorMissing", into: &failures)
      require(!target.dockingAnchorHasModel, "edge.flat.anchorHasModel", into: &failures)
      require(target.dockedRootBoundToAnchor, "edge.flat.anchorNotBound", into: &failures)
      require(target.dockingAnchorPreservesAuthoredTransform, "edge.flat.anchorTransform", into: &failures)
    case .dockedToPanorama:
      require(target.productShape == VisionProductShape.panorama.rawValue, "edge.panorama.shape", into: &failures)
      require(target.sceneLifecycle == "open", "edge.panorama.sceneNotOpen", into: &failures)
      require(target.sceneContent == VisionSceneContent.blackPanorama.rawValue, "edge.panorama.blackScene", into: &failures)
      require(target.customSceneRequestedOpen, "edge.panorama.sceneIntentLost", into: &failures)
      require(target.panoramaRootEnabled, "edge.panorama.rootNotVisible", into: &failures)
      require(!target.immersiveSceneEnabled, "edge.panorama.customSceneVisible", into: &failures)
    case .panoramaToFlatWindow:
      require(target.productShape == VisionProductShape.flatWindow.rawValue, "edge.panoramaToFlat.shape", into: &failures)
      require(target.sceneLifecycle == "closed", "edge.panoramaToFlat.sceneNotClosed", into: &failures)
      require(target.sceneContent == "none", "edge.panoramaToFlat.sceneContent", into: &failures)
      require(!target.customSceneRequestedOpen, "edge.panoramaToFlat.sceneIntent", into: &failures)
      require(!target.immersiveSceneEnabled, "edge.panoramaToFlat.customSceneVisible", into: &failures)
      require(!target.panoramaRootEnabled, "edge.panoramaToFlat.panoramaRootVisible", into: &failures)
    }
    return failures
  }

  static func coldSwitchFailures(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(baseline, role: "baseline")
    failures.append(contentsOf: schemaFailures(target, role: "target"))
    require(target.route == VisionRegressionRoute.ffmpegCompressed.rawValue, "routeSwitch.route", into: &failures)
    require(target.source == baseline.source && target.source != "none", "routeSwitch.source", into: &failures)
    require(
      baseline.sourceAccessRequirement != "none"
        && target.sourceAccessRequirement == baseline.sourceAccessRequirement,
      "routeSwitch.sourceAccessRequirement",
      into: &failures
    )
    require(target.mediaSessionID != baseline.mediaSessionID, "routeSwitch.session", into: &failures)
    require(target.rendererIdentity != baseline.rendererIdentity, "routeSwitch.renderer", into: &failures)
    require(
      target.rendererGraphID != baseline.rendererGraphID && target.rendererGraphID != "none",
      "routeSwitch.rendererGraph",
      into: &failures
    )
    require(
      target.rendererSynchronizerIdentity != baseline.rendererSynchronizerIdentity
        && target.rendererSynchronizerIdentity != "none",
      "routeSwitch.synchronizer",
      into: &failures
    )
    require(target.videoEntityIdentity != baseline.videoEntityIdentity, "routeSwitch.entity", into: &failures)
    require(
      target.audioRendererIdentity != baseline.audioRendererIdentity,
      "routeSwitch.audioRenderer",
      into: &failures
    )
    require(target.routeSwitchOperationState == "completed", "routeSwitch.operation", into: &failures)
    require(target.productShape == baseline.productShape, "routeSwitch.shapeChanged", into: &failures)
    require(target.placement == baseline.placement, "routeSwitch.placementChanged", into: &failures)
    require(target.sceneLifecycle == baseline.sceneLifecycle, "routeSwitch.sceneLifecycleChanged", into: &failures)
    require(target.sceneContent == baseline.sceneContent, "routeSwitch.sceneContentChanged", into: &failures)
    require(
      target.customSceneRequestedOpen == baseline.customSceneRequestedOpen,
      "routeSwitch.sceneIntentChanged",
      into: &failures
    )
    requireUnchangedProjectionAndStereo(
      baseline: baseline,
      target: target,
      prefix: "routeSwitch",
      failures: &failures
    )
    require(target.status == baseline.status, "routeSwitch.statusChanged", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "routeSwitch.rateChanged",
      into: &failures
    )
    require(
      abs(target.audioRendererVolume - baseline.audioRendererVolume) < 0.001,
      "routeSwitch.volumeChanged",
      into: &failures
    )
    require(target.audioRendererMuted == baseline.audioRendererMuted, "routeSwitch.muteChanged", into: &failures)
    require(
      target.selectedAudioStreamIndex == baseline.selectedAudioStreamIndex,
      "routeSwitch.audioTrackChanged",
      into: &failures
    )
    require(target.sampleCount > 0, "routeSwitch.freshSample", into: &failures)
    require(target.currentSeconds > baseline.currentSeconds, "routeSwitch.timeDidNotAdvance", into: &failures)
    require(
      target.displayedPixelBufferIdentity != baseline.displayedPixelBufferIdentity,
      "routeSwitch.displayedPixelDidNotAdvance",
      into: &failures
    )
    requireActiveOutput(target, failures: &failures)
    requireSourceAccessActive(target, failures: &failures)
    requireHealthySharedAudioGraph(target, failures: &failures)
    require(
      target.lastCleanupMediaSessionID == baseline.mediaSessionID,
      "routeSwitch.oldSessionCleanupMissing",
      into: &failures
    )
    require(target.lastCleanupOperationKind == "close", "routeSwitch.oldCloseKind", into: &failures)
    require(target.lastCleanupOperationState == "completed", "routeSwitch.oldCloseState", into: &failures)
    require(target.lastCleanupRendererFlushCount > 0, "routeSwitch.oldRendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoProviderCancelled, "routeSwitch.oldVideoProviderActive", into: &failures)
    require(target.lastCleanupAudioProviderCancelled, "routeSwitch.oldAudioProviderActive", into: &failures)
    require(target.lastCleanupAudioRendererFlushed, "routeSwitch.oldAudioRendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoRendererFlushed, "routeSwitch.oldVideoRendererNotFlushed", into: &failures)
    require(!target.lastCleanupRealityKitBindingActive, "routeSwitch.oldRealityBindingActive", into: &failures)
    require(!target.lastCleanupPresentationBindingAttached, "routeSwitch.oldPresentationBindingAttached", into: &failures)
    return failures
  }

  static func cleanupFailures(
    mediaSessionID: String,
    target: VisionRegressionEvidenceSnapshot,
    requirePresentationClosed: Bool = true
  ) -> [String] {
    var failures = schemaFailures(target, role: "target")
    require(!target.hasActiveMediaSession, "cleanup.mediaSessionOpen", into: &failures)
    require(!target.hasVideoEntity, "cleanup.videoEntityPresent", into: &failures)
    require(target.productShape == "none", "cleanup.presentedShapeRetained", into: &failures)
    require(target.mediaSessionID == "none", "cleanup.currentSessionRetained", into: &failures)
    require(target.route == "none", "cleanup.currentRouteRetained", into: &failures)
    require(target.source == "none", "cleanup.currentSourceRetained", into: &failures)
    require(target.sourceAccessRequirement == "none", "cleanup.sourceAccessRetained", into: &failures)
    require(!target.securityScopeHeld, "cleanup.securityScopeHeld", into: &failures)
    require(target.status == "Idle", "cleanup.statusNotIdle", into: &failures)
    require(!target.realityKitBindingActive, "cleanup.currentRealityBindingActive", into: &failures)
    require(!target.presentationBindingAttached, "cleanup.currentPresentationBindingAttached", into: &failures)
    require(target.presentationBinding == "none", "cleanup.presentationBindingRetained", into: &failures)
    require(target.sceneContainer == "none", "cleanup.sceneContainerRetained", into: &failures)
    require(!target.parentIsWindowRoot, "cleanup.windowParentRetained", into: &failures)
    require(!target.parentIsDockedRoot, "cleanup.dockedParentRetained", into: &failures)
    require(!target.parentIsPanoramaRoot, "cleanup.panoramaParentRetained", into: &failures)
    require(target.rendererIdentity == "none", "cleanup.rendererRetained", into: &failures)
    require(target.rendererGraphID == "none", "cleanup.rendererGraphRetained", into: &failures)
    require(
      target.rendererSynchronizerIdentity == "none",
      "cleanup.synchronizerRetained",
      into: &failures
    )
    require(target.audioRendererIdentity == "none", "cleanup.audioRendererRetained", into: &failures)
    require(target.audioRendererGraphID == "none", "cleanup.audioGraphRetained", into: &failures)
    require(
      target.audioRendererSynchronizerIdentity == "none",
      "cleanup.audioSynchronizerRetained",
      into: &failures
    )
    require(!target.panoramaRootEnabled, "cleanup.panoramaRootVisible", into: &failures)
    if requirePresentationClosed {
      require(target.sceneLifecycle == "closed", "cleanup.sceneOpen", into: &failures)
      require(target.windowLifecycle == "closed", "cleanup.windowOpen", into: &failures)
      require(target.sceneContent == "none", "cleanup.sceneContentRetained", into: &failures)
      require(!target.customSceneRequestedOpen, "cleanup.sceneIntentRetained", into: &failures)
      require(!target.immersiveSceneEnabled, "cleanup.customSceneVisible", into: &failures)
    }
    require(target.lastCleanupMediaSessionID == mediaSessionID, "cleanup.sessionEvidence", into: &failures)
    require(target.lastCleanupOperationKind == "close", "cleanup.operationKind", into: &failures)
    require(target.lastCleanupOperationState == "completed", "cleanup.operationState", into: &failures)
    require(target.lastCleanupRendererFlushCount > 0, "cleanup.rendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoProviderCancelled, "cleanup.videoProviderActive", into: &failures)
    require(target.lastCleanupAudioProviderCancelled, "cleanup.audioProviderActive", into: &failures)
    require(target.lastCleanupAudioRendererFlushed, "cleanup.audioRendererNotFlushed", into: &failures)
    require(target.lastCleanupVideoRendererFlushed, "cleanup.videoRendererNotFlushed", into: &failures)
    require(!target.lastCleanupRealityKitBindingActive, "cleanup.realityBindingActive", into: &failures)
    require(!target.lastCleanupPresentationBindingAttached, "cleanup.presentationBindingAttached", into: &failures)
    return failures
  }

  private static func activePlaybackFailures(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(baseline, role: "baseline")
    failures.append(contentsOf: schemaFailures(target, role: "target"))
    require(target.mediaSessionID == baseline.mediaSessionID, "playback.sessionChanged", into: &failures)
    require(target.rendererIdentity == baseline.rendererIdentity, "playback.rendererChanged", into: &failures)
    require(
      target.rendererGraphID == baseline.rendererGraphID && target.rendererGraphID != "none",
      "playback.rendererGraphChanged",
      into: &failures
    )
    require(
      target.rendererSynchronizerIdentity == baseline.rendererSynchronizerIdentity
        && target.rendererSynchronizerIdentity != "none",
      "playback.synchronizerChanged",
      into: &failures
    )
    require(target.videoEntityIdentity == baseline.videoEntityIdentity, "playback.entityChanged", into: &failures)
    require(target.route == baseline.route, "playback.routeChanged", into: &failures)
    require(target.source == baseline.source, "playback.sourceChanged", into: &failures)
    require(
      target.sourceAccessRequirement == baseline.sourceAccessRequirement,
      "playback.sourceAccessRequirementChanged",
      into: &failures
    )
    requireSourceAccessActive(baseline, failures: &failures)
    requireSourceAccessActive(target, failures: &failures)
    require(target.streamEpoch == baseline.streamEpoch, "playback.streamEpochChanged", into: &failures)
    require(target.rendererFlushCount == baseline.rendererFlushCount, "playback.rendererFlushed", into: &failures)
    require(
      abs(target.rendererTimelineRate - baseline.rendererTimelineRate) < 0.001,
      "playback.timelineRateChanged",
      into: &failures
    )
    require(target.sampleCount > baseline.sampleCount, "playback.sampleDidNotAdvance", into: &failures)
    require(target.currentSeconds > baseline.currentSeconds, "playback.timeDidNotAdvance", into: &failures)
    require(
      target.displayedPixelBufferIdentity != baseline.displayedPixelBufferIdentity,
      "playback.displayedPixelDidNotAdvance",
      into: &failures
    )
    requireActiveOutput(target, failures: &failures)
    return failures
  }

  private static func samePlaybackGraphFailures(
    expectedRoute: VisionRegressionRoute,
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot
  ) -> [String] {
    var failures = schemaFailures(baseline, role: "baseline")
    failures.append(contentsOf: schemaFailures(target, role: "target"))
    require(baseline.route == expectedRoute.rawValue, "control.baselineRoute", into: &failures)
    require(target.route == expectedRoute.rawValue, "control.targetRoute", into: &failures)
    require(target.source == baseline.source, "control.sourceChanged", into: &failures)
    require(
      target.sourceAccessRequirement == baseline.sourceAccessRequirement,
      "control.sourceAccessRequirementChanged",
      into: &failures
    )
    require(target.mediaSessionID == baseline.mediaSessionID, "control.sessionChanged", into: &failures)
    require(target.rendererIdentity == baseline.rendererIdentity, "control.rendererChanged", into: &failures)
    require(
      target.rendererGraphID == baseline.rendererGraphID && target.rendererGraphID != "none",
      "control.rendererGraphChanged",
      into: &failures
    )
    require(
      target.rendererSynchronizerIdentity == baseline.rendererSynchronizerIdentity
        && target.rendererSynchronizerIdentity != "none",
      "control.synchronizerChanged",
      into: &failures
    )
    require(target.videoEntityIdentity == baseline.videoEntityIdentity, "control.entityChanged", into: &failures)
    require(target.productShape == baseline.productShape, "control.shapeChanged", into: &failures)
    require(target.placement == baseline.placement, "control.placementChanged", into: &failures)
    require(target.sceneLifecycle == baseline.sceneLifecycle, "control.sceneLifecycleChanged", into: &failures)
    require(target.sceneContent == baseline.sceneContent, "control.sceneContentChanged", into: &failures)
    require(
      target.customSceneRequestedOpen == baseline.customSceneRequestedOpen,
      "control.sceneIntentChanged",
      into: &failures
    )
    requireUnchangedProjectionAndStereo(
      baseline: baseline,
      target: target,
      prefix: "control",
      failures: &failures
    )
    requireSourceAccessActive(baseline, failures: &failures)
    requireSourceAccessActive(target, failures: &failures)
    requireHealthySharedAudioGraph(baseline, failures: &failures)
    requireHealthySharedAudioGraph(target, failures: &failures)
    require(
      target.audioRendererIdentity == baseline.audioRendererIdentity,
      "control.audio.rendererChanged",
      into: &failures
    )
    requireActiveOutput(target, failures: &failures)
    return failures
  }

  private static func requireUnchangedVideoStream(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.streamEpoch == baseline.streamEpoch, "control.streamEpochChanged", into: &failures)
    require(target.rendererFlushCount == baseline.rendererFlushCount, "control.rendererFlushed", into: &failures)
  }

  private static func requireFreshOutput(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.sampleCount > baseline.sampleCount, "control.sampleDidNotAdvance", into: &failures)
    require(target.currentSeconds > baseline.currentSeconds, "control.timeDidNotAdvance", into: &failures)
    require(
      target.displayedPixelBufferIdentity != baseline.displayedPixelBufferIdentity,
      "control.displayedPixelDidNotAdvance",
      into: &failures
    )
  }

  private static func requireFreshAudio(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(
      target.audioRendererSampleBufferCount > baseline.audioRendererSampleBufferCount,
      "control.audio.sampleDidNotAdvance",
      into: &failures
    )
  }

  private static func requireActiveOutput(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.presentationSettled, "playback.presentationNotSettled", into: &failures)
    require(
      target.candidateProductShape == target.productShape,
      "playback.candidateShapeMismatch",
      into: &failures
    )
    requireProductShapeBinding(target, failures: &failures)
    require(target.presentationBindingAttached, "playback.presentationNotAttached", into: &failures)
    require(target.realityKitBindingActive, "playback.realityBindingInactive", into: &failures)
    require(target.rendererMatchesSession, "playback.rendererMismatch", into: &failures)
    require(target.rendererError == "none", "playback.rendererError", into: &failures)
    require(normalized(target.componentRenderingStatus) == "ready", "playback.componentNotReady", into: &failures)
    require(target.displayedPixelBuffer, "playback.displayedPixelMissing", into: &failures)
    require(
      target.displayedPixelBufferIdentity != "none",
      "playback.displayedPixelIdentityMissing",
      into: &failures
    )
  }

  private static func requireHealthySharedAudioGraph(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.audioRendererError == "none", "control.audio.rendererError", into: &failures)
    require(
      target.audioRendererMediaSessionID == target.mediaSessionID,
      "control.audio.sessionMismatch",
      into: &failures
    )
    require(
      target.rendererGraphID != "none"
        && target.audioRendererGraphID == target.rendererGraphID,
      "control.audio.graphMismatch",
      into: &failures
    )
    require(
      target.audioRendererIdentity != "none",
      "control.audio.rendererMissing",
      into: &failures
    )
    require(
      target.audioRendererVideoRendererIdentity == target.rendererIdentity,
      "control.audio.videoRendererMismatch",
      into: &failures
    )
    require(
      target.rendererSynchronizerIdentity != "none"
        && target.audioRendererSynchronizerIdentity == target.rendererSynchronizerIdentity,
      "control.audio.synchronizerMismatch",
      into: &failures
    )
    require(
      target.audioRendererSampleBufferCount > 0,
      "control.audio.sampleMissing",
      into: &failures
    )
  }

  private static func requireSourceAccessActive(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    let access = normalized(target.sourceAccessRequirement)
    if access == "securityscoped" {
      require(target.securityScopeHeld, "source.securityScopeNotHeld", into: &failures)
    } else if access == "notrequired" {
      require(!target.securityScopeHeld, "source.unexpectedSecurityScope", into: &failures)
    } else {
      failures.append("source.accessRequirementUnknown")
    }
  }

  private static func requireSameAudioGraph(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(
      target.audioRendererIdentity == baseline.audioRendererIdentity,
      "playback.audioRendererChanged",
      into: &failures
    )
    require(
      target.audioRendererGraphID == baseline.audioRendererGraphID,
      "playback.audioGraphChanged",
      into: &failures
    )
    require(
      target.audioRendererSynchronizerIdentity == baseline.audioRendererSynchronizerIdentity,
      "playback.audioSynchronizerChanged",
      into: &failures
    )
    require(
      target.audioRendererVideoRendererIdentity == baseline.audioRendererVideoRendererIdentity,
      "playback.audioVideoRendererChanged",
      into: &failures
    )
    if baseline.audioRendererIdentity != "none" {
      requireHealthySharedAudioGraph(baseline, failures: &failures)
      requireHealthySharedAudioGraph(target, failures: &failures)
    }
  }

  private static func requireProductShapeBinding(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    switch target.productShape {
    case VisionProductShape.flatWindow.rawValue:
      require(target.placement == VisionPlaybackPlacement.window.rawValue, "flat.placement", into: &failures)
      require(target.projection == VisionProjection.flat.rawValue, "flat.projection", into: &failures)
      require(target.parentIsWindowRoot, "flat.parent", into: &failures)
      require(!target.parentIsDockedRoot && !target.parentIsPanoramaRoot, "flat.extraParent", into: &failures)
      requireWindowBinding(target, failures: &failures)
    case VisionProductShape.portalWindow.rawValue:
      require(target.placement == VisionPlaybackPlacement.window.rawValue, "portal.placement", into: &failures)
      require(target.projection == VisionProjection.sourcePanoramic.rawValue, "portal.projection", into: &failures)
      require(target.parentIsWindowRoot, "portal.parent", into: &failures)
      require(!target.parentIsDockedRoot && !target.parentIsPanoramaRoot, "portal.extraParent", into: &failures)
      requireWindowBinding(target, failures: &failures)
    case VisionProductShape.docked.rawValue:
      require(target.placement == VisionPlaybackPlacement.docked.rawValue, "docked.placement", into: &failures)
      require(target.projection == VisionProjection.flat.rawValue, "docked.projection", into: &failures)
      require(target.customSceneRequestedOpen, "docked.sceneIntent", into: &failures)
      require(target.parentIsDockedRoot, "docked.parent", into: &failures)
      require(!target.parentIsWindowRoot && !target.parentIsPanoramaRoot, "docked.extraParent", into: &failures)
      requireSceneBinding(target, failures: &failures)
    case VisionProductShape.panorama.rawValue:
      require(target.placement == VisionPlaybackPlacement.panorama.rawValue, "panorama.placement", into: &failures)
      require(target.projection == VisionProjection.sourcePanoramic.rawValue, "panorama.projection", into: &failures)
      require(target.parentIsPanoramaRoot, "panorama.parent", into: &failures)
      require(!target.parentIsWindowRoot && !target.parentIsDockedRoot, "panorama.extraParent", into: &failures)
      requireSceneBinding(target, failures: &failures)
    default:
      failures.append("playback.unknownProductShape")
    }
  }

  private static func requireUnchangedProjectionAndStereo(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    prefix: String,
    failures: inout [String]
  ) {
    require(target.projection == baseline.projection, "\(prefix).projectionChanged", into: &failures)
    require(
      target.detectedProjectionKind == baseline.detectedProjectionKind,
      "\(prefix).detectedProjectionChanged",
      into: &failures
    )
    require(
      target.effectiveProjectionKind == baseline.effectiveProjectionKind,
      "\(prefix).effectiveProjectionChanged",
      into: &failures
    )
    require(
      target.formatRevision == baseline.formatRevision,
      "\(prefix).formatRevisionChanged",
      into: &failures
    )
    require(target.stereoLayout == baseline.stereoLayout, "\(prefix).stereoChanged", into: &failures)
    require(
      target.coreEffectiveStereoLayout == baseline.coreEffectiveStereoLayout,
      "\(prefix).coreStereoChanged",
      into: &failures
    )
    require(
      target.effectiveViewPackingKind == baseline.effectiveViewPackingKind,
      "\(prefix).viewPackingChanged",
      into: &failures
    )
    require(
      target.effectiveHasLeftStereoEyeView == baseline.effectiveHasLeftStereoEyeView
        && target.effectiveHasRightStereoEyeView == baseline.effectiveHasRightStereoEyeView,
      "\(prefix).stereoEyesChanged",
      into: &failures
    )
    require(
      normalized(target.actualViewingMode) == normalized(baseline.actualViewingMode),
      "\(prefix).actualViewingModeChanged",
      into: &failures
    )
    require(
      normalized(target.actualImmersiveViewingMode)
        == normalized(baseline.actualImmersiveViewingMode),
      "\(prefix).actualImmersiveViewingModeChanged",
      into: &failures
    )
  }

  private static func requirePlanarPresentation(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(
      target.presentationGeometry == "planar" && target.planarMeshActive,
      "presentation.planarMissing",
      into: &failures
    )
  }

  private static func requireImmersivePresentation(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(
      target.presentationGeometry == "immersive" && !target.planarMeshActive,
      "presentation.immersiveMissing",
      into: &failures
    )
  }

  private static func requirePanoramicProjection(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(
      normalized(target.detectedProjectionKind).contains("equirectangular"),
      "projection.sourceNotPanoramic",
      into: &failures
    )
    require(
      normalized(target.effectiveProjectionKind).contains("equirectangular"),
      "projection.effectiveNotPanoramic",
      into: &failures
    )
  }

  private static func requireModeAcknowledgementIfChanged(
    baseline: VisionRegressionEvidenceSnapshot,
    target: VisionRegressionEvidenceSnapshot,
    expectedSurface: VisionSurface,
    failures: inout [String]
  ) {
    guard normalized(baseline.actualImmersiveViewingMode)
      != normalized(target.actualImmersiveViewingMode)
    else { return }
    require(
      target.immersiveModeChangeSequence > baseline.immersiveModeChangeSequence,
      "immersiveMode.acknowledgementMissing",
      into: &failures
    )
    require(
      target.lastAcknowledgedImmersiveModeSurface == expectedSurface.rawValue,
      "immersiveMode.acknowledgedOnWrongSurface",
      into: &failures
    )
  }

  private static func requireWindowBinding(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.windowLifecycle == "open", "window.notOpen", into: &failures)
    require(target.parentIsWindowRoot, "window.parent", into: &failures)
    require(target.presentationBinding == VisionSurface.playbackWindow.rawValue, "window.realityView", into: &failures)
    require(target.sceneContainer == VisionSceneID.playbackWindow, "window.sceneContainer", into: &failures)
  }

  private static func requireSceneBinding(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.sceneLifecycle == "open", "scene.notOpen", into: &failures)
    require(target.windowLifecycle == "closed", "scene.playbackWindowStillOpen", into: &failures)
    require(target.presentationBinding == VisionSurface.scene.rawValue, "scene.realityView", into: &failures)
    require(target.sceneContainer == VisionSceneID.playbackSpace, "scene.sceneContainer", into: &failures)
  }

  private static func requireStereoEyes(
    _ target: VisionRegressionEvidenceSnapshot,
    failures: inout [String]
  ) {
    require(target.effectiveHasLeftStereoEyeView, "stereo.leftEyeMissing", into: &failures)
    require(target.effectiveHasRightStereoEyeView, "stereo.rightEyeMissing", into: &failures)
  }

  private static func require(
    _ condition: @autoclosure () -> Bool,
    _ failure: String,
    into failures: inout [String]
  ) {
    if !condition() { failures.append(failure) }
  }

  private static func schemaFailures(
    _ snapshot: VisionRegressionEvidenceSnapshot,
    role: String
  ) -> [String] {
    snapshot.missingRequiredKeys.map { "evidence.schemaMissing.\(role).\($0)" }
      + snapshot.invalidRequiredKeys.map { "evidence.schemaInvalid.\(role).\($0)" }
  }

  private static func normalized(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) -> String { self[key] as? String ?? "none" }
  func bool(_ key: String) -> Bool { self[key] as? Bool ?? false }
  func uint64(_ key: String) -> UInt64 {
    if let value = self[key] as? UInt64 { return value }
    if let value = self[key] as? Int { return UInt64(Swift.max(0, value)) }
    return 0
  }
  func double(_ key: String) -> Double {
    if let value = self[key] as? Double { return value }
    if let value = self[key] as? Float { return Double(value) }
    return 0
  }
  func int(_ key: String) -> Int { self[key] as? Int ?? -1 }
}
