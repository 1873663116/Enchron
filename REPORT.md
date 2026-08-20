# Playback stop teardown report

## Result

The playback teardown path now stops audible output before the player presentation disappears, interrupts a blocked FFmpeg HTTP read before `closeAndWait()` waits for in-flight work, and prevents a cancelled or stale network retry from reopening playback after Back.

## Changes

- `PlaybackRuntime.beginStop` calls the new synchronous `PlaybackCoreController.hush()` operation on the active, departing, and prepared technical-session controllers before it creates the asynchronous close task or clears presentation state.
- `SampleBufferPlaybackSession` owns the hush operation and still records the stop as a close timeline event. Direct session close also hushes before the rest of cleanup.
- `PlaybackCoreController.close()` and `closeAndWait()` interrupt the current session's byte source before cleanup begins or any seek, format, or subtitle task is awaited. The existing task cancellation and await order is unchanged.
- `FFmpegDemuxSession` uses a narrow source-pointer lock for interruption. It does not wait for the operation lock that may be held by a blocked seek.
- `PBFFmpegDemuxSourceInterrupt` sets terminal and active atomic interrupt flags and broadcasts the demux condition variable without acquiring the demux mutex or joining its read thread. A concurrent seek cannot clear the terminal close interruption. Seek and destroy retain their existing transient read-thread stop behavior before close.
- `PlaybackLaunchCoordinator.retry` checks cancellation and launch generation before the delay, after the delay, and after `waitForConnection`, before it can call `playbackRuntime.open`.
- Regression coverage now includes an immediate controller hush check, a loopback HTTP response that blocks until demux interruption cancels the read, and the coordinator retry validity predicate.

## Verification

The required simulator build passed:

```text
xcodebuild build -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -quiet
Result: PASS
```

The build emitted the repository's existing SwiftLint and Apple API deprecation warnings. It emitted no build error.

The `PlaybackCore` Xcode scheme is not configured for the test action:

```text
xcodebuild test -project Enchron.xcodeproj -scheme PlaybackCore -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
Result: NOT RUN, xcodebuild exit 66: Scheme PlaybackCore is not currently configured for the test action.
```

I therefore used the in-repository package test path under `Packages/PlaybackCore`, as allowed by the task:

```text
cd Packages/PlaybackCore
swift test
Before change: 201 tests in 3 suites, 75 issues.
After change: 203 tests in 3 suites, 75 issues.
Result: the suite retains its baseline failures and added no new issue.
```

Both new PlaybackCore regressions passed in the full run:

```text
controllerHushStopsTheTimelineWithoutClosingTheSession: PASS
interruptingDemuxSourceAbortsBlockedHTTPRead: PASS
```

They also passed when run alone. The loopback interruption check completed in 0.005 seconds in the final targeted run.

The coordinator retry test compiled for the visionOS Simulator target:

```text
swift build --build-tests --triple arm64-apple-xros27.0-simulator
Result: PASS
```

SwiftPM could not execute that bundle directly because its test helper is a macOS process and rejects a visionOS Simulator Mach-O bundle. The `PlaybackFeature` Xcode scheme also has no test action. The production coordinator code compiled in the required Enchron simulator build, and the pure retry predicate compiled in the simulator test bundle.

`git diff --check` passed.

## Pre-existing PlaybackCore failures

The final package run reported the same 75 issue count as the pre-change baseline. The failures below are the complete final list. The media bridge failures are caused by unavailable external `TestMedia` paths or AVFoundation fixture loading in this worktree. The remaining failures are existing platform-assumption or timing-sensitive tests. Neither new regression appears in this list.

