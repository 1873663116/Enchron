import Darwin
import CoreVideo
import Foundation
import PlaybackCore

private struct VisionRegressionFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

@MainActor
final class VisionRegressionRunner {
  private static var hasStarted = false

  private struct Fixtures {
    let flat: URL
    let panorama: URL
  }

  private struct Observation {
    let values: [String: Any]
    let typed: VisionRegressionEvidenceSnapshot
    let displayedPixelBuffer: CVPixelBuffer?
    let renderer: AnyObject?
    let videoEntity: AnyObject?

    init(
      _ values: [String: Any],
      displayedPixelBuffer: CVPixelBuffer?,
      renderer: AnyObject?,
      videoEntity: AnyObject?
    ) {
      self.values = values
      typed = VisionRegressionEvidenceSnapshot(values)
      self.displayedPixelBuffer = displayedPixelBuffer
      self.renderer = renderer
      self.videoEntity = videoEntity
    }
  }

  private struct ControlResult {
    let baseline: Observation
    let target: Observation
  }

  private struct Record {
    let result: VisionRegressionCaseResult
    let evidence: [String: Any]
  }

  private let model: VisionPlaybackModel
  private let actions: VisionPresentationActions
  private let onProgress: @MainActor (String) -> Void
  private var stereoSuiteSessionID: String?
  private var stereoSuiteRendererIdentity: String?
  private var currentCaseEvidence = [String: Any]()
  private var retainedCaseObservations = [String: Observation]()
  private var currentCaseID = "notStarted"
  private var currentCaseNumber = 0
  private var currentCaseSummary = "准备回归测试"
  private var currentExpectedPicture = "等待测试开始"

  init(
    model: VisionPlaybackModel,
    actions: VisionPresentationActions,
    onProgress: @escaping @MainActor (String) -> Void = { _ in }
  ) {
    self.model = model
    self.actions = actions
    self.onProgress = onProgress
  }

  func runAndExit() async {
    let runID = ProcessInfo.processInfo.environment["PLAYBACKLAB_PRESENTATION_PROBE_RUN_ID"]
      ?? UUID().uuidString
    guard !Self.hasStarted else {
      trace("run.skipDuplicate id=\(runID)")
      return
    }
    Self.hasStarted = true
    trace("run.start id=\(runID) cases=\(VisionRegressionPlan.cases.count)")
    do {
      try validateProvenance()
      let fixtures = try loadFixtures()
      var records = [Record]()
      for (index, testCase) in VisionRegressionPlan.cases.enumerated() {
        currentCaseID = testCase.id
        currentCaseNumber = index + 1
        currentCaseSummary = caseSummary(testCase.kind)
        currentExpectedPicture = caseExpectedPicture(testCase.kind)
        let startedAt = Date()
        reportProgress(action: "开始用例")
        trace("case.start index=\(index + 1)/\(VisionRegressionPlan.cases.count) id=\(testCase.id)")
        let record = await run(testCase, fixtures: fixtures)
        records.append(record)
        let outcome = record.result.passed ? "pass" : "fail"
        let error = record.result.error.map { " error=\($0)" } ?? ""
        trace(
          "case.\(outcome) index=\(index + 1)/\(VisionRegressionPlan.cases.count) "
            + "id=\(testCase.id) elapsed=\(elapsed(since: startedAt))s\(error)"
        )
        if !record.result.passed {
          reportProgress(
            action: "用例失败",
            detail: record.result.error ?? "unknown"
          )
        }
      }
      let validation = VisionRegressionPlan.validate(results: records.map(\.result))
      try write(runID: runID, records: records, validation: validation, fixtureError: nil)
      trace(
        "run.finish id=\(runID) passed=\(validation.passed) "
          + "failedCases=\(validation.failedCaseIDs.count)"
      )
      exit(validation.passed ? EXIT_SUCCESS : EXIT_FAILURE)
    } catch {
      trace("run.abort id=\(runID) error=\(error.localizedDescription)")
      let validation = VisionRegressionPlan.validate(results: [])
      try? write(
        runID: runID,
        records: [],
        validation: validation,
        fixtureError: error.localizedDescription
      )
      exit(EXIT_FAILURE)
    }
  }

  private func run(
    _ testCase: VisionRegressionCase,
    fixtures: Fixtures
  ) async -> Record {
    currentCaseEvidence = [:]
    retainedCaseObservations = [:]
    do {
      let evidence = try await execute(testCase.kind, fixtures: fixtures)
      return Record(
        result: VisionRegressionCaseResult(caseID: testCase.id, passed: true),
        evidence: evidence
      )
    } catch {
      let target = observe()
      remember(target, as: "target")
      await holdForObservation(
        action: "失败状态停留",
        expected: currentExpectedPicture,
        detail: error.localizedDescription
      )
      return Record(
        result: VisionRegressionCaseResult(
          caseID: testCase.id,
          passed: false,
          error: error.localizedDescription
        ),
        evidence: currentCaseEvidence
      )
    }
  }

