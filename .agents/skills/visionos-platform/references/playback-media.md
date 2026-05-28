# MPV Production Playback, Apple AV Reference, HDR

Purpose: route visionOS media decisions through Apple platform sources and
Enchron playback boundaries.
Status: Active visionOS reference.
Owner/scope: mpv production playback, AVKit/AVFoundation reference behavior,
MPV comparison, HDR/EDR, subtitles/tracks, video surfaces, and playback
diagnostics. Media-profile specific immersive playback lives in
`immersive-media-profiles.md`.
This file is not a product contract; active Enchron contracts live in
`docs/contracts/`.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Media-Device/avkit-adopting-the-system-player-interface-in-visionos.md#documentation-avkit-adopting-the-system-player-interface-in-visionos`
  — AVKit system player interface baseline for visionOS.
- `Apple-Media-Device/avkit-avplayerviewcontroller.md#documentation-avkit-avplayerviewcontroller`
  — `AVPlayerViewController` platform player surface.
- `Apple-Media-Device/avfoundation-avplayer.md#documentation-avfoundation-avplayer`
  — `AVPlayer` time-based media control.
- `Apple-Media-Device/avkit-playing-immersive-media-with-avkit.md#documentation-avkit-playing-immersive-media-with-avkit`
  — AVKit immersive media playback.
- `Apple-Media-Device/avfoundation-configuring-your-app-for-media-playback.md#documentation-avfoundation-configuring-your-app-for-media-playback`
  — app-level media playback configuration for iOS, tvOS, and visionOS.

### Open if

- `Apple-Media-Device/avkit-avexperiencecontroller.md#documentation-avkit-avexperiencecontroller`
  — controls and observes `AVPlayerViewController` experience changes.
- `Apple-Media-Device/avkit-avexperiencecontroller-experience-swift.enum.md#documentation-avkit-avexperiencecontroller-experience-swiftenum`
  — AVKit experience enum.
- `Apple-Media-Device/avkit-avdisplaydynamicrange.md#documentation-avkit-avdisplaydynamicrange`
  — AVKit dynamic range values; local platform list excludes visionOS, so use
  this as an availability check before adopting.
- `Apple-Media-Device/avkit-avplayerviewcontroller-preferreddisplaydynamicrange.md#documentation-avkit-avplayerviewcontroller-preferreddisplaydynamicrange`
  — preferred display dynamic range on `AVPlayerViewController`; local
  platform list excludes visionOS, so do not assume Enchron can use it.
- `Apple-Media-Device/avfaudio-handling-audio-interruptions.md#documentation-avfaudio-handling-audio-interruptions`
  — AVFAudio interruption handling.
- `Apple-Media-Device/avfaudio-responding-to-audio-route-changes.md#documentation-avfaudio-responding-to-audio-route-changes`
  — AVFAudio route-change handling.
- `Apple-Media-Device/avkit-avpictureinpicturecontroller-ispictureinpicturesupported.md#documentation-avkit-avpictureinpicturecontroller-ispictureinpicturesupported`
  — Picture in Picture support check.
- `Apple-Media-Device/metal-hdr-content.md#documentation-metal-hdr-content`
  — HDR content handling in Metal.
- `Apple-Media-Device/realitykit-scene-content-videos.md#documentation-realitykit-scene-content-videos`
  — RealityKit video API overview.
- `Apple-Media-Device/realitykit-videoplayercomponent.md#documentation-realitykit-videoplayercomponent`
  — RealityKit video component for immersive media.
- `Apple-Media-Device/realitykit-rendering-stereoscopic-video-with-realitykit.md#documentation-realitykit-rendering-stereoscopic-video-with-realitykit`
  — side-by-side stereoscopic video sample using RealityKit.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Destination Video" "visionOS" "AVPlayerViewController"`
  for the sample app baseline.
- Xcode Documentation Search:
  `"Determining whether to bring your app to visionOS" "Picture in Picture"`
  for migration constraints and unavailable iOS media affordances.
