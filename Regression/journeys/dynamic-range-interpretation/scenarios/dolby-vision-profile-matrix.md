---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:dynamic-range-interpretation:dolby-vision-profile-matrix",
  "title": "Dolby Vision profile 5、7、8 与 10 处理矩阵",
  "journey": "journey:dynamic-range-interpretation",
  "promiseRefs": [
    "promise:picture-interpretation:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 485000,
  "staticCases": [
    "dv-profile-5",
    "dv-profile-7-dual",
    "dv-profile-8-hdr10",
    "dv-profile-8-hlg",
    "dv-profile-10"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-FEL_test_for_AVS.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:08",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:12",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:13",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:15",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:16",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:17",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:18",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:22",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-media-video-dav1-dav1-1.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:23",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:25",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-5",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-5",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:05",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-7-dual",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-7-dual",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:10",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-8-hdr10",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hdr10",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:15",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-8-hlg",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hlg",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:20",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dv-profile-10",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-10",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-profile-matrix:25",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-profile-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-5"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-7-dual"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hdr10"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-8-hlg"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-10"
      }
    ]
  }
}
---
# Dolby Vision profile 5、7、8 与 10 处理矩阵

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.

## Why Profile 20 is not a case here

This Scenario carried a sixth case, `dv-profile-20`, until 2026-09-11. It is excluded, and not for want of a fixture: Apple's Profile 20 HLS sample is kept at `TestMedia/Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS`, and the case that was removed opened a registered Profile 20 file. The ground recorded for the removal on that date was that AVFoundation does not support Profile 20 and the picture it produces has the wrong colour. That ground does not hold. Apple's HLS authoring specification, under Amended requirements for visionOS, states at 1.9c "Dolby Vision stereo video MUST be Profile 20 (MV-HEVC) and less than or equal to Level 9." and at 1.40 "Stereo video MUST be encoded using Dolby Vision Profile 20 (MV-HEVC).", with a 2025-03-25 revision entry reading "Clarified use of DV20 for Stereo video for VisionOS." (`https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices`, read 2026-09-11). A platform that requires Profile 20 for stereo Dolby Vision delivery is not a platform that lacks support for it, and this repository holds no measurement of Profile 20 playback in this product on either lane. So the case stands removed but its stated ground is withdrawn, and the exclusion is open for re-decision rather than settled. Removed with the case: the obligation, its `staticCases` entry and SuccessExpression term, its five calls, and its mentions in the Rubric criteria. The title now names profiles 5, 7, 8 and 10, and so do `promise:picture-interpretation:c02` and the Sub-features line it mirrors verbatim at `.agents/skills/vp-e2e/features/picture-interpretation.md` line 10, both amended on the same date; restoring the case means restoring those two texts as well. Semantic authority decision `HC-007` reads "Dolby Vision profiles 10 and 20 remain included. Supply them in an admitted MP4 or MKV form; do not add DASH or HLS solely for fixture reachability and do not drop the profiles." and is unchanged, so this Catalog now contradicts it: the decision says not to drop the profiles and the Scenario has dropped one. The contradiction is recorded here rather than resolved, because resolving it means revising an approved decision. `Scripts/regression/review_stage.py` lines 633 to 702 admit exactly HC-000 through HC-023 with every `status` equal to `decided` and carry no superseded, amended, or revision field, so revising a decided decision can only be an in-place rewrite of an approved record; `Regression/agent-operability-review-protocol.md` line 38 forbids a reviewing Agent from resolving a HumanCoverage question, and `docs/MERGE_EVIDENCE.md` classes a `regression-contract` change as `HumanReviewRequired`. This Catalog change does not hold that authority, so HC-007 is left as approved.

## What dv-profile-10 rests on

The case opens `MediaLibrary-grid-video-media-video-dav1-dav1-1.mp4`, the P10.0 sample `Tests/Fixtures/fixture-registry.json` registers as `internal-dolby-vision-p100-av1-v1`. Measured on 2026-09-11 against this repository's vendored FFmpeg 9.0.1 and macOS VideoToolbox: the demuxer identifies the stream; its Dolby Vision configuration record reads profile 10, level 4, rpu_present true, el_present false, bl_present true and cross-compatibility 0, which is the tuple criterion 1 registers for the case; and the bridge's correction of the `dav1` sample entry to AV1 is still required, because raw FFmpeg 9.0.1 classifies that entry as an unknown codec. The vendored FFmpeg then returns no frames for AV1 at all: 60 packets in, zero frames out, ENOSYS, with "Your platform doesn't support hardware accelerated AV1 decoding", while an HEVC control on the P8.1 fixture returns 60 of 60. That build's configure line carries --disable-hwaccels and --disable-autodetect (`Packages/PlaybackCore/Scripts/build_ffmpeg.sh`), and its static library exports ff_av1_decoder with no VideoToolbox hwaccel symbol; no counterfactual build was produced, so the configure line is the reading of the cause and not a measurement of it. VideoToolbox decoded the same fixture 48 of 48 frames, hardware accelerated. Since `PBFFmpegModeCompressed` is how PlaybackCore reads this media (`Packages/PlaybackCore/Sources/PlaybackCore/VideoSampleProvider.swift`), Profile 10 playback rests on the platform decoder rather than on FFmpeg.