  private func execute(
    _ kind: VisionRegressionCaseKind,
    fixtures: Fixtures
  ) async throws -> [String: Any] {
    switch kind {
    case .lifecycle(let lifecycle):
      return try await exercise(lifecycle)

    case .sceneLifecycleWithPlayback(let lifecycle):
      return try await exercise(lifecycle, fixture: fixtures.flat)

    case .productShape(let route, let shape):
      let fixture = shape == .portalWindow || shape == .panorama
        ? fixtures.panorama : fixtures.flat
      let baseline = try await prepareNewSession(
        fixture: fixture,
        route: playbackRoute(route)
      )
      remember(baseline, as: "baseline")
      try await transition(to: shape)
      let target = try await waitForPresentation(shape, after: baseline)
      return evidence(baseline: baseline, target: target)

    case .stereoRoundTrip(let shape, let layout):
      try await prepareStereoSuiteIfNeeded(fixtures: fixtures)
      try await ensureStereoFixtureHeadroom()
      let setupBaseline = observe()
      remember(setupBaseline, as: "setupBaseline")
      try await transition(to: shape)
      let shapeReady = try await waitForPresentation(shape, after: setupBaseline)
      remember(shapeReady, as: "shapeReady")
      try await command(.setStereo(.mono))
      let baseline = observe()
      remember(baseline, as: "baseline")
      try requireStereoSuiteIdentity(baseline)

      try await command(.setStereo(layout))
      let target = try await waitForStereo(layout, after: baseline)
      remember(target, as: "stereoTarget")
      try requireStereoSuiteIdentity(target)

      try await command(.setStereo(.mono))
      let restored = try await waitForStereo(.mono, after: target)
      remember(restored, as: "stereoRestored")
      try requireStereoSuiteIdentity(restored)
      return [
        "baseline": baseline.values,
        "target": target.values,
        "restored": restored.values,
      ]

    case .sceneRestoration(let sceneBaseline, let exit):
      let prepared: Observation
      if sceneBaseline == .customSceneOpen {
        prepared = try await prepareSceneFirstSession(
          fixture: fixtures.panorama,
          route: .appleCompressed
        )
      } else {
        prepared = try await prepareNewSession(
          fixture: fixtures.panorama,
          route: .appleCompressed
        )
      }
      try await transition(to: .portalWindow, preserveOpenScene: sceneBaseline == .customSceneOpen)
      let baseline = try await waitForPresentation(.portalWindow, after: prepared)
      remember(baseline, as: "baseline")
      try await command(.showPanorama)
      let panorama = try await waitForPresentation(.panorama, after: baseline)
      remember(panorama, as: "panorama")
      let restored: Observation
      switch exit {
      case .showWindow:
        try await command(.showWindow)
        restored = try await waitForPresentation(.portalWindow, after: panorama)
        try expectNoFailures(
          VisionRegressionEvidenceContract.activeMediaSceneRestorationFailures(
            baseline: sceneBaseline,
            target: restored.typed
          )
        )
      case .closeMedia:
        await model.closeMedia(actions: actions)
        restored = observe()
      }
      if exit == .closeMedia {
        try expectNoFailures(
          VisionRegressionEvidenceContract.mediaCloseSceneRestorationFailures(
            mediaSessionID: baseline.typed.mediaSessionID,
            baseline: sceneBaseline,
            target: restored.typed
          )
        )
      }
      remember(restored, as: "restored")
      return [
        "baseline": baseline.values,
        "panorama": panorama.values,
        "restored": restored.values,
      ]

    case .presentationEdge(let edge):
      return try await exercise(edge, fixtures: fixtures)

    case .control(let route, let control):
      let prepared = try await prepareNewSession(
        fixture: fixtures.flat,
        route: playbackRoute(route)
      )
      let baseline = try await waitForControlAudioBaseline(after: prepared)
      remember(baseline, as: "controlBaseline")
      let result = try await exercise(control, route: route, baseline: baseline)
      return evidence(baseline: result.baseline, target: result.target)

    case .coldRouteSwitch:
      let prepared = try await prepareNewSession(
        fixture: fixtures.flat,
        route: .appleCompressed
      )
      let baseline = try await waitForControlAudioBaseline(after: prepared)
      remember(baseline, as: "baseline")
      await model.selectRoute(.ffmpegCompressed)
      let target = try await waitForEvidence("routeSwitch.evidence") { observation in
        VisionRegressionEvidenceContract.coldSwitchFailures(
          baseline: baseline.typed,
          target: observation.typed
        )
      }
      return evidence(baseline: baseline, target: target)

    case .cleanup:
      let cleanupBaseline = observe()
      remember(cleanupBaseline, as: "baseline")
      let mediaSessionID = cleanupBaseline.typed.mediaSessionID
      try expect(mediaSessionID != "none", "cleanup.activeSessionMissing")
      await model.closeMedia(actions: actions)
      try await command(.closeScene)
      try await command(.closePlaybackWindow)
      let target = observe()
      try expectNoFailures(
        VisionRegressionEvidenceContract.cleanupFailures(
          mediaSessionID: mediaSessionID,
          target: target.typed
        )
      )
      return ["target": target.values]
    }
  }

