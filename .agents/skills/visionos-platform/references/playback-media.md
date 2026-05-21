# Playback, AVKit, AVFoundation, MPV, HDR

Use for `PlaybackCore`, `WindowVideoView`, `WindowVideoViewModel`,
`AppleReferenceVideoSurface`, MPV output, AVKit comparison, HDR/EDR,
subtitles/tracks, video surfaces, playback diagnostics, and immersive media.

## Apple Sources

- AVFoundation overview: https://developer.apple.com/av-foundation/
- AVFoundation docs: https://developer.apple.com/documentation/avfoundation/
- AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- AVKit: https://developer.apple.com/documentation/avkit
- AVPlayerViewController: https://developer.apple.com/documentation/avkit/avplayerviewcontroller
- Adopting the system player interface in visionOS: https://developer.apple.com/documentation/avkit/adopting-the-system-player-interface-in-visionos
- Playing immersive media with AVKit: https://developer.apple.com/documentation/avkit/playing-immersive-media-with-avkit
- AVExperienceController: https://developer.apple.com/documentation/avkit/avexperiencecontroller
- AVExperienceController.Experience: https://developer.apple.com/documentation/avkit/avexperiencecontroller/experience-swift.enum
- AVDisplayDynamicRange: https://developer.apple.com/documentation/avkit/avdisplaydynamicrange
- preferredDisplayDynamicRange: https://developer.apple.com/documentation/avkit/avplayerviewcontroller/preferreddisplaydynamicrange
- Destination Video sample: https://developer.apple.com/documentation/visionos/destination-video
- Apple movie profiles: https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf
- HDR content in Metal: https://developer.apple.com/documentation/metal/hdr-content
- RealityKit videos: https://developer.apple.com/documentation/realitykit/scene-content-videos
- Playing immersive media with RealityKit: https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit
- Rendering stereoscopic video with RealityKit: https://developer.apple.com/documentation/visionos/rendering-stereoscopic-video-with-realitykit

## Correct Decisions

- Apple recommends `AVPlayerViewController` for system video playback
  integration in visionOS.
- Enchron's MPV path can still be valid, but AVKit is the baseline for system
  behavior, diagnostics, HDR comparison, tracks/subtitles affordance, and
  immersive playback expectations.
- If using MPV + Metal, the app owns what the system player normally supplies:
  controls, readiness, errors, dynamic range behavior, subtitles/tracks,
  accessibility, and transitions into immersive experiences.
- `preferredDisplayDynamicRange` matters only when content and display support
  HDR. HDR labels must follow evidence, not toggles.
- A UIKit `UIViewRepresentable` bridge can be appropriate for `AVPlayerLayer`,
  `CAMetalLayer`, or `MTKView`. It is an implementation bridge, not a license to
  make the app UIKit-shaped.
- Window Metal output, RealityKit texture playback, and fully immersive Metal
  rendering are different surfaces.

## iOS/macOS Conflicts

- Do not use iOS full-screen player assumptions as the target experience.
- Do not assume macOS `AVPlayerView` patterns are the system answer on visionOS.
- Do not subclass `AVPlayerViewController`; Apple documents unsupported
  subclassing behavior.
- Do not equate "AVPlayer can do this" with "MPV already does this." Use AVKit
  as evidence and comparison.
- Do not treat a 2D `CAMetalLayer` or `MTKView` path as automatically correct
  for RealityKit immersive rendering.
- Do not infer HDR from filename, user toggle, or UI label. Use media metadata,
  output contract, and display behavior.

## Enchron Checkpoints

- Keep playback mode decision in `PlayerUI`; `PlaybackCore` reports facts.
- Keep the AV reference path isolated and diagnostic unless product direction
  explicitly changes.
- HDR/EDR changes should include an evidence path: metadata, AVKit comparison
  when useful, MPV output contract, layer/display configuration, and device
  verification when required.