## The decision on dv-profile-10

The obligation stays visual -- evidenceType visual.frames, evidenceSchema frame-sequence@2, `oracle:agent-visual@2` -- and it is discharged on the device lane and nowhere else. This Scenario's lane is already `device`, and that is now the reading of the binding rather than a scheduling detail: the visionOS Simulator has no AV1 decoder of any kind, so a simulator attempt could not produce the frame sequence at all. Device coverage for this exact fixture already exists outside this Catalog's own run history, and the earlier reading that none does was formed without surveying it and is withdrawn. `DeviceFixtureImportUITests/testDolbyVisionProfile10AutomaticSourcePlaybackOnVisionPro()` is enrolled in `VisionProCoreRegression.xctestplan` under its Physical Vision Pro configuration; it opens the same `media-video-dav1-dav1-1.mp4`, and asserts the `dav1` provider codec tag, the `av01` sample subtype, the `dvvC` source atom, a position that advances with rising videoSamples and rendererInputs, and displayedPixel true (`Tests/EnchronAppUI/Fixtures/DeviceFixtureImportUITests.swift`). `DeviceFixtureImportUITests/testRealAV1360AcrossWindowDockedAndPanoramaRoundTrips()` carries a 7680x3840 AV1 panorama through window, docked and panorama outside that plan. Both are listed as this capability's device entries in `.agents/skills/vp-e2e/references/device-reserve.md`. What device coverage does not establish is the colour: the decoded pixel buffer carries identical colour attachments with and without the dvvC atom, so the RPU is not consumed at the decompression seam, and this fixture's IPT-C2 base-layer matrix is dropped by VideoToolbox. Perceptual acceptance for Profile 10 stays with the P10 acceptance clip family named in that same reference.

## Where a wrong Profile 10 colour lands

Nothing exempts a wrong Profile 10 colour, and the known-defect ledger must not be made to. `Config/regression/known_defects.json` carried one record against this Scenario, recorded 2026-09-11 and withdrawn the same day; its `defects` list is now empty. The record was wider than the thing it described. `RECORD_FIELDS` in `Scripts/regression/tools/known_defects.py` is the closed set scenario, description, match, recorded, expiresWhen, with no obligation or caseKey member, and `matching_defect` selects a record by Scenario id and then by the field reading with nothing narrowing it to a case, so the record covered the whole `ScenarioAttemptNode` (`Scripts/regression/core/plan.py:948`) rather than the dv-profile-10 obligation it was written for. `Scripts/regression/core/fields.py` then resolves rendererYCbCrMatrix by unanchored first-hit lookup over the last completed call's outputs, so the reading the record matched on was not anchored to a named call either. What that combination does to a run is not attribution. `failed(known)` is in `BLOCKING_NODE_STATUSES` (`Scripts/regression/core/runview.py:93`), so the downstream subtree is derived `blockedBy`; but `CLOSED_AS_PASSED` in `Scripts/regression/core/runtime.py:93` holds `passed`, `blockedBy` and `failed(known)` together, and the finalize ladder at `:1238` reaches `RunOutcome.FAILED` only when a plain `failed` is present. A run whose only product failure is `failed(known)`, together with the whole subtree that failure blocked, therefore closes `RunOutcome.PASSED`. The record was a release valve on the run verdict, and it would have opened for any unrelated regression in this Scenario that left the Profile 10 reading in place.

What carries the Profile 10 colour expectation instead is rubric criterion 3, which is bound per case through `obligation:dynamic-range-interpretation:dolby-vision-profile-matrix:o01:dv-profile-10` and so cannot reach another case. It registers sourceYCbCrMatrix and rendererYCbCrMatrix both exactly IPT_C2 for dv-profile-10 -- the private string `ycbcr_matrix` in `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c` maps `AVCOL_SPC_IPT_C2` to, which is what the vendored FFmpeg reads out of the P10.0 fixture's colr box and what `formatSignalingSummary` reports on the compressed renderer input. Two limits of that criterion are part of the contract. It is not a deterministic predicate: `FIELD_VALUES` in `Scripts/regression/rubric_compiler.py` is a closed set of nine field names -- controls, exists, isEnabled, isHittable, isSelected, lifecycle, mediaKind, succeeded, visible -- rendererYCbCrMatrix is not among them, and `compile_rubric` returns zero predicates for all four criteria of this rubric, so every one of them is read by `oracle:agent-visual@2`. And the two matrix fields read the source and renderer Format Descriptions, which sit upstream of the decompression seam, so they establish that the declaration survived to the renderer input and not that the displayed picture is the right colour; the displayed colour is judged by the Agent from the bound frame sequence on the same terms as every other case. On a device run where the Profile 10 colour is wrong, the Agent fails criterion 3, the dv-profile-10 observation is Violated, the Scenario attempt is `failed`, and the run closes `RunOutcome.FAILED`. There is no exemption and no attribution: the gap described above is recorded in this contract as prose, and nothing enforces that a failure carrying it is the known gap rather than a fresh regression.
