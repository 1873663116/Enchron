# visionOS 26 Skill Crosswalk

Status: Active audit crosswalk.
Date: 2026-05-22.
Source input: `docs/reference/2026-05-22-visionos26-migration-audit.md`.

This crosswalk maps the external migration audit into the project-local
`visionos-platform` skill. It is a change map, not a second rule system.

| Audit section | Current skill/reference | Action | Risk | Notes |
| --- | --- | --- | --- | --- |
| 2, 3 scene-first, windows, volumes, immersive spaces | `references/app-scenes.md` | Change | High | Add visionOS 26 launch, locking, persistent UI, surface snapping, clipping margins, scene bridging. Version absolute volume wording by deployment target and current SDK. |
| 4 UI, coordinates, input, privacy | `references/spatial-ui.md`, `references/realitykit-spatialscene.md` | Change + add | High | Split system gaze/focus, SwiftUI hover, pointer `onHover`, RealityKit hover effects, targeted gestures, `GestureComponent`, and `ManipulationComponent`. |
| 5 ARKit, Full Space, spatial sensing | `references/arkit-privacy.md` | Change | High | Keep provider-specific authorization. Add RealityKit `SpatialTrackingSession` as a higher-level path that still needs capability and permission checks. |
| 6 performance, background, testing | `references/performance-debugging.md`, `references/files-network-persistence.md` | Change | Medium | Keep Simulator/device split. Add Shared Space versus Full Space profiling, multi-app coexistence, background visibility, and media comfort/device verification. |
| 7 video playback audit | New `references/immersive-media-profiles.md`; existing `references/playback-media.md` | Add + change | High | Keep `playback-media.md` as baseline playback and MPV/AVKit comparison. Route APMP, AIV, spatial video, Quick Look, AVExperienceController, and RealityKit `VideoPlayerComponent` into the new focused reference. |
| 8 old content pruning | `references/app-scenes.md`, `references/playback-media.md`, `references/realitykit-spatialscene.md`, `references/misconceptions.md` | Delete/soften | Medium | Remove absolute volume wording and default custom-sphere video assumptions from normative guidance. Keep custom rendering as an exception path with rationale. |

## Current Project Facts

- `XrPlayer.xcodeproj/project.pbxproj` currently sets `XROS_DEPLOYMENT_TARGET`
  to `26.2`.
- Version gates remain required in the skill because target settings can change
  and references are reused by future tasks and subagents.
- Enchron already has a product-level `Apple-native first, mpv-safe fallback`
  strategy in `docs/product_philosophy.md`.
- `MediaProfile` is already the shared fact layer in
  `docs/ubiquitous_language.md`; this update makes media-profile-first routing
  visible at the skill level.

## Implementation Notes

- Preserve the thin router. Add routes, not a large platform manual.
- Keep `misconceptions.md`; extend it with media-profile mistakes.
- New media-profile work should answer both surface ownership and content
  ownership before selecting APIs.
- The current MPV panorama path remains current implementation reality, but
  APMP, AIV, Spatial Video, and system immersive playback should not inherit it
  by default.
