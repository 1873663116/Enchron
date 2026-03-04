# visionOS FFmpeg + mpv Build Scripts

These scripts automate building FFmpeg and mpv (`libmpv`) for visionOS device and simulator, then package them into `MPV.xcframework`.

## Prerequisites

- macOS with Xcode 16+
- Command Line Tools configured (`xcode-select -p`)
- `meson` and `ninja` installed (`brew install meson ninja`)

## Directory Layout

- Source checkout: `third_party/ffmpeg`, `third_party/mpv`
- FFmpeg output: `build/ffmpeg/{device,simulator}`
- mpv output: `build/mpv/{device,simulator}`
- Final package: `build/MPV.xcframework`

## Usage

Build everything (clone/update sources, build both targets, package):

```bash
./scripts/build-all.sh
```

Build FFmpeg only:

```bash
./scripts/build-ffmpeg.sh --target all
./scripts/build-ffmpeg.sh --target device
./scripts/build-ffmpeg.sh --target simulator
```

Build mpv only (requires FFmpeg output for matching target):

```bash
./scripts/build-mpv.sh --target all
```

Package XCFramework only (requires FFmpeg + mpv outputs for both targets):

```bash
./scripts/package-xcframework.sh
```

## Notes

- Cross-files:
  - `scripts/visionos-arm64.cross`
  - `scripts/visionos-sim-arm64.cross`
- Headers/module map are sourced from `Libraries/mpv/`.
