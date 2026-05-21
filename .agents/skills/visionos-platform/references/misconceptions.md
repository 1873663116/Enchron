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

Read: `app-scenes.md`, then Apple docs for windows/spaces.

## UI And Input

- "Hover is pointer hover."
- "`onHover` is enough for gaze."
- "44 pt targets are fine."
- "A `TapGesture` is equivalent to a `Button`."
- "Dense desktop sidebars are fine because this is a productivity app."
- "Custom glass/material always looks more native."

Read: `spatial-ui.md`, then HIG Eyes/Gestures/Buttons/Spatial Layout.

## Playback And Media

- "AVKit docs are irrelevant because Enchron uses MPV."
- "AVKit docs prove MPV already behaves correctly."
- "HDR labels can follow user toggles instead of media/display evidence."
- "A 2D Metal layer is automatically compatible with immersive rendering."
- "iOS full-screen playback is the model for Vision Pro playback."

Read: `playback-media.md`, plus `metal-compositor.md` if custom rendering is
involved.

## RealityKit, ARKit, Sensors

- "Hand tracking is needed for normal controls."
- "The app can know where the user is looking."
- "iOS ARKit display code ports directly."
- "RealityKit entities can be recreated freely inside SwiftUI updates."
- "ARKit authorization can be guessed from the provider name."

Read: `realitykit-spatialscene.md` and `arkit-privacy.md`.

## Files, Persistence, Performance

- "Photo library or local file access behaves like desktop file access."
- "Credentials can live in defaults during early development."
- "UserDefaults is fine as a general database."
- "Simulator verification is enough for spatial, video, HDR, or performance."
- "Debug build performance is enough evidence."

Read: `files-network-persistence.md` and `performance-debugging.md`.
