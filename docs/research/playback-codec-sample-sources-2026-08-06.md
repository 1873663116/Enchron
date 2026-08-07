# Playback codec sample sources, 2026-08-06

This report records trustworthy media fixtures for ProRes, MV-HEVC, Dolby Vision HEVC, and future Dolby Vision AV1 work. It separates files that are safe to keep locally from public streams whose redistribution terms are unclear.

## Material added to TestMedia

### Apple MV-HEVC sample

Apple's sample project [Processing spatial video with a custom video compositor](https://developer.apple.com/documentation/avfoundation/processing-spatial-video-with-a-custom-video-compositor) includes a short spatial movie. The downloadable archive is 6,443,491 bytes:

`https://docs-assets.developer.apple.com/published/31c34ca0bfce/ProcessingSpatialVideoWithACustomVideoCompositor.zip`

The movie and the archive's MIT-style `LICENSE.txt` are preserved at:

`TestMedia/Samples/Spatial/MVHEVC-Apple-Official/`

`ffprobe` 8.0.1 reports a 4.053833-second QuickTime file containing:

- HEVC Main 10, `hvc1`, 1280 x 1280, 29.97 fps, `yuv420p10le`;
- `view_ids_available=0,1` and `view_pos_available=1,2`, confirming two coded views rather than ordinary single-view HEVC;
- rectilinear stereo metadata, left primary eye, 11.8 mm baseline, disparity adjustment, and horizontal field of view;
- AAC-LC stereo and a timecode track.

The movie is 3,184,870 bytes. Its SHA-256 is `7c8763d13fad98ba3157c9ae761f265389e2d6c8960b27c356c84511fb816ecf`.

### Apple HLG sample

Apple's [Editing and playing HDR video](https://developer.apple.com/documentation/avfoundation/editing-and-playing-hdr-video) sample project includes a 14-second HLG reference movie and a project license. Both are preserved at:

`TestMedia/Samples/DynamicRange/HLG/Apple-Official/`

`HDRMovie.mov` is HEVC Main10 `hvc1`, 3840 x 2160 at 30 fps, HLG/BT.2020. It is 220,156 bytes and its SHA-256 is `b6ad35c00e93277e9d794c340b9996758b43dd8092aa56eabdbbcd38ef84d17b`. It is a pure HLG reference, not a Dolby Vision Profile 8.4 asset: the file contains neither `dvvC` nor `amve`.

### FFmpeg FATE ProRes test vectors

The former locally generated VideoToolbox files had only a structural oracle: codec mapping, CoreMedia format-description construction and compressed-sample creation. They were replaced by the smaller ProRes inputs referenced by FFmpeg FATE at commit `5c395992f99feb47860e4cc99a0cea2009457870`:

`TestMedia/TestVectors/Upstream/FATE/ProRes/`

The retained vectors cover 422 Proxy, LT, Standard and HQ plus two 4444 alpha/transparency inputs. FATE does not provide a 4444 XQ vector at the pinned revision; the real ARRI ALEXA Mini file supplies that subtype and professional playback input. These upstream files remain structural vectors and do not replace camera-originated acceptance media.

