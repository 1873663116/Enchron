---
name: visionos-platform
description: Use for Enchron/XrPlayer work that touches visionOS-specific Swift, SwiftUI, RealityKit, ARKit, Metal, AVKit/video playback, scene/window lifecycle, spatial interaction, privacy, performance, networking, persistence, or any area where iOS/macOS Swift instincts might conflict with Apple Vision Pro behavior. Do not use for pure Swift Domain, UseCase, or unit-test changes with no platform surface. This is an official-docs router; load only the matching reference file for the task.
---

# visionOS Platform Router

This skill prevents iOS/macOS Swift and SwiftUI habits from silently becoming
visionOS decisions in Enchron.

The skill body is only an entry point. Do not read every reference by default.
Pick the task area below, then load only the matching file in `references/`.
When the work is broad or architectural, read multiple matching files in order.

If a subagent must use this skill, pass both this `SKILL.md` path and the
specific reference path it should read.

## Loading Rule

Codex keeps skill metadata in context, not this full body. After the skill
triggers, read this router, then the smallest relevant reference file.

Use live Apple documentation when the answer depends on current API
availability, OS-version behavior, privacy requirements, App Store constraints,
media/HDR behavior, ARKit permissions, or performance claims.

Coding, debugging, build triage, runtime triage, and code review all count as
skill triggers when they touch a visionOS platform surface.

When this skill and an iOS/macOS skill both appear relevant, this skill controls
surface selection, lifecycle, privacy, media behavior, rendering, input, and
verification. iOS/macOS skills may help with Swift syntax, general Foundation
patterns, or cross-platform API mechanics only after the visionOS surface is
chosen.

## Workflow

1. Classify the touched Enchron module and visionOS surface.
2. Open the matching reference file from the route table.
3. Open the Apple docs linked by that reference when the behavior is not already
   certain.
4. Name the inherited iOS/macOS assumption that could be wrong.
5. Inspect the local code before proposing or editing.
6. Make the smallest change aligned with the visionOS source.
7. Verify with the narrowest automated check and list any required Simulator or
   device checks.

## Route Table

| Task area | Local files likely involved | Read |
| --- | --- | --- |
| App scene lifecycle, windows, volumes, immersive spaces, launch/default size/restoration | `XrPlayer/App`, `MainView`, `AppModel`, `DesignPreviewApp` | `references/app-scenes.md` |
| SwiftUI controls, DesignPreview, gaze hover, ornaments, spatial layout, accessibility | `PlayerUI`, `DesignPreview`, `Shared/DesignSystem`, `Settings` | `references/spatial-ui.md` |
| Playback, AVFoundation/AVKit, MPV comparison, HDR/EDR, subtitles/tracks, video surfaces | `PlaybackCore`, `WindowVideoView`, `WindowVideoViewModel`, `PlayerUI/Views/*Video*` | `references/playback-media.md` |
| Immersive media profiles, APMP, Spatial Video, Apple Immersive Video, AVExperienceController, RealityKit VideoPlayerComponent | `PlaybackCore`, `PlayerUI`, `SpatialScene`, media routing plans | `references/immersive-media-profiles.md` |
| RealityKit scenes, `RealityView`, entities, attachments, panoramas, virtual screens, volumes | `SpatialScene`, RealityKit renderers, immersive views | `references/realitykit-spatialscene.md` |
| ARKit data, world/hand/scene sensing, camera access, privacy permissions | `SpatialScene`, ARKit integration, privacy-sensitive features | `references/arkit-privacy.md` |
| Custom Metal immersive rendering, Compositor Services, render loops, stereoscopic drawing | `Shared/Metal*`, `WindowVideoView`, future custom immersive renderer | `references/metal-compositor.md` |
| File browsing, PhotoKit, UTType, WebDAV, SMB, URL loading, credentials, persistence | `FileBrowsing`, `Persistence`, network adapters, credential stores | `references/files-network-persistence.md` |
| Simulator/device gap, profiling, RealityKit render cost, thermal/power, visual debugging | Any performance or QA task | `references/performance-debugging.md` |
| Suspicious platform assumptions or code review | Any module | `references/misconceptions.md` |

## Cross-Read Rules

- SwiftUI window, scene, volume, immersive-space, presentation, or restoration
  work: read `app-scenes.md`.
- SwiftUI controls, layout, hover/focus, ornaments, accessibility, or
  DesignPreview work: read `spatial-ui.md`.
- MPV `CAMetalLayer`, EDR/HDR, texture bridge, or renderer timing: read
  `playback-media.md`, `metal-compositor.md`, and `performance-debugging.md`.
- Spatial Video, 3D video, APMP, Apple Immersive Video, Quick Look immersive
  preview, `AVExperienceController`, or RealityKit `VideoPlayerComponent` work:
  read `immersive-media-profiles.md`, then `playback-media.md` only if baseline
  playback or engine comparison is involved.
- Immersive video in RealityKit: read `immersive-media-profiles.md` and
  `realitykit-spatialscene.md`; add `playback-media.md` when baseline playback
  or engine comparison matters.
- Any ARKit provider, sensing permission, world/hand/scene/camera/accessory
  feature: read `arkit-privacy.md` even if the code lives in `SpatialScene`.
- SMB, WebDAV, LAN discovery, arbitrary host entry, or local file selection:
  read `files-network-persistence.md`.
- Custom spatial controls or RealityKit entities that can be activated: read
  `spatial-ui.md` and the accessibility section in that file.

## Broad Task Reading Order

For a broad Enchron platform audit, read:

1. `references/app-scenes.md`
2. `references/misconceptions.md`
3. `references/playback-media.md`
4. `references/immersive-media-profiles.md`
5. `references/metal-compositor.md`
6. `references/realitykit-spatialscene.md`
7. `references/arkit-privacy.md`
8. `references/spatial-ui.md`
9. `references/files-network-persistence.md`
10. `references/performance-debugging.md`

For a small edit, read only one task reference plus `misconceptions.md` if the
code smells like an iOS/macOS port.

## Version Gate Rule

Before choosing a visionOS 26 API, answer:

1. What is the project minimum deployment target?
2. Is the API available at that target?
3. If not, where is the availability guard, runtime capability check, or
   fallback?
4. Does the fallback preserve product behavior, or is it intentionally degraded?

## Default Surface Question

Before choosing an API, answer:

What visionOS surface owns this behavior?

- Bounded 2D UI: standard window.
- Bounded 3D object/model: volume.
- Unbounded spatial content controlled by the app: `ImmersiveSpace`.
- Custom immersive Metal renderer: `ImmersiveSpace` with `CompositorLayer`;
  check Compositor Services docs for full/mixed/progressive behavior.
- Maximum system video integration: `AVPlayerViewController`.
- Media-profile immersive video: Quick Look, AVKit, or RealityKit
  `VideoPlayerComponent`, chosen by media profile.
- Custom immersive video: RealityKit video APIs first, with AVKit as baseline
  and MPV/Metal/custom compositor paths requiring exception rationale.
- Network/file/persistence: Foundation, Network, Security, SwiftData, plus
  visionOS privacy and lifecycle constraints.

For video/media work, also answer:

What media profile owns this content?

- 2D flat video.
- 3D flat or stereoscopic video.
- Spatial Video / MV-HEVC with spatial metadata.
- APMP 180.
- APMP 360 / Wide FOV.
- Apple Immersive Video.
- Custom or unknown media.

Do not start from "this is SwiftUI, so use iOS/macOS pattern X." Start from the
visionOS surface and then choose the Swift API.
