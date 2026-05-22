# Enchron Quality Gates

Purpose: define minimum acceptance checks before a change is handed off.
Status: Active quality gate.
Owner/scope: verification expectations for code, docs, platform behavior, and
experience risk. This file is not a feature spec, architecture contract, or QA
report archive.

## General Gate

- The change must preserve `ARCHITECTURE.md` invariants and active contracts.
- The change must use project vocabulary from `docs/ubiquitous_language.md`.
- The verification scope must match the touched surface.
- Automated checks and human Simulator/device checks must be reported
  separately.
- A build or script pass is not evidence that spatial interaction, HDR,
  immersive video, comfort, audio, or performance is correct.

## visionOS Platform Gate

- Before choosing a visionOS API, identify the owning surface: window, volume,
  `ImmersiveSpace`, RealityKit scene, Compositor Services, AVKit system video,
  or file/network/persistence service.
- Before choosing a visionOS 26 API, identify the minimum deployment target and
  whether the API is available at that target.
- If an API is above the minimum deployment target, the change needs an
  availability guard, runtime capability check, or fallback.
- If the fallback degrades product behavior, the degradation must be explicit.
- Any SwiftUI, RealityKit, ARKit, Metal, AVKit, scene lifecycle, spatial input,
  privacy, media, performance, file/network, or persistence change must route
  through `.agents/skills/visionos-platform/SKILL.md`.

## Media Profile Gate

- Video/media changes must answer both questions:
  What visionOS surface owns this behavior?
  What media profile owns this content?
- Minimum media profile set: 2D flat video, 3D flat or stereoscopic video,
  Spatial Video / MV-HEVC with spatial metadata, APMP 180, APMP 360 / Wide FOV,
  Apple Immersive Video, and custom or unknown media.
- For Spatial Video, APMP, Apple Immersive Video, or immersive 3D playback,
  Quick Look, AVKit, and RealityKit `VideoPlayerComponent` must be considered
  before MPV texture bridging, Metal, or custom compositor work.
- A custom media renderer needs an exception rationale that names the media
  profile and the system behavior it must replace.
- Device risk notes are required for immersive media comfort mitigation,
  spatial audio, captions/subtitles, power, and long-viewing behavior.

## Documentation Gate

- Skill docs should stay router-oriented. Add a reference when detail would make
  `SKILL.md` too broad.
- External audits belong under `docs/reference/` with a non-normative header
  unless promoted into project rules.
- When adding a skill route, update the corresponding reference and
  misconception checklist.
- Run the project guard for skill-doc changes:
  `bun .agents/skills/visionos-platform/scripts/verify-skill-docs.ts`.
