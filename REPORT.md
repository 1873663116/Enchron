# Media Byte Stream foundation report

## Result

This unit moves the loopback HTTP byte endpoint from `MediaLibrary` to `MediaSource` and makes it a single app-wide instance. SMB and WebDAV now implement the new byte-source protocol and register routes on that endpoint. Local file playback and Emby playback keep their previous URL paths, and PlaybackCore still receives only an openable `URL`.

The authority and implementation are recorded in these commits before the delivery artifacts:

- `5ea02e9f docs: record media byte stream refactor authority`
- `beeedd20 refactor: centralize remote byte streaming in MediaSource`

The comparison base is `a1298902df818d7e192bf3fbaedda542607c55bf`.

## Implementation

`Modules/MediaSource/MediaByteStream.swift` now owns both the source contract and the HTTP endpoint.

| Contract member | Type | Meaning in this unit |
|---|---|---|
| `totalLength` | `Int64?` | A finite byte count or `nil` when the source cannot report one. The endpoint rejects `nil` until M3 adds unknown-length transfer. |
| `seekability` | `MediaByteSourceSeekability` | Distinguishes sequential and random-access sources. This endpoint currently accepts random access only. |
| `liveness` | `MediaByteSourceLiveness` | Distinguishes finite and live sources without making callers infer that fact from a URL. |
| `suggestedBufferDepth` | `MediaByteBufferDepth` | Carries no-buffer, automatic, or byte-count guidance. SMB and WebDAV preserve the former 1 MiB bounded read size. |
| `read(in:)` | `Range<Int64> -> Data` | Reads the requested half-open byte range. |

`MediaByteStreamEndpoint.shared` has a private initializer, starts one loopback `NWListener`, and gives each registered source a UUID route on the listener's port. A `MediaAccessLease` owns each route. Releasing the lease unregisters only that route, cancels its active connections and reads, waits for those reads to finish, and then runs source-specific cleanup. This preserves SMB's requirement to disconnect its playback connection after server work has stopped.

The endpoint retains the existing GET, HEAD, bounded-read, open-ended range, suffix range, 416 response, and `Connection: close` behavior. M3 and M9 remain separate work, so this unit does not add chunked unknown-length responses or connection reuse.

The old `Modules/MediaLibrary/Services/HTTPRangeStreamingServer.swift` was deleted. Xcode project membership and `Config/design_source_architecture_inputs.xcfilelist` now point to the MediaSource file. `Scripts/verification/verify_media_byte_stream_foundation.py` checks that ownership and routing remain in place and that MediaLibrary and PlaybackCore do not acquire the wrong dependencies.

## Source routing after this unit

| Source | Playback URL after this unit | Lifecycle |
|---|---|---|
| Local file | Original file URL | Unchanged and does not enter the loopback endpoint. |
| SMB | Route on `MediaByteStreamEndpoint.shared` | Still opens a separate playback `SMB2Manager`; its route lease disconnects that manager after active reads stop. M11 was not implemented. |
| WebDAV | Route on `MediaByteStreamEndpoint.shared` | The existing `URLSession`, authorization header, exact 206 validation, and ranged reads remain unchanged. |
| Emby | Existing `source.directPlayURL` | Unchanged. FFmpeg still opens the remote HTTP URL directly in this unit. |

`ResolvedMediaSource` remains the handoff boundary. MediaLibrary passes its URL and access lease through the existing playback launch path. PlaybackCore does not import MediaSource and does not see `MediaByteSource`.

## Verification

### Required visionOS build

The required command completed with exit status 0:

```text
xcodebuild build -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -quiet
```

The output contained the repository's existing SwiftLint and visionOS 27 deprecation warnings. It contained no build errors.

### MediaSource, SMB, and WebDAV tests

The focused Simulator run used the Enchron scheme with parallel testing disabled and selected `SMBDataSourceAdapterTests` and `WebDAVDataSourceAdapterTests`. Its result bundle reported:

