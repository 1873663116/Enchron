# Dolby Vision Profile 7 AVFoundation experiment

## Finding

Dolby Vision Profile 7 dual-layer HEVC is not natively supportable through PlaybackCore's AVFoundation decode contract on the tested Apple stack. CoreMedia accepted a Profile 7 `dvcC` format description, but VideoToolbox rejected that same description when asked to create a decompression session. The returned status was `-12910`, `kVTVideoDecoderUnsupportedDataFormatErr`. No compressed sample could be submitted and no frame could be produced.

PlaybackCore therefore uses the split path. For an interleaved Profile 7 stream it runs FFmpeg 9.0.1's `dovi_split` bitstream filter in explicit `mode=bl`. The resulting format is ordinary HEVC with the HDR10-compatible base layer. The enhancement layer and Dolby Vision RPU are not sent to AVFoundation.

This is a deliberate capability reduction. Profile 7 sources now play their HDR10 base layer, not Dolby Vision and not FEL reconstruction. PlaybackCore continues to report the source's Profile 7 and enhancement-layer facts, so the user-visible capability model can describe the fallback honestly.

## Apple contract

Apple's public playback and authoring documentation describes single-layer Dolby Vision inputs. The [HLS Authoring Specification for Apple Devices](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices) names supported single-layer profiles and compatibility forms, but does not define Profile 7 dual-layer HEVC as an Apple playback input. [TN3145](https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata) also states that only single-track files are supported in its Dolby Vision 8.4 guidance.

