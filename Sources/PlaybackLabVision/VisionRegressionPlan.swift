import Foundation

enum VisionRegressionRoute: String, CaseIterable, Sendable {
  case appleCompressed
  case ffmpegCompressed
}

enum VisionRegressionControl: String, CaseIterable, Sendable {
  case pause
  case play
  case rate
  case seek
  case audioTrack
  case volume
  case muteToggle
  case reopen
  case close
}

enum VisionRegressionSceneBaseline: String, Equatable, Sendable {
  case closed
  case customSceneOpen
}

enum VisionRegressionLifecycle: String, Equatable, Sendable {
  case playbackWindowOpenWithoutMedia
  case playbackWindowCloseWithoutMedia
  case customSceneOpenWithoutMedia
  case customSceneCloseWithoutMedia
}

enum VisionRegressionPlaybackSceneLifecycle: String, Equatable, Sendable {
  case openDoesNotMigrate
  case closeDoesNotMigrate
}

enum VisionRegressionSceneExit: String, Equatable, Sendable {
  case showWindow
  case closeMedia
}

enum VisionRegressionEdge: String, Equatable, Sendable {
  case dockedToFlatWindow
  case dockedToPanorama
  case panoramaToFlatWindow
}

enum VisionRegressionCaseKind: Equatable, Sendable {
  case lifecycle(VisionRegressionLifecycle)
  case sceneLifecycleWithPlayback(VisionRegressionPlaybackSceneLifecycle)
  case productShape(route: VisionRegressionRoute, shape: VisionProductShape)
  case stereoRoundTrip(shape: VisionProductShape, layout: VisionStereoLayout)
  case sceneRestoration(
    baseline: VisionRegressionSceneBaseline,
    exit: VisionRegressionSceneExit
  )
  case presentationEdge(VisionRegressionEdge)
  case control(route: VisionRegressionRoute, control: VisionRegressionControl)
  case coldRouteSwitch
  case cleanup
}

struct VisionRegressionCase: Identifiable, Equatable, Sendable {
  let id: String
  let kind: VisionRegressionCaseKind
}

struct VisionRegressionCaseResult: Equatable, Sendable {
  let caseID: String
  let passed: Bool
  let error: String?

  init(caseID: String, passed: Bool, error: String? = nil) {
    self.caseID = caseID
    self.passed = passed
    self.error = error
  }
}

struct VisionRegressionValidation: Equatable, Sendable {
  let missingCaseIDs: [String]
  let duplicateCaseIDs: [String]
  let unexpectedCaseIDs: [String]
  let failedCaseIDs: [String]

  var completed: Bool {
    missingCaseIDs.isEmpty
      && duplicateCaseIDs.isEmpty
      && unexpectedCaseIDs.isEmpty
  }

  var passed: Bool {
    completed && failedCaseIDs.isEmpty
  }
}

enum VisionRegressionPlan {
  static let cases: [VisionRegressionCase] = {
    let routes = VisionRegressionRoute.allCases
    let shapes: [VisionProductShape] = [
      .flatWindow,
      .portalWindow,
      .docked,
      .panorama,
    ]
    let stereoLayouts: [VisionStereoLayout] = [.sideBySide, .overUnder]

    var cases: [VisionRegressionCase] = []

    for lifecycle in [
      VisionRegressionLifecycle.playbackWindowOpenWithoutMedia,
      .playbackWindowCloseWithoutMedia,
      .customSceneOpenWithoutMedia,
      .customSceneCloseWithoutMedia,
    ] {
      cases.append(
        VisionRegressionCase(
          id: "lifecycle.\(lifecycle.rawValue)",
          kind: .lifecycle(lifecycle)
        )
      )
    }

    for route in routes {
      for shape in shapes {
        cases.append(
          VisionRegressionCase(
            id: "shape.\(route.rawValue).\(shape.rawValue)",
            kind: .productShape(route: route, shape: shape)
          )
        )
      }
    }

    for lifecycle in [
      VisionRegressionPlaybackSceneLifecycle.openDoesNotMigrate,
      .closeDoesNotMigrate,
    ] {
      cases.append(
        VisionRegressionCase(
          id: "scene.windowPlayback.\(lifecycle.rawValue)",
          kind: .sceneLifecycleWithPlayback(lifecycle)
        )
      )
    }

    for shape in shapes {
      for layout in stereoLayouts {
        cases.append(
          VisionRegressionCase(
            id: "stereo.\(shape.rawValue).mono-\(layout.rawValue)-roundTrip",
            kind: .stereoRoundTrip(shape: shape, layout: layout)
          )
        )
      }
    }

    cases.append(
      VisionRegressionCase(
        id: "scene.panoramaFromClosed.restoresClosed",
        kind: .sceneRestoration(baseline: .closed, exit: .showWindow)
      )
    )
    cases.append(
      VisionRegressionCase(
        id: "scene.panoramaFromOpen.restoresCustomScene",
        kind: .sceneRestoration(baseline: .customSceneOpen, exit: .showWindow)
      )
    )
    cases.append(
      VisionRegressionCase(
        id: "scene.closeMediaFromPanorama.restoresClosed",
        kind: .sceneRestoration(baseline: .closed, exit: .closeMedia)
      )
    )
    cases.append(
      VisionRegressionCase(
        id: "scene.closeMediaFromPanorama.restoresCustomScene",
        kind: .sceneRestoration(baseline: .customSceneOpen, exit: .closeMedia)
      )
    )

    for edge in [
      VisionRegressionEdge.dockedToFlatWindow,
      .dockedToPanorama,
      .panoramaToFlatWindow,
    ] {
      cases.append(
        VisionRegressionCase(
          id: "edge.\(edge.rawValue)",
          kind: .presentationEdge(edge)
        )
      )
    }

    for route in routes {
      for control in VisionRegressionControl.allCases {
        cases.append(
          VisionRegressionCase(
            id: "control.\(route.rawValue).\(control.rawValue)",
            kind: .control(route: route, control: control)
          )
        )
      }
    }

    cases.append(
      VisionRegressionCase(
        id: "route.appleCompressed-to-ffmpegCompressed.coldSwitch",
        kind: .coldRouteSwitch
      )
    )
    cases.append(
      VisionRegressionCase(
        id: "cleanup.final",
        kind: .cleanup
      )
    )

    return cases
  }()

  static let expectedCaseIDs = Set(cases.map(\.id))

  static func validate(results: [VisionRegressionCaseResult]) -> VisionRegressionValidation {
    let resultIDs = results.map(\.caseID)
    let resultIDSet = Set(resultIDs)
    let counts = Dictionary(grouping: resultIDs, by: { $0 }).mapValues(\.count)

    return VisionRegressionValidation(
      missingCaseIDs: expectedCaseIDs.subtracting(resultIDSet).sorted(),
      duplicateCaseIDs: counts.compactMap { $0.value > 1 ? $0.key : nil }.sorted(),
      unexpectedCaseIDs: resultIDSet.subtracting(expectedCaseIDs).sorted(),
      failedCaseIDs: Set(results.lazy.filter { !$0.passed }.map(\.caseID)).sorted()
    )
  }
}
