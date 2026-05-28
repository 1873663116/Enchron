# RealityKit, SpatialScene, Volumes, Virtual Screens

Use for `SpatialScene`, `RealityView`, RealityKit entities, attachments,
panoramas, virtual screens, environment domes, volumes, and immersive scene
presentation.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Media-Device/realitykit-realityview.md#documentation-realitykit-realityview`
  — `RealityView` as the SwiftUI entry point for rich 3D RealityKit content.
- `Apple-Media-Device/realitykit-realityviewcontent.md#documentation-realitykit-realityviewcontent`
  — content value used to add and remove RealityKit entities.
- `Apple-Media-Device/realitykit-presentation-views-and-attachments.md#documentation-realitykit-presentation-views-and-attachments`
  — RealityKit views, attachments, environment, rendering effects, and related
  presentation APIs.
- `Apple-Media-Device/realitykit-viewattachmentcomponent.md#documentation-realitykit-viewattachmentcomponent`
  — component-based SwiftUI attachment API for RealityKit entities.
- `Apple-UI-Frameworks/swiftui-immersive-spaces.md#documentation-swiftui-immersive-spaces`
  — mixed, full, and progressive immersive-space behavior.

### Open if

- `Apple-Media-Device/realitykit-attachment.md#documentation-realitykit-attachment`
  — `Attachment<Content>` for SwiftUI views that are presented with
  RealityKit content.
- `Apple-Media-Device/realitykit-scene-content-videos.md#documentation-realitykit-scene-content-videos`
  — RealityKit video overview, `VideoPlayerComponent`, immersive viewing mode,
  and `VideoMaterial`.
- `Apple-Media-Device/realitykit-videoplayercomponent.md#documentation-realitykit-videoplayercomponent`
  — immersive media playback in RealityKit, captions/subtitles, passthrough
  tinting, viewing modes, and transition events.
- `Apple-Media-Device/realitykit-videomaterial.md#documentation-realitykit-videomaterial`
  — material-based video on 3D surfaces.
- `Apple-Media-Device/realitykit-rendering-stereoscopic-video-with-realitykit.md#documentation-realitykit-rendering-stereoscopic-video-with-realitykit`
  — sample code for side-by-side stereoscopic video rendering with
  RealityKit, `VideoPlayerComponent`, and `AVSampleBufferVideoRenderer`.
- `Apple-UI-Frameworks/swiftui-geometryreader3d.md#documentation-swiftui-geometryreader3d`
  — container view that reads available 3D size and coordinate space.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-geometryproxy3d`
  — proxy for access to a container view's 3D size and coordinate space.
- `Apple-Media-Device/spatial-coordinatespace3d.md#documentation-spatial-coordinatespace3d`
  — Spatial framework 3D coordinate-space conversion.
- `Apple-Media-Device/realitykit.md#documentation-realitykit-inputtargetcomponent`
  — `InputTargetComponent` for targeted entity interaction.
- `Apple-Media-Device/realitykit.md#documentation-realitykit-collisioncomponent`
  — collision shape/component evidence for RealityKit interactions.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Adding 3D content to your app" "visionOS" "RealityView"`
  for the article-level scene setup path.
- Xcode Documentation Search:
  `"Playing immersive media with RealityKit" "desiredImmersiveViewingMode"`
  for the immersive-media walkthrough.

### Official web fallback

- WWDC25 287 `What is new in RealityKit`
- `https://developer.apple.com/design/human-interface-guidelines/spatial-layout/`
- `https://developer.apple.com/design/human-interface-guidelines/immersive-experiences`

## Correct Decisions

- Use windows for UI-centric 2D work.
- Use volumes for bounded 3D objects that should be inspected from multiple
  angles.
- Use immersive spaces for unbounded spatial experiences.
- 3D content inside a 2D window can be clipped; if the content is primarily 3D,
  consider a volume.
- Put initial RealityKit content creation in the `RealityView` make closure.
  Use the optional update closure, RealityKit systems, or scene update events
  for state-driven and per-frame changes instead of recreating expensive
  RealityKit state from SwiftUI body churn.
- RealityKit interaction needs the proper pieces: targeted SwiftUI gesture,
  `InputTargetComponent`, and collision shapes.
- Use attachments for SwiftUI controls that belong with RealityKit content.
- For future Apple-native immersive media research, consider
  `VideoPlayerComponent` as well as `VideoMaterial`. `VideoPlayerComponent` is
  the RealityKit path for immersive media controls, viewing modes,
  captions/subtitles, passthrough tinting, and transition events.
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
- Do not claim APMP, Apple Immersive Video, or Spatial Video production support
  from generic textures alone. Name whether the work is current mpv-first
  rendering, diagnostics, or future Apple-native research.
- Do not combine progressive RealityKit video with a non-progressive
  `ImmersionStyle`.

## Enchron Checkpoints

- `SpatialScene` owns spatial presentation, not non-spatial playback control.
- Virtual-screen geometry and saved positions should be physically meaningful,
  not arbitrary 2D layout constants.
- Panorama and virtual-screen paths should explicitly state their surface:
  RealityKit material/texture, volume, immersive space, or future compositor.
- Immersive media work should state whether it uses current mpv-first texture
  bridging, diagnostics, future AVKit / RealityKit `VideoPlayerComponent`
  research, `VideoMaterial`, or future Compositor Services.
- If a task touches APMP, Apple Immersive Video, Spatial Video, or 3D media
  playback, answer the media profile question before selecting RealityKit
  APIs or reusing the existing panorama sphere path.