That omission set the expectation, but it did not settle the result. [`CMVideoFormatDescriptionCreate`](https://developer.apple.com/documentation/coremedia/cmvideoformatdescriptioncreate(allocator:codectype:width:height:extensions:formatdescriptionout:)) constructs metadata and can preserve extension atoms that a decoder does not support. [`VTDecompressionSessionCreate`](https://developer.apple.com/documentation/videotoolbox/vtdecompressionsessioncreate(allocator:formatdescription:decoderspecification:imagebufferattributes:outputcallback:decompressionsessionout:)) and a non-null image in the [`VTDecompressionOutputCallback`](https://developer.apple.com/documentation/videotoolbox/vtdecompressionoutputcallback) are the stronger discriminator used here.

## Native experiment

The experiment ran before the production implementation. It used the active developer directory reported by `xcode-select -p`:

```text
/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer
Xcode 27.0, build 27A5237l
Swift 6.4
```

The controls were real files which Apple accepts as compressed Dolby Vision inputs:

```text
Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4
Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4
```

The Profile 7 input came from `Profile7.6/FEL_test_for_AVS.mkv`, whose single video stream contains the base layer, RPU NAL units, and enhancement layer. The experiment built the exact FFmpeg-reported Profile 7.6 configuration, including base-layer and enhancement-layer presence, then passed the interleaved samples unchanged.

| Input | Format description | Decompression session | Submitted samples | Successful callbacks | Pixel buffers |
| --- | ---: | ---: | ---: | ---: | ---: |
| Profile 5 control | accepted | accepted | 48 | 48 | 48 |
| Profile 8.1 control | accepted | accepted | 48 | 48 | 48 |
| Profile 7.6 BL + RPU + EL | accepted, status `0` | rejected, status `-12910` | 0 | 0 | 0 |

The control window was a measurement, not an acceptance threshold. Profile 7 failed before sample submission, while both controls produced actual pixels through the same callback path. This is why successful `CMVideoFormatDescription` construction is not treated as native support.

## What FFmpeg 9.0.1 exposes for the supplied source

A probe compiled against the vendored FFmpeg 9.0.1 inspected `AVFormatContext.stream_groups` and every video stream's `AV_PKT_DATA_DOVI_CONF` side data.

| Container | FFmpeg representation |
| --- | --- |
| `FEL_test_for_AVS.mp4` | Two video streams, no stream group. Stream 0 is the base layer. Stream 1 reports Profile 7, level 6, RPU and enhancement layer present, base layer absent, compatibility ID 6. |
| `FEL_test_for_AVS.mkv` | One interleaved video stream, no stream group. It reports Profile 7, level 6, base layer, RPU and enhancement layer present, compatibility ID 6. |
| `FEL_test_for_AVS.m2ts` | Two video streams and one `AV_STREAM_GROUP_PARAMS_DOLBY_VISION` group. The group identifies streams 0 and 1 as split base and enhancement layers, with stream 1 as the enhancement layer. |

The group does not create a decoder input that Apple accepts. It identifies the relationship between two FFmpeg streams. PlaybackCore still has one AVFoundation decoder input, and the native interleaved form was rejected by VideoToolbox.

FFmpeg documents `dovi_split` as the Profile 7 multilayer splitter. Its default `bl` mode removes UNSPEC62 RPU and UNSPEC63 enhancement-layer NAL units and emits ordinary HEVC. PlaybackCore sets the mode explicitly rather than depending on the default. See the [FFmpeg bitstream-filter documentation](https://ffmpeg.org/ffmpeg-bitstream-filters.html#dovi_005fsplit).

## Implementation

`PlaybackFFmpegBridge.c` now detects a selected stream whose FFmpeg Dolby Vision configuration is exactly Profile 7 with both base and enhancement layers present. It initializes `dovi_split` with `mode=bl`, feeds demuxed packets through the filter, drains it at source EOF, and propagates filter errors instead of turning them into end-of-stream.

The supplied containers need two related paths:

```text
interleaved MKV ── dovi_split=mode=bl ──┐
                                       ├── HEVC hvcC, no dvcC/dvvC ── VideoToolbox pixels
split MP4/M2TS ── select base layer ───┘
```

The supplied MP4 has one additional packet-ordering defect at every GOP boundary: FFmpeg places the next VPS/SPS/PPS after the preceding VCL NAL. VideoToolbox returns `kVTVideoDecoderBadDataErr` for that access unit. The bridge now holds only those trailing parameter sets and prefixes them to the following IRAP sample. It does not discard them because the parameter sets change between GOPs. This correction is restricted to a detected Profile 7 MOV-family base-layer path whose `hvcC` had to be bootstrapped from the bitstream.

The permanent regression uses the same shared demux path as `SampleBufferPlaybackSession`. It verifies Profile 7 and compatibility ID 6 diagnostics, an HEVC format with `hvcC` and without `dvcC` or `dvvC`, absence of NAL types 62 and 63, the MP4 parameter-set relocation before a later IRAP, and non-null VideoToolbox pixel output. Setting `PLAYBACKCORE_PROFILE7_FULL_DECODE=1` extends that test to natural EOF for all three containers and requires one successful pixel callback for every submitted sample.

## Verification

The focused default regression passed:

```sh
swift test \
  --scratch-path /Volumes/Cortisol/Build/Enchron-dolby-profile7-native/swift-split-test \
  --filter profile7SourcesDeliverDecodableBaseLayerSamples
```

Result: one test passed in 0.219 seconds.

The full-source variant passed after reading the MP4, MKV, and M2TS to natural EOF:

```sh
PLAYBACKCORE_PROFILE7_FULL_DECODE=1 swift test \
  --scratch-path /Volumes/Cortisol/Build/Enchron-dolby-profile7-native/swift-split-full \
  --filter profile7SourcesDeliverDecodableBaseLayerSamples
```

Result: one test passed in 11.845 seconds. Every submitted sample produced a `noErr` callback and a non-null pixel buffer.

The package build passed:

```sh
swift build \
  --scratch-path /Volumes/Cortisol/Build/Enchron-dolby-profile7-native/swift-build-final
```

The unfiltered macOS test command was also run, including a second attempt under `arch -arm64`. It is not green in this checkout. The runner reports 199 tests and 15 issues. The failures include a missing Apple Immersive fixture, visionOS-versus-visionOS-Simulator platform expectations, an existing MV-HEVC `hvcC` equality expectation, subtitle timing, and several concurrent seek timeouts. The second run also reported that an `arm64e` XCTest bundle was incompatible with the current process. The new Profile 7 regression passed inside both unfiltered runs. I did not change unrelated tests or claim that the full suite passed.

No visionOS Simulator tests and no physical Vision Pro tests were run, as required. The result proves the macOS VideoToolbox boundary on this Xcode 27 beta 5 stack and the PlaybackCore base-layer path. It does not claim wearer-visible output, physical-device performance, or that a future Apple OS cannot add Profile 7 support.
