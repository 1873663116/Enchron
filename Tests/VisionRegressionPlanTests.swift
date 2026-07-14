import Foundation

enum VisionRegressionPlanTests {
  static func run() {
    expect(
      VisionRegressionPlan.cases.count == 49,
      "the regression manifest contains exactly 49 independent cases"
    )

    let expectedIDs: Set<String> = [
      "lifecycle.playbackWindowOpenWithoutMedia",
      "lifecycle.playbackWindowCloseWithoutMedia",
      "lifecycle.customSceneOpenWithoutMedia",
      "lifecycle.customSceneCloseWithoutMedia",
      "shape.appleCompressed.flatWindow",
      "shape.appleCompressed.portalWindow",
      "shape.appleCompressed.docked",
      "shape.appleCompressed.panorama",
      "shape.ffmpegCompressed.flatWindow",
      "shape.ffmpegCompressed.portalWindow",
      "shape.ffmpegCompressed.docked",
      "shape.ffmpegCompressed.panorama",
      "scene.windowPlayback.openDoesNotMigrate",
      "scene.windowPlayback.closeDoesNotMigrate",
      "stereo.flatWindow.mono-sideBySide-roundTrip",
      "stereo.flatWindow.mono-overUnder-roundTrip",
      "stereo.portalWindow.mono-sideBySide-roundTrip",
      "stereo.portalWindow.mono-overUnder-roundTrip",
      "stereo.docked.mono-sideBySide-roundTrip",
      "stereo.docked.mono-overUnder-roundTrip",
      "stereo.panorama.mono-sideBySide-roundTrip",
      "stereo.panorama.mono-overUnder-roundTrip",
      "scene.panoramaFromClosed.restoresClosed",
      "scene.panoramaFromOpen.restoresCustomScene",
      "scene.closeMediaFromPanorama.restoresClosed",
      "scene.closeMediaFromPanorama.restoresCustomScene",
      "edge.dockedToFlatWindow",
      "edge.dockedToPanorama",
      "edge.panoramaToFlatWindow",
      "control.appleCompressed.pause",
      "control.appleCompressed.play",
      "control.appleCompressed.rate",
      "control.appleCompressed.seek",
      "control.appleCompressed.audioTrack",
      "control.appleCompressed.volume",
      "control.appleCompressed.muteToggle",
      "control.appleCompressed.reopen",
      "control.appleCompressed.close",
      "control.ffmpegCompressed.pause",
      "control.ffmpegCompressed.play",
      "control.ffmpegCompressed.rate",
      "control.ffmpegCompressed.seek",
      "control.ffmpegCompressed.audioTrack",
      "control.ffmpegCompressed.volume",
      "control.ffmpegCompressed.muteToggle",
      "control.ffmpegCompressed.reopen",
      "control.ffmpegCompressed.close",
      "route.appleCompressed-to-ffmpegCompressed.coldSwitch",
      "cleanup.final",
    ]
    expect(
      VisionRegressionPlan.expectedCaseIDs == expectedIDs,
      "the manifest IDs match the accepted regression contract exactly"
    )
    let stereoIndices = VisionRegressionPlan.cases.indices.filter {
      if case .stereoRoundTrip = VisionRegressionPlan.cases[$0].kind { return true }
      return false
    }
    expect(
      stereoIndices == Array(14..<22),
      "the eight fixed-session Stereo cases remain one contiguous suite"
    )

    let passingResults = expectedIDs.map {
      VisionRegressionCaseResult(caseID: $0, passed: true)
    }
    let passingValidation = VisionRegressionPlan.validate(results: passingResults)
    expect(passingValidation.completed, "an exact passing result set completes")
    expect(passingValidation.passed, "an exact passing result set passes")

    let missingID = "shape.appleCompressed.portalWindow"
    let duplicateID = "control.appleCompressed.pause"
    let failingID = "stereo.panorama.mono-overUnder-roundTrip"
    let unexpectedID = "shape.appleCompressed.full"
    var invalidResults = passingResults.filter { $0.caseID != missingID }
    invalidResults.append(VisionRegressionCaseResult(caseID: duplicateID, passed: true))
    invalidResults.append(VisionRegressionCaseResult(caseID: failingID, passed: false))
    invalidResults.append(VisionRegressionCaseResult(caseID: unexpectedID, passed: true))

    let invalidValidation = VisionRegressionPlan.validate(results: invalidResults)
    expect(!invalidValidation.completed, "an invalid result set cannot complete")
    expect(!invalidValidation.passed, "an invalid result set cannot pass")
    expect(invalidValidation.missingCaseIDs == [missingID], "missing IDs are explicit")
    expect(invalidValidation.duplicateCaseIDs == [duplicateID, failingID], "duplicate IDs are explicit")
    expect(invalidValidation.unexpectedCaseIDs == [unexpectedID], "unexpected IDs are explicit")
    expect(invalidValidation.failedCaseIDs == [failingID], "failed IDs are explicit")

    let completedWithFailure = VisionRegressionPlan.validate(
      results: passingResults.map {
        $0.caseID == failingID
          ? VisionRegressionCaseResult(caseID: $0.caseID, passed: false)
          : $0
      }
    )
    expect(completedWithFailure.completed, "a full terminal result set is completed")
    expect(!completedWithFailure.passed, "a completed result set with a failure does not pass")
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