Apple documents the six corresponding CoreMedia codec constants and AVFoundation codec types: [Core Media video codec constants](https://developer.apple.com/documentation/coremedia/video-codec-constants) and [AVVideoCodecType](https://developer.apple.com/documentation/avfoundation/avvideocodectype).

### ARRI camera-originated ProRes fixtures

ARRI's official [Camera Sample Footage](https://www.arri.com/en/learn-help/learn-help-camera-system/camera-sample-footage-reference-image) page states that its clips are camera-captured and intended for workflow evaluation. Two original QuickTime files are preserved without transcoding or remuxing at:

`TestMedia/Samples/Professional/ProRes/`

| Camera/file | ProRes signal | Audio | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| ALEXA Mini `M001C001_161207_R00H.mov` | 4444 XQ `ap4x`, 12-bit 4:4:4, 1080p24 | 24-bit PCM, 48 kHz, 5ch | 528,482,304 B | `489c351c03f188bd1cdbd50e8c8fa8e874237f9d272fe82679765565cbb85f08` |
| AMIRA `B001C001_140702_R3VJ.mov` | 422 Standard `apcn`, 10-bit 4:2:2, 1080p24 | 24-bit PCM, 48 kHz, 5ch | 170,307,452 B | `318a5b2f9d0d579e33290bb291cf6539902a4a7e0c067bcb16e176c973d098e5` |

Both files retain ARRI camera and Apple ProRes encoder metadata and include timecode tracks. They are positive professional-playback fixtures rather than locally generated bridge inputs. No redistribution permission was identified, so they remain internal TestMedia assets. The temporary 1.78 GB AMIRA archive and an extra extracted clip were removed after verification and can be downloaded again from ARRI.

## Existing Dolby Vision coverage

The retained `TestMedia/Samples/DynamicRange/DolbyVision` collection contains three single-layer HEVC Dolby Vision configurations at HD and UHD resolutions:

| Content | Dolby Vision profile | Compatibility ID | Levels present | Video tag | Audio |
| --- | ---: | ---: | --- | --- | --- |
| Dolby Vision base layer | 5 | 0 | 1, 6 | `dvh1` | E-AC-3 Atmos, 5.1 |
| HDR10-compatible | 8 | 1 | 1, 6 | `hvc1` | E-AC-3 Atmos, 5.1 |
| HLG-compatible | 8 | 4 | 1, 6 | `hvc1` | E-AC-3 Atmos, 5.1 |

All inspected files report RPU present, enhancement layer absent, base layer present, and `dv_md_compression=none`. The included Dolby license permits internal noncommercial evaluation and prohibits modification, commercial use, and transfer to a third party.

This is sufficient for baseline Profile 5, 8.1, and 8.4 assembly tests. It is not sufficient to claim broad dynamic-metadata coverage: all files are variants of the same “Patterns of Nature” asset, and `ffprobe` exposes the configuration record but does not enumerate Dolby metadata levels, scene-refresh behavior, content-mapping versions, or trim combinations.

## Additional official material preserved for internal validation

### Dolby Vision Profile 8.1 Glass Blowing

Dolby's camera-content [Profile 8.1 Glass Blowing sample](https://media.developer.dolby.com/DolbyVision_Atmos/mp4/P81_GlassBlowing2_1920x1080%4059.94fps_15200kbps_fmp4.mp4) is preserved without transcoding or remuxing at:

`TestMedia/Samples/DynamicRange/DolbyVision/Profile8.1/OfficialDolby/`

The file is 344,509,829 bytes. `ffprobe` 8.0.1 verifies HEVC Main10 `hev1`, 1920 x 1080 at 60000/1001 fps, Dolby Vision Profile 8 Level 5 with compatibility ID 1 and RPU present, plus E-AC-3/JOC 5.1 audio. Its SHA-256 is `8e86ed6bb71cc71ec0394dad274c335fcfeaaa6801aed3abcea5ee98b6cd1168`. It adds real-content and 59.94 fps coverage beyond the existing 24 fps `Patterns of Nature` family, but does not by itself prove which RPU metadata levels exercise a visible trim.

### Dolby Vision Profile 20 / stereo Dolby Vision

Apple's [3D streaming example](https://developer.apple.com/streaming/examples/advanced-stream-3d.html) is the strongest public source for Dolby Vision combined with MV-HEVC. Its [master playlist](https://devstreaming-cdn.apple.com/videos/streaming/examples/historic_planet_content_2023-10-26-3d-video/main.m3u8) explicitly declares `dvh1.20.01`, `.03`, `.05`, and `.06`, PQ, `REQ-VIDEO-LAYOUT="CH-STEREO"`, resolutions from 360p through 2160p, and AC-3 or E-AC-3/JOC audio.

The stream is 64.875 seconds. The original playlists, complete 1080p video rendition, E-AC-3/JOC 5.1 audio rendition and AC-3 5.1 audio rendition were downloaded without transcoding or remuxing to:

`TestMedia/Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS/`

`ffprobe` 8.0.1 identifies the selected video as HEVC Main10 `dvh1`, Dolby Vision Profile 20 Level 3, RPU present, compatibility ID 0, 1920 x 1080 at 24 fps, with coded view IDs 0 and 1. Its initialization segment SHA-256 is `db746623a2d2ceb823b54fec139643f52d730e5d3e143401596f9b0771a22756`.

The playlist states `Copyright © 2023 Apple Inc. All rights reserved.` The local copy is an internal validation asset and must not be redistributed. The local master still references Apple renditions that were not downloaded, so direct local probing must use the selected `prog_index.m3u8` files.

## High-value official sources not downloaded

### Dolby Browser Test Kit

Dolby's [Browser Test Kit](https://ott.dolby.com/browser_test_kit/index.html) and its [MP4 test-signal catalog](https://ott.dolby.com/browser_test_kit/help_files/topics/r_test_signals_all.html) provide official Profile 5, 8.1, and 8.4 files over multiple frame rates, resolutions, and audio variants. Direct archives include:

- [24 fps](https://ott.dolby.com/browser_test_kit/source_mp4s/24fps.zip), 548,549,728 B
- [25 fps](https://ott.dolby.com/browser_test_kit/source_mp4s/25fps.zip), 542,017,259 B
- [30 fps](https://ott.dolby.com/browser_test_kit/source_mp4s/30fps.zip), 663,064,590 B
- [50 fps](https://ott.dolby.com/browser_test_kit/source_mp4s/50fps.zip), 1,056,420,568 B
- [120 fps](https://ott.dolby.com/browser_test_kit/source_mp4s/120fps.zip), 2,054,434,463 B

The site states `All rights reserved`. Before downloading a full archive, select the exact missing metadata or frame-rate case and confirm its local-use terms. Downloading every archive would add several gigabytes without proving new metadata coverage.

### Other Apple MV-HEVC sources

Apple's public [Spatial Video HLS example](https://developer.apple.com/streaming/examples/immersive-media/spatial-video/) provides a 61-second SDR rectilinear MV-HEVC stream with AAC. The downloaded sample-project fixture represents the same essential format in a much smaller, licensed local file.

Apple's [APMP 180-degree example](https://developer.apple.com/streaming/examples/immersive-media/stereo-180-apmp/) adds MV-HEVC with half-equirectangular projection. It is useful only when projection metadata is in scope; its lowest rendition is approximately 183 MB.

Apple's [Authoring Apple Immersive Video](https://developer.apple.com/documentation/immersivemediasupport/authoring-apple-immersive-video) package contains 4320 x 4320, 90 fps, PQ MV-HEVC and calibration data, but the package is approximately 378.9 MB. It is a later immersive-media fixture, not a first requirement for basic MV-HEVC support.

### FFmpeg FATE samples

FFmpeg documents `fate-rsync` as the supported way to obtain regression media in its [FATE documentation](https://ffmpeg.org/fate.html). Useful small assets include:

- `rsync://fate-suite.ffmpeg.org/fate-suite/hevc-conformance/MVHEVCS_A.bit`, 214,382 B;
- `MVHEVCS_B.bit`, 616,300 B;
- `MVHEVCS_E.bit`, 240,393 B;
- `MVHEVCS_F.bit`, 268,751 B;
- ProRes 422 Proxy/LT/Standard/HQ and alpha samples under `fate-suite/prores/`, each about 115–220 KB.

These are good parser and demux regression inputs. They do not prove QuickTime/MP4 assembly, Apple spatial metadata, or rendered stereo behavior. FFmpeg does not state that all FATE media inherits the source-code license, so the files should not be treated as redistributable project assets without provenance checks.

## Dolby Vision AV1

Dolby Vision over AV1 is a real standardized capability, not merely a proposal. Dolby identifies it as Profile 10, a single-layer 10-bit AV1 profile. Apple's current HLS appendix gives a concrete Profile 10.4 example: AV1 base codec `av01.0.13M.10.0.112`, supplemental codec `dav1.10.09/db4h`, and HLG video range. See [Apple's HLS authoring appendixes](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices-appendixes) and Dolby's [Introduction to Dolby Vision Profile 10](https://professionalsupport.dolby.com/s/article/Introduction-to-Dolby-Vision-Profile-10).

Dolby's OTT Content Explorer exposes first-party, clear-CMAF, video-only Profile 10 test files. All three listed files and their manifests are now retained without transcoding or remuxing at:

`TestMedia/Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/`

| Profile | Direct MP4 | Size | Range-probe result |
| --- | --- | ---: | --- |
| 10.0, 25 fps | [P10.0 MP4](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_25/media-video-dav1-dav1-1.mp4) | 30,403,501 B | `dav1`, level 4, compatibility ID 0, PQ/IPT-PQ-C2, RPU present |
| 10.1, 30 fps | [P10.1 MP4](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_1_30/media-video-av01-dav1-db1p-1.mp4) | 34,060,133 B | AV1 Main 10-bit, level 4, compatibility ID 1, PQ/BT.2020, mastering-display and content-light metadata |
| 10.4, 30 fps | [P10.4 MP4](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_4_30/media-video-av01-dav1-db4h-1.mp4) | 34,345,638 B | AV1 Main 10-bit, level 4, compatibility ID 4, HLG/BT.2020 |

The corresponding official manifests are [Profile 10.0](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_25/dash_video_only.mpd), [Profile 10.1](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_1_30/dash_video_only_ess.mpd), and [Profile 10.4](https://ott.dolby.com/OTTEP/vision/clear_cmaf/P10_4_30/dash_video_only_ess.mpd).

One implementation boundary is already visible: FFmpeg 8.0.1 recognizes the Profile 10.1 and 10.4 files as `AV_CODEC_ID_AV1` with Dolby Vision configuration side data, but reports the Profile 10.0 `dav1` sample entry as an unknown codec. Treating Dolby Vision AV1 as a future capability remains appropriate, but the product record should say “formal format and official fixtures exist; implementation deferred,” not imply that the format or samples do not yet exist.

## Recommended acquisition order

1. Use the added Apple MOV to establish ordinary MV-HEVC demux, two-view signaling, spatial metadata, sample construction, and device presentation.
2. Use the six FATE ProRes vectors for codec mapping and alpha handling. Use the two camera-originated ARRI files for positive ProRes 422/4444 playback acceptance and for the important ProRes-plus-multichannel-PCM integration path.
3. Use the locally preserved Apple Profile 20 HLS rendition to separate HLS/demux behavior from MV-HEVC and Dolby Vision assembly; retain the original segment structure.
4. Expand existing Dolby Vision coverage by metadata property, not by file count. First inspect current RPU metadata with Dolby tooling or `dovi_tool`; then download only a Browser Test Kit case that adds a missing frame rate, metadata level, content-mapping version, or scene-refresh pattern.
5. Keep the downloaded Profile 10.0, 10.1 and 10.4 files as future-capability fixtures. The first implementation spike should begin with Profile 10.1 and 10.4, then separately handle Profile 10.0's `dav1` sample entry.
