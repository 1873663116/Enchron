# visionOS Misconception Checklist

Pause and consult the relevant reference if any of these assumptions appear in
code, comments, plans, or proposed fixes.

## Platform And Scene Model

- "visionOS SwiftUI is basically iPadOS SwiftUI."
- "Use macOS window-management patterns for placement."
- "Use full screen for video."
- "The app can move or resize windows whenever it wants."
- "Multiple immersive spaces can be open if they have different ids."
- "If `openImmersiveSpace` is called, it definitely opened."
- "A volume is just a bigger window."
- "A 3D-looking card is a volume."
- "A `WindowGroup` can only open generic windows, so video/library windows need
  global app state instead of value-based scene routing."
- "Older fixed-volume guidance is the whole current platform contract."
- "UIKit scene bridging means UIKit lifecycle should drive Enchron architecture."

Read: `app-scenes.md`, then Apple docs for windows/spaces.

## UI And Input

- "Hover is pointer hover."
- "`onHover` is enough for gaze."
- "44 pt targets are fine."
- "A `TapGesture` is equivalent to a `Button`."
- "Dense desktop sidebars are fine because this is a productivity app."
- "Custom glass/material always looks more native."
- "Explicit accessibility labels are always better than correct semantic labels."
- "RealityKit `ManipulationComponent` is the right path for normal playback
  buttons."
- "Apple Pencil or spatial accessory support can be accepted or rejected without
  checking current availability and device support."

Read: `spatial-ui.md`, then HIG Eyes/Gestures/Buttons/Spatial Layout.

## Playback And Media

- "AVKit docs are irrelevant because Enchron uses MPV."
- "AVKit docs prove MPV already behaves correctly."
- "AVKit docs define Enchron's current production playback route."
- "Apple reference playback is a production fallback."
- "HDR labels can follow user toggles instead of media/display evidence."
- "A 2D Metal layer is automatically compatible with immersive rendering."
- "iOS full-screen playback is the model for Vision Pro playback."
- "visionOS media playback inherits iOS Picture in Picture, background, routing,
  and full-screen behavior unchanged."
- "RealityKit video means only `VideoMaterial`."
- "`CompositorLayer` always means full immersion."
- "360 video defaults to drawing video on the inside of a sphere."
- "3D video embedded inline will display stereoscopically."
- "Spatial Video is side-by-side 3D."
- "Apple Immersive Video is ordinary high-resolution 180 or 360 video."
- "`AVPlayerLayer` or an MPV layer can display pixels, so the visionOS media
  experience is done."
- "APMP or Apple Immersive Video metadata can be ignored if frames decode."
- "High-motion immersive video can go directly to full immersion."

Read: `immersive-media-profiles.md`, `playback-media.md`, plus
`metal-compositor.md` if custom rendering is involved.

## RealityKit, ARKit, Sensors

- "Hand tracking is needed for normal controls."
- "The app can know where the user is looking."
- "iOS ARKit display code ports directly."
- "RealityKit entities can be recreated freely inside SwiftUI updates."
- "ARKit authorization can be guessed from the provider name."
- "All ARKit providers require Full Space."
- "RealityKit `SpatialTrackingSession` bypasses ARKit privacy requirements."

Read: `realitykit-spatialscene.md` and `arkit-privacy.md`.

## Files, Persistence, Performance

- "Photo library or local file access behaves like desktop file access."
- "SMB or WebDAV on the LAN does not need local-network privacy."
- "A raw file path remains valid after document selection."
- "Credentials can live in defaults during early development."
- "UserDefaults is fine as a general database."
- "Simulator verification is enough for spatial, video, HDR, or performance."
- "Simulator playback proves audio, subtitles, comfort, power, and immersive
  transitions."
- "Debug build performance is enough evidence."

Read: `files-network-persistence.md` and `performance-debugging.md`.
