import Foundation

enum VisionRegressionEvidenceTests {
  static func run() {
    testProductShapes()
    testStereo()
    testLifecycleAndSceneIndependence()
    testPreparationRestorationAndEdges()
    testControls()
    testRouteSwitchAndCleanup()
  }

  private static func testProductShapes() {
    let baseline = VisionRegressionEvidenceSnapshot(snapshot())
    for shape in VisionProductShape.allCases {
      let target = VisionRegressionEvidenceSnapshot(shapeSnapshot(shape))
      expect(
        VisionRegressionEvidenceContract.presentationFailures(
          expectedRoute: .appleCompressed,
          expectedShape: shape,
          baseline: baseline,
          target: target
        ).isEmpty,
        "fresh attached \(shape.rawValue) passes"
      )
    }

    var stalePixel = shapeSnapshot(.flatWindow)
    stalePixel["displayedPixelBufferIdentity"] = "pixel-1"
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .flatWindow,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(stalePixel)
      ).contains("playback.displayedPixelDidNotAdvance"),
      "a retained prior pixel cannot prove a presentation"
    )

    var wrongProjection = shapeSnapshot(.panorama)
    wrongProjection["effectiveProjectionKind"] = "Rectilinear"
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .panorama,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(wrongProjection)
      ).contains("projection.effectiveNotPanoramic"),
      "requested Panorama cannot replace effective sample projection"
    )

    var rewrittenProjectionRevision = shapeSnapshot(.portalWindow)
    rewrittenProjectionRevision["effectiveFormatRevision"] = UInt64(2)
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .portalWindow,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(rewrittenProjectionRevision)
      ).contains("projection.unexpectedRevisionChange"),
      "presentation geometry changes must not rewrite source projection"
    )

    var staleAcknowledgement = shapeSnapshot(.panorama)
    staleAcknowledgement["immersiveModeChangeSequence"] = UInt64(1)
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .panorama,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(staleAcknowledgement)
      ).contains("immersiveMode.acknowledgementMissing"),
      "a mode value from the source surface cannot acknowledge the target surface"
    )

    var wrongAnchor = shapeSnapshot(.docked)
    wrongAnchor["dockingAnchorPreservesAuthoredTransform"] = false
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .docked,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(wrongAnchor)
      ).contains("docked.authoredTransformNotPreserved"),
      "Docked requires the authored RCP transform"
    )

    wrongAnchor = shapeSnapshot(.docked)
    wrongAnchor["dockingAnchorHasModel"] = true
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .docked,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(wrongAnchor)
      ).contains("docked.anchorIsNotPure"),
      "Docked runtime anchor cannot carry authored visible geometry"
    )

    var notReady = shapeSnapshot(.flatWindow)
    notReady["componentRenderingStatus"] = "notReady"
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .flatWindow,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(notReady)
      ).contains("playback.componentNotReady"),
      "notReady cannot pass a substring check for ready"
    )

    var mismatchedCandidate = shapeSnapshot(.flatWindow)
    mismatchedCandidate["candidateProductShape"] = VisionProductShape.portalWindow.rawValue
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .flatWindow,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(mismatchedCandidate)
      ).contains("playback.candidateShapeMismatch"),
      "presented shape requires the matching candidate and container binding"
    )
  }

  private static func testStereo() {
    let baseline = VisionRegressionEvidenceSnapshot(snapshot())
    var values = advancedSnapshot()
    values["stereoLayout"] = VisionStereoLayout.sideBySide.rawValue
    values["coreEffectiveStereoLayout"] = VisionStereoLayout.sideBySide.rawValue
    values["effectiveFormatRevision"] = UInt64(2)
    values["effectiveViewPackingKind"] = "SideBySide"
    values["effectiveHasLeftStereoEyeView"] = true
    values["effectiveHasRightStereoEyeView"] = true
    values["actualViewingMode"] = "stereo"
    values["viewingModeChangeSequence"] = UInt64(2)
    expect(
      VisionRegressionEvidenceContract.stereoFailures(
        expectedLayout: .sideBySide,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(values)
      ).isEmpty,
      "Stereo requires sample signaling and target-surface acknowledgement"
    )

    values["actualViewingMode"] = "mono"
    expect(
      VisionRegressionEvidenceContract.stereoFailures(
        expectedLayout: .sideBySide,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(values)
      ).contains("stereo.actualStereo"),
      "desired Stereo cannot replace RealityKit actual mode"
    )

    values["actualViewingMode"] = "stereo"
    values["effectiveProjectionKind"] = "Rectilinear"
    expect(
      VisionRegressionEvidenceContract.stereoFailures(
        expectedLayout: .sideBySide,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(values)
      ).contains("stereo.effectiveProjectionChanged"),
      "Stereo cannot silently change the effective projection"
    )
  }

  private static func testLifecycleAndSceneIndependence() {
    var windowOnly = emptySnapshot()
    windowOnly["windowLifecycle"] = "open"
    expect(
      VisionRegressionEvidenceContract.lifecycleFailures(
        expected: .playbackWindowOpenWithoutMedia,
        target: VisionRegressionEvidenceSnapshot(windowOnly)
      ).isEmpty,
      "Playback Window can open without media"
    )

    var sceneOnly = emptySnapshot()
    sceneOnly["sceneLifecycle"] = "open"
    sceneOnly["sceneContent"] = VisionSceneContent.customScene.rawValue
    sceneOnly["customSceneRequestedOpen"] = true
    sceneOnly["immersiveSceneLoaded"] = true
    sceneOnly["immersiveSceneEnabled"] = true
    sceneOnly["dockingAnchorReady"] = true
    sceneOnly["dockedRootBoundToAnchor"] = true
    sceneOnly["dockingAnchorPreservesAuthoredTransform"] = true
    expect(
      VisionRegressionEvidenceContract.lifecycleFailures(
        expected: .customSceneOpenWithoutMedia,
        target: VisionRegressionEvidenceSnapshot(sceneOnly)
      ).isEmpty,
      "Custom Scene can open before a player exists"
    )

    let baseline = VisionRegressionEvidenceSnapshot(snapshot())
    var opened = advancedSnapshot()
    opened["sceneLifecycle"] = "open"
    opened["sceneContent"] = VisionSceneContent.customScene.rawValue
    opened["customSceneRequestedOpen"] = true
    opened["immersiveSceneLoaded"] = true
    opened["immersiveSceneEnabled"] = true
    opened["dockingAnchorPreservesAuthoredTransform"] = true
    expect(
      VisionRegressionEvidenceContract.sceneOpenWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(opened)
      ).isEmpty,
      "opening Scene does not migrate a Window-bound video"
    )

    var migrated = opened
    migrated["parentIsWindowRoot"] = false
    migrated["parentIsDockedRoot"] = true
    expect(
      VisionRegressionEvidenceContract.sceneOpenWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(migrated)
      ).contains("window.parent"),
      "Scene open cannot silently Dock"
    )

    var changedStereo = opened
    changedStereo["stereoLayout"] = VisionStereoLayout.sideBySide.rawValue
    expect(
      VisionRegressionEvidenceContract.sceneOpenWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(changedStereo)
      ).contains("sceneOpen.stereoChanged"),
      "Scene lifecycle cannot silently change Stereo"
    )

    var changedAudioGraph = opened
    changedAudioGraph["audioRendererIdentity"] = "audio-renderer-2"
    expect(
      VisionRegressionEvidenceContract.sceneOpenWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(changedAudioGraph)
      ).contains("playback.audioRendererChanged"),
      "Scene lifecycle cannot replace the shared audio graph"
    )

    let openedBaseline = VisionRegressionEvidenceSnapshot(opened)
    var closed = snapshot(sampleCount: 3, currentSeconds: 2)
    closed["displayedPixelBufferIdentity"] = "pixel-3"
    expect(
      VisionRegressionEvidenceContract.sceneCloseWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: openedBaseline,
        target: VisionRegressionEvidenceSnapshot(closed)
      ).isEmpty,
      "closing Scene leaves the Window-bound video on the same graph"
    )
  }

  private static func testPreparationRestorationAndEdges() {
    expect(
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: .appleCompressed,
        target: VisionRegressionEvidenceSnapshot(snapshot())
      ).isEmpty,
      "a prepared session requires a playing Flat Window with visible output"
    )

    var notPlaying = snapshot()
    notPlaying["status"] = "Ready"
    expect(
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: .appleCompressed,
        target: VisionRegressionEvidenceSnapshot(notPlaying)
      ).contains("prepare.status"),
      "prepared-session evidence cannot stop at Ready"
    )

    var missingAccess = snapshot()
    missingAccess["sourceAccessRequirement"] = "none"
    expect(
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: .appleCompressed,
        target: VisionRegressionEvidenceSnapshot(missingAccess)
      ).contains("prepare.sourceAccess"),
      "a prepared baseline must identify its source access contract"
    )

    var unknownAccess = snapshot()
    unknownAccess["sourceAccessRequirement"] = "temporary"
    expect(
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: .appleCompressed,
        target: VisionRegressionEvidenceSnapshot(unknownAccess)
      ).contains("source.accessRequirementUnknown"),
      "unknown source access evidence fails closed"
    )

    var restoredScene = snapshot()
    restoredScene["sceneLifecycle"] = "open"
    restoredScene["sceneContent"] = VisionSceneContent.customScene.rawValue
    restoredScene["customSceneRequestedOpen"] = true
    restoredScene["immersiveSceneLoaded"] = true
    restoredScene["immersiveSceneEnabled"] = true
    expect(
      VisionRegressionEvidenceContract.activeMediaSceneRestorationFailures(
        baseline: .customSceneOpen,
        target: VisionRegressionEvidenceSnapshot(restoredScene)
      ).isEmpty,
      "leaving Panorama restores the authored custom Scene around active media"
    )

    var closedMedia = emptySnapshot()
    addCleanupEvidence(to: &closedMedia)
    expect(
      VisionRegressionEvidenceContract.mediaCloseSceneRestorationFailures(
        mediaSessionID: "session-1",
        baseline: .closed,
        target: VisionRegressionEvidenceSnapshot(closedMedia)
      ).isEmpty,
      "closing media restores a previously closed Scene"
    )

    var sceneAfterMediaClose = closedMedia
    sceneAfterMediaClose["sceneLifecycle"] = "open"
    sceneAfterMediaClose["sceneContent"] = VisionSceneContent.customScene.rawValue
    sceneAfterMediaClose["customSceneRequestedOpen"] = true
    sceneAfterMediaClose["immersiveSceneLoaded"] = true
    sceneAfterMediaClose["immersiveSceneEnabled"] = true
    expect(
      VisionRegressionEvidenceContract.mediaCloseSceneRestorationFailures(
        mediaSessionID: "session-1",
        baseline: .customSceneOpen,
        target: VisionRegressionEvidenceSnapshot(sceneAfterMediaClose)
      ).isEmpty,
      "closing media restores a previously open custom Scene and its pure anchor"
    )

    var dockedToFlat = shapeSnapshot(.flatWindow)
    dockedToFlat["sceneLifecycle"] = "open"
    dockedToFlat["sceneContent"] = VisionSceneContent.customScene.rawValue
    dockedToFlat["customSceneRequestedOpen"] = true
    dockedToFlat["immersiveSceneLoaded"] = true
    dockedToFlat["immersiveSceneEnabled"] = true
    expect(
      VisionRegressionEvidenceContract.presentationEdgeFailures(
        edge: .dockedToFlatWindow,
        target: VisionRegressionEvidenceSnapshot(dockedToFlat)
      ).isEmpty,
      "Docked returns to Flat Window while the custom Scene stays open"
    )

    var dockedToPanorama = shapeSnapshot(.panorama)
    dockedToPanorama["customSceneRequestedOpen"] = true
    expect(
      VisionRegressionEvidenceContract.presentationEdgeFailures(
        edge: .dockedToPanorama,
        target: VisionRegressionEvidenceSnapshot(dockedToPanorama)
      ).isEmpty,
      "Docked may enter Panorama while retaining custom Scene intent"
    )

    expect(
      VisionRegressionEvidenceContract.presentationEdgeFailures(
        edge: .panoramaToFlatWindow,
        target: VisionRegressionEvidenceSnapshot(shapeSnapshot(.flatWindow))
      ).isEmpty,
      "Panorama returns to a Flat Window when no custom Scene was requested"
    )

    dockedToFlat["panoramaRootEnabled"] = true
    expect(
      VisionRegressionEvidenceContract.presentationEdgeFailures(
        edge: .dockedToFlatWindow,
        target: VisionRegressionEvidenceSnapshot(dockedToFlat)
      ).contains("edge.flat.panoramaRootVisible"),
      "the restored custom Scene cannot leave the Panorama root visible"
    )
  }

  private static func testControls() {
    let playing = VisionRegressionEvidenceSnapshot(snapshot())

    var pausedValues = snapshot()
    pausedValues["status"] = "Paused"
    pausedValues["rendererTimelineRate"] = 0.0
    pausedValues["lastCompletedOperationKind"] = "pause"
    pausedValues["lastCompletedOperationState"] = "completed"
    let paused = VisionRegressionEvidenceSnapshot(pausedValues)
    expect(
      VisionRegressionEvidenceContract.pauseFailures(
        expectedRoute: .appleCompressed,
        baseline: playing,
        target: paused
      ).isEmpty,
      "pause proves synchronizer rate zero on the same graph"
    )

    var resumedValues = advancedSnapshot()
    resumedValues["lastCompletedOperationKind"] = "play"
    resumedValues["lastCompletedOperationState"] = "completed"
    let resumed = VisionRegressionEvidenceSnapshot(resumedValues)
    expect(
      VisionRegressionEvidenceContract.playFailures(
        expectedRoute: .appleCompressed,
        baseline: paused,
        target: resumed
      ).isEmpty,
      "play starts from an observed paused baseline and produces a fresh pixel"
    )

    expect(
      VisionRegressionEvidenceContract.playFailures(
        expectedRoute: .appleCompressed,
        baseline: playing,
        target: resumed
      ).contains("control.play.baselineStatus"),
      "play cannot pass without a paused baseline"
    )

    resumedValues["rendererTimelineRate"] = 1.5
    resumedValues["lastCompletedOperationKind"] = "setRate"
    expect(
      VisionRegressionEvidenceContract.rateFailures(
        expectedRoute: .appleCompressed,
        expectedRate: 1.5,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(resumedValues)
      ).isEmpty,
      "rate preserves the graph and advances output"
    )

    resumedValues["status"] = "Paused"
    expect(
      VisionRegressionEvidenceContract.rateFailures(
        expectedRoute: .appleCompressed,
        expectedRate: 1.5,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(resumedValues)
      ).contains("control.rate.status"),
      "rate cannot pass if playback stopped"
    )
    resumedValues["status"] = "Playing"

    var seekValues = advancedSnapshot()
    seekValues["currentSeconds"] = 4.0
    seekValues["streamEpoch"] = UInt64(2)
    seekValues["audioRendererStreamEpoch"] = UInt64(2)
    seekValues["rendererFlushCount"] = UInt64(1)
    seekValues["lastCompletedOperationKind"] = "seek"
    seekValues["lastCompletedOperationState"] = "completed"
    seekValues["lastCompletedOperationTargetTime"] = 4.0
    expect(
      VisionRegressionEvidenceContract.seekFailures(
        expectedRoute: .appleCompressed,
        expectedSeconds: 4,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(seekValues)
      ).isEmpty,
      "seek requires target time, a new epoch, flush, sample, and pixel"
    )

    seekValues["rendererTimelineRate"] = 0.0
    expect(
      VisionRegressionEvidenceContract.seekFailures(
        expectedRoute: .appleCompressed,
        expectedSeconds: 4,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(seekValues)
      ).contains("control.seek.rateChanged"),
      "seek must preserve the observed playback rate"
    )
    seekValues["rendererTimelineRate"] = 1.0

    var audioValues = snapshot()
    audioValues["selectedAudioStreamIndex"] = 2
    audioValues["audioRendererSampleBufferCount"] = UInt64(2)
    audioValues["audioRendererStreamEpoch"] = UInt64(2)
    expect(
      VisionRegressionEvidenceContract.audioTrackFailures(
        expectedRoute: .appleCompressed,
        expectedStreamIndex: 2,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(audioValues)
      ).isEmpty,
      "audio selection requires a different selected stream and fresh PCM"
    )

    audioValues["audioRendererError"] = "decode failed"
    expect(
      VisionRegressionEvidenceContract.audioTrackFailures(
        expectedRoute: .appleCompressed,
        expectedStreamIndex: 2,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(audioValues)
      ).contains("control.audio.rendererError"),
      "audio control cannot pass with a renderer error"
    )
    audioValues["audioRendererError"] = "none"

    var volumeValues = snapshot()
    volumeValues["audioRendererVolume"] = 0.35
    expect(
      VisionRegressionEvidenceContract.volumeFailures(
        expectedRoute: .appleCompressed,
        expectedVolume: 0.35,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(volumeValues)
      ).isEmpty,
      "volume reaches the shared renderer without changing video state"
    )

    volumeValues["audioRendererGraphID"] = "other-graph"
    expect(
      VisionRegressionEvidenceContract.volumeFailures(
        expectedRoute: .appleCompressed,
        expectedVolume: 0.35,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(volumeValues)
      ).contains("control.audio.graphMismatch"),
      "audio controls must prove the shared renderer graph"
    )

    volumeValues = snapshot()
    volumeValues["audioRendererVolume"] = 0.35
    volumeValues["effectiveViewPackingKind"] = "SideBySide"
    expect(
      VisionRegressionEvidenceContract.volumeFailures(
        expectedRoute: .appleCompressed,
        expectedVolume: 0.35,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(volumeValues)
      ).contains("control.viewPackingChanged"),
      "an atomic control cannot silently change effective Stereo signaling"
    )

    var muteValues = snapshot()
    muteValues["audioRendererMuted"] = true
    expect(
      VisionRegressionEvidenceContract.muteFailures(
        expectedRoute: .appleCompressed,
        expectedMuted: true,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(muteValues)
      ).isEmpty,
      "mute reaches the shared renderer without changing video state"
    )

    var reopenedValues = snapshot()
    reopenedValues["mediaSessionID"] = "session-2"
    reopenedValues["rendererIdentity"] = "renderer-2"
    reopenedValues["rendererGraphID"] = "graph-2"
    reopenedValues["rendererSynchronizerIdentity"] = "synchronizer-2"
    reopenedValues["videoEntityIdentity"] = "entity-2"
    reopenedValues["audioRendererMediaSessionID"] = "session-2"
    reopenedValues["audioRendererGraphID"] = "graph-2"
    reopenedValues["audioRendererIdentity"] = "audio-renderer-2"
    reopenedValues["audioRendererVideoRendererIdentity"] = "renderer-2"
    reopenedValues["audioRendererSynchronizerIdentity"] = "synchronizer-2"
    reopenedValues["displayedPixelBufferIdentity"] = "pixel-2"
    addCleanupEvidence(to: &reopenedValues)
    expect(
      VisionRegressionEvidenceContract.reopenFailures(
        expectedRoute: .appleCompressed,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(reopenedValues)
      ).isEmpty,
      "reopen proves replacement plus old-session cleanup"
    )

    reopenedValues["sourceAccessRequirement"] = "notRequired"
    expect(
      VisionRegressionEvidenceContract.reopenFailures(
        expectedRoute: .appleCompressed,
        baseline: playing,
        target: VisionRegressionEvidenceSnapshot(reopenedValues)
      ).contains("control.reopen.sourceAccessRequirement"),
      "reopen must preserve the source access contract"
    )
  }

  private static func testRouteSwitchAndCleanup() {
    let baseline = VisionRegressionEvidenceSnapshot(snapshot())
    var switched = advancedSnapshot()
    switched["route"] = VisionRegressionRoute.ffmpegCompressed.rawValue
    switched["mediaSessionID"] = "session-2"
    switched["rendererIdentity"] = "renderer-2"
    switched["rendererGraphID"] = "graph-2"
    switched["rendererSynchronizerIdentity"] = "synchronizer-2"
    switched["videoEntityIdentity"] = "entity-2"
    switched["audioRendererMediaSessionID"] = "session-2"
    switched["audioRendererGraphID"] = "graph-2"
    switched["audioRendererIdentity"] = "audio-renderer-2"
    switched["audioRendererVideoRendererIdentity"] = "renderer-2"
    switched["audioRendererSynchronizerIdentity"] = "synchronizer-2"
    switched["routeSwitchOperationState"] = "completed"
    addCleanupEvidence(to: &switched)
    expect(
      VisionRegressionEvidenceContract.coldSwitchFailures(
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(switched)
      ).isEmpty,
      "cold switch requires a replacement graph, fresh output, and old cleanup"
    )

    switched["sourceAccessRequirement"] = "notRequired"
    expect(
      VisionRegressionEvidenceContract.coldSwitchFailures(
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(switched)
      ).contains("routeSwitch.sourceAccessRequirement"),
      "cold route switch must preserve the source access contract"
    )
    switched["sourceAccessRequirement"] = "securityScoped"

    switched["lastCleanupPresentationBindingAttached"] = true
    expect(
      VisionRegressionEvidenceContract.coldSwitchFailures(
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(switched)
      ).contains("routeSwitch.oldPresentationBindingAttached"),
      "the old binding cannot remain attached after a cold switch"
    )

    switched["lastCleanupPresentationBindingAttached"] = false
    switched["effectiveProjectionKind"] = "Rectilinear"
    expect(
      VisionRegressionEvidenceContract.coldSwitchFailures(
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(switched)
      ).contains("routeSwitch.effectiveProjectionChanged"),
      "cold route switch must preserve effective projection"
    )

    var cleanup = emptySnapshot()
    addCleanupEvidence(to: &cleanup)
    expect(
      VisionRegressionEvidenceContract.cleanupFailures(
        mediaSessionID: "session-1",
        target: VisionRegressionEvidenceSnapshot(cleanup)
      ).isEmpty,
      "cleanup requires close, flush, invalidated bindings, and closed containers"
    )

    var incompleteCleanup = cleanup
    incompleteCleanup["lastCleanupAudioRendererFlushed"] = false
    expect(
      VisionRegressionEvidenceContract.cleanupFailures(
        mediaSessionID: "session-1",
        target: VisionRegressionEvidenceSnapshot(incompleteCleanup)
      ).contains("cleanup.audioRendererNotFlushed"),
      "cleanup cannot pass without the audio renderer flush"
    )

    incompleteCleanup = cleanup
    incompleteCleanup["rendererIdentity"] = "renderer-retained"
    expect(
      VisionRegressionEvidenceContract.cleanupFailures(
        mediaSessionID: "session-1",
        target: VisionRegressionEvidenceSnapshot(incompleteCleanup)
      ).contains("cleanup.rendererRetained"),
      "cleanup cannot pass while a renderer identity remains current"
    )

    cleanup.removeValue(forKey: "lastCleanupRealityKitBindingActive")
    expect(
      VisionRegressionEvidenceContract.cleanupFailures(
        mediaSessionID: "session-1",
        target: VisionRegressionEvidenceSnapshot(cleanup)
      ).contains("evidence.schemaMissing.target.lastCleanupRealityKitBindingActive"),
      "missing negative evidence fails closed"
    )

    var wrongBool = emptySnapshot()
    addCleanupEvidence(to: &wrongBool)
    wrongBool["lastCleanupRealityKitBindingActive"] = "false"
    expect(
      VisionRegressionEvidenceContract.cleanupFailures(
        mediaSessionID: "session-1",
        target: VisionRegressionEvidenceSnapshot(wrongBool)
      ).contains("evidence.schemaInvalid.target.lastCleanupRealityKitBindingActive"),
      "wrong-typed negative evidence fails closed"
    )

    var wrongString = shapeSnapshot(.flatWindow)
    wrongString["rendererError"] = 42
    expect(
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: .appleCompressed,
        expectedShape: .flatWindow,
        baseline: baseline,
        target: VisionRegressionEvidenceSnapshot(wrongString)
      ).contains("evidence.schemaInvalid.target.rendererError"),
      "wrong-typed error evidence cannot fall back to none"
    )
  }

  private static func shapeSnapshot(_ shape: VisionProductShape) -> [String: Any] {
    var values = advancedSnapshot()
    values["productShape"] = shape.rawValue
    values["candidateProductShape"] = shape.rawValue
    values["immersiveModeChangeSequence"] = UInt64(2)
    switch shape {
    case .flatWindow:
      break
    case .portalWindow:
      values["projection"] = VisionProjection.sourcePanoramic.rawValue
      values["effectiveProjectionKind"] = "Equirectangular"
      values["presentationGeometry"] = "immersive"
      values["planarMeshActive"] = false
    case .docked:
      values["placement"] = VisionPlaybackPlacement.docked.rawValue
      values["sceneLifecycle"] = "open"
      values["sceneContent"] = VisionSceneContent.customScene.rawValue
      values["customSceneRequestedOpen"] = true
      values["windowLifecycle"] = "closed"
      values["presentationBinding"] = VisionSurface.scene.rawValue
      values["sceneContainer"] = VisionSceneID.playbackSpace
      values["parentIsWindowRoot"] = false
      values["parentIsDockedRoot"] = true
      values["immersiveSceneLoaded"] = true
      values["immersiveSceneEnabled"] = true
      values["lastAcknowledgedImmersiveModeSurface"] = VisionSurface.scene.rawValue
    case .panorama:
      values["projection"] = VisionProjection.sourcePanoramic.rawValue
      values["effectiveProjectionKind"] = "Equirectangular"
      values["presentationGeometry"] = "immersive"
      values["planarMeshActive"] = false
      values["placement"] = VisionPlaybackPlacement.panorama.rawValue
      values["sceneLifecycle"] = "open"
      values["sceneContent"] = VisionSceneContent.blackPanorama.rawValue
      values["windowLifecycle"] = "closed"
      values["presentationBinding"] = VisionSurface.scene.rawValue
      values["sceneContainer"] = VisionSceneID.playbackSpace
      values["parentIsWindowRoot"] = false
      values["parentIsPanoramaRoot"] = true
      values["panoramaRootEnabled"] = true
      values["actualImmersiveViewingMode"] = "progressive"
      values["lastAcknowledgedImmersiveModeSurface"] = VisionSurface.scene.rawValue
    }
    return values
  }

  private static func advancedSnapshot() -> [String: Any] {
    var values = snapshot(sampleCount: 2, currentSeconds: 1)
    values["displayedPixelBufferIdentity"] = "pixel-2"
    values["audioRendererSampleBufferCount"] = UInt64(2)
    return values
  }

  private static func emptySnapshot() -> [String: Any] {
    var values = snapshot()
    values["route"] = "none"
    values["source"] = "none"
    values["sourceAccessRequirement"] = "none"
    values["securityScopeHeld"] = false
    values["productShape"] = "none"
    values["candidateProductShape"] = VisionProductShape.flatWindow.rawValue
    values["windowLifecycle"] = "closed"
    values["sceneLifecycle"] = "closed"
    values["presentationSettled"] = false
    values["presentationBindingAttached"] = false
    values["realityKitBindingActive"] = false
    values["presentationBinding"] = "none"
    values["sceneContainer"] = "none"
    values["parentIsWindowRoot"] = false
    values["displayedPixelBuffer"] = false
    values["displayedPixelBufferIdentity"] = "none"
    values["mediaSessionID"] = "none"
    values["rendererIdentity"] = "none"
    values["rendererGraphID"] = "none"
    values["rendererSynchronizerIdentity"] = "none"
    values["videoEntityIdentity"] = "none"
    values["audioRendererSampleBufferCount"] = UInt64(0)
    values["audioRendererMediaSessionID"] = "none"
    values["audioRendererGraphID"] = "none"
    values["audioRendererIdentity"] = "none"
    values["audioRendererVideoRendererIdentity"] = "none"
    values["audioRendererSynchronizerIdentity"] = "none"
    values["audioRendererStreamEpoch"] = UInt64(0)
    values["hasActiveMediaSession"] = false
    values["hasVideoEntity"] = false
    values["status"] = "Idle"
    return values
  }

  private static func addCleanupEvidence(to values: inout [String: Any]) {
    values["lastCleanupMediaSessionID"] = "session-1"
    values["lastCleanupOperationKind"] = "close"
    values["lastCleanupOperationState"] = "completed"
    values["lastCleanupRendererFlushCount"] = UInt64(1)
    values["lastCleanupVideoProviderCancelled"] = true
    values["lastCleanupAudioProviderCancelled"] = true
    values["lastCleanupAudioRendererFlushed"] = true
    values["lastCleanupVideoRendererFlushed"] = true
    values["lastCleanupRealityKitBindingActive"] = false
    values["lastCleanupPresentationBindingAttached"] = false
  }

  private static func snapshot(
    sampleCount: UInt64 = 1,
    currentSeconds: Double = 0
  ) -> [String: Any] {
    [
      "route": VisionRegressionRoute.appleCompressed.rawValue,
      "source": "fixture.mov",
      "sourceAccessRequirement": "securityScoped",
      "securityScopeHeld": true,
      "productShape": VisionProductShape.flatWindow.rawValue,
      "candidateProductShape": VisionProductShape.flatWindow.rawValue,
      "projection": VisionProjection.flat.rawValue,
      "detectedProjectionKind": "Equirectangular",
      "effectiveProjectionKind": "Equirectangular",
      "placement": VisionPlaybackPlacement.window.rawValue,
      "stereoLayout": VisionStereoLayout.mono.rawValue,
      "sceneContent": "none",
      "customSceneRequestedOpen": false,
      "windowLifecycle": "open",
      "sceneLifecycle": "closed",
      "immersiveSceneLoaded": false,
      "immersiveSceneEnabled": false,
      "panoramaRootEnabled": false,
      "presentationSettled": true,
      "presentationBindingAttached": true,
      "realityKitBindingActive": true,
      "presentationGeometry": "planar",
      "planarMeshActive": true,
      "presentationBinding": VisionSurface.playbackWindow.rawValue,
      "sceneContainer": VisionSceneID.playbackWindow,
      "parentIsWindowRoot": true,
      "parentIsDockedRoot": false,
      "parentIsPanoramaRoot": false,
      "actualImmersiveViewingMode": "portal",
      "immersiveModeChangeSequence": UInt64(1),
      "lastAcknowledgedImmersiveModeSurface": VisionSurface.playbackWindow.rawValue,
      "actualViewingMode": "mono",
      "viewingModeChangeSequence": UInt64(1),
      "lastAcknowledgedViewingModeSurface": VisionSurface.playbackWindow.rawValue,
      "videoEntityIdentity": "entity-1",
      "rendererIdentity": "renderer-1",
      "rendererGraphID": "graph-1",
      "rendererSynchronizerIdentity": "synchronizer-1",
      "rendererMatchesSession": true,
      "rendererError": "none",
      "componentRenderingStatus": "ready",
      "displayedPixelBuffer": true,
      "displayedPixelBufferIdentity": "pixel-1",
      "sampleCount": sampleCount,
      "streamEpoch": UInt64(1),
      "rendererFlushCount": UInt64(0),
      "effectiveFormatRevision": UInt64(1),
      "currentSeconds": currentSeconds,
      "status": "Playing",
      "rendererTimelineRate": 1.0,
      "audioRendererSampleBufferCount": UInt64(1),
      "audioRendererMediaSessionID": "session-1",
      "audioRendererGraphID": "graph-1",
      "audioRendererIdentity": "audio-renderer-1",
      "audioRendererVideoRendererIdentity": "renderer-1",
      "audioRendererSynchronizerIdentity": "synchronizer-1",
      "audioRendererStreamEpoch": UInt64(1),
      "audioRendererError": "none",
      "audioRendererVolume": 1.0,
      "audioRendererMuted": false,
      "selectedAudioStreamIndex": 1,
      "lastCompletedOperationKind": "none",
      "lastCompletedOperationState": "none",
      "lastCompletedOperationTargetTime": -1.0,
      "mediaSessionID": "session-1",
      "effectiveViewPackingKind": "none",
      "effectiveHasLeftStereoEyeView": false,
      "effectiveHasRightStereoEyeView": false,
      "coreEffectiveStereoLayout": VisionStereoLayout.mono.rawValue,
      "routeSwitchOperationState": "none",
      "dockingAnchorReady": true,
      "dockingAnchorHasModel": false,
      "dockingAnchorComponentCount": 0,
      "dockedRootBoundToAnchor": true,
      "dockingAnchorPreservesAuthoredTransform": true,
      "hasActiveMediaSession": true,
      "hasVideoEntity": true,
      "lastCleanupMediaSessionID": "none",
      "lastCleanupOperationKind": "none",
      "lastCleanupOperationState": "none",
      "lastCleanupRendererFlushCount": UInt64(0),
      "lastCleanupVideoProviderCancelled": false,
      "lastCleanupAudioProviderCancelled": false,
      "lastCleanupAudioRendererFlushed": false,
      "lastCleanupVideoRendererFlushed": false,
      "lastCleanupRealityKitBindingActive": true,
      "lastCleanupPresentationBindingAttached": true,
      "presentationRollbackState": "none",
      "presentationRollbackError": "none",
    ]
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) {
    guard condition() else {
      FileHandle.standardError.write(Data("RED \(message)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}
