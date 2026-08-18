# Media Byte Stream Unit 2 report

## Result

Unit 2 completes M6 and M8 of the Media Byte Stream refactor.

Emby video bytes now enter through a `MediaByteSource` backed by `URLSession`. The source sends the current Emby token in both the `api_key` query item and the `X-Emby-Token` header, follows the system session's normal redirect handling, and performs exact ranged reads against the Emby stream URL. `EmbyPlaybackBridge` registers this source on `MediaByteStreamEndpoint.shared` and gives PlaybackFeature the resulting loopback handle. It no longer gives FFmpeg the remote `directPlayURL`.

PlaybackFeature now accepts only `MediaByteStreamHandle`. MediaSource issues loopback handles for remote sources and file handles for local passthrough. The old bare-URL launch initializers, the bare-URL `beginPlayback` method, and `ResolvedMediaSource` were removed in the same change. PlaybackCore remains independent of MediaSource and still receives the handle's plain openable URL.

The implementation and tests are committed as:

```text
d6026ad refactor: route Emby through media byte streams
```

The comparison base is `a1298902df818d7e192bf3fbaedda542607c55bf`.

## Source routing

| Source | MediaSource handoff | URL opened by PlaybackCore |
|---|---|---|
| Local file and staged Photos file | `MediaByteStreamHandle.localFile` | Original file URL |
| SMB | Handle issued by `MediaByteStreamEndpoint.shared` | Loopback route |
| WebDAV | Handle issued by `MediaByteStreamEndpoint.shared` | Loopback route |
| Emby video | `EmbyMediaByteSource` registered on `MediaByteStreamEndpoint.shared` | Loopback route |

The handle has no public initializer. Its public local-file factory rejects non-file URLs, while the shared endpoint creates loopback handles inside MediaSource. The `Issuance` value records whether a handle represents local passthrough or a loopback route. This value supports runtime assertions, while the required `MediaByteStreamHandle` parameter provides the compile-time gate.

`MediaPlaybackItem` and `PlaybackLaunchRequest` retain the complete handle instead of splitting its URL from its access lease. Their `url` and access properties are derived views used by the existing playback implementation. Releasing a remote handle's lease still unregisters only its endpoint route.

## Emby byte source

`Modules/Emby/EmbyMediaByteSource.swift` uses an injected `URLSession`, with `.shared` as the production default. This keeps Emby byte traffic on the system networking stack and preserves the dependency direction established by ADR 0018: Emby depends on MediaSource, PlaybackFeature depends on MediaSource, and PlaybackCore does not.

For every upstream read, the source:

1. Replaces any stale `api_key` query item with the authenticated server's current token.
2. Sends the same token as `X-Emby-Token`.
3. Sends an exact inclusive HTTP `Range` header derived from the requested half-open Swift range.
4. Requests identity transfer encoding so the response byte positions remain meaningful.
5. Requires HTTP 206 and a valid, matching `Content-Range`.
6. Treats the response's total length as authoritative for that read and updates `totalLength`.
7. Requires the response body to contain exactly the requested number of bytes.

HTTP 416 updates the known length from `Content-Range: bytes */length` when present and throws `unsatisfiableRange`. A mismatched range, a short response, a non-206 success response, or malformed range metadata also throws. The source never pads a missing tail with zero bytes.

The system session follows redirects. This unit does not add custom certificate handling. Moving Emby video reads to `URLSession` establishes the network-library side of the later shared certificate policy, but S1 through S3 and their user interface remain separate work.

External Emby subtitle sidecars are unchanged. `DeliveryUrl` values continue through the existing external subtitle path and do not use `EmbyMediaByteSource` in this unit.

## PlaybackFeature gate

`PlaybackLaunchRequest` has one public initializer and its first parameter is `MediaByteStreamHandle`. There is no public request initializer that accepts `URL`, and `PlaybackLaunching` no longer exposes `beginPlayback(for: URL)`.

The migration covers the MediaLibrary launch path, Source Directory playback, local and Photos resolution, SMB and WebDAV routes, Emby launch and queue paths, App composition, and existing test fixtures. Local sources continue to give PlaybackCore a file URL. Remote sources give it the loopback URL carried by the issued handle.

`Scripts/verification/verify_media_byte_stream_foundation.py` now checks the handle owner, the absence of the bare-URL PlaybackFeature entry, Emby's shared-endpoint routing, and Xcode and architecture input membership.

## Verification

### Toolchain

