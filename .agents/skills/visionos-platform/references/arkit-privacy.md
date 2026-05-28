# ARKit, Sensors, Privacy, World Understanding

Use for ARKit data access, world/scene/hand tracking, real-world surroundings,
camera access, sensor privacy, and any feature that asks what the user is doing
or where real-world objects are.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Media-Device/arkit.md#documentation-arkit`
  — ARKit framework root.
- `Apple-Media-Device/arkit.md#documentation-arkit-arkit-in-visionos`
  — ARKit in visionOS overview.
- `Apple-Media-Device/realitykit.md#documentation-realitykit-spatialtrackingsession`
  — RealityKit `SpatialTrackingSession` high-level tracking path.
- `Apple-Media-Device/arkit-tracking-accessories-in-volumetric-windows.md#documentation-arkit-tracking-accessories-in-volumetric-windows`
  — accessory tracking in volumetric windows.
- `Apple-Media-Device/arkit-accessorytrackingprovider.md#documentation-arkit-accessorytrackingprovider`
  — ARKit `AccessoryTrackingProvider`.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Adopting best practices for privacy" "visionOS" "ARKit"`
  for platform privacy and user-preference guidance.
- Xcode Documentation Search:
  `"Setting up access to ARKit data" "requiredAuthorizations"`
  for provider authorization setup.
- Xcode Documentation Search:
  `"Bringing your ARKit app to visionOS" "Full Space"`
  for migration guidance.
- Xcode Documentation Search:
  `"Incorporating real-world surroundings in an immersive experience" "visionOS"`
  for surroundings and scene-sensing guidance.
- Xcode Documentation Search:
  `"Tracking points in world space" "visionOS"`
  for world-space tracking guidance.
- Xcode Documentation Search:
  `"Accessing the main camera" "visionOS" "enterprise"`
  for camera entitlement constraints.

### Official web fallback

- WWDC25 287 `What is new in RealityKit`

## Correct Decisions

- Standard gaze and hand input do not expose raw gaze/hand position to the app.
  The system handles private sensor data for ordinary input.
- Use standard SwiftUI/UIKit event handling for ordinary interaction.
- Request ARKit data only when the system interaction model cannot express the
  feature.
- Most world, hand, and scene-sensing ARKit providers require Full Space
  presentation, but the rule is provider-specific. Verify each provider's
  presentation context, support checks, and authorization requirements in
  current Apple docs.
- Use "Full Space", "presentation context", and exact provider names when
  describing availability. Do not use "immersive space" as a loose synonym for
  every sensing requirement.
- RealityKit `SpatialTrackingSession` and high-level anchoring APIs can provide
  a RealityKit-shaped path to ARKit data. They still require capability checks,
  authorization handling, and a fallback story when sensitive data is involved.
- Add provider-specific usage descriptions before requesting sensitive data.
- Check provider-specific `requiredAuthorizations`; do not guess.
- Handle denied and later-revoked authorization with a usable fallback.
- Main camera access is an enterprise entitlement path, not a general app
  capability.

## iOS/macOS Conflicts

- Do not assume an app can read what the user is looking at.
- Do not use hand tracking to implement ordinary button presses, sliders, or
  selection.
- Do not treat iOS ARKit as the display stack. visionOS ARKit is mainly for
  sensing/world data; presentation is SwiftUI, RealityKit, or Compositor
  Services.
- Do not treat a RealityKit access path as a privacy downgrade or a permission
  bypass.
- Do not ship a core UI feature that has no fallback when ARKit authorization is
  denied.
- Do not infer permission requirements from similar provider names. Verify the
  current Apple docs for the exact provider.
- Do not assume every ARKit provider is Full Space only. Accessory tracking and
  future provider-specific APIs can have different presentation constraints.

## Enchron Checkpoints

- Enchron playback controls should work through standard input first.
- Scene positioning and screen placement can use spatial state, but privacy
  boundaries must be explicit before adding ARKit providers.
- Any future world-aware scene feature needs a permission/fallback story before
  implementation.
- Provider adoption should name the exact provider, `isSupported` behavior,
  authorization type, presentation surface, and Simulator/device support.
- RealityKit `SpatialTrackingSession` adoption should name the tracked anchors
  or scene-understanding capabilities, unavailable-capability behavior,
  authorization behavior, and whether manual `ARKitSession` access is required.