- `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim`
- `apmpWideProviderPreservesUniqueSourcePayloadAndLensMetadata`
- `appleAPACHLSKeepsItsCompressedPacketsAndConfiguration`
- `appleAudioRendererAcceptsTheCompressedAudioCapabilitySet`
- `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`
- `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`
- `cameraOriginalMVHEVCPreservesItsCompleteSourceDecoderConfiguration`
- `controllerRejectsSecondOpenAndRecordsTheRejection` with 2 issues
- `controllerSeekKeepsSessionAndAdvancesStreamEpoch` with 2 issues
- `damagedTransportStreamAACSkipsInvalidPacketsAndProducesAudio`
- `dolbyDigitalPlusAtmosKeepsItsSixChannelCompressedLayout`
- `dolbyVisionFixturesPreserveConfigurationAtomsAndCompressedSamples` with 3 parameterized issues
- `dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals`
- `equirectangularSourceFormatIncludesItsKnownHorizontalFieldOfView`
- `generatedAV1AndFLACFixtureKeepsBothTracksCompressed`
- `generatedAudioCodecMatrixProducesEveryRegisteredAudioFormat` with 3 issues
- `generatedVideoOnlyFixtureHasNoAudioTracks`
- `highEfficiencyAACProfilesKeepTheirCoreAudioFormat` with 4 parameterized issues
- `httpPlaybackReadsTheWholeSourceWithoutStalling`
- `missingAV1ExtradataIsBootstrappedFromSphericalFixtureBitstream`
- `missingFirstDisplayedFrameFailsWithoutGuessingTheCause`
- `mvhevcClassificationFallsBackToMonoWhenDeliveredDescriptionHasNoLhvC`
- `mvhevcProviderPreservesUniqueSourceOnlyLhvCPayloadAndStereoMetadata`
- `newerSeekSupersedesOlderSeekAndOwnsFinalTarget` with 2 issues
- `nonSquarePixelStereoFixtureCarriesItsDisplayGeometryThroughTheBridge`
- `officialAppleProjectedMediaKeepsItsSourceProjectionKind`
- `officialProResCameraOriginalsDoNotRequireCodecExtradata` with 2 parameterized issues
- `openedHTTPContextBoundsRangesAfterTheInitialRequest`
- `opusUsesPacketTimingInsteadOfClaimingAFixedFrameCount` with 2 issues
- `proRes422And4444FixturesCreateCompressedSamples` with 6 parameterized issues
- `proResCameraOriginalKeepsFiveChannelPCMAsSourcePCM` with 3 issues
- `proResTransparencyPCM16LEProducesLinearPCMSamples`
- `profile10Dav1FixtureCreatesCompressedAV1SamplesWithDolbyVisionConfiguration`
- `profile10Dav1ProviderKeepsAV1SampleSubtypeCompatible`
- `profile10PointOnePreservesStaticHDRMetadataInItsFormatDescription`
- `profile20KeepsDolbyVisionAndMultiviewHEVCSignalsTogether`
- `profile5BridgeMatchesAVFoundationDolbyVisionDecoderConfiguration` with 3 parameterized issues
- `profile7SourcesDeliverDecodableBaseLayerSamples`
- `rapidRelativeSeeksAccumulateInsideTheCore` with 2 issues
- `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition`
- `retiredMPEG4Part2CodecIsRejectedByPlaybackCore`
- `sharedDemuxSourceOpensHTTPContainerOnceForAllReaders`
- `sourceOnlyDolbyConfigurationDoesNotReplaceBridgeFormat`
- `sourcePCMIsNotReportedAsAnFFmpegDecodePath`
- `sourceReadMonitorCountsMediaInformationReads`
- `sourceReadMonitorCountsSharedDemuxReads`
- `suppliedAssetWithDifferentDecoderConfigurationKeepsBridgeFormat`
- `suppliedAssetWithMultipleMatchingVideoFormatsKeepsBridgeFormat`
- `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession` with 2 issues
- `vrAndDolbyFixturesCreateCompressedSamplesThroughFFmpegBridge`
- `xHEAACMatchesAVFoundationsCompressedFormatDescription`
- `xHEAACWithLoudnessInfoRemainsADemuxOnlyPath`

## Not verified

I did not claim physical audio silence from simulator or unit-test results. A real Vision Pro with an accessible remote Emby source is required to verify the wearer-observed audio cutoff and the complete Back interaction. No physical-device session with that source was available for this change.
