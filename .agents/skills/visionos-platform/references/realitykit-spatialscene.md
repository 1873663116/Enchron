# RealityKit, SpatialScene, Volumes, Virtual Screens

Use for `SpatialScene`, `RealityView`, RealityKit entities, attachments,
panoramas, virtual screens, environment domes, volumes, and immersive scene
presentation.

## Apple Sources

### Open first

- Adding 3D content to your app: https://developer.apple.com/documentation/visionos/adding-3d-content-to-your-app
- RealityKit: https://developer.apple.com/documentation/realitykit
- RealityView: https://developer.apple.com/documentation/realitykit/realityview
- VideoPlayerComponent: https://developer.apple.com/documentation/realitykit/videoplayercomponent
- ViewAttachmentComponent: https://developer.apple.com/documentation/realitykit/viewattachmentcomponent

### Open if

- RealityViewContent: https://developer.apple.com/documentation/realitykit/realityviewcontent
- Views and attachments: https://developer.apple.com/documentation/realitykit/presentation-views-and-attachments
- Attachment: https://developer.apple.com/documentation/realitykit/attachment
- RealityKit videos: https://developer.apple.com/documentation/realitykit/scene-content-videos
- VideoMaterial: https://developer.apple.com/documentation/realitykit/videomaterial
- Playing immersive media with RealityKit: https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit
- Rendering stereoscopic video with RealityKit: https://developer.apple.com/documentation/visionos/rendering-stereoscopic-video-with-realitykit
- What is new in RealityKit: https://developer.apple.com/videos/play/wwdc2025/287/
- Spatial layout HIG: https://developer.apple.com/design/human-interface-guidelines/spatial-layout/
- Immersive experiences HIG: https://developer.apple.com/design/human-interface-guidelines/immersive-experiences
- Immersive spaces: https://developer.apple.com/documentation/swiftui/immersive-spaces
- GeometryReader3D: https://developer.apple.com/documentation/swiftui/geometryreader3d
- CoordinateSpace3D: https://developer.apple.com/documentation/spatial/coordinatespace3d

## Correct Decisions

- Use windows for UI-centric 2D work.
- Use volumes for bounded 3D objects that should be inspected from multiple
  angles.
- Use immersive spaces for unbounded spatial experiences.
- 3D content inside a 2D window can be clipped; if the content is primarily 3D,
  consider a volume.
- `RealityView` creation work runs once. Update existing entities/components in
  update paths instead of recreating expensive RealityKit state from SwiftUI
  body churn.
- RealityKit interaction needs the proper pieces: targeted SwiftUI gesture,
  `InputTargetComponent`, and collision shapes.
- Use attachments for SwiftUI controls that belong with RealityKit content.
- For current video work, consider `VideoPlayerComponent` as well as
  `VideoMaterial`. `VideoPlayerComponent` is the RealityKit path for immersive
  media controls, viewing modes, captions/subtitles, passthrough tinting, and
  transition events.
- For APMP, Apple Immersive Video, and Spatial Video in RealityKit, read
  `immersive-media-profiles.md`. `VideoPlayerComponent` is the core RealityKit
  route for system-understood immersive media profiles, not a small replacement
  trick for `VideoMaterial`.
- `desiredImmersiveViewingMode` and SwiftUI `ImmersionStyle` must match for
  progressive or full immersive playback. Treat portal, progressive, and full
  as behavior and comfort choices, not just visual styles.
- Attachments can be created through the `RealityView` attachments closure or
  component-based APIs such as `ViewAttachmentComponent`; choose the current API
  that matches the local code and OS target.
- Explicitly set transforms and positions in immersive spaces. Do not rely on
  an unexamined origin.

## iOS/macOS Conflicts

- Do not bring `ARView` / `ARSCNView` display habits from iOS as the default.
  In visionOS, SwiftUI and RealityKit are the presentation model; ARKit supplies
  sensing data when needed.
- Do not make every spatial feature an immersive space.
- Do not make dense 2D controls into a volume because it seems more spatial.
- Do not anchor large UI to the user's head; Apple warns that head-anchored
  content can feel confining.
- Do not fill peripheral vision with bright motion or high-contrast animation.
- Do not put RealityKit setup in SwiftUI body-driven code paths.
- Do not assume "RealityKit video" means only `VideoMaterial`.
- Do not render APMP, Apple Immersive Video, or Spatial Video as generic
  textures unless the plan explains why `VideoPlayerComponent`, AVKit, and
  Quick Look are insufficient.
- Do not combine progressive RealityKit video with a non-progressive
  `ImmersionStyle`.

## Enchron Checkpoints

- `SpatialScene` owns spatial presentation, not non-spatial playback control.
- Virtual-screen geometry and saved positions should be physically meaningful,
  not arbitrary 2D layout constants.
- Panorama and virtual-screen paths should explicitly state their surface:
  RealityKit material/texture, volume, immersive space, or future compositor.
- Immersive media work should state whether it uses AVKit, RealityKit
  `VideoPlayerComponent`, `VideoMaterial`, MPV texture bridging, or future
  Compositor Services.
- If a task touches APMP, Apple Immersive Video, Spatial Video, or 3D media
  playback, answer the media profile question before selecting RealityKit
  APIs or reusing the existing panorama sphere path.
