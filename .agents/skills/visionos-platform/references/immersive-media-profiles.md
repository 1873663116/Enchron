# Immersive Media Profiles, APMP, Spatial Video

Use for media-profile-first decisions: 2D video, 3D video, Spatial Video,
APMP 180, APMP 360 or Wide FOV, Apple Immersive Video, Quick Look preview,
AVKit immersive playback, RealityKit `VideoPlayerComponent`, and any proposed
custom MPV, Metal, or compositor path for non-2D media profiles.

## Apple Sources

### Open first

- Explore video experiences for visionOS: https://developer.apple.com/videos/play/wwdc2025/304/
- Support immersive video playback in visionOS apps: https://developer.apple.com/videos/play/wwdc2025/296/
- Learn about the Apple Projected Media Profile: https://developer.apple.com/videos/play/wwdc2025/297/
- Playing immersive media with AVKit: https://developer.apple.com/documentation/avkit/playing-immersive-media-with-avkit
- Playing immersive media with RealityKit: https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit

### Open if

- AVExperienceController: https://developer.apple.com/documentation/avkit/avexperiencecontroller
- VideoPlayerComponent: https://developer.apple.com/documentation/realitykit/videoplayercomponent
- Learn about Apple Immersive Video technologies: https://developer.apple.com/videos/play/wwdc2025/403/
- Creating spatial photos and videos with spatial metadata: https://developer.apple.com/documentation/imageio/creating-spatial-photos-and-videos-with-spatial-metadata
- Apple Movie Profiles for Spatial and Immersive Media: https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf
- HTTP Live Streaming examples: https://developer.apple.com/streaming/examples/
- AVFoundation: https://developer.apple.com/documentation/avfoundation

## Correct Decisions

- Classify the media profile before selecting a playback API.
- Minimum profile set: 2D flat video, 3D flat or stereoscopic video,
  Spatial Video / MV-HEVC with spatial metadata, APMP 180, APMP 360 / Wide FOV,
  Apple Immersive Video, and custom or unknown media.
- File preview and library preview default to Quick Look or `PreviewApplication`
  when product needs allow system preview.
- Standard long-form video, movies, courses, sports, captions, audio behavior,
  system controls, and HLS default to AVKit with `AVPlayerViewController`.
- Expanded or immersive system video transitions use AVKit and
  `AVExperienceController` when the content profile supports those experiences.
- Video that belongs inside a 3D scene, game world, portal, or custom spatial UI
  uses RealityKit `VideoPlayerComponent` before lower-level custom rendering.
- APMP and Apple Immersive Video should preserve official projection metadata,
  view packing, spatial audio, captions, and comfort behavior.
- RealityKit progressive immersive playback must match
  `desiredImmersiveViewingMode` with the SwiftUI `ImmersionStyle`.
- APMP high-motion playback should prefer portal or progressive behavior and
  rely on system comfort mitigation before custom full immersion.
- AVFoundation, Core Media, Video Toolbox, HLS tools, and Immersive Media
  Support are media creation, conversion, metadata, and distribution tools, not
  a reason to bypass system playback presentation by default.
- Custom Metal, Compositor Services, or MPV texture bridging for APMP, AIV,
  Spatial Video, or 3D content requires an exception rationale explaining why
  Quick Look, AVKit, and RealityKit do not satisfy the product behavior.

## iOS/macOS Conflicts

- Do not treat `AVPlayerLayer`, `CAMetalLayer`, or an MPV window surface as a
  complete visionOS media experience for APMP, AIV, Spatial Video, or 3D video.
- Do not treat 360 video as a default custom inside-out sphere problem when
  APMP metadata and system playback paths are available.
- Do not assume inline 3D video displays stereoscopically; expanded playback is
  the system route for stereoscopic 3D movie viewing.
- Do not equate Spatial Video with side-by-side 3D. Spatial Video depends on
  MV-HEVC and spatial metadata.
- Do not treat Apple Immersive Video as ordinary high-resolution 180 or 360
  video; its metadata and audio workflow are part of the format.
- Do not discard APMP or Apple Immersive Video metadata and then claim format
  support because decoded frames can be drawn.
- Do not jump directly to full immersion for high-motion APMP content.
- Do not use Simulator playback as final evidence for audio, captions,
  comfort, power, spatial styling, or immersive transitions.

## Enchron Checkpoints

- Answer both routing questions before implementation:
  What visionOS surface owns this behavior?
  What media profile owns this content?
- Keep `PlaybackCore` responsible for media facts and playback state, not
  presentation mode decisions.
- Keep `PlayerUI` responsible for playback mode decisions using shared domain
  semantics, not concrete engine identity.
- MPV window playback remains valid for 2D and open-format media where
  Apple-native evidence is insufficient.
- For 3D, Spatial Video, APMP, and Apple Immersive Video, start from Quick Look,
  AVKit, or RealityKit. Enter MPV texture bridging only after an exception
  rationale.
- A custom panorama sphere may remain an implementation path for legacy or
  unsupported open-format inputs, but it is not the default policy for APMP or
  Apple-native immersive profiles.
- Verification for immersive profiles needs device risk notes, especially for
  comfort mitigation, spatial audio, captions/subtitles, power, and long-viewing
  behavior.

## Version Gates

- Before choosing a visionOS 26 media API, identify the project minimum
  deployment target.
- If the API is above that target, add an availability guard, runtime capability
  check, or explicit fallback.
- If fallback behavior is degraded, name the product-level degradation.
- If the project target already includes the API, still record the dependency in
  the relevant plan or code review when the feature is central to playback.
