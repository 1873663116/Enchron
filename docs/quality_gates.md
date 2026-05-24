# Enchron Acceptance Signals

Purpose: describe the signals that make a change credible enough to hand off.
Status: Active acceptance guidance.
Owner/scope: evidence expectations for code, docs, platform behavior, and experience risk.
This file is not a feature spec, architecture contract, release checklist, or QA archive.

## General Signals

A good change preserves `ARCHITECTURE.md` invariants, uses project vocabulary from `docs/ubiquitous_language.md`, and chooses the smallest evidence that can see the risk it touched.

Automated checks and human Simulator/device checks answer different questions. Keep them separate in the handoff when both matter.

A build or script pass is useful evidence. It is not evidence that spatial interaction, HDR, immersive video, comfort, audio, or performance is correct.

Human verification notes should name only what automation cannot prove: device feel, comfort, spatial interaction, HDR/EDR credibility, long-viewing behavior, signing identity, compliance, or other judgment-heavy surfaces.

## Apple Toolchain Signals

`XrPlayer.xcodeproj` is the complete app build source of truth. `Package.swift` covers package-scoped core tests.

Use `xcodebuild` when the change touches the app target, UI, scene lifecycle, assets, target membership, bundle behavior, entitlements, signing surface, or RealityKitContent. Use `swift test` when the change stays inside the package-covered core.

Discover local simulator destinations with `xcrun simctl` and `xcodebuild -showdestinations`; do not guess device names.

Raise `xcodebuild analyze` when the touched surface involves playback, mpv, AVKit, Metal, CoreVideo, bridging, threading, remote I/O, or persistence risk.

For command examples, use `docs/reference/apple-toolchain-guide.md`.

## visionOS Platform Signals

Before choosing an API, know which visionOS surface owns the behavior: window, volume, `ImmersiveSpace`, RealityKit scene, Compositor Services, AVKit system video, or file/network/persistence service.

When API availability, privacy, App Store constraints, media/HDR behavior, ARKit permissions, or performance claims matter, route through `.agents/skills/visionos-platform/SKILL.md` and the smallest relevant reference file. Skill routing confirms the platform boundary; it is not a request to read the full reference set.

For visionOS 26 APIs, check the project deployment target and the fallback story. A degraded fallback is acceptable only when the product behavior is explicit.

## Media Signals

Video/media changes need two facts in view:

- What visionOS surface owns this behavior?
- What media profile owns this content?

The shared media profiles are 2D flat video, 3D flat or stereoscopic video, Spatial Video / MV-HEVC with spatial metadata, APMP 180, APMP 360 / Wide FOV, Apple Immersive Video, and custom or unknown media.

For Spatial Video, APMP, Apple Immersive Video, or immersive 3D playback, consider Quick Look, AVKit, and RealityKit `VideoPlayerComponent` before MPV texture bridging, Metal, or custom compositor work.

Custom media rendering needs a concrete reason: name the media profile and the system behavior being replaced.

Device risk notes are useful for immersive media comfort, spatial audio, captions/subtitles, power, and long-viewing behavior.

## Documentation Signals

Active docs are maps for future work, not phase summaries. Write the state the project should keep using.

Skill docs stay router-oriented. Add or update a reference when detail would make `SKILL.md` too broad.

External audits belong under `docs/reference/` with a non-normative header unless promoted into project rules.

New architecture terms belong in `docs/ubiquitous_language.md`. New or changed module boundaries belong in `ARCHITECTURE.md` and any active contract before code relies on them.

Use kebab-case for active docs; date-prefixed docs use `YYYY-MM-DD`. Leave archive names alone unless the task is explicitly archival cleanup.

## Release Signals

Release work has two different truths: technical readiness and distribution readiness.

Archive success only proves the project can produce an archive. It does not prove product behavior, signing readiness, privacy completeness, license compliance, export compliance, or TestFlight/App Store feedback.

MPVKit-GPL and other third-party dependencies need explicit license/compliance attention before TestFlight or App Store distribution.

Agents can inspect release settings and prepare commands. Changing signing identity, development team, bundle identifier, provisioning profile, entitlements, or compliance-sensitive settings is a human decision.
