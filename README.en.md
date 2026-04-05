# XrPlayer

[中文](./README.md) | [English](./README.en.md)

XrPlayer is an immersive video player for visionOS.

## Positioning

XrPlayer is not meant to be a flat 2D player transplanted into a headset. The goal is to deliver a native spatial media experience on visionOS with:

- unified local and remote media browsing
- a shared playback core and control system
- three playback modes:
  - window mode
  - immersive scene mode
  - panoramic mode

At this stage, the project is more focused on playback quality than feature count:

- first-play latency and cold-start feel
- secondary timeline and playback controls
- HDR detection and output trustworthiness
- remote source stability for SMB and WebDAV

## Current Status

- The README and public-facing wording now consistently use `XrPlayer`
- `Enchron` may still appear in the current workspace path, commit history, or internal docs
- The codebase currently covers local playback, remote browsing/playback, playback controls, HDR state handling, and baseline persistence
- Core behavior can be validated with `swift test`

## Core Capabilities

- local file browsing and playback
- remote source support: `SMB`, `WebDAV`
- playlist, audio/subtitle selection, playback speed, skip controls
- secondary timeline for precise seeking
- HDR content detection with explicit output mode handling
- persistence for playback progress, preferences, and selected scene-related values

## Naming Convention

- `XrPlayer`: product name and the default public-facing name
- `Enchron`: current workspace name / internal codename

Seeing the following is expected:

- `Enchron/` workspace directory
- `XrPlayer/`
- `XrPlayer.xcodeproj`
- `XrPlayer` scheme

That does not mean the product is unnamed. It only means the codebase and workspace still preserve some internal naming.

## Development Environment

- Xcode 16+
- Swift 6
- macOS 14+
- visionOS SDK

Notes:

- SMB support depends on `AMSMB2`
- without that dependency, the SMB adapter falls back to a stub implementation that compiles but cannot establish real SMB connections

## Quick Start

### 1. Clone the repo

```bash
git clone <your-repo-url>
cd Enchron
```

### 2. Open in Xcode

```bash
open XrPlayer.xcodeproj
```

Use the `XrPlayer` scheme and run on the visionOS Simulator or an Apple Vision Pro device.

### Build Entrypoints

- Use `XrPlayer.xcodeproj` for normal development, running, and simulator/device builds
- The top-level `Package.swift` exists only for auxiliary `swift build` / `swift test` validation and is not the main app project
- `XrPlayer/XrPlayer.xcodeproj.bak` is a historical backup and should not be used for active development or builds

### 3. Run tests

```bash
swift test
```

## Repository Layout

```text
Enchron/
  XrPlayer/             # main app code
    FileBrowsing/       # local/remote source integration and browsing
    PlaybackCore/       # playback core and player adapters
    PlayerUI/           # controls and playback interactions
    Persistence/        # preferences, progress, and credential storage
  Tests/                # SwiftPM tests
```

## Documentation

- Product philosophy: `docs/product_philosophy.md`
- Requirements: `docs/Requirements.md`
- Quality gates: `docs/quality_gates.md`
- Architecture docs: `docs/design_docs/`
