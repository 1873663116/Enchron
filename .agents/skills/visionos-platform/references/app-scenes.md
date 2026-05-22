# App Scenes, Windows, Volumes, Immersive Spaces

Use for `XrPlayer/App`, `MainView`, `AppModel`, `DesignPreviewApp`, scene
declarations, window opening, immersive-space opening, default size, launch
behavior, restoration, and placement.

## Apple Sources

### Open first

- visionOS docs: https://developer.apple.com/documentation/visionos/
- Presenting windows and spaces: https://developer.apple.com/documentation/visionos/presenting-windows-and-spaces
- Positioning and sizing windows: https://developer.apple.com/documentation/visionos/positioning-and-sizing-windows
- Set the scene with SwiftUI in visionOS: https://developer.apple.com/videos/play/wwdc2025/290/
- WindowGroup: https://developer.apple.com/documentation/swiftui/windowgroup
- Immersive spaces: https://developer.apple.com/documentation/swiftui/immersive-spaces

### Open if

- Creating SwiftUI windows in visionOS: https://developer.apple.com/documentation/visionos/creating-a-new-swiftui-window-in-visionos
- Persistent UI and scene restoration: https://developer.apple.com/documentation/visionos/adopting-best-practices-for-scene-restoration
- UIHostingSceneDelegate: https://developer.apple.com/documentation/swiftui/uihostingscenedelegate
- Volumetric window style: https://developer.apple.com/documentation/swiftui/windowstyle/volumetric
- World scaling behavior: https://developer.apple.com/documentation/swiftui/worldscalingbehavior
- Default volumetric size: https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:depth:in:)
- Window resizability: https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
- Default window placement: https://developer.apple.com/documentation/swiftui/scene/defaultwindowplacement(_:)
- OpenWindowAction: https://developer.apple.com/documentation/swiftui/openwindowaction
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
- Do not make absolute claims about volume sizing or placement without checking
  the project deployment target and current SwiftUI scene API. Older guidance
  around fixed volume size may not describe newer visionOS scene capabilities.
- First-window launch and most placement are system-owned. Do not build product
  logic around app-controlled screen coordinates.
- visionOS 26 adds scene lifecycle and persistent UI APIs for launch behavior,
  restoration, locking windows or volumes in physical space, and unique windows.
  Use them only when the target and product behavior justify persistent scenes.
- visionOS 26 volume features include surface snapping and clipping margins.
  Treat snapped-surface details as ARKit or capability-gated data when Apple
  docs require permission or support checks.
- Scene bridging lets UIKit lifecycle apps request SwiftUI windows, volumes, or
  immersive spaces. It is a migration bridge, not a reason to make Enchron
  view-controller-first.
- `openImmersiveSpace` is async and has success/failure/cancel outcomes.
- Only one immersive space can be open at a time.
- `dismissImmersiveSpace` has no id because only one immersive space can exist.
- If an immersive style is not declared, mixed is the default style.
- Scene restoration can reopen meaningful windows; suppress restoration for
  transient windows and restore only user-owned spatial context.
- Use value-based `WindowGroup` and `openWindow(value:)` when a window is keyed
  by user-owned data such as a library item, source, playlist, or preview
  context. Do not centralize that identity in global app state by default.

## iOS/macOS Conflicts

- Do not design a classic iOS/macOS full-screen path for playback. Use larger
  windows, AVKit expanded experiences, volumes, or immersion.
- Do not expect app code to move or resize windows after presentation.
- Do not assume older volume behavior is the full platform contract. Check
  availability before relying on newer locking, snapping, clipping, or
  bridging behavior.
- Do not use macOS screen-coordinate mental models for first launch.
- Do not scatter `openImmersiveSpace` calls across feature views. Keep one
  coordinated lifecycle path so one-space-at-a-time behavior is handled.
- Do not model a volume as "a bigger window" or a 3D-looking card.
- Do not use a volume for dense 2D settings or library navigation unless the
  content itself is spatial.
- Do not use scene bridging as permission to import UIKit lifecycle assumptions
  into product architecture.
- Do not invent manual scene identity/restoration when SwiftUI scene values fit
  the problem.

## Enchron Checkpoints

- `MainView` should remain the canonical place that actually calls
  `openImmersiveSpace` / `dismissImmersiveSpace` unless the architecture is
  deliberately changed.
- Feature views should request immersive state changes through app state or a
  coordinator.
- `DesignPreview` window shells should use real `WindowGroup` scene settings
  for scene-level review, not fake large rounded rectangles inside a Canvas.
- Enchron's main player UI remains a window surface; immersive playback remains
  an `ImmersiveSpace`. Future volumes should be reserved for content with real
  3D or spatial semantics, not dense settings, library lists, or control panels.
