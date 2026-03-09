# XrPlayer

[中文](./README.md) | [English](./README.en.md)

XrPlayer is an immersive video player for visionOS.

The public-facing product name is `XrPlayer`. `Enchron` is better treated as an internal codename, workspace name, or temporary documentation label, not the external brand name.

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
  workspace-agents/     # product, architecture, quality, and skill docs
```

## Documentation

- Product philosophy: `workspace-agents/product_philosophy.md`
- Requirements: `workspace-agents/Requirements.md`
- Known issues: `workspace-agents/known_issues.md`
- Quality gates: `workspace-agents/quality_gates.md`
- Architecture docs: `workspace-agents/design_docs/`

## Contributing

Issues and PRs are welcome. Before submitting, at minimum run:

```bash
swift test
```

If your change touches playback, HDR, remote connections, or core interaction paths, also include:

- regression coverage
- logs or smoke-check evidence
- risks and rollback notes
