# FFmpeg 9.0.1 HTTP reuse and HEVC configuration report

## Result

PlaybackCore now gives FFmpeg's HTTP protocol the options required to reuse one authenticated media connection while the MOV demuxer seeks between the file head and its tail metadata. The remote-open acceptance probe still makes two successful media requests, but those requests now share one TCP connection.

`AV_PKT_DATA_HEVC_CONF` was evaluated and deliberately not added to the bridge. It carries the decoder configuration for a Dolby Vision enhancement layer. PlaybackCore currently sends one decoded base-layer stream to VideoToolbox and builds that stream's `CMFormatDescription` from `AVCodecParameters.extradata`. Substituting enhancement-layer configuration would describe the wrong decoder input.

## Measured behavior

The measurements below came from `Scripts/verification/measure-remote-media-open.py` and its local authenticated range-serving HTTP server. The media fixture was `HNVR-158_H_4096p_8K_LR_180_clip.mp4`.

| Open measurement | Before | After |
| --- | ---: | ---: |
| Successful media requests | 2 | 2 |
| Media TCP connections | 2 | 1 |
| Media bytes read | 137,484 | 137,484 |
| Wire requests, including the 401 challenge | 3 | 3 |
| Wire TCP connections, including the 401 challenge | 3 | 2 |

Before, the successful ranges were `bytes=0-` and `bytes=110201178-110305893`. After, they were `bytes=0-131071` and `bytes=110201178-110305893`. The final acceptance command asserted both numbers and exited successfully:

```sh
python3 Scripts/verification/measure-remote-media-open.py \
  --scratch-path /Volumes/Cortisol/DerivedData/Enchron-http-reuse-hevcconf-after-probe \
  --expect-requests 2 \
  --expect-connections 1 \
  --json
```

The playback mode exercises the same source beyond header parsing.

| Playback measurement | Before | After |
| --- | ---: | ---: |
| Successful media requests | 3 | 4 |
| Media TCP connections | 3 | 1 |
| Playback bytes | 110,296,464 | 110,305,218 |
| Delivered media seconds | 60.026633 | 60.026633 |
| Read to source rate ratio | 0.9999145 | 0.9999939 |

The extra playback request is the cost of bounding the initial response. After the tail-header seek, FFmpeg reads `bytes=676-131747`, then continues with `bytes=131748-110305893`. Both requests stay on the same media connection. I left `request_size` unset because applying the bound to normal playback would force the full file into repeated fixed-size requests without evidence that such a request rate is desirable.

## HTTP option placement and size

The bridge passes `seekable=1`, `multiple_requests=1`, `initial_request_size=131072`, and `short_seek_size=131072` in the dictionary supplied to `avio_open2`. They must be present before `avio_open2` establishes the HTTP connection. Setting them afterward on the `AVIOContext`, as the bridge does for `end_offset`, is too late for FFmpeg's HTTP open state.

For this authenticated probe, forcing `seekable=1` is necessary because the first response is the 401 challenge and has no `Content-Range`. Without the option, FFmpeg disables its initial bounded-request state before it receives the authenticated 206 response.

The 128 KiB value comes from the actual acceptance workload. FFmpeg's AVIO buffer and generic short-seek unit are both 32 KiB, while the fixture's tail header occupies 104,716 bytes. Four 32 KiB units are the smallest whole-unit value that contains it. A 32 KiB trial reused the connection but split the tail header and raised the open request count from two to three. The final value keeps two open requests and one connection.

The verification script gained `--expect-requests` and `--expect-connections`, so the measured acceptance contract is executable instead of depending on inspection of JSON output. The HTTP range tests also assert the bounded first request and the two ranges used when demuxing returns from the tail to the first sample.

## Why `AV_PKT_DATA_HEVC_CONF` was declined

FFmpeg 9.0.1 documents `AV_PKT_DATA_HEVC_CONF` as a raw ISO/IEC 14496-15 `HEVCDecoderConfigurationRecord` parsed from an ISOBMFF `hvcE` box or the corresponding Matroska `BlockAdditionMapping`. FFmpeg's `dovi_split` bitstream filter installs it as the enhancement layer's extradata, then removes the side data because it no longer applies after the split.

That is different from every HEVC configuration the bridge currently needs for a `CMFormatDescription`:

- The base video layer uses `AVCodecParameters.extradata`, normally the `hvcC` record.
- MV-HEVC metadata uses the source `lhvC` atom path already present in the bridge.
- Missing base-layer configuration is reconstructed from base-layer packet parameter sets.
- Dual-layer Dolby Vision is intentionally exposed as its decodable HDR10 base layer because PlaybackCore does not split and decode the enhancement layer.

Reading `AV_PKT_DATA_HEVC_CONF` would therefore add no information to the existing base-layer format description. Using it as `hvcC` would be incorrect. It should be adopted only with a future enhancement-layer split and decode path, where it would configure that second decoder input.

## macOS verification

The prechange baseline and final suite used `swift test` inside `Packages/PlaybackCore`, with scratch directories under `/Volumes/Cortisol`. Both runs executed 198 Swift Testing tests and ended with the same nine failed test names and 14 issues. The runner also printed the same pre-existing XCTest bundle architecture warning in both runs. No new failing test remained after the HTTP assertions were updated.

The nine baseline and final failures were:

- `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat()`
- `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC()`
- `controllerRejectsSecondOpenAndRecordsTheRejection()`
- `controllerSeekKeepsSessionAndAdvancesStreamEpoch()`
- `dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals()`
- `newerSeekSupersedesOlderSeekAndOwnsFinalTarget()`
- `rapidRelativeSeeksAccumulateInsideTheCore()`
- `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition()`
- `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession()`

`swift build --scratch-path /Volumes/Cortisol/DerivedData/Enchron-http-reuse-hevcconf-after-build` passed. The focused tests `openedHTTPContextBoundsInitialAndLaterRequests()` and `sharedDemuxSourceOpensHTTPContainerOnceForAllReaders()` also passed.

The evidence is stored in `/Volumes/Cortisol/DerivedData/Enchron-http-reuse-hevcconf-evidence/`, including the before and after probe JSON, build log, focused test logs, and full test logs. Per the task constraints, no visionOS simulator suite or physical Vision Pro lane was used, and FFmpeg was not rebuilt.

Before capturing the baseline, I found the ignored FFmpeg bundle contents one level above the `PlaybackFFmpeg.xcframework` directory expected by SwiftPM. I moved those already-built files into the expected ignored directory. This local dependency-layout repair is not tracked or included in the commit.
