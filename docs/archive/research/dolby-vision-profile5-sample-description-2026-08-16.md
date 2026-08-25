# Dolby Vision Profile 5 colour defect

## Root cause

PlaybackCore did produce `kCMVideoCodecType_DolbyVisionHEVC` and a `dvcC` atom for the three local Profile 5 subjects. It did not silently reduce those files to plain HEVC. The `hvcC` and `dvcC` payloads produced by the bridge were also byte-for-byte equal to the payloads AVFoundation parsed from each same file. This disproves the initial `hvcC` lead for Profile 5 itself.

The defect was in the sample-description envelope around those correct atoms. `create_dolby_vision_format` built an ISO/MP4 `dvh1` sample entry, then passed `NULL` as the `CMImageDescriptionFlavor` to `CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData`. CoreMedia defines `NULL` as QuickTime Movie flavor. AVFoundation's format for the same MP4 contained `kCMFormatDescriptionExtension_VerbatimISOSampleEntry`; the bridge format instead contained `kCMFormatDescriptionExtension_VerbatimSampleDescription` and no verbatim ISO sample entry.

The resulting path was:

```text
MP4 dvh1 + hvcC + dvcC
            |
            v
correct Dolby atom payloads inside a QuickTime-flavor description
            |
            v
Apple does not receive the native ISO-family Dolby Vision sample entry
            |
            v
Profile 5 IPT-PQ-C2 base picture can be interpreted as ordinary HEVC YCbCr
```

Profile 5 has no conventional fallback picture, so losing the ISO-family Dolby Vision interpretation exposes its IPT-coded base picture to the wrong colour interpretation. That is the mechanism for the gross hue error.

The fix passes `kCMImageDescriptionFlavor_ISOFamily`. After the change, the bridge format contains `VerbatimISOSampleEntry`, contains no QuickTime `VerbatimSampleDescription`, remains `kCMVideoCodecType_DolbyVisionHEVC`, and retains byte-identical `hvcC` and `dvcC` payloads relative to AVFoundation.

## Atom-level evidence

The new `profile5BridgeMatchesAVFoundationDolbyVisionDecoderConfiguration(relativePath:)` regression covers:

- `HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4`
- `UHD/Patterns_Of_Nature_DoVi_24_P5_UHD_HEVC-10mbps_DD+JOC-768kbps_iOS.mp4`
- `Dolby Vision Profile 5_8.1 Test/CM4_L3L8_Test_with_CM29_fallback_IPT_P5.mp4`

Before the production change, all three cases proved that the subtype was Dolby Vision HEVC and that both `hvcC` and `dvcC` matched AVFoundation. All three then failed because the bridge had no `VerbatimISOSampleEntry`; all three also had the unwanted QuickTime `VerbatimSampleDescription`. The run failed with six issues. After selecting ISO family flavor, all three cases passed.

This test compares format descriptions built independently by PlaybackCore and AVFoundation from the same files. It does not rely on a screenshot or subjective colour judgment.

## Existing dvh1 failure

The pre-existing `dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals` failure was real but separate from the Profile 5 root cause. Its Apple multiview fixture has no usable Dolby Vision configuration. The bridge correctly falls back to ordinary HEVC, but `formatByPreservingSourceSignals` replaced AVFoundation's 175-byte `hvcC` with the bridge reconstruction's 229-byte `hvcC` while preserving the source `lhvC`. That made the final pair internally inconsistent and caused the stated assertion failure.

The fix keeps AVFoundation's same-file `hvcC` and `lhvC` together while removing only `dvcC` and `dvvC` for the intentional HEVC fallback. It does not relax matching for caller-supplied assets or unrelated sources.

## Baseline and validation

The first unmodified macOS run used:

```text
arch -arm64 swift test --scratch-path /Volumes/Cortisol/SwiftScratch/Enchron-dolby-profile5-baseline
```

It ran 198 tests and reproduced the expected nine failing tests: the two missing Apple fixture tests, the macOS platform-expectation test, the `dvh1` atom test, the rapid-subtitle-seek test, and four playback seek tests. The run reported 14 issues. A subsequent `--skip-build` enumeration run also exposed the already unstable `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` timeout, so that extra failure is treated as baseline noise rather than a regression from this change.

The focused Dolby Vision and MV-HEVC run executed nine selected tests, including three argument cases for the new Profile 5 regression; all passed. The final full macOS run executed 199 tests. The new Profile 5 regression and the formerly failing `dvh1` test passed. Eight baseline failures remained and the issue count fell from 14 to 13, exactly accounting for the repaired `dvh1` assertion. An independent `arch -arm64 swift build --scratch-path /Volumes/Cortisol/SwiftScratch/Enchron-dolby-profile5-build` completed successfully. Existing SDK deprecation warnings remain unchanged.

## Validation boundary

This work used the PlaybackCore macOS lane and local media fixtures only. It did not run the visionOS simulator suite or use a physical Vision Pro. The evidence proves the format-description mechanism and regression behavior; it does not claim wearer-visible pixel acceptance.
