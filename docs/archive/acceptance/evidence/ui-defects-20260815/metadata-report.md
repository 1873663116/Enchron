# Player Controls Deck metadata truncation report

## Result

Commit `8b768d1` fixes the metadata-row width allocation in `Modules/PlaybackPresentation/Views/PlaybackPanel.swift`. The right technical specification keeps its trailing alignment and can use the space that the left label does not need. The commit does not change `DesignTokens`, action closures, seek callbacks, or any file outside `PlaybackPanel.swift`.

## Confirmed mechanism

The media-information well is 440pt wide. Its 24pt horizontal padding on both sides leaves 392pt for the metadata row. The former `HStack` also reserved a 24pt gap, then gave both `Text` views `.frame(maxWidth: .infinity)`. SwiftUI therefore proposed `(392 - 24) / 2 = 184pt` to each text. The left `Flat · Mono` label could not release its unused share to the right label.

The right label first used `.minimumScaleFactor(0.75)` inside that 184pt allocation. If the scaled text still exceeded the allocation, `.lineLimit(1)` truncated it. The scale and ellipsis were consequences of the equal-width frames, not of the 440pt well being too narrow for the reported Dolby Vision string.

## Fix

`PlaybackMediaMetadataRow` now contains two naturally sized `Text` views with `Spacer(minLength: DesignTokens.Spacing.xl)` between them. The spacer expands when the row has spare width, so the left text stays at the leading edge and the right text stays at the trailing edge. The 24pt minimum gap remains unchanged.

The technical label has `layoutPriority(1)`. When the labels compete for width, SwiftUI allocates the technical label before the spatial label. This choice favors the specification that exposed the defect. A string that is wider than the whole row can still truncate, but it stays at the metadata font size.

The commit extracts only this row and adds one `#Preview` at the production 440pt well width. The preview covers a short specification, the exact Dolby Vision Profile 5 specification from the defect, and a synthetic string that exceeds the container.

## Text-length evidence

An Xcode code snippet measured the intrinsic one-line sizes with `DesignTokens.Typography.metadata.monospacedDigit()` on the visionOS 27.0 `Apple Vision Pro` simulator. Each measured text was 14.5pt high.

| Case | Spatial width | Technical width | Required width with 24pt gap | Result in 392pt |
| --- | ---: | ---: | ---: | --- |
| Short: `1920×1080 · SDR · H.264` | 66.5pt | 155.5pt | 246.0pt | Fits with 146.0pt spare. The spacer places the labels at opposite edges. |
| Defect: `3840×2160 · Dolby Vision Profile 5 · HEVC · 24 fps` | 66.5pt | 301.0pt | 391.5pt | Fits at full size with 0.5pt spare. No scale or truncation is needed. |
| Synthetic overflow | 66.5pt | 929.5pt | 1020.0pt | Exceeds the row by 628.0pt. The single-line text truncates at full font size. |

The running DesignPreview app also displayed its short 440pt row with the two labels at the opposite edges in the simulator. This observation does not substitute for the failed canvas snapshot of the Dolby case.

## `minimumScaleFactor` conclusion

The row no longer uses `.minimumScaleFactor(0.75)`. After the width allocation is fixed, the reported Dolby Vision string needs 391.5pt and the row provides 392pt. Retaining the scale factor would only shrink genuinely oversized strings before truncation and would hide future width-allocation defects. The synthetic overflow preview keeps that boundary visible.

## Action-closure judgment

The closure rewrites in `prior-attempt.patch` were not required. Before any source edit, the beta5 `DesignPreview` scheme built successfully with method references such as `action: toggleSettings`, `onSeekBegan: beginTimelineSeek`, and `onSeekEnded: commitTimelineSeek`. The minimal metadata-only change then built successfully in both `DesignPreview` and the `Enchron` App scheme without those rewrites. No compiler diagnostic reported a function-conversion or actor-isolation constraint. The commit omits every closure rewrite.

## Verification and limits

The active developer directory was `/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer`, which reports Xcode 27.0 build `27A5237l`.

The unmodified baseline `DesignPreview` scheme built successfully through the Xcode IDE build tool in 31.605 seconds. The modified scheme built successfully in 31.478 seconds. The final `Enchron` App build used the explicit arm64 simulator destination and exited with status 0:

```text
DEVELOPER_DIR=/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer \
xcodebuild -quiet -project Enchron.xcodeproj -scheme Enchron \
  -configuration Debug \
  -destination 'platform=visionOS Simulator,id=65A9A16C-CB84-4737-93DB-C93A01FDDB9C' \
  -derivedDataPath /Volumes/Cortisol/DevSpace/Xcode/DerivedData/Enchron-wt-deck-metadata \
  CODE_SIGNING_ALLOWED=NO build
```

`git diff --check` passed. The committed diff contains only `Modules/PlaybackPresentation/Views/PlaybackPanel.swift`. `prior-attempt.patch` was deleted before the commit.

A generic simulator build also tried to compile the third-party `RealityKitScriptingMacros` target for x86_64 and failed there with exit 65. The explicit arm64 simulator build passed afterward. The x86_64 failure did not report a diagnostic in `PlaybackPanel.swift`.

Xcode's `RenderPreview` tool did not deliver a canvas snapshot. One attempt timed out while launching `DesignPreview.app` after 15 seconds. After the simulator booted, the preview process launched but the preview update exceeded the tool's fixed 5-second limit. The retained `#Preview` is build-verified, but the Dolby and synthetic preview pixels were not captured.

No physical Vision Pro command, build destination, installation, launch, screenshot, or recording was used. This report does not claim wearer-visible acceptance on hardware.