- Xcode Documentation Search:
  `"Playing immersive media with RealityKit" "VideoPlayerComponent"`
  for article-level immersive RealityKit walkthrough.

### Official web fallback

- `https://developer.apple.com/av-foundation/`
- `https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf`

## Correct Decisions

- Enchron's current production playback direction is mpv-first. Production
  playback work should converge around mpv.
- mpv is the current production basis for playback, compatibility, open
  formats, complex subtitles/tracks, remote I/O, HDR experiments, and future
  immersive rendering exploration.
- Apple recommends `AVPlayerViewController` for system video playback
  integration in visionOS. In Enchron, that fact is reference and diagnostics
  evidence unless a future architecture decision promotes Apple AV into
  production.
- For Spatial Video, APMP, Apple Immersive Video, or immersive 3D playback
  research, read `immersive-media-profiles.md` before making platform claims.
- Open the Destination Video sample when changing presentation transitions,
  system playback UI, or spatial-audio behavior in reference/future research;
  it is the concrete platform baseline, not just a sample link.
- If using MPV + Metal, the app owns what the system player normally supplies:
  controls, readiness, errors, dynamic range behavior, subtitles/tracks,
  accessibility, and transitions into immersive experiences.
- AVFoundation is the cross-Apple-platform media framework for time-based media,
  and can be useful for metadata, diagnostics, HDR/EDR observation, and future
  Apple-native media research. It is not a current production playback route.
- `preferredDisplayDynamicRange` matters only where the API is available and
  content and display support HDR. The local AVKit docset platform list does
  not include visionOS for this API; HDR labels must follow evidence, not
  toggles.
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
- Do not turn AVKit reference behavior into Enchron's current production route.
- Do not subclass `AVPlayerViewController`; Apple documents unsupported
  subclassing behavior.
- Apple migration docs list Picture in Picture and AV routing as unavailable on
  visionOS. Do not design Enchron playback UX around those iOS affordances.
  Check current API availability before adding conditional fallback behavior.
- Do not equate "AVPlayer can do this" with "MPV already does this." Use AVKit
  as evidence and comparison.
- Do not treat AVKit system UI as Enchron's product state machine.
- Do not treat a working MPV surface as proof that future Apple-native
  immersive media research is complete.
- Do not use this baseline playback reference as the only source for APMP,
  Apple Immersive Video, Spatial Video, or immersive 3D decisions.
- Do not treat a 2D `CAMetalLayer` or `MTKView` path as automatically correct
  for RealityKit immersive rendering.
- Do not infer HDR from filename, user toggle, or UI label. Use media metadata,
  output contract, and display behavior.

## Enchron Checkpoints

- Keep playback mode decision in `PlayerUI`; `PlaybackCore` reports facts.
- Enchron's current production media direction is mpv-first.
- Apple AV / AVFoundation / AVKit are reference, diagnostics, subjective visual
  comparison, HDR/EDR observation, and future platform investigation surfaces.
- Apple AV is not the current production `PlaybackEngine`, default fallback, or
  current engine-routing target branch.
- AVKit evidence does not prove mpv correctness.
- mpv behavior does not prove future Apple-native media profile support.
- APMP, Apple Immersive Video, Spatial Video, and immersive 3D playback require
  the media-profile reference before claims about support or future direction.
- Production engine routing is defined by
  `docs/contracts/playback-engine-routing.md`.
- Diagnostic Apple reference playback is not a selected production
  `PlaybackEngineRoute`.
- `PlayerUI` must not branch on mpv vs Apple reference playback. It must use
  shared playback and domain semantics.
- HDR/EDR changes should include an evidence path: metadata, AVKit comparison
  when useful, MPV output contract, layer/display configuration, and device
  verification when required.
- If future Apple AV production playback is proposed, require a new explicit
  architecture decision, capability boundary, tests, and doc updates before
  treating it as implementation guidance.
