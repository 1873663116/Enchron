# ARKit, Sensors, Privacy, World Understanding

Use for ARKit data access, world/scene/hand tracking, real-world surroundings,
camera access, sensor privacy, and any feature that asks what the user is doing
or where real-world objects are.

## Apple Sources

### Open first

- Privacy and user preferences: https://developer.apple.com/documentation/visionos/adopting-best-practices-for-privacy
- Setting up access to ARKit data: https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data
- ARKit: https://developer.apple.com/documentation/arkit
- ARKit in visionOS: https://developer.apple.com/documentation/arkit/arkit-in-visionos
- Tracking accessories in volumetric windows: https://developer.apple.com/documentation/arkit/tracking-accessories-in-volumetric-windows
- AccessoryTrackingProvider: https://developer.apple.com/documentation/arkit/accessorytrackingprovider

### Open if

- Bringing your ARKit app to visionOS: https://developer.apple.com/documentation/visionos/bringing-your-arkit-app-to-visionos
- Incorporating surroundings: https://developer.apple.com/documentation/visionos/incorporating-real-world-surroundings-in-an-immersive-experience
- Tracking points in world space: https://developer.apple.com/documentation/visionos/tracking-points-in-world-space
- Accessing the main camera: https://developer.apple.com/documentation/visionos/accessing-the-main-camera

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
