# Performance, Debugging, Simulator, Device

Use for performance planning, Simulator/device differences, RealityKit render
cost, video/HDR validation, thermal/power, Instruments, visual debugging, and
QA evidence.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Media-Device/realitykit.md#documentation-realitykit-ecs-scenes`
  — RealityKit scene API surface.
- `Apple-Media-Device/realitykit.md#documentation-realitykit-ecs-events`
  — RealityKit event API surface for subscriptions and diagnostics.
- `Apple-Media-Device/metal.md#documentation-metal`
  — Metal framework root for lower-level rendering and diagnostics.
- `Apple-Tools-Misc/compositorservices.md#documentation-compositorservices`
  — Compositor Services root for custom immersive render loops.

### Open if

- `Apple-Media-Device/realitykit.md#documentation-realitykit-ecs-systems`
  — RealityKit systems API surface for per-frame scene work.
- `Apple-Media-Device/metal-hdr-content.md#documentation-metal-hdr-content`
  — HDR content checks for Metal paths.
- `Apple-Tools-Misc/compositorservices-drawing-fully-immersive-content-using-metal.md#documentation-compositorservices-drawing-fully-immersive-content-using-metal`
  — fully immersive Metal rendering contract.

### Search when DocSet lacks the article

- Xcode Documentation Search:
  `"Creating a performance plan for visionOS app" "RealityKit Trace"`
  for performance planning.
- Xcode Documentation Search:
  `"Analyzing the performance of your visionOS app" "Instruments"`
  for profiling workflow.
- Xcode Documentation Search:
  `"Understanding the visionOS render pipeline" "render server" "compositor"`
  for render-pipeline ownership.
- Xcode Documentation Search:
  `"Reducing the rendering cost of RealityKit content on visionOS"`
  for RealityKit-specific render-cost guidance.
- Xcode Documentation Search:
  `"Diagnosing issues in the appearance of your running app" "Xcode"`
  for visual debugging workflow.
- Xcode Documentation Search:
  `"Running your app in Simulator or on a device" "visionOS"`
  for Simulator/device gaps.
- Xcode Documentation Search:
  `"Interacting with your app in the visionOS Simulator"`
  for Simulator interaction workflow.

## Correct Decisions

- Simulator is useful but not authoritative for rendering, input, audio/video,
  hardware features, HDR, or thermal behavior.
- Profile on physical device for performance claims.
- Track launch/load time, responsiveness/latency, render frame pacing, power,
  memory, network, and task efficiency.
- Shared Space and Full Space have different performance and coexistence
  profiles. Test both when a feature can run in both contexts.
- Multi-app coexistence is part of the Shared Space performance model. Do not
  assume Enchron owns the whole render or attention budget outside Full Space.
- Background or inactive scene state does not always mean the user cannot see
  or hear relevant app content. Save state and reduce work deliberately.
- RealityKit render-server stalls and entity commits are first-class
  performance concerns.
- Use the RealityKit Trace template for RealityKit/render-server bottlenecks,
  commits, dropped frames, high power use, animation, physics, and spatial
  systems.
- Use the visionOS render-pipeline docs to decide whether the bottleneck lives
  in app main-thread work, RealityKit/Core Animation commits, render server,
  compositor, or Metal/Compositor Services frame submission.
- Debug immersive placement with visible axes, bounds, overlays, or temporary
  diagnostic entities when needed.
- Immersive media profile claims need device checks for comfort mitigation,
  spatial audio, captions/subtitles, power, and long-viewing behavior.
- Use release-like configuration for performance claims; Debug builds are for
  functional diagnosis.

## iOS/macOS Conflicts

- Do not accept "works in Simulator" as evidence that a spatial, video, HDR, or
  performance path is correct on device.
- Do not optimize from Debug-build metrics alone.
- Do not ignore thermal pressure; Apple documents user-visible impact when
  resource use pushes the device beyond limits.
- Do not treat 2D layout inspection as sufficient for immersive content.
- Do not treat APMP, Apple Immersive Video, Spatial Video, or high-motion
  immersive playback as verified because a short Simulator playback starts.
- Do not assume macOS desktop profiling signals map directly to Vision Pro
  comfort or spatial frame pacing.
- Do not profile Compositor Services work only through RealityKit signals; Metal
  immersive rendering needs Metal/compositor timing evidence.

## Enchron Checkpoints

- UI-only changes can usually be verified with build plus visual review.
- HDR, MPV Metal output, RealityKit texture bridge, and immersive scene claims
  need explicit Simulator/device risk notes.
- APMP, Apple Immersive Video, Spatial Video, and custom immersive video paths
  need human headset verification notes even when docs and builds pass.
- A QA report should separate automated verification from human headset checks.
