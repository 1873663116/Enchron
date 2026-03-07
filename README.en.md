# XrPlayer

[中文](./README.md) | [English](./README.en.md)

XrPlayer is a visionOS-focused video player project. The goal is to provide a unified browsing and playback experience across local and remote sources (SMB / WebDAV), and keep evolving spatial playback interactions.

## Current Status

- The current mainline focus is v0.3: remote source flow is now in a practically usable stage.
- `main` already includes the latest remote connection/browsing fixes (SMB + WebDAV).
- Core logic can be validated with `swift test`.

## Core Features

- Local file browsing and playback
- Remote source integration: `WebDAV`, `SMB`
- Remote directory browsing (folders are listed, not only video files)
- Data source management (add, connect, delete)
- Connection error feedback and basic authentication handling

## Remote Connection Rules (v0.3)

- Address is required, username is optional.
- Password is only required when the server challenges for authentication.
- A data source is persisted only after a successful connection.
- Credentials are stored in Keychain for reuse.

## Development Environment

- Xcode 16+
- Swift 6
- macOS 14+
- visionOS SDK (for simulator/device build)

> Note: SMB depends on `AMSMB2`. Without this dependency, SMB adapter compiles in fallback stub mode and cannot establish real SMB connections.

## Quick Start

### 1) Clone

```bash
git clone <your-repo-url>
cd XrPlayer
```

### 2) Open and Run in Xcode

```bash
open XrPlayer.xcodeproj
```

Select `XrPlayer` scheme and run on visionOS Simulator or Apple Vision Pro device.

### 3) Run Core Tests

```bash
swift test
```

## Project Layout

```text
XrPlayer/
  FileBrowsing/      # local/remote source integration and file browsing
  PlaybackCore/      # playback core and player adapters
  PlayerUI/          # controls and interaction
  Persistence/       # persistence and Keychain credential storage
docs/                # requirements, architecture, and roadmap
Tests/               # SwiftPM tests
```

## Roadmap

- v0.3: make remote sources production-usable (in progress)
- Next: playback stability, UI polishing, more protocols/media capabilities

See `docs/phase4_implementation_roadmap.md` for details.

## Contributing

Issues and PRs are welcome. Before submitting:

```bash
swift test
```

In PR description, include:

- Goal of the change
- Reproduction and validation steps
- Risks and rollback plan (if any)