```text
totalTestCount: 14
passedTests: 14
failedTests: 0
skippedTests: 0
result: Passed
```

The result is recorded at:

```text
/Volumes/Cortisol/DevSpace/Xcode/DerivedData/Enchron-ehciyasfslulybcnvatkhsefkkbl/Logs/Test/Test-Enchron-2026.08.18_11-40-11-+0900.xcresult
```

The ten SMB/byte-stream tests include the protocol fake served through the migrated endpoint. They verify requested offset and length, response `Content-Length`, bounded reads, open-ended ranges, suffix ranges, HEAD without a source read, route-release cancellation, and the shared instance and shared listener port. The four WebDAV tests verify authenticated browsing, the ranged request made through the resolved loopback URL, lease survival after browsing disconnect, and authentication rejection.

A later repeat reached Xcode's test action but failed to materialize an `xctest` worker on the already booted Simulator. No test process started. The completed 14-test result above is the execution evidence; the repeated worker-start failure was not counted as a test result.

### PlaybackCore range tests

The PlaybackCore HTTP tests completed separately with three passes and no failures:

```text
openedHTTPContextBoundsRangesAfterTheInitialRequest
sharedDemuxSourceOpensHTTPContainerOnceForAllReaders
httpPlaybackReadsTheWholeSourceWithoutStalling
```

### PlaybackCore baseline comparison

PlaybackCore test fixtures derive `TestMedia` from `#filePath`. This nested worktree adds one path component, so each of the five fixture roots received one temporary `deletingLastPathComponent()` during the runs. Those changes were removed afterward, and no PlaybackCore test or production file is present in the branch diff.

The baseline at `a1298902` ran 201 tests and produced 13 issues in these eight failing tests:

1. `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`
2. `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`
3. `controllerRejectsSecondOpenAndRecordsTheRejection`
4. `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition`
5. `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession`
6. `newerSeekSupersedesOlderSeekAndOwnsFinalTarget`
7. `controllerSeekKeepsSessionAndAdvancesStreamEpoch`
8. `rapidRelativeSeeksAccumulateInsideTheCore`

The post-change full run reproduced all eight names. Under the concurrent machine load it also timed out once in `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim`, for 14 issues. That test passed immediately when run by itself. Base commit `a1298902` is titled `Record the ProRes timeout as a flake under load` and records the same ninth failure followed by clean eight-failure reruns. The branch does not change any file under `Packages/PlaybackCore/Sources` or its package manifest. The focused HTTP tests all passed, so the migration adds no persistent PlaybackCore failure.

### Structural checks

These checks passed:

```text
Scripts/verification/verify_media_byte_stream_foundation.py
swiftlint lint --strict Modules/MediaSource/MediaByteStream.swift
git diff --check
```

The new Swift file has zero strict SwiftLint violations. The repository's design-source architecture check also passed after the Xcode input list was migrated.

The broader existing `verify_package_membership.py` proceeds through that architecture check and then reports two unrelated existing exception-list entries as missing: `PlaybackFeature/Model/UnmetCapability.swift` and `PlaybackPresentation/Model/PlaybackPanelExpansion.swift`. This unit does not modify either file. The required Enchron build passes with the current project membership.

## Deferred work

Unit 2 still needs to implement the Emby `MediaByteSource`, preserve its token and redirect behavior through the system network client, and replace `source.directPlayURL` with a route from `MediaByteStreamEndpoint.shared`. PlaybackCore must continue to receive only the resulting openable URL.

This unit intentionally leaves M3 unknown-length chunked transfer, M8's typed PlaybackFeature gate, M9 connection reuse, M10 bridge cleanup, M11 SMB connection pooling, and M12 authoritative read-time length handling for their planned units.

`final-code.diff` contains the full repository diff from `a1298902`, excluding the diff file itself to avoid recursive content.
