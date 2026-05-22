# Playback Baseline, AVKit, AVFoundation, MPV, HDR

Purpose: route visionOS media decisions through Apple platform sources and
Enchron playback boundaries.
Status: Active visionOS reference.
Owner/scope: playback, AVKit/AVFoundation, MPV comparison, HDR/EDR,
subtitles/tracks, video surfaces, and playback diagnostics. Media-profile
specific immersive playback lives in `immersive-media-profiles.md`.
This file is not a product contract; active Enchron contracts live in
`docs/contracts/`.

## Apple Sources

### Open first

- Adopting the system player interface in visionOS: https://developer.apple.com/documentation/avkit/adopting-the-system-player-interface-in-visionos
- Destination Video sample: https://developer.apple.com/documentation/visionos/destination-video
- Determining whether to bring your app to visionOS: https://developer.apple.com/documentation/visionos/determining-whether-to-bring-your-app-to-visionos
- AVPlayerViewController: https://developer.apple.com/documentation/avkit/avplayerviewcontroller

### Open if

- AVFoundation overview: https://developer.apple.com/av-foundation/
- AVFoundation docs: https://developer.apple.com/documentation/avfoundation/
- AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- AVKit: https://developer.apple.com/documentation/avkit
- Playing immersive media with AVKit: https://developer.apple.com/documentation/avkit/playing-immersive-media-with-avkit
- AVExperienceController: https://developer.apple.com/documentation/avkit/avexperiencecontroller
- AVExperienceController.Experience: https://developer.apple.com/documentation/avkit/avexperiencecontroller/experience-swift.enum
- AVDisplayDynamicRange: https://developer.apple.com/documentation/avkit/avdisplaydynamicrange
- preferredDisplayDynamicRange: https://developer.apple.com/documentation/avkit/avplayerviewcontroller/preferreddisplaydynamicrange
- Configuring your app for media playback: https://developer.apple.com/documentation/visionos/configuring-your-app-for-media-playback
- Handling audio interruptions: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
- Responding to audio route changes: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- AVPictureInPictureController support check: https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/ispictureinpicturesupported()
- Apple movie profiles: https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf
- HDR content in Metal: https://developer.apple.com/documentation/metal/hdr-content
- RealityKit videos: https://developer.apple.com/documentation/realitykit/scene-content-videos
- Playing immersive media with RealityKit: https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit
- Rendering stereoscopic video with RealityKit: https://developer.apple.com/documentation/visionos/rendering-stereoscopic-video-with-realitykit

## Correct Decisions

- Apple recommends `AVPlayerViewController` for system video playback
  integration in visionOS.
- For Spatial Video, APMP, Apple Immersive Video, or immersive 3D playback
  decisions, read `immersive-media-profiles.md` before choosing AVKit,
  RealityKit, MPV, Metal, or custom compositor paths.
- Open the Destination Video sample when changing presentation transitions,
  system playback UI, or spatial-audio behavior; it is the concrete baseline,
  not just a sample link.
- Enchron's production media direction is Apple-native first, mpv-safe
  fallback. AVKit and AVFoundation are the baseline for Apple-native media
  behavior, system playback surfaces, HDR/EDR handling, Spatial Video, MV-HEVC,
  Apple immersive media, and future visionOS media support.
- Enchron's MPV path remains the open-format baseline for MKV, WebM, AVI,
  TS/M2TS, FLV, complex subtitles, complex tracks, dirty inputs, and remote I/O
  cases where Apple-native evidence is insufficient.
- If using MPV + Metal, the app owns what the system player normally supplies:
  controls, readiness, errors, dynamic range behavior, subtitles/tracks,
  accessibility, and transitions into immersive experiences.
- AVFoundation is the cross-Apple-platform media framework for time-based media,
  but visionOS playback experience decisions still start from the owning
  surface and media profile. Do not stop at `AVPlayerLayer` or an MPV layer when
  the content profile requires spatial styling or immersive media behavior.
- `preferredDisplayDynamicRange` matters only when content and display support
  HDR. HDR labels must follow evidence, not toggles.
- Audio session, interruptions, route changes, spatial-audio behavior,
  captions/subtitles, external subtitle files, and remote-command expectations
  are part of the media surface. Do not treat them as generic iOS details.
- A UIKit `UIViewRepresentable` bridge can be appropriate for `AVPlayerLayer`,
  `CAMetalLayer`, or `MTKView`. It is an implementation bridge, not a license to
  make the app UIKit-shaped.
- Window Metal output, RealityKit texture playback, and fully immersive Metal
  rendering are different surfaces.

## iOS/macOS Conflicts

- Do not use iOS full-screen player assumptions as the target experience.
- Do not assume macOS `AVPlayerView` patterns are the system answer on visionOS.
- Do not assume an iOS/macOS `AVPlayer` pattern is correct on visionOS without
  checking the owning visionOS surface.
- Do not subclass `AVPlayerViewController`; Apple documents unsupported
  subclassing behavior.
- Apple migration docs list Picture in Picture and AV routing as unavailable on
  visionOS. Do not design Enchron playback UX around those iOS affordances.
  Check current API availability before adding conditional fallback behavior.
- Do not equate "AVPlayer can do this" with "MPV already does this." Use AVKit
  as evidence and comparison.
- Do not treat AVKit system UI as Enchron's product state machine.
- Do not treat a working MPV surface as proof that Apple-native immersive media
  obligations are satisfied.
- Do not use this baseline playback reference as the only source for APMP,
  Apple Immersive Video, Spatial Video, or immersive 3D decisions.
- Do not treat a 2D `CAMetalLayer` or `MTKView` path as automatically correct
  for RealityKit immersive rendering.
- Do not infer HDR from filename, user toggle, or UI label. Use media metadata,
  output contract, and display behavior.

## Enchron Checkpoints

- Keep playback mode decision in `PlayerUI`; `PlaybackCore` reports facts.
- Enchron's production media direction is Apple-native first, mpv-safe
  fallback.
- Apple AV / AVKit is the platform baseline for Apple-native media behavior,
  system playback surfaces, HDR/EDR handling, Spatial Video, MV-HEVC, Apple
  immersive media, and future visionOS media support.
- mpv remains the open-format baseline for MKV, WebM, AVI, TS/M2TS, FLV,
  complex subtitles, complex tracks, dirty inputs, and remote I/O cases where
  Apple-native evidence is insufficient.
- AVKit evidence does not prove mpv correctness.
- mpv behavior does not replace AVKit or AVFoundation platform obligations.
- APMP, Apple Immersive Video, Spatial Video, and immersive 3D playback require
  the media-profile reference before a custom MPV or Metal plan is accepted.
- Production engine routing is defined by
  `docs/contracts/playback-engine-routing.md`.
- Diagnostic Apple reference playback is not the same thing as a selected
  production `PlaybackEngineRoute`.
- `PlayerUI` must not branch on mpv vs `appleAV`. It must use shared playback
  and domain semantics.
- HDR/EDR changes should include an evidence path: metadata, AVKit comparison
  when useful, MPV output contract, layer/display configuration, and device
  verification when required.
