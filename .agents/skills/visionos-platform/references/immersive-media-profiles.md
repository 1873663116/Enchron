# Immersive Media Profiles, APMP, Spatial Video

Purpose: keep media-profile facts separate from current production playback
direction.
Status: Active visionOS reference.
Owner/scope: 2D video, 3D video, Spatial Video, APMP 180, APMP 360 or Wide
FOV, Apple Immersive Video, Quick Look preview, AVKit immersive playback,
RealityKit `VideoPlayerComponent`, and proposed custom MPV, Metal, or
compositor paths for non-2D media profiles.
This file is not a production playback-routing contract.

Enchron's current production playback route is mpv-first. Apple system media
APIs in this file are reference and future investigation surfaces unless a new
architecture decision promotes them into production.

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

- Classify the media profile before selecting an API, declaring support, or
  declaring a future research path.
- Minimum profile set: 2D flat video, 3D flat or stereoscopic video,
  Spatial Video / MV-HEVC with spatial metadata, APMP 180, APMP 360 / Wide FOV,
  Apple Immersive Video, and custom or unknown media.
- Current Enchron production playback remains mpv-first.
- File preview and library preview default to Quick Look or `PreviewApplication`
  when product needs allow system preview.
- For future Apple-native playback research, standard long-form video, movies,
  courses, sports, captions, audio behavior, system controls, and HLS should be
  compared against AVKit with `AVPlayerViewController`.
- For future Apple-native expanded or immersive system video research, use
  AVKit and `AVExperienceController` when the content profile supports those
  experiences.
- For future RealityKit-based immersive media research, evaluate RealityKit
  `VideoPlayerComponent` before lower-level custom rendering.
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
  Spatial Video, or 3D content must name the current mpv capability being
  exercised or the future Apple-native behavior being studied.

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
- MPV is the current production basis for playback and future immersive
  rendering exploration.
- For 3D, Spatial Video, APMP, and Apple Immersive Video, separate current
  mpv-first support from future Apple-native platform research. Quick Look,
  AVKit, and RealityKit are comparison or future adoption candidates, not
  current production routes.
- A custom panorama sphere may remain an implementation path for legacy or
  unsupported open-format inputs. Support claims for APMP or Apple-native
  immersive profiles need explicit media-profile evidence.
- Verification for immersive profiles needs device risk notes, especially for
  comfort mitigation, spatial audio, captions/subtitles, power, and long-viewing
  behavior.
- If future Apple AV / AVKit / RealityKit production playback is proposed,
  require an explicit architecture decision, capability boundary, tests, and
  doc updates before treating it as Enchron implementation guidance.

## Version Gates

- Before choosing a visionOS 26 media API, identify the project minimum
  deployment target.
- If the API is above that target, add an availability guard, runtime capability
  check, or explicit fallback.
- If fallback behavior is degraded, name the product-level degradation.
- If the project target already includes the API, still record the dependency in
  the relevant plan or code review when the feature is central to playback.
