# visionOS Sample Code Corpus

Purpose: route implementation-pattern research to durable local copies of
Apple sample projects and selected open-source visionOS media apps.
Status: Supporting reference, not API authority.
Owner/scope: video playback, `WindowGroup` sizing, AVKit player surfaces,
RealityKit media playback, immersive-media transitions, ornaments, and related
scene composition patterns.
Captured: 2026-05-28 local copies under `~/Documents/CodeReferences`.

This file is not a product contract and does not replace Apple documentation,
SDK headers, DocSetQuery, or current Enchron runtime evidence.

## Priority

Use this corpus after checking current Apple documentation, SDK headers, and the
smallest matching `visionos-platform` reference file.

Treat Apple sample code as implementation guidance for how Apple composes APIs
in a complete project. Treat open-source projects as comparison material only.
Samples may be stale, tied to an older Xcode or visionOS release, or simplified
for teaching.

## Local Corpus

Root:

`~/Documents/CodeReferences/Apple/visionOS/VideoPlayback`

### Apple Official Samples

These are downloaded official sample projects, with source folders and original
zip files kept outside the Enchron repo. Local copies were captured on
2026-05-28.

- `apple-official/PlayingImmersiveMediaWithAVKit`
  - Source:
    `https://developer.apple.com/documentation/avkit/playing-immersive-media-with-avkit`
  - Use for: immersive-media profile playback with `AVPlayerViewController`,
    `AVExperienceController`, expanded/immersive experience routing, Spatial
    Video, APMP, and Apple Immersive Video.
  - Do not use as the primary reference for Enchron's current windowed flat
    2D playback fixture.
- `apple-official/PlayingImmersiveMediaWithRealityKit`
  - Source:
    `https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit`
  - Use for: immersive-media profile playback with `VideoPlayerComponent`,
    `GeometryReader3D`, `RealityView`, Spatial Video, APMP, and Apple
    Immersive Video.
  - Do not use as the primary reference for Enchron's current windowed flat
    2D playback fixture.
- `apple-official/CreatingAMultiviewVideoPlaybackExperienceInVisionOS`
  - Source: Apple Developer sample "Creating a multiview video playback
    experience in visionOS".
  - Use for: flat/windowed `AVPlayerViewController` in SwiftUI,
    `windowResizability`, expanded playback, and multiview player
    coordination.
- `apple-official/zips/DestinationVideo.zip`
  - Source:
    `https://developer.apple.com/documentation/visionos/destination-video`
  - Use for: Destination Video, windowed/full-window flat playback,
    `PlayerView` / `SystemPlayerView` composition, custom immersive
    environments, docking regions, media reflections, and SharePlay.
  - Large archive; extract only when the investigation needs source details.

### Open-Source Comparison Repositories

These are complete local clones, not shallow scratch checkouts. Local clones
were captured on 2026-05-28.

- `open-source/openimmersive`
  - Upstream: `https://github.com/acuteimmersive/openimmersive`
  - Use for: app-level composition around an immersive video player.
- `open-source/openimmersivelib`
  - Upstream: `https://github.com/acuteimmersive/openimmersivelib`
  - Use for: RealityKit immersive playback implementation, custom controls,
    and `VideoPlayerComponent` / renderer handling.
- `open-source/AVP-Simple-Video-Player`
  - Upstream: `https://github.com/Netruk44/AVP-Simple-Video-Player`
  - Use for: minimal `AVPlayerViewController` wrapping patterns.
- `open-source/NetflixVisionPro`
  - Upstream: `https://github.com/barisozgenn/NetflixVisionPro`
  - Use for: early visionOS media UI comparison only.

## How To Explore

Prefer a subagent for broad exploration across this corpus so the main thread
does not absorb entire sample projects. Give the subagent this file path plus
the specific question and requested evidence shape.

Use direct inspection in the main thread when:

- the relevant files are already narrowed to a few source files,
- the answer will affect Enchron architecture or platform behavior,
- the sample finding conflicts with current Apple docs or SDK headers,
- the user asks for a grounded final recommendation.

When citing these samples in a decision, record the sample name, local path,
download or clone date if known, and the current Apple-doc or SDK evidence that
still supports the pattern.

## Guardrails

- Do not copy sample code into Enchron without adapting ownership, tokens,
  accessibility, platform availability, and product boundaries.
- Do not treat a sample's missing code path as proof that the API cannot do
  something.
- Do not let open-source projects override Apple docs, SDK headers, or local
  runtime evidence.
- Keep sample projects outside Enchron so Xcode indexing, target membership,
  git status, and project search remain clean.
