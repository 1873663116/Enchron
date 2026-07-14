import SwiftUI

@main
struct PlaybackLabVisionApp: App {
  @State private var model = VisionPlaybackModel()

  var body: some Scene {
    WindowGroup("Playback Controls", id: VisionSceneID.controlWindow) {
      VisionContentView(model: model)
    }
    .windowResizability(.contentSize)

    WindowGroup(
      "Playback",
      id: VisionSceneID.playbackWindow,
      for: VisionSurfaceRequest.self
    ) { request in
      VisionPlaybackSurfaceView(model: model, request: request.wrappedValue)
    }
    .windowResizability(.contentSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    ImmersiveSpace(
      id: VisionSceneID.playbackSpace,
      for: VisionSurfaceRequest.self
    ) { request in
      VisionImmersiveView(model: model, request: request.wrappedValue)
    }
    .immersionStyle(
      selection: .constant(.progressive(0...1, initialAmount: 1)),
      in: .progressive
    )
  }
}
