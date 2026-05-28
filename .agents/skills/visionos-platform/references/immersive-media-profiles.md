# Immersive Media Profiles, APMP, Spatial Video

Use for media-profile-first decisions: 2D video, 3D video, Spatial Video,
APMP 180, APMP 360 or Wide FOV, Apple Immersive Video, Quick Look preview,
AVKit immersive playback, RealityKit `VideoPlayerComponent`, and any proposed
custom MPV, Metal, or compositor path for non-2D media profiles.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Media-Device/avkit-playing-immersive-media-with-avkit.md#documentation-avkit-playing-immersive-media-with-avkit`
  — AVKit immersive playback route and the WWDC25 296 sample entry point.
- `Apple-Media-Device/avkit-avexperiencecontroller.md#documentation-avkit-avexperiencecontroller`
  — `AVExperienceController`, visionOS 2.0, controls
  `AVPlayerViewController` experiences and supersedes other presentation APIs
  after attachment.
- `Apple-Media-Device/realitykit-videoplayercomponent.md#documentation-realitykit-videoplayercomponent`
  — RealityKit video component, captions/subtitles, passthrough tinting, light
  spill, immersive viewing modes, and transition events.
- `Apple-UI-Frameworks/swiftui-immersive-spaces.md#documentation-swiftui-immersive-spaces`
  — mixed, full, and progressive `ImmersiveSpace` behavior for matching
  RealityKit immersive video mode to SwiftUI scene style.

### Open for media-profile evidence

- `Apple-Media-Device/imageio-creating-spatial-photos-and-videos-with-spatial-metadata.md#documentation-imageio-creating-spatial-photos-and-videos-with-spatial-metadata`
  — Spatial photo/video metadata, MV-HEVC distinction, and Apple Vision Pro
  presentation behavior.
- `Apple-Media-Device/avfoundation-converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video.md#documentation-avfoundation-converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video`
  — side-by-side 3D to MV-HEVC conversion and optional spatial metadata.
- `Apple-Media-Device/avfoundation-converting-projected-video-to-apple-projected-media-profile.md#documentation-avfoundation-converting-projected-video-to-apple-projected-media-profile`
  — equirectangular or half-equirectangular content conversion to APMP.
- `Apple-Media-Device/immersivemediasupport-authoring-apple-immersive-video.md#documentation-immersivemediasupport-authoring-apple-immersive-video`
  — Apple Immersive Video authoring workflow and AIV metadata context.
- `Apple-Media-Device/immersivemediasupport-venuedescriptor.md#documentation-immersivemediasupport-venuedescriptor`
  — `VenueDescriptor` metadata needed for Apple Immersive Video.
- `Apple-Media-Device/avfoundation.md#documentation-avfoundation-avmetadataidentifier-quicktimemetadataaimedata`
  — QuickTime AIME metadata identifier.
- `Apple-Media-Device/avfoundation.md#documentation-avfoundation-avassetplaybackconfigurationoption-spatialvideo`
  — AVFoundation playback configuration option for Spatial Video.
- `Apple-Media-Device/avfoundation.md#documentation-avfoundation-avassetplaybackconfigurationoption-appleimmersivevideo`
  — AVFoundation playback configuration option for Apple Immersive Video.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Playing immersive media with RealityKit" "VideoPlayerComponent" "desiredImmersiveViewingMode"`
  for the article-level RealityKit walkthrough, which is not present in the
  Dash Apple API Reference docset.

### Official web fallback

- WWDC25 304 `Explore video experiences for visionOS`
- WWDC25 296 `Support immersive video playback in visionOS apps`
- WWDC25 297 `Learn about the Apple Projected Media Profile`
- WWDC25 403 `Learn about Apple Immersive Video technologies`
- `https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf`
- `https://developer.apple.com/streaming/examples/`

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
- For APMP high-motion playback, consult the WWDC/APMP fallback evidence before
  choosing full immersion; prefer portal or progressive behavior when current
  evidence supports system comfort mitigation.
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
