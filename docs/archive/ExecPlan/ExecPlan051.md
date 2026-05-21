# HDR Diagnostics Observability Cleanup

## Goal

Keep ordinary playback UI honest by removing user-facing HDR ON/OFF controls, defaulting playback to the EDR path, and making true-device HDR probe data easy to retrieve without relying on live stdout capture.

## Scope

- Remove HDR toggles from ordinary playback controls and video detail setup.
- Keep HDR renderer switching and MPV probe tools inside the debug diagnostics overlay.
- Persist HDR probe samples/errors to an app-accessible diagnostics log so device runs can be pulled from the Mac.
- Verify with package tests and a visionOS simulator build.

## Non-goals

- Do not solve MPV HDR color correctness in this pass.
- Do not promote Apple Reference to the default playback engine.
- Do not claim final display HDR or RealityKit HDR preservation.

## Validation

- `swift test`
- `xcodebuild -project XrPlayer.xcodeproj -scheme XrPlayer -destination 'generic/platform=visionOS Simulator' build`
- Manual true-device check: sample MPV drawable, then pull the app diagnostics log and confirm it records the same fields shown in the overlay.
