# Window HDR / EDR Diagnostics Phase 1

## Goal

Implement a narrow window-playback diagnostic path that can prove whether MPV writes extended-range GPU values into an EDR-configured `CAMetalLayer` drawable under an extended-linear contract.

This phase does not validate RealityKit, Panorama, final display nits, Dolby Vision passthrough, HDR10+ dynamic metadata passthrough, or complete color accuracy.

## Decisions

- Use `.rgba16Float + wantsExtendedDynamicRangeContent + extendedLinearDisplayP3` as the phase-1 window EDR contract.
- Treat `> 1.0` as a strong EDR signal only under that extended-linear contract.
- Add synthetic EDR probe first, then MPV drawable probe.
- Use manual sampling, with one automatic supplemental sample after HDR ON/OFF changes.
- Do not expose user-selectable ROI in phase 1. Disable subtitles/OSD during diagnostic sampling where possible.
- Add Apple `AVPlayerLayer` as an in-player reference surface behind an MPV / Apple switch.
- Keep Apple reference out of the production playback protocol and preferences.
- Add a short verification guide; do not add HDR asset generation scripts.

## Implementation Steps

1. Rename misleading HDR surface state and user-facing labels so layer readiness is not described as verified HDR.
2. Configure and report the native MPV `CAMetalLayer` colorspace as extended linear Display P3.
3. Add pure HDR probe statistics models and tests for max, p99 luminance, threshold counts, and ON/OFF deltas.
4. Add a low-frequency `HDRProbeController` that samples synthetic float data and current MPV drawable data with CPU readback.
5. Expose diagnostic state and actions through `WindowVideoViewModel` without changing `PlaybackControlling`.
6. Add `AVPlayerLayer` reference rendering and a playback-page MPV / Apple switch that preserves URL, timecode, play/pause, and rate.
7. Extend the debug overlay with the phase-1 strong-signal fields and detailed diagnostic state.
8. Add a verification guide covering local, simulator, true-device, and asset checks.

## Verification

- Swift package tests passed for pure probe statistics.
- visionOS app build passed with Xcode CLI.
- Simulator/local validation covers UI state, metadata parsing, renderer switching, synthetic probe math, and sample caching.
- Vision Pro validation is still required for actual EDR surface behavior with synthetic probe and HDR10 test pattern.
