import RealityKit
import SwiftUI

struct VisionPlaybackSurfaceView: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @Bindable var model: VisionPlaybackModel
  let request: VisionSurfaceRequest?
  @State private var surfaceInstanceID = UUID()

  var body: some View {
    let entityGeneration = model.videoEntityGeneration
    let attachment = request.map {
      VisionSurfaceAttachment(request: $0, instanceID: surfaceInstanceID)
    }
    RealityView { content in
      guard let attachment,
        model.presentationSurfaceDidAttach(.playbackWindow, attachment: attachment)
      else {
        if let request {
          dismissWindow(id: VisionSceneID.playbackWindow, value: request)
        } else {
          dismissWindow(id: VisionSceneID.playbackWindow)
        }
        return
      }
      content.add(model.windowPresentationRoot)
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .playbackWindow,
        attachment: attachment,
        root: model.windowPresentationRoot
      )
      model.subscribeToSurfaceUpdates(
        in: content,
        surface: .playbackWindow,
        attachment: attachment
      )
    } update: { content in
      _ = entityGeneration
      guard let attachment,
        model.presentationSurfaceIsActive(.playbackWindow, attachment: attachment)
      else { return }
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .playbackWindow,
        attachment: attachment,
        root: model.windowPresentationRoot
      )
      model.subscribeToSurfaceUpdates(
        in: content,
        surface: .playbackWindow,
        attachment: attachment
      )
    }
    .frame(width: 1280, height: 720)
    .onDisappear {
      guard let attachment else { return }
      model.presentationSurfaceDidDetach(.playbackWindow, attachment: attachment)
    }
  }
}

struct VisionImmersiveView: View {
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
  @Bindable var model: VisionPlaybackModel
  let request: VisionSurfaceRequest?
  @State private var surfaceInstanceID = UUID()

  var body: some View {
    let entityGeneration = model.videoEntityGeneration
    let sceneContent = model.presentation.facts.sceneContent
    let attachment = request.map {
      VisionSurfaceAttachment(request: $0, instanceID: surfaceInstanceID)
    }
    RealityView { content in
      guard let attachment,
        model.presentationSurfaceDidAttach(.scene, attachment: attachment)
      else {
        await dismissImmersiveSpace()
        return
      }
      if sceneContent == .customScene,
        let scene = await model.immersiveSceneEntity()
      {
        content.add(scene)
      }
      content.add(model.panoramaPresentationRoot)
      model.updateImmersiveSceneVisibility()
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .scene,
        attachment: attachment,
        root: model.dockedPresentationRoot
      )
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .scene,
        attachment: attachment,
        root: model.panoramaPresentationRoot
      )
      model.subscribeToSurfaceUpdates(
        in: content,
        surface: .scene,
        attachment: attachment
      )
    } update: { content in
      _ = entityGeneration
      _ = sceneContent
      guard let attachment,
        model.presentationSurfaceIsActive(.scene, attachment: attachment)
      else { return }
      model.updateImmersiveSceneVisibility()
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .scene,
        attachment: attachment,
        root: model.dockedPresentationRoot
      )
      model.subscribeToVideoPlayerEvents(
        in: content,
        surface: .scene,
        attachment: attachment,
        root: model.panoramaPresentationRoot
      )
      model.subscribeToSurfaceUpdates(
        in: content,
        surface: .scene,
        attachment: attachment
      )
    }
    .onDisappear {
      guard let attachment else { return }
      model.presentationSurfaceDidDetach(.scene, attachment: attachment)
    }
  }
}
