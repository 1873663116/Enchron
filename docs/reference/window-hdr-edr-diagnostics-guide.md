# Window HDR / EDR Diagnostics Guide

This guide defines how to validate the phase-1 window HDR diagnostics without over-claiming what the evidence proves.

## What Phase 1 Can Prove

Phase 1 can prove that an HDR10-compatible source reaches an EDR-configured MPV window surface and produces extended GPU values under the extended-linear Display P3 contract.

It does not prove final display nits, Dolby Vision passthrough, HDR10+ dynamic metadata passthrough, RealityKit preservation, Panorama preservation, or complete color correctness.

## Local, Simulator, and CI Checks

These checks do not require Vision Pro hardware:

- Source metadata parsing: HDR10, HLG, Dolby Vision source labels, and unknown states.
- Math Synthetic self-test: `maxRGB`, `p99Luminance`, `countAbove1`, `countAbove2`, and ON/OFF delta.
- Playback page UI in debug builds: MPV / Apple switch, MPV drawable sample button, conservative labels, and debug overlay fields.
- AVFoundation metadata panel: `eligibleForHDRPlayback`, `containsHDRVideo`, transfer, primaries, matrix, and unsupported states.
- Renderer switching state: same URL, same timecode, same play/pause/rate intent.

Simulator and CI cannot validate onscreen EDR output, final headroom, Vision Pro brightness behavior, RealityKit compositor behavior, or final nits.

## Vision Pro Checks

Use Vision Pro hardware for these checks:

- Confirm the MPV window layer reports `.rgba16Float`, `framebufferOnly = false`, `wantsEDR = true`, and extended linear Display P3.
- Run Math Synthetic only as a calculator sanity check. It does not prove Metal, CAMetalLayer, or onscreen EDR.
- Play a known HDR10 test pattern, pause on a high-light frame, and press `MPV Drawable Sample`.
- Toggle HDR OFF/ON and confirm the latest matching ON/OFF samples produce a meaningful delta in high-light statistics.
- Compare Apple Reference only as a system reference. If MPV has extended values but looks less saturated, record `PASS_WITH_COLOR_RISK`.

Do not use screenshots, screen recordings, AirPlay captures, or YouTube as HDR validation evidence.

## Source File Checks

Before using a file for HDR diagnostics, inspect it with:

```bash
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,pix_fmt,bits_per_raw_sample,color_range,color_space,color_transfer,color_primaries \
  -show_entries stream_side_data \
  -of json input_hdr.mp4
```

For a phase-1 HDR10 baseline, prefer files that report:

- HEVC Main10 or equivalent 10-bit HDR-capable codec.
- `pix_fmt = yuv420p10le` or another real 10-bit format.
- `color_transfer = smpte2084`.
- `color_primaries = bt2020`.
- `color_space = bt2020nc`.
- Mastering Display metadata and Content Light Level metadata when available.

Missing MaxCLL/MaxFALL does not automatically mean the file is SDR, but it weakens tone-mapping attribution. Metadata can be wrong; use test patterns before movie scenes.

## Test Assets

Use a small fixed set:

- One known HDR10 PQ test pattern for the main pass/fail decision.
- One SDR Rec.709 file as a negative control.
- One HLG file for compatibility observation only.
- Dolby Vision and HDR10+ files only for source detection and label wording.

Self-created ffmpeg/x265 files can test parser and pipeline behavior, but they are not calibration truth unless the PQ/HLG pixel values and metadata are independently verified. Do not add generated samples to pass/fail criteria as if they were mastering-reference material.

## Acceptance Labels

- `PASS`: HDR10 source detected, EDR layer configured, probe contract is extended-linear Display P3, MPV HDR ON drawable sample shows extended values, and matching HDR ON/OFF delta is meaningful.
- `PASS_WITH_COLOR_RISK`: numeric EDR chain passes, but Apple Reference appears more natural or MPV color/gamut mapping looks suspect.
- `INCONCLUSIVE`: output contract, sync, source file, or environment is not reliable enough.
- `FAIL`: extended-linear contract is confirmed, but MPV HDR ON never produces extended values and ON/OFF samples have no meaningful statistical difference.
