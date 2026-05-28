# App Scenes, Windows, Volumes, Immersive Spaces

Use for `XrPlayer/App`, `MainView`, `AppModel`, `DesignPreviewApp`, scene
declarations, window opening, immersive-space opening, default size, launch
behavior, restoration, and placement.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-windowgroup`
  — SwiftUI scene type for windows and value-based scene identity.
- `Apple-UI-Frameworks/swiftui-immersive-spaces.md#documentation-swiftui-immersive-spaces`
  — immersive-space overview, one-space-at-a-time behavior, and mixed/full/
  progressive styles.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-environmentvalues-openimmersivespace`
  — async open action and result handling for immersive spaces.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-environmentvalues-dismissimmersivespace`
  — dismiss action for the currently open immersive space.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-windowstyle-volumetric`
  — volumetric window style for bounded 3D content.

### Open if

- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-uihostingscenedelegate`
  — scene delegate bridge for hosting SwiftUI scenes from UIKit lifecycle code.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-worldscalingbehavior`
  — world-scaling behavior for spatial content.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-scene-defaultsizewidthheightdepthin`
  — default volumetric scene size.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-scene-windowresizability`
  — scene window resizability.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-scene-defaultwindowplacement`
  — default placement for scene windows.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-openwindowaction`
  — programmatic window opening.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-immersionstyle`
  — declared immersion styles.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-immersionstyle-mixed`
  — mixed immersive style.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-immersionstyle-full`
  — full immersive style.
- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-immersionstyle-progressive`
  — progressive immersive style.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Presenting windows and spaces" "visionOS" "WindowGroup" "ImmersiveSpace"`
  for article-level window/space lifecycle guidance.
- Xcode Documentation Search:
  `"Positioning and sizing windows" "visionOS" "defaultWindowPlacement"`
  for article-level placement and size guidance.
- Xcode Documentation Search:
  `"Creating SwiftUI windows in visionOS" "openWindow" "WindowGroup"`
  for current visionOS window creation examples.
- Xcode Documentation Search:
  `"Adopting best practices for scene restoration" "visionOS"`
  for persistent UI and restoration guidance.

### Official web fallback

- WWDC25 290 `Set the scene with SwiftUI in visionOS`

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