```text
Xcode 27.0
Build version 27A5237l
/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer
```

### Required visionOS build

The required command completed with exit status 0:

```text
xcodebuild build -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -quiet
```

The output contained the repository's existing SwiftLint and visionOS 27 deprecation warnings. It contained no build errors.

### Emby, handle gate, SMB and WebDAV tests

The focused visionOS Simulator run selected the new Emby and gate suites together with the required SMB and WebDAV suites:

```text
xcodebuild test -project Enchron.xcodeproj -scheme Enchron \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EnchronAppTests/SMBDataSourceAdapterTests \
  -only-testing:EnchronAppTests/WebDAVDataSourceAdapterTests \
  -only-testing:EnchronAppTests/EmbyMediaByteSourceTests \
  -only-testing:EnchronAppTests/PlaybackLaunchHandleGateTests \
  -quiet
```

The result bundle reports:

```text
totalTestCount: 17
passedTests: 17
failedTests: 0
skippedTests: 0
result: Passed
```

The result is recorded at:

```text
/Volumes/Cortisol/DevSpace/Xcode/DerivedData/Enchron-ehciyasfslulybcnvatkhsefkkbl/Logs/Test/Test-Enchron-2026.08.18_12-20-37-+0900.xcresult
```

The Emby test uses the real shared loopback endpoint with a `URLProtocol`-backed fake upstream. It verifies offset, suffix and open-ended tail reads, exact translated upstream ranges, replacement of a stale query token, propagation of the token header, response-authoritative length updates, and an error for an unsatisfiable range. The gate test issues one local-file handle and one endpoint route, constructs playback requests from both, and verifies their distinct issuance and openable URLs. The type of `PlaybackLaunchRequest.init(source:...)` is the compile-time proof that a bare URL cannot enter PlaybackFeature.

The same run kept all ten SMB tests and all four WebDAV tests green.

### PlaybackCore focused HTTP tests

From `Packages/PlaybackCore`, the three required filters passed:

```text
openedHTTPContextBoundsRangesAfterTheInitialRequest
sharedDemuxSourceOpensHTTPContainerOnceForAllReaders
httpPlaybackReadsTheWholeSourceWithoutStalling
```

They completed with three passes and no failures.

### PlaybackCore full baseline

PlaybackCore fixtures derive `TestMedia` from `#filePath`. This worktree is nested one directory deeper than the fixture assumption. As in Unit 1, one temporary `deletingLastPathComponent()` was added to each of the five fixture roots for the test run and removed afterward. No PlaybackCore source or test file remains changed.

The full run executed 201 tests and reproduced the established 13 issues in exactly these eight failing tests:

1. `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`
2. `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`
3. `controllerRejectsSecondOpenAndRecordsTheRejection`
4. `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition`
5. `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession`
6. `newerSeekSupersedesOlderSeekAndOwnsFinalTarget`
7. `controllerSeekKeepsSessionAndAdvancesStreamEpoch`
8. `rapidRelativeSeeksAccumulateInsideTheCore`

No new PlaybackCore failure was added.

### Structural checks

These checks passed:

```text
Scripts/verification/verify_media_byte_stream_foundation.py
swiftlint lint --strict Modules/Emby/EmbyMediaByteSource.swift Modules/MediaSource/MediaByteStreamHandle.swift Tests/EnchronApp/EmbyMediaByteSourceTests.swift Tests/EnchronApp/PlaybackLaunchHandleGateTests.swift
git diff --check
```

The four new files have zero strict SwiftLint violations. The architecture verification reports that MediaSource owns the handle and endpoint, Emby routes through the shared endpoint, PlaybackFeature has no bare-URL entry, and PlaybackCore has not acquired a MediaSource dependency.

## Limits of this unit

A real Emby server and its credentials are not available in this environment, so an Emby end-to-end playback run could not be performed. The local integration test exercises the complete byte path from a loopback playback URL through `MediaByteStreamEndpoint.shared` and `EmbyMediaByteSource` to a controlled HTTP response, but it cannot prove a particular server's redirect, authentication, certificate or media-container behavior.

This unit does not implement certificate trust work S1 through S3, unknown-length transfer M3, connection reuse M9, bridge cleanup M10, SMB pooling M11, or the repository-wide display-size separation in M12. Within the Emby source, server `Content-Range` values are authoritative at read time and unsatisfied or incomplete reads fail without zero filling.

`final-code.diff` contains the full repository diff from `a1298902`, excluding `final-code.diff` itself to prevent recursive content.
