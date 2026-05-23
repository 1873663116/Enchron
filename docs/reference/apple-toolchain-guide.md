# Apple Toolchain Guide

Purpose: help agents choose the right Apple-native tool for Enchron work.
Status: Active reference guide. `AGENTS.md` and `docs/quality_gates.md` carry the project-level boundaries.
Owner/scope: Xcode, SwiftPM, simulator, analysis, performance, archive, and release-adjacent workflows.
This file is not a Swift tutorial, Apple documentation mirror, legal opinion, or release checklist archive.

## Core Judgment

XrPlayer is a visionOS app project. Start from the Xcode project and the touched visionOS surface, then choose the smallest useful tool.

Useful default shape:

1. `xcodebuild`, `xcrun`, `xcode-select --print-path`, `xcrun simctl`, and `swift`
2. SwiftPM for `Package.swift`-covered package work
3. SwiftLint, `swift format` / `swift-format`, and `xcodebuild analyze`
4. XcodeBuildMCP for simulator UI, screenshots, gestures, accessibility, and Xcode IDE workflows
5. Other runtimes only when a concrete script or explicit subproject owns the task

## Repository Shape

- `XrPlayer.xcodeproj` owns the complete app build.
- `Package.swift` defines `XrPlayerCoreTestsSupport`; it is not a full app manifest.
- Root `Package.resolved` and the Xcode workspace SwiftPM lockfile describe different scopes.
- `DesignPreview` is a separate Xcode target with its own local instructions.
- `.mcp.json` starts XcodeBuildMCP through Node tooling, but that is MCP bootstrap, not app build/test policy.

## Looking Around Safely

These commands reveal local toolchain state without changing it:

```bash
xcode-select --print-path
xcodebuild -version
swift --version
xcrun --find xcodebuild
xcrun --find swift
xcrun --find swift-format || true
xcrun simctl list devices available
xcodebuild -list -project XrPlayer.xcodeproj
xcodebuild -showdestinations -project XrPlayer.xcodeproj -scheme XrPlayer
xcodebuild -showdestinations -project XrPlayer.xcodeproj -scheme DesignPreview
```

When SDK, deployment target, language mode, signing, or bundle identity matters:

```bash
xcodebuild \
  -showBuildSettings \
  -project XrPlayer.xcodeproj \
  -scheme XrPlayer \
| grep -E 'SDKROOT|SUPPORTED_PLATFORMS|XROS_DEPLOYMENT_TARGET|SWIFT_VERSION|PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM'
```

Treat global Xcode selection, signing, device state, package locks, language mode, deployment target, entitlements, and bundle identity as project or human decisions, not incidental cleanup.

## Building And Testing

Full app build:

```bash
xcodebuild \
  -project XrPlayer.xcodeproj \
  -scheme XrPlayer \
  -configuration Debug \
  -destination '<destination copied from -showdestinations>' \
  build
```

DesignPreview build:

```bash
xcodebuild \
  -project XrPlayer.xcodeproj \
  -scheme DesignPreview \
  -configuration Debug \
  -destination '<destination copied from -showdestinations>' \
  build
```

Package-covered core tests:

```bash
swift test
```

`swift test` verifies only the package graph. It says nothing by itself about windows, immersive spaces, assets, RealityKitContent, signing, Metal, HDR, mpv, or device behavior.

## Quality Tools

SwiftLint:

```bash
swiftlint lint --quiet
```

Formatting:

```bash
swift format lint XrPlayer Tests
swift format --in-place <touched swift files>
```

Use formatting near changed files. Whole-repo formatting belongs in a separate formatting-only change.

Static analysis:

```bash
xcodebuild \
  -project XrPlayer.xcodeproj \
  -scheme XrPlayer \
  -configuration Debug \
  analyze
```

`analyze` is most useful when the touched area includes playback, mpv, AVKit, Metal, CoreVideo, bridging headers, adapter boundaries, threading, HDR, subtitles, remote I/O, or persistence edge cases.

## Choosing Evidence

| Surface | Good evidence |
| --- | --- |
| Docs / agents / contracts | `git diff --check` plus targeted `rg` |
| Pure Domain / UseCase / ValueObject | `swift test`; SwiftLint when architecture guards are relevant |
| Xcode target, asset, bundle, signing, entitlements, UI, scene, RealityKitContent | Matching `xcodebuild build` / `test` |
| PlaybackCore, mpv, Apple AV, HDR, subtitles, audio tracks, Metal, CoreVideo, remote I/O | Xcode build plus relevant tests; add `xcodebuild analyze` when it can see the risk |
| DesignPreview UI | DesignPreview build or Canvas/Simulator check, with the visual boundary named |
| Performance, drops, memory, thermal, startup, long viewing | Instruments / `xctrace` evidence |
| Release, TestFlight, App Store | Archive plus signing/license/privacy/export-compliance/test-feedback review |

## Debug And Performance

Use LLDB when the truth is in stack frames, variables, threads, breakpoints, or crash state.

Use Instruments / `xctrace` when the truth is performance: CPU, GPU, memory, leaks, hangs, frame timing, launch time, power, or long-viewing behavior.

Simulator evidence is useful but bounded. Vision Pro device checks still matter for comfort, spatial interaction, HDR/EDR credibility, power, long playback, and immersive media behavior.

## Archive And Release

Archive is release-adjacent evidence:

```bash
mkdir -p build
xcodebuild \
  -project XrPlayer.xcodeproj \
  -scheme XrPlayer \
  -configuration Release \
  -destination 'generic/platform=visionOS' \
  -archivePath build/XrPlayer.xcarchive \
  archive
```

Release work keeps technical verification separate from identity and compliance:

- signing and provisioning
- bundle identifier and development team
- entitlements and privacy strings
- third-party license review, including MPVKit-GPL
- export compliance
- TestFlight or App Store Connect feedback

Agents can inspect and explain these surfaces. Release identity and compliance-sensitive settings change only by explicit human direction.

## Script Shape

Future repository scripts should wrap Apple-native tools. Useful shell-wrapper names would be:

```text
scripts/doctor-apple-toolchain.sh
scripts/build-xrplayer.sh
scripts/build-designpreview.sh
scripts/test-core.sh
scripts/analyze-xrplayer.sh
scripts/archive-xrplayer.sh
```

Inspect a script before running it. A script is an ergonomics layer, not a new build system.
