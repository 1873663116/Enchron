---
name: visionos-platform
description: Use for Enchron/XrPlayer work that touches visionOS-specific Swift, SwiftUI, RealityKit, ARKit, Metal, AVKit/video playback, scene/window lifecycle, spatial interaction, privacy, performance, networking, persistence, or any area where iOS/macOS Swift instincts might conflict with Apple Vision Pro behavior. This is an official-docs router; load only the matching reference file for the task.
---

# visionOS Platform Router

This skill prevents iOS/macOS Swift habits from silently becoming visionOS
decisions in Enchron.

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
| RealityKit scenes, `RealityView`, entities, attachments, panoramas, virtual screens, volumes | `SpatialScene`, RealityKit renderers, immersive views | `references/realitykit-spatialscene.md` |
| ARKit data, world/hand/scene sensing, camera access, privacy permissions | `SpatialScene`, ARKit integration, privacy-sensitive features | `references/arkit-privacy.md` |
| Custom Metal immersive rendering, Compositor Services, render loops, stereoscopic drawing | `Shared/Metal*`, `WindowVideoView`, future custom immersive renderer | `references/metal-compositor.md` |
| File browsing, PhotoKit, UTType, WebDAV, SMB, URL loading, credentials, persistence | `FileBrowsing`, `Persistence`, network adapters, credential stores | `references/files-network-persistence.md` |
| Simulator/device gap, profiling, RealityKit render cost, thermal/power, visual debugging | Any performance or QA task | `references/performance-debugging.md` |
| Suspicious platform assumptions or code review | Any module | `references/misconceptions.md` |

## Broad Task Reading Order

For a broad Enchron platform audit, read:

1. `references/app-scenes.md`
2. `references/playback-media.md`
3. `references/realitykit-spatialscene.md`
4. `references/spatial-ui.md`
5. `references/files-network-persistence.md`
6. `references/performance-debugging.md`
7. `references/misconceptions.md`

For a small edit, read only one task reference plus `misconceptions.md` if the
code smells like an iOS/macOS port.

## Default Surface Question

Before choosing an API, answer:

What visionOS surface owns this behavior?

- Bounded 2D UI: standard window.
- Bounded 3D object/model: volume.
- Unbounded spatial content controlled by the app: `ImmersiveSpace`.
- Fully custom stereoscopic Metal renderer: `ImmersiveSpace` with
  `CompositorLayer`.
- Maximum system video integration: `AVPlayerViewController`.
- Custom immersive video: RealityKit video APIs, with AVKit as baseline.
- Network/file/persistence: Foundation, Network, Security, SwiftData, plus
  visionOS privacy and lifecycle constraints.

Do not start from "this is SwiftUI, so use iOS/macOS pattern X." Start from the
visionOS surface and then choose the Swift API.
