# Performance, Debugging, Simulator, Device

Use for performance planning, Simulator/device differences, RealityKit render
cost, video/HDR validation, thermal/power, Instruments, visual debugging, and
QA evidence.

## Apple Sources

- Creating a performance plan: https://developer.apple.com/documentation/visionos/creating-a-performance-plan-for-visionos-app
- Analyzing visionOS app performance: https://developer.apple.com/documentation/visionos/analyzing-the-performance-of-your-visionos-app
- Reducing RealityKit rendering cost: https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos
- Understanding the visionOS render pipeline: https://developer.apple.com/documentation/visionos/understanding-the-visionos-render-pipeline
- Diagnosing appearance issues: https://developer.apple.com/documentation/xcode/diagnosing-issues-in-the-appearance-of-your-running-app
- Running in Simulator or on device: https://developer.apple.com/documentation/visionos/running-your-app-in-simulator-or-on-a-device
- Interacting with the simulator: https://developer.apple.com/documentation/visionos/interacting-with-your-app-in-the-visionos-simulator
- RealityKit: https://developer.apple.com/documentation/realitykit
- Metal: https://developer.apple.com/documentation/metal

## Correct Decisions

- Simulator is useful but not authoritative for rendering, input, audio/video,
  hardware features, HDR, or thermal behavior.
- Profile on physical device for performance claims.
- Track launch/load time, responsiveness/latency, render frame pacing, power,
  memory, network, and task efficiency.
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
- Use release-like configuration for performance claims; Debug builds are for
  functional diagnosis.

## iOS/macOS Conflicts

- Do not accept "works in Simulator" as evidence that a spatial, video, HDR, or
  performance path is correct on device.
- Do not optimize from Debug-build metrics alone.
- Do not ignore thermal pressure; Apple documents user-visible impact when
  resource use pushes the device beyond limits.
- Do not treat 2D layout inspection as sufficient for immersive content.
- Do not assume macOS desktop profiling signals map directly to Vision Pro
  comfort or spatial frame pacing.
- Do not profile Compositor Services work only through RealityKit signals; Metal
  immersive rendering needs Metal/compositor timing evidence.

## Enchron Checkpoints

- UI-only changes can usually be verified with build plus visual review.
- HDR, MPV Metal output, RealityKit texture bridge, and immersive scene claims
  need explicit Simulator/device risk notes.
- A QA report should separate automated verification from human headset checks.
