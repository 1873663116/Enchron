# App Scenes, Windows, Volumes, Immersive Spaces

Use for `XrPlayer/App`, `MainView`, `AppModel`, `DesignPreviewApp`, scene
declarations, window opening, immersive-space opening, default size, launch
behavior, restoration, and placement.

## Apple Sources

- visionOS docs: https://developer.apple.com/documentation/visionos/
- Presenting windows and spaces: https://developer.apple.com/documentation/visionos/presenting-windows-and-spaces
- Positioning and sizing windows: https://developer.apple.com/documentation/visionos/positioning-and-sizing-windows
- Creating SwiftUI windows in visionOS: https://developer.apple.com/documentation/visionos/creating-a-new-swiftui-window-in-visionos
- Scene restoration: https://developer.apple.com/documentation/visionos/adopting-best-practices-for-scene-restoration
- WindowGroup: https://developer.apple.com/documentation/swiftui/windowgroup
- Volumetric window style: https://developer.apple.com/documentation/swiftui/windowstyle/volumetric
- World scaling behavior: https://developer.apple.com/documentation/swiftui/worldscalingbehavior
- Default volumetric size: https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:depth:in:)
- Window resizability: https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
- Default window placement: https://developer.apple.com/documentation/swiftui/scene/defaultwindowplacement(_:)
- Immersive spaces: https://developer.apple.com/documentation/swiftui/immersive-spaces
- Open immersive space: https://developer.apple.com/documentation/swiftui/environmentvalues/openimmersivespace
- Dismiss immersive space: https://developer.apple.com/documentation/swiftui/environmentvalues/dismissimmersivespace
- Immersion styles: https://developer.apple.com/documentation/swiftui/immersionstyle
- Mixed: https://developer.apple.com/documentation/swiftui/immersionstyle/mixed
- Full: https://developer.apple.com/documentation/swiftui/immersionstyle/full
- Progressive: https://developer.apple.com/documentation/swiftui/immersionstyle/progressive

## Correct Decisions

- A standard window is for bounded 2D app UI.
- A volume is a `WindowGroup` with `.windowStyle(.volumetric)` for bounded 3D
  content people can view from multiple angles.
- An `ImmersiveSpace` is for unbounded spatial content controlled by the app.
- `Window` scenes do not support the volumetric window style.
- A volume's physical size is set at creation and is not changed later by app
  code.
- First-window launch and most placement are system-owned. Do not build product
  logic around app-controlled screen coordinates.
- `openImmersiveSpace` is async and has success/failure/cancel outcomes.
- Only one immersive space can be open at a time.
- `dismissImmersiveSpace` has no id because only one immersive space can exist.
- If an immersive style is not declared, mixed is the default style.
- Scene restoration can reopen meaningful windows; suppress restoration for
  transient windows and restore only user-owned spatial context.

## iOS/macOS Conflicts

- Do not design a classic iOS/macOS full-screen path for playback. Use larger
  windows, AVKit expanded experiences, volumes, or immersion.
- Do not expect app code to move or resize windows after presentation.
- Do not use macOS screen-coordinate mental models for first launch.
- Do not scatter `openImmersiveSpace` calls across feature views. Keep one
  coordinated lifecycle path so one-space-at-a-time behavior is handled.
- Do not model a volume as "a bigger window" or a 3D-looking card.
- Do not use a volume for dense 2D settings or library navigation unless the
  content itself is spatial.

## Enchron Checkpoints

- `MainView` should remain the canonical place that actually calls
  `openImmersiveSpace` / `dismissImmersiveSpace` unless the architecture is
  deliberately changed.
- Feature views should request immersive state changes through app state or a
  coordinator.
- `DesignPreview` window shells should use real `WindowGroup` scene settings
  for scene-level review, not fake large rounded rectangles inside a Canvas.
