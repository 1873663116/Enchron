# HDR Diagnostics Reliability Fixes

## Goal

Tighten the phase-1 window HDR diagnostics implementation so it is safe for debug use and produces evidence that can be interpreted without hidden side effects.

This pass still does not validate RealityKit, Panorama, final display nits, Dolby Vision passthrough, HDR10+ dynamic metadata passthrough, or complete color accuracy.

## Scope

- Gate HDR Lab controls behind a diagnostics feature flag.
- Rename misleading output/probe concepts.
- Prevent MPV probe sampling from permanently changing subtitles or OSD.
- Make probe contract explicit and mark mismatches as inconclusive.
- Reduce MPV drawable readback cost with bounded center-region sampling.
- Pair HDR ON/OFF samples only when media, renderer, time, and contract match.
- Tighten Apple reference lifecycle and stale metadata handling.
- Expose the five diagnostic state layers in the overlay.
- Add pure tests for contract and sample pairing logic.

## Verification

- `swift test` passed.
- `git diff --check` passed.
- `xcodebuild -project XrPlayer.xcodeproj -scheme XrPlayer -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/enchr-hdr-reliability build` passed.