  private func prepareNewSession(
    fixture: URL,
    route: PlaybackRoute
  ) async throws -> Observation {
    stereoSuiteSessionID = nil
    stereoSuiteRendererIdentity = nil
    await model.closeAndWait()
    if model.presentationFacts.sceneLifecycle != .closed {
      try await command(.closeScene)
    }
    if model.presentation.isWindowOpen {
      try await command(.closePlaybackWindow)
    }
    if model.selectedRoute != route { await model.selectRoute(route) }
    await model.openImportedVideo(fixture)
    try await command(.openPlaybackWindow)
    _ = try await waitForMediaInputReady()
    try await command(.setProjection(.flat))
    if model.presentationFacts.sceneLifecycle != .closed {
      try await command(.closeScene)
    }
    try await command(.setStereo(.mono))
    let prepared = try await waitForEvidence("media.notPrepared", timeout: .seconds(10)) {
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: self.regressionRoute(route),
        target: $0.typed
      )
    }
    remember(prepared, as: "preparation")
    return prepared
  }

  private func prepareSceneFirstSession(
    fixture: URL,
    route: PlaybackRoute
  ) async throws -> Observation {
    stereoSuiteSessionID = nil
    stereoSuiteRendererIdentity = nil
    await model.closeAndWait()
    if model.presentationFacts.sceneLifecycle != .closed {
      try await command(.closeScene)
    }
    if model.presentation.isWindowOpen {
      try await command(.closePlaybackWindow)
    }
    try await command(.openScene)
    let sceneBeforeMedia = observe()
    try expectNoFailures(
      VisionRegressionEvidenceContract.lifecycleFailures(
        expected: .customSceneOpenWithoutMedia,
        target: sceneBeforeMedia.typed
      )
    )
    remember(sceneBeforeMedia, as: "sceneBeforeMedia")
    if model.selectedRoute != route { await model.selectRoute(route) }
    await model.openImportedVideo(fixture)
    try await command(.openPlaybackWindow)
    _ = try await waitForMediaInputReady()
    try await command(.setProjection(.flat))
    try await command(.setStereo(.mono))
    let prepared = try await waitForEvidence("media.sceneFirstNotPrepared", timeout: .seconds(10)) {
      VisionRegressionEvidenceContract.preparedSessionFailures(
        expectedRoute: self.regressionRoute(route),
        sceneBaseline: .customSceneOpen,
        target: $0.typed
      )
    }
    remember(prepared, as: "preparation")
    return prepared
  }

  private func prepareStereoSuiteIfNeeded(fixtures: Fixtures) async throws {
    if let expectedSession = stereoSuiteSessionID,
      let expectedRenderer = stereoSuiteRendererIdentity
    {
      let current = observe().typed
      try expect(current.mediaSessionID == expectedSession, "stereo.sessionChangedBetweenCases")
      try expect(
        current.rendererIdentity == expectedRenderer,
        "stereo.rendererChangedBetweenCases"
      )
      return
    }

    let opened = try await prepareNewSession(
      fixture: fixtures.panorama,
      route: .appleCompressed
    )
    stereoSuiteSessionID = opened.typed.mediaSessionID
    stereoSuiteRendererIdentity = opened.typed.rendererIdentity
  }

  private func requireStereoSuiteIdentity(_ observation: Observation) throws {
    try expect(
      observation.typed.mediaSessionID == stereoSuiteSessionID,
      "stereo.fixedSessionChanged"
    )
    try expect(
      observation.typed.rendererIdentity == stereoSuiteRendererIdentity,
      "stereo.fixedRendererChanged"
    )
  }

  private func ensureStereoFixtureHeadroom() async throws {
    guard model.durationSeconds > 0,
      model.durationSeconds - model.currentSeconds < 10
    else { return }
    await model.seek(to: 0)
    _ = try await waitForPlayableMedia()
    try requireStereoSuiteIdentity(observe())
  }

  private func transition(
    to shape: VisionProductShape,
    preserveOpenScene: Bool = false
  ) async throws {
    if model.presentedProductShape == shape { return }
    switch model.presentationFacts.placement {
    case .docked:
      try await command(.showWindow, rememberAs: "transition.windowFromDocked")
    case .panorama:
      try await command(.setProjection(.flat), rememberAs: "transition.windowFromPanorama")
    case .window:
      break
    }
    try await command(.setProjection(.flat), rememberAs: "transition.flatProjection")
    if !preserveOpenScene, model.presentationFacts.sceneLifecycle != .closed {
      try await command(.closeScene, rememberAs: "transition.sceneClosed")
    }
    if !model.presentation.isWindowOpen {
      try await command(.openPlaybackWindow, rememberAs: "transition.windowOpened")
    }
    switch shape {
    case .flatWindow:
      try await command(.setProjection(.flat), rememberAs: "transition.targetFlat")
    case .portalWindow:
      try await command(
        .setProjection(.sourcePanoramic),
        rememberAs: "transition.targetPortal"
      )
    case .docked:
      try await command(.openScene, rememberAs: "transition.sceneOpened")
      try await command(.dock, rememberAs: "transition.targetDocked")
    case .panorama:
      try await command(
        .setProjection(.sourcePanoramic),
        rememberAs: "transition.portalBeforePanorama"
      )
      try await command(.showPanorama, rememberAs: "transition.targetPanorama")
    }
  }

  private func exercise(
    _ lifecycle: VisionRegressionLifecycle
  ) async throws -> [String: Any] {
    await model.closeAndWait()
    if model.presentationFacts.sceneLifecycle != .closed {
      try await command(.closeScene)
    }
    if model.presentation.isWindowOpen {
      try await command(.closePlaybackWindow)
    }

    switch lifecycle {
    case .playbackWindowOpenWithoutMedia:
      try await command(.openPlaybackWindow)
    case .playbackWindowCloseWithoutMedia:
      try await command(.openPlaybackWindow)
      try await command(.closePlaybackWindow)
    case .customSceneOpenWithoutMedia:
      try await command(.openScene)
    case .customSceneCloseWithoutMedia:
      try await command(.openScene)
      try await command(.closeScene)
    }

    let target = observe()
    try expectNoFailures(
      VisionRegressionEvidenceContract.lifecycleFailures(
        expected: lifecycle,
        target: target.typed
      )
    )
    return ["target": target.values]
  }

  private func exercise(
    _ lifecycle: VisionRegressionPlaybackSceneLifecycle,
    fixture: URL
  ) async throws -> [String: Any] {
    let windowBaseline = try await prepareNewSession(
      fixture: fixture,
      route: .appleCompressed
    )
    remember(windowBaseline, as: "baseline")
    try await command(.openScene)
    let opened = try await waitForEvidence("scene.openMigratedPlayback") {
      VisionRegressionEvidenceContract.sceneOpenWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: windowBaseline.typed,
        target: $0.typed
      )
    }
    remember(opened, as: "opened")
    guard lifecycle == .closeDoesNotMigrate else {
      return evidence(baseline: windowBaseline, target: opened)
    }

    try await command(.closeScene)
    let closed = try await waitForEvidence("scene.closeMigratedPlayback") { target in
      VisionRegressionEvidenceContract.sceneCloseWithoutMigrationFailures(
        expectedRoute: .appleCompressed,
        baseline: opened.typed,
        target: target.typed
      )
    }
    return [
      "baseline": windowBaseline.values,
      "opened": opened.values,
      "target": closed.values,
    ]
  }

  private func exercise(
    _ edge: VisionRegressionEdge,
    fixtures: Fixtures
  ) async throws -> [String: Any] {
    let prepared = try await prepareNewSession(
      fixture: fixtures.panorama,
      route: .appleCompressed
    )
    switch edge {
    case .dockedToFlatWindow:
      try await transition(to: .docked)
      let baseline = try await waitForPresentation(.docked, after: prepared)
      remember(baseline, as: "edgeBaseline")
      try await command(.showWindow)
      let target = try await waitForPresentation(.flatWindow, after: baseline)
      try expectNoFailures(
        VisionRegressionEvidenceContract.presentationEdgeFailures(
          edge: edge,
          target: target.typed
        )
      )
      return evidence(baseline: baseline, target: target)
    case .dockedToPanorama:
      try await transition(to: .docked)
      let baseline = try await waitForPresentation(.docked, after: prepared)
      remember(baseline, as: "edgeBaseline")
      try await command(.setProjection(.sourcePanoramic))
      let target = try await waitForPresentation(.panorama, after: baseline)
      try expectNoFailures(
        VisionRegressionEvidenceContract.presentationEdgeFailures(
          edge: edge,
          target: target.typed
        )
      )
      return evidence(baseline: baseline, target: target)
    case .panoramaToFlatWindow:
      try await transition(to: .panorama)
      let baseline = try await waitForPresentation(.panorama, after: prepared)
      remember(baseline, as: "edgeBaseline")
      try await command(.setProjection(.flat))
      let target = try await waitForPresentation(.flatWindow, after: baseline)
      try expectNoFailures(
        VisionRegressionEvidenceContract.presentationEdgeFailures(
          edge: edge,
          target: target.typed
        )
      )
      return evidence(baseline: baseline, target: target)
    }
  }

  private func exercise(
    _ control: VisionRegressionControl,
    route: VisionRegressionRoute,
    baseline: Observation
  ) async throws -> ControlResult {
    switch control {
    case .pause:
      let playing = try await ensurePlayingBaseline(route: route, after: baseline)
      model.pause()
      let target = try await waitForEvidence("control.pause") { target in
        VisionRegressionEvidenceContract.pauseFailures(
          expectedRoute: route,
          baseline: playing.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: playing, target: target)

    case .play:
      let playing = try await ensurePlayingBaseline(route: route, after: baseline)
      model.pause()
      let paused = try await waitForEvidence("control.playPausedBaseline") { target in
        VisionRegressionEvidenceContract.pauseFailures(
          expectedRoute: route,
          baseline: playing.typed,
          target: target.typed
        )
      }
      remember(paused, as: "pausedBaseline")
      model.play()
      let target = try await waitForEvidence("control.play") { target in
        VisionRegressionEvidenceContract.playFailures(
          expectedRoute: route,
          baseline: paused.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: paused, target: target)

    case .rate:
      let playing = try await ensurePlayingBaseline(route: route, after: baseline)
      model.setRate(1.5)
      let target = try await waitForEvidence("control.rate") { target in
        VisionRegressionEvidenceContract.rateFailures(
          expectedRoute: route,
          expectedRate: 1.5,
          baseline: playing.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: playing, target: target)

    case .seek:
      let playing = try await ensurePlayingBaseline(route: route, after: baseline)
      let targetSeconds = min(max(model.durationSeconds * 0.4, 1), 5)
      await model.seek(to: targetSeconds)
      let target = try await waitForEvidence("control.seek") { target in
        VisionRegressionEvidenceContract.seekFailures(
          expectedRoute: route,
          expectedSeconds: targetSeconds,
          baseline: playing.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: playing, target: target)

    case .audioTrack:
      guard let track = model.audioTracks.first(where: {
        $0.streamIndex != model.selectedAudioStreamIndex
      }) else {
        throw VisionRegressionFailure(message: "control.audioTrack.fixtureHasNoAlternateAudio")
      }
      model.selectAudioTrack(track.streamIndex)
      let target = try await waitForEvidence("control.audioTrack") { target in
        VisionRegressionEvidenceContract.audioTrackFailures(
          expectedRoute: route,
          expectedStreamIndex: track.streamIndex,
          baseline: baseline.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: baseline, target: target)

    case .volume:
      model.setVolume(0.35)
      let target = try await waitForEvidence("control.volume") { target in
        VisionRegressionEvidenceContract.volumeFailures(
          expectedRoute: route,
          expectedVolume: 0.35,
          baseline: baseline.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: baseline, target: target)

    case .muteToggle:
      let expected = !model.isMuted
      model.setMuted(expected)
      let target = try await waitForEvidence("control.muteToggle") { target in
        VisionRegressionEvidenceContract.muteFailures(
          expectedRoute: route,
          expectedMuted: expected,
          baseline: baseline.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: baseline, target: target)

    case .reopen:
      await model.reopen()
      let target = try await waitForEvidence("control.reopen") { target in
        VisionRegressionEvidenceContract.reopenFailures(
          expectedRoute: route,
          baseline: baseline.typed,
          target: target.typed
        )
      }
      return ControlResult(baseline: baseline, target: target)

    case .close:
      let mediaSessionID = baseline.typed.mediaSessionID
      await model.closeMedia(actions: actions)
      let target = observe()
      try expectNoFailures(
        VisionRegressionEvidenceContract.cleanupFailures(
          mediaSessionID: mediaSessionID,
          target: target.typed,
          requirePresentationClosed: false
        )
      )
      return ControlResult(baseline: baseline, target: target)
    }
  }

  private func waitForPlayableMedia() async throws -> Observation {
    try await waitForEvidence("media.notReady", timeout: .seconds(10)) { target in
      var failures = [String]()
      if !["Ready", "Playing", "Paused"].contains(target.typed.status) {
        failures.append("media.status")
      }
      if target.typed.sampleCount == 0 { failures.append("media.sample") }
      failures.append(contentsOf: self.activeOutputFailures(target))
      return failures
    }
  }

  private func waitForControlAudioBaseline(after baseline: Observation) async throws -> Observation {
    try await waitForEvidence("control.audioBaseline", timeout: .seconds(3)) { target in
      var failures = VisionRegressionEvidenceContract.controlAudioBaselineFailures(
        target: target.typed
      )
      if target.typed.mediaSessionID != baseline.typed.mediaSessionID {
        failures.append("control.audioBaselineSessionChanged")
      }
      if target.typed.rendererIdentity != baseline.typed.rendererIdentity {
        failures.append("control.audioBaselineRendererChanged")
      }
      return failures
    }
  }

  private func waitForMediaInputReady() async throws -> Observation {
    try await waitForEvidence("media.inputNotReady", timeout: .seconds(10)) { target in
      var failures = [String]()
      if !["Ready", "Playing", "Paused"].contains(target.typed.status) {
        failures.append("media.status")
      }
      if target.typed.sampleCount == 0 { failures.append("media.sample") }
      if !target.typed.presentationBindingAttached { failures.append("media.binding") }
      if !target.typed.realityKitBindingActive { failures.append("media.realityBinding") }
      if !target.typed.rendererMatchesSession { failures.append("media.renderer") }
      if target.typed.rendererError != "none" { failures.append("media.rendererError") }
      if target.typed.componentRenderingStatus.lowercased() != "ready" {
        failures.append("media.component")
      }
      if !target.typed.displayedPixelBuffer { failures.append("media.displayedPixel") }
      return failures
    }
  }

  private func waitForPresentation(
    _ shape: VisionProductShape,
    after baseline: Observation
  ) async throws -> Observation {
    guard let expectedRoute = VisionRegressionRoute(rawValue: baseline.typed.route) else {
      throw VisionRegressionFailure(message: "shape.baselineRouteMissing")
    }
    let observation = try await waitForEvidence(
      "shape.\(shape.rawValue).evidence",
      timeout: .seconds(3)
    ) {
      VisionRegressionEvidenceContract.presentationFailures(
        expectedRoute: expectedRoute,
        expectedShape: shape,
        baseline: baseline.typed,
        target: $0.typed
      )
    }
    await holdForObservation(
      action: "播放形态已稳定",
      expected: shapeExpectedPicture(shape)
    )
    return observation
  }

  private func waitForStereo(
    _ layout: VisionStereoLayout,
    after baseline: Observation
  ) async throws -> Observation {
    let observation = try await waitForEvidence(
      "stereo.\(layout.rawValue).evidence",
      timeout: .seconds(3)
    ) {
      VisionRegressionEvidenceContract.stereoFailures(
        expectedLayout: layout,
        baseline: baseline.typed,
        target: $0.typed
      )
    }
    await holdForObservation(
      action: "立体布局已稳定",
      expected: "保持当前窗口或空间形态，画面为 \(stereoLabel(layout))"
    )
    return observation
  }

  private func ensurePlayingBaseline(
    route: VisionRegressionRoute,
    after baseline: Observation
  ) async throws -> Observation {
    if baseline.typed.status != "Playing" || baseline.typed.rendererTimelineRate <= 0 {
      model.play()
    }
    let playing = try await waitForEvidence("control.playingBaseline") { target in
      var failures = self.activeOutputFailures(target)
      if target.typed.route != route.rawValue { failures.append("control.baselineRoute") }
      if target.typed.mediaSessionID != baseline.typed.mediaSessionID {
        failures.append("control.baselineSessionChanged")
      }
      if target.typed.rendererIdentity != baseline.typed.rendererIdentity {
        failures.append("control.baselineRendererChanged")
      }
      if target.typed.videoEntityIdentity != baseline.typed.videoEntityIdentity {
        failures.append("control.baselineEntityChanged")
      }
      if target.typed.status != "Playing" { failures.append("control.baselineStatus") }
      if target.typed.rendererTimelineRate <= 0 { failures.append("control.baselineRate") }
      return failures
    }
    remember(playing, as: "playingBaseline")
    return playing
  }

  private func freshActiveOutputFailures(
    baseline: Observation,
    target: Observation
  ) -> [String] {
    var failures = activeOutputFailures(target)
    if target.typed.mediaSessionID != baseline.typed.mediaSessionID {
      failures.append("control.sessionChanged")
    }
    if target.typed.rendererIdentity != baseline.typed.rendererIdentity {
      failures.append("control.rendererChanged")
    }
    if target.typed.sampleCount <= baseline.typed.sampleCount {
      failures.append("control.sampleDidNotAdvance")
    }
    if target.typed.currentSeconds <= baseline.typed.currentSeconds {
      failures.append("control.timeDidNotAdvance")
    }
    return failures
  }

  private func activeOutputFailures(_ target: Observation) -> [String] {
    var failures = [String]()
    if !target.typed.presentationSettled { failures.append("playback.presentationNotSettled") }
    if !target.typed.presentationBindingAttached { failures.append("playback.bindingNotAttached") }
    if !target.typed.realityKitBindingActive { failures.append("playback.realityBindingInactive") }
    if !target.typed.rendererMatchesSession { failures.append("playback.rendererMismatch") }
    if target.typed.rendererError != "none" { failures.append("playback.rendererError") }
    if target.typed.componentRenderingStatus.lowercased() != "ready" {
      failures.append("playback.componentNotReady")
    }
    if !target.typed.displayedPixelBuffer { failures.append("playback.displayedPixelMissing") }
    return failures
  }

  private func command(_ command: PresentationCommand) async throws {
    let startedAt = Date()
    let name = String(describing: command)
    reportProgress(
      action: commandLabel(command),
      expected: commandExpectedPicture(command)
    )
    trace("command.start case=\(currentCaseID) command=\(name)")
    let result = await model.performPresentationCommand(command, actions: actions)
    guard result.succeeded else {
      trace(
        "command.fail case=\(currentCaseID) command=\(name) "
          + "elapsed=\(elapsed(since: startedAt))s error=\(result.error ?? "failed")"
      )
      throw VisionRegressionFailure(
        message: "command.\(name).\(result.error ?? "failed")"
      )
    }
    trace(
      "command.pass case=\(currentCaseID) command=\(name) "
        + "elapsed=\(elapsed(since: startedAt))s"
    )
  }

  private func command(
    _ command: PresentationCommand,
    rememberAs key: String
  ) async throws {
    try await self.command(command)
    remember(observe(), as: key)
  }

  private func waitForEvidence(
    _ failure: String,
    timeout: Duration = .seconds(3),
    validator: @escaping @MainActor (Observation) -> [String]
  ) async throws -> Observation {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    let startedAt = Date()
    var latest = observe()
    var lastFailureSignature: String?
    while clock.now < deadline {
      latest = observe()
      remember(latest, as: "latest")
      let failures = validator(latest)
      if failures.isEmpty {
        trace(
          "assert.pass case=\(currentCaseID) assertion=\(failure) "
            + "elapsed=\(elapsed(since: startedAt))s"
        )
        return latest
      }
      let signature = failures.joined(separator: ",")
      if signature != lastFailureSignature {
        reportProgress(
          action: "等待画面达到预期",
          detail: "尚未满足：\(signature)"
        )
        trace(
          "assert.pending case=\(currentCaseID) assertion=\(failure) "
            + "elapsed=\(elapsed(since: startedAt))s unmet=\(signature)"
        )
        lastFailureSignature = signature
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    let failures = validator(latest)
    trace(
      "assert.timeout case=\(currentCaseID) assertion=\(failure) "
        + "elapsed=\(elapsed(since: startedAt))s unmet=\(failures.joined(separator: ","))"
    )
    throw VisionRegressionFailure(message: "\(failure).\(failures.joined(separator: ","))")
  }

  private func waitUntil(
    _ failure: String,
    timeout: Duration = .seconds(3),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
    try expect(condition(), failure)
  }

  private func observe() -> Observation {
    let observation = model.presentationObservation()
    return Observation(
      observation.state,
      displayedPixelBuffer: observation.displayedPixelBuffer,
      renderer: observation.renderer,
      videoEntity: observation.videoEntity
    )
  }

  private func remember(_ observation: Observation, as key: String) {
    currentCaseEvidence[key] = observation.values
    retainedCaseObservations[key] = observation
  }

  private func evidence(
    baseline: Observation,
    target: Observation
  ) -> [String: Any] {
    ["baseline": baseline.values, "target": target.values]
  }

  private func expectNoFailures(_ failures: [String]) throws {
    if let first = failures.first {
      throw VisionRegressionFailure(message: first)
    }
  }

  private func elapsed(since start: Date) -> String {
    String(format: "%.2f", Date().timeIntervalSince(start))
  }

  private func trace(_ message: String) {
    let line = "[VisionRegression] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
  }

  private func reportProgress(
    action: String,
    expected: String? = nil,
    detail: String? = nil
  ) {
    let expected = expected ?? currentExpectedPicture
    var lines = [
      "测试 \(currentCaseNumber)/\(VisionRegressionPlan.cases.count)",
      "播放形态：\(currentCaseSummary)",
      "当前动作：\(action)",
      "此刻应看到：\(expected)",
    ]
    if let detail { lines.append("状态：\(detail)") }
    lines.append("内部用例：\(currentCaseID)")
    onProgress(lines.joined(separator: "\n"))
  }

  private func holdForObservation(
    action: String,
    expected: String,
    detail: String? = nil
  ) async {
    for secondsRemaining in stride(from: 7, through: 1, by: -1) {
      let countdown = detail.map { "\($0) · 还剩 \(secondsRemaining) 秒" }
        ?? "还剩 \(secondsRemaining) 秒"
      reportProgress(
        action: "\(action) · 观察中",
        expected: expected,
        detail: countdown
      )
      try? await Task.sleep(for: .seconds(1))
    }
  }

  private func caseSummary(_ kind: VisionRegressionCaseKind) -> String {
    switch kind {
    case .lifecycle(let lifecycle):
      return "无媒体的窗口与场景生命周期 · \(lifecycle.rawValue)"
    case .sceneLifecycleWithPlayback(let lifecycle):
      return "平面窗口播放时开关天空盒 · \(lifecycle.rawValue)"
    case .productShape(let route, let shape):
      return "\(routeLabel(route)) · \(shapeLabel(shape))"
    case .stereoRoundTrip(let shape, let layout):
      return "\(shapeLabel(shape)) · Mono ↔ \(stereoLabel(layout))"
    case .sceneRestoration(let baseline, let exit):
      return "全景退出后的场景恢复 · \(baseline.rawValue) · \(exit.rawValue)"
    case .presentationEdge(let edge):
      return "播放形态路线 · \(edge.rawValue)"
    case .control(let route, let control):
      return "\(routeLabel(route)) · 播放控制 \(control.rawValue)"
    case .coldRouteSwitch:
      return "Apple Compressed → FFmpeg Compressed 冷切换"
    case .cleanup:
      return "最终清理"
    }
  }

  private func caseExpectedPicture(_ kind: VisionRegressionCaseKind) -> String {
    switch kind {
    case .productShape(_, let shape), .stereoRoundTrip(let shape, _):
      return shapeExpectedPicture(shape)
    case .lifecycle(let lifecycle):
      switch lifecycle {
      case .playbackWindowOpenWithoutMedia:
        return "出现一个空的播放窗口；不应自动播放或打开天空盒"
      case .playbackWindowCloseWithoutMedia:
        return "播放窗口关闭；不应打开天空盒"
      case .customSceneOpenWithoutMedia:
        return "天空盒场景出现，但没有视频画面"
      case .customSceneCloseWithoutMedia:
        return "天空盒场景关闭，回到现实空间"
      }
    case .sceneLifecycleWithPlayback:
      return "视频始终留在可移动的平面窗口；开关天空盒不应迁移视频"
    case .sceneRestoration:
      return "先出现完整全景，退出后恢复进入全景前的天空盒开关状态"
    case .presentationEdge(let edge):
      switch edge {
      case .dockedToFlatWindow:
        return "Docking 画面离开锚点，恢复为可移动的平面窗口"
      case .dockedToPanorama:
        return "先离开 Docking，再进入黑场中的完整全景网格；不应出现小球"
      case .panoramaToFlatWindow:
        return "完整全景关闭，恢复为可移动的平面窗口"
      }
    case .control:
      return "保持平面播放窗口，只验证当前播放控制，不应改变呈现形态"
    case .coldRouteSwitch:
      return "平面窗口保持存在，播放器会重开并继续出画面"
    case .cleanup:
      return "播放窗口和天空盒都关闭，不再有视频画面"
    }
  }

  private func commandLabel(_ command: PresentationCommand) -> String {
    switch command {
    case .openPlaybackWindow: "打开播放窗口"
    case .closePlaybackWindow: "关闭播放窗口"
    case .openScene: "打开天空盒场景"
    case .closeScene: "关闭天空盒场景"
    case .showWindow: "退出当前空间形态并恢复窗口"
    case .dock: "把平面视频停靠到 Screen 锚点"
    case .showPanorama: "从 Portal 展开为完整全景"
    case .setProjection(.flat): "切换为平面投影"
    case .setProjection(.sourcePanoramic): "切换为 Portal 投影"
    case .setStereo(let layout): "切换立体布局为 \(stereoLabel(layout))"
    }
  }

  private func commandExpectedPicture(_ command: PresentationCommand) -> String {
    switch command {
    case .openPlaybackWindow:
      return "出现可用 Window Bar 移动的独立播放窗口"
    case .closePlaybackWindow:
      return "播放窗口消失"
    case .openScene:
      return "天空盒出现；视频保持原来的窗口或停靠形态"
    case .closeScene:
      return "天空盒消失；视频保持原来的窗口形态"
    case .showWindow:
      return "沉浸全景或 Docking 消失，恢复独立播放窗口"
    case .dock:
      return "天空盒中的 Screen 锚点承载平面视频；没有全景球"
    case .showPanorama:
      return "窗口关闭，黑场中出现覆盖视野的完整 180°/360° 全景网格"
    case .setProjection(.flat):
      return "视频是矩形平面；没有 Portal 透视，也没有全景球"
    case .setProjection(.sourcePanoramic):
      return "同一播放窗口内出现 Portal 透视；不是普通平面，也不是完整沉浸全景"
    case .setStereo(let layout):
      return "保持当前播放形态，仅画面变为 \(stereoLabel(layout))；窗口和场景不应增减"
    }
  }

  private func shapeExpectedPicture(_ shape: VisionProductShape) -> String {
    switch shape {
    case .flatWindow:
      return "可移动的矩形平面播放窗口；没有 Portal 或全景球"
    case .portalWindow:
      return "播放窗口内是有视差和透视的 Portal；天空盒不应自动打开"
    case .docked:
      return "天空盒中的 Screen 锚点承载平面视频；没有全景球"
    case .panorama:
      return "黑场中覆盖视野的完整 180°/360° 全景网格；没有播放窗口或小球"
    }
  }

  private func shapeLabel(_ shape: VisionProductShape) -> String {
    switch shape {
    case .flatWindow: "平面 Window"
    case .portalWindow: "Portal Window"
    case .docked: "天空盒 Docking"
    case .panorama: "沉浸全景"
    }
  }

  private func routeLabel(_ route: VisionRegressionRoute) -> String {
    switch route {
    case .appleCompressed: "Apple Compressed"
    case .ffmpegCompressed: "FFmpeg Compressed"
    }
  }

  private func stereoLabel(_ layout: VisionStereoLayout) -> String {
    switch layout {
    case .mono: "Mono"
    case .sideBySide: "左右 3D"
    case .overUnder: "上下 3D"
    }
  }

  private func expect(_ condition: @autoclosure () -> Bool, _ failure: String) throws {
    if !condition() { throw VisionRegressionFailure(message: failure) }
  }

  private func playbackRoute(_ route: VisionRegressionRoute) -> PlaybackRoute {
    switch route {
    case .appleCompressed: .appleCompressed
    case .ffmpegCompressed: .ffmpegCompressed
    }
  }

  private func regressionRoute(_ route: PlaybackRoute) -> VisionRegressionRoute {
    switch route {
    case .appleCompressed: .appleCompressed
    case .ffmpegCompressed: .ffmpegCompressed
    }
  }

  private func loadFixtures() throws -> Fixtures {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let flat = documents.appendingPathComponent("presentation-probe-controls.mp4")
    let panorama = documents.appendingPathComponent("presentation-probe-apmp.mov")
    guard FileManager.default.fileExists(atPath: flat.path) else {
      throw VisionRegressionFailure(message: "fixture.flatMissing")
    }
    guard FileManager.default.fileExists(atPath: panorama.path) else {
      throw VisionRegressionFailure(message: "fixture.panoramaMissing")
    }
    return Fixtures(flat: flat, panorama: panorama)
  }

  private func write(
    runID: String,
    records: [Record],
    validation: VisionRegressionValidation,
    fixtureError: String?
  ) throws {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let output = documents.appendingPathComponent("presentation-probe-\(runID).json")
    let payload: [String: Any] = [
      "runID": runID,
      "completed": validation.completed,
      "passed": validation.passed,
      "expectedCaseCount": VisionRegressionPlan.cases.count,
      "resultCaseCount": records.count,
      "missingCaseIDs": validation.missingCaseIDs,
      "duplicateCaseIDs": validation.duplicateCaseIDs,
      "unexpectedCaseIDs": validation.unexpectedCaseIDs,
      "failedCaseIDs": validation.failedCaseIDs,
      "fixtureError": fixtureError ?? "none",
      "provenance": provenance(),
      "cases": records.map { record in
        [
          "caseID": record.result.caseID,
          "passed": record.result.passed,
          "error": record.result.error ?? "none",
          "evidence": record.evidence,
        ] as [String: Any]
      },
    ]
    let data = try JSONSerialization.data(
      withJSONObject: payload,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: output, options: .atomic)
  }

  private func provenance() -> [String: Any] {
    let environment = ProcessInfo.processInfo.environment
    func value(_ key: String) -> String { environment[key] ?? "unknown" }
    let worktreeDirty: Any
    switch environment["PLAYBACKLAB_PROVENANCE_WORKTREE_DIRTY"] {
    case "true": worktreeDirty = true
    case "false": worktreeDirty = false
    default: worktreeDirty = "unknown"
    }
    return [
      "gitHead": value("PLAYBACKLAB_PROVENANCE_GIT_HEAD"),
      "worktreeDirty": worktreeDirty,
      "worktreeStatusSHA256": value("PLAYBACKLAB_PROVENANCE_WORKTREE_STATUS_SHA256"),
      "worktreeContentSHA256": value("PLAYBACKLAB_PROVENANCE_WORKTREE_CONTENT_SHA256"),
      "xcodeVersion": value("PLAYBACKLAB_PROVENANCE_XCODE_VERSION"),
      "visionOSSDKVersion": value("PLAYBACKLAB_PROVENANCE_VISIONOS_SDK_VERSION"),
      "deviceIdentifier": value("PLAYBACKLAB_PROVENANCE_DEVICE_IDENTIFIER"),
      "deviceOS": ProcessInfo.processInfo.operatingSystemVersionString,
      "flatFixture": "presentation-probe-controls.mp4",
      "flatFixtureSHA256": value("PLAYBACKLAB_PROVENANCE_FLAT_FIXTURE_SHA256"),
      "panoramaFixture": "presentation-probe-apmp.mov",
      "panoramaFixtureSHA256": value("PLAYBACKLAB_PROVENANCE_PANORAMA_FIXTURE_SHA256"),
      "realityAsset": "Immersive_Space.reality",
      "realityAssetSHA256": value("PLAYBACKLAB_PROVENANCE_REALITY_ASSET_SHA256"),
    ]
  }

  private func validateProvenance() throws {
    let environment = ProcessInfo.processInfo.environment
    let requiredKeys = [
      "PLAYBACKLAB_PRESENTATION_PROBE_RUN_ID",
      "PLAYBACKLAB_PROVENANCE_GIT_HEAD",
      "PLAYBACKLAB_PROVENANCE_WORKTREE_DIRTY",
      "PLAYBACKLAB_PROVENANCE_WORKTREE_STATUS_SHA256",
      "PLAYBACKLAB_PROVENANCE_WORKTREE_CONTENT_SHA256",
      "PLAYBACKLAB_PROVENANCE_XCODE_VERSION",
      "PLAYBACKLAB_PROVENANCE_VISIONOS_SDK_VERSION",
      "PLAYBACKLAB_PROVENANCE_DEVICE_IDENTIFIER",
      "PLAYBACKLAB_PROVENANCE_FLAT_FIXTURE_SHA256",
      "PLAYBACKLAB_PROVENANCE_PANORAMA_FIXTURE_SHA256",
      "PLAYBACKLAB_PROVENANCE_REALITY_ASSET_SHA256",
    ]
    let missing = requiredKeys.filter { environment[$0]?.isEmpty != false }
    guard missing.isEmpty else {
      throw VisionRegressionFailure(message: "provenance.missing.\(missing.joined(separator: ","))")
    }
    guard ["true", "false"].contains(environment["PLAYBACKLAB_PROVENANCE_WORKTREE_DIRTY"])
    else {
      throw VisionRegressionFailure(message: "provenance.invalid.worktreeDirty")
    }
  }
}
