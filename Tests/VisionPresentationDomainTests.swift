import Foundation

@main
struct VisionPresentationDomainTests {
  static func main() async {
    expect(
      VisionPresentationFacts(
        projection: .flat,
        placement: .window,
        sceneLifecycle: .closed,
        sceneContent: nil,
        stereoLayout: .mono
      ).productShape == .flatWindow,
      "flat window shape"
    )
    expect(
      VisionPresentationFacts(
        projection: .sourcePanoramic,
        placement: .window,
        sceneLifecycle: .open,
        sceneContent: .customScene,
        stereoLayout: .sideBySide
      ).productShape == .portalWindow,
      "portal uses the playback window"
    )
    expect(
      VisionPresentationFacts(
        projection: .flat,
        placement: .docked,
        sceneLifecycle: .open,
        sceneContent: .customScene,
        stereoLayout: .overUnder
      ).productShape == .docked,
      "docked is flat content in the custom scene"
    )
    expect(
      VisionPresentationFacts(
        projection: .sourcePanoramic,
        placement: .panorama,
        sceneLifecycle: .open,
        sceneContent: .blackPanorama,
        stereoLayout: .mono
      ).productShape == .panorama,
      "panorama uses the black immersive content"
    )

    let dockable = VisionPresentationFacts(
      projection: .flat,
      placement: .window,
      sceneLifecycle: .open,
      sceneContent: .customScene,
      stereoLayout: .mono
    )
    expect(dockable.canDock, "flat window can dock only while the custom scene is open")
    expect(
      dockable.sceneLifecycleCommand == .closeScene,
      "an open custom scene exposes Close Scene in a window shape"
    )
    expect(
      dockable.primaryPresentationCommands == [.dock],
      "flat window exposes Dock only when the custom scene is ready"
    )

    let portal = VisionPresentationFacts(
      projection: .sourcePanoramic,
      placement: .window,
      sceneLifecycle: .open,
      sceneContent: .customScene,
      stereoLayout: .mono
    )
    expect(!portal.canDock, "portal does not expose docking")
    expect(
      portal.primaryPresentationCommands == [.showPanorama],
      "portal exposes Panorama and never Dock"
    )

    let panorama = VisionPresentationFacts(
      projection: .sourcePanoramic,
      placement: .panorama,
      sceneLifecycle: .open,
      sceneContent: .blackPanorama,
      stereoLayout: .mono,
      customSceneRequestedOpen: false
    )
    expect(!panorama.canDock, "panorama does not expose docking")
    expect(
      panorama.sceneLifecycleCommand == nil
        && panorama.primaryPresentationCommands == [.showWindow],
      "panorama exposes Portal return without a Scene toggle"
    )
    expect(
      !panorama.shouldRestoreCustomSceneAfterPanorama,
      "panorama entered from a closed scene returns to a closed scene"
    )

    let panoramaFromScene = VisionPresentationFacts(
      projection: .sourcePanoramic,
      placement: .panorama,
      sceneLifecycle: .open,
      sceneContent: .blackPanorama,
      stereoLayout: .mono,
      customSceneRequestedOpen: true
    )
    expect(
      panoramaFromScene.shouldRestoreCustomSceneAfterPanorama,
      "panorama entered from an open scene restores the custom scene"
    )

    let docked = VisionPresentationFacts(
      projection: .flat,
      placement: .docked,
      sceneLifecycle: .open,
      sceneContent: .customScene,
      stereoLayout: .mono,
      customSceneRequestedOpen: true
    )
    expect(
      docked.sceneLifecycleCommand == nil
        && docked.primaryPresentationCommands == [.showWindow],
      "docked exposes Window return without Portal or Scene controls"
    )

    expect(
      Set(VisionStereoLayout.allCases) == Set([.mono, .sideBySide, .overUnder]),
      "stereo remains an independent three-value dimension"
    )

    let commands: [PresentationCommand] = [
      .openPlaybackWindow,
      .closePlaybackWindow,
      .openScene,
      .closeScene,
      .showWindow,
      .dock,
      .showPanorama,
      .setProjection(.sourcePanoramic),
      .setStereo(.sideBySide),
    ]
    expect(commands.count == 9, "the public command seam exposes product intents")
    VisionRegressionPlanTests.run()
    VisionRegressionEvidenceTests.run()
    await VisionPresentationCoordinatorTests.run()
    print("GREEN vision presentation domain")
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
