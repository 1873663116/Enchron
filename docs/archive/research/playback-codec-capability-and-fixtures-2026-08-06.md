# Playback codec capability and fixture research

Date: 2026-08-06

## Scope

The current product direction keeps H.264 and HEVC, retains Dolby Vision HEVC while improving metadata preservation, validates MV-HEVC separately, completes AV1 support within the configurations the target M5 Vision Pro can actually decode, removes VP9 and MPEG-4 Part 2 unless a real user-media need appears, and adds the ProRes 422 and 4444 families as professional review formats. Dolby Vision Profile 10 over AV1 remains a future capability. ProRes RAW is outside the stated ProRes 422/4444 scope unless it is explicitly added later.

## Hardware and platform boundary

Apple's M5 MacBook Pro specification lists hardware-accelerated H.264, HEVC, ProRes and ProRes RAW, plus AV1 decode. The Apple Vision Pro specification identifies the M5 chip but does not publish the same detailed Media Engine list. Product acceptance therefore needs runtime probes on the actual M5 Vision Pro, not an inference from the Mac specification.

The relevant runtime probes are:

- `VTIsHardwareDecodeSupported(codecType)` for H.264, HEVC, AV1 and each ProRes subtype.
- `VTIsStereoMVHEVCDecodeSupported()` for MV-HEVC. MV-HEVC is an HEVC multiview extension and has its own support query.
- A `VTDecompressionSession` created with `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder` when profile, level, chroma, bit depth and resolution need to be proven rather than only the general codec family.

Sources:

- [M5 MacBook Pro specifications](https://www.apple.com/macbook-pro/specs/)
- [Apple Vision Pro specifications](https://www.apple.com/apple-vision-pro/specs/)
- [VTIsHardwareDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:))
- [VTIsStereoMVHEVCDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtisstereomvhevcdecodesupported())
- [Require hardware-accelerated video decoder](https://developer.apple.com/documentation/videotoolbox/kvtvideodecoderspecification_requirehardwareacceleratedvideodecoder)

## Current implementation gaps

`PlaybackFFmpegBridge.c` currently maps H.264, HEVC, Dolby Vision HEVC, AV1, VP9 and MPEG-4 Part 2. It does not map `AV_CODEC_ID_PRORES` to the Core Media ProRes subtype constants. It also has no explicit MV-HEVC capability probe or multi-image format inspection.

The ProRes mapping needs to distinguish the sample entry / codec tag, not collapse the family into one type:

| ProRes variant | Core Media subtype |
|---|---|
| 422 Proxy | `kCMVideoCodecType_AppleProRes422Proxy` |
| 422 LT | `kCMVideoCodecType_AppleProRes422LT` |
| 422 | `kCMVideoCodecType_AppleProRes422` |
| 422 HQ | `kCMVideoCodecType_AppleProRes422HQ` |
| 4444 | `kCMVideoCodecType_AppleProRes4444` |
| 4444 XQ | `kCMVideoCodecType_AppleProRes4444XQ` |

Professional ProRes MOV files commonly carry Linear PCM audio. The current bridge rejects PCM source tracks because only AAC, AC-3, E-AC-3, MP2, MP3, ALAC and Opus use the compressed path and only FLAC uses the FFmpeg-to-PCM path. The agreed target boundary is now stricter: FFmpeg demuxes but never decodes audio, and AVFoundation receives correctly described source packets, including source PCM. ProRes video support therefore needs a real ProRes-plus-PCM fixture and Linear PCM sample-buffer assembly.

## Why the video/audio test matrix can be factored

The codec cross-product is not the correct primary test structure. Each video codec can be validated with a canonical audio track or no audio, and each audio codec can be validated with a canonical video track. This changes the main codec work from `video codec count × audio codec count` to approximately `video codec count + audio codec count`.

The factorization is not absolute because both streams still share one media timeline and renderer graph. Integration fixtures remain necessary for behavior that is not owned by either codec alone:

- stream start offsets, edit lists and different time scales;
- PTS/DTS reordering and missing packet durations;
- seek, flush, discontinuity and end-of-stream coordination;
- audio preroll, video bootstrap and renderer backpressure;
- remote or non-seekable sources opened by independent video and audio `AVFormatContext` instances;
- multichannel layout, codec private data and packet-description correctness while video and audio advance on the same timeline.

A small set of integration sentinels should cover these mechanisms. A full video/audio Cartesian product is not required.

Codec and container packaging cannot be factored as aggressively. The same codec can have materially different initialization and packet representations: H.264/HEVC Annex-B versus `avcC`/`hvcC`, AAC ADTS versus AudioSpecificConfig/ESDS, and AV1 sequence headers in MP4, Matroska/WebM and IVF. Tests should cover each distinct packaging transformation, not every container name.

## Dolby Vision model

Dolby Vision is a constrained combination of:

1. a base coded picture stream such as HEVC, AV1 or MV-HEVC;
2. Dolby Vision profile and level signaling in the container/sample description;
3. Dolby RPU dynamic metadata carried with the coded samples;
4. related color and HDR metadata such as `colr`, mastering display information, content light level and, for Profile 8.4 on Apple platforms, ambient viewing environment metadata.

A Dolby Vision profile binds these dimensions. Profile 5 is single-layer 10-bit HEVC without an HDR10/HLG-compatible base presentation. Profile 8.1 uses an HDR10-compatible HEVC base; Profile 8.4 uses an HLG-compatible HEVC base. Profile 10 uses AV1. Profile 20 uses MV-HEVC Main10 for stereo Dolby Vision on Apple Vision Pro.

Encoding and metadata coverage can therefore be separated inside a declared profile, but arbitrary codec and Dolby metadata combinations are invalid. The efficient test structure is:

- one structural fixture for each supported profile and sample-entry signaling form;
- byte/structure checks that RPU NAL units survive each bridge transformation;
- a small set of metadata-behavior fixtures covering meaningful metadata changes and fallbacks;
- rendered device evidence for the profiles and visual behavior being claimed.

This is not a full cross-product. Profile 10 and Profile 20 are distinct capabilities because their profiles explicitly bind Dolby metadata to AV1 and MV-HEVC respectively.

Sources:

- [Dolby Vision profiles and levels](https://professionalsupport.dolby.com/s/article/What-is-Dolby-Vision-Profile?language=en_US)
- [Dolby Vision metadata levels](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?lang=en&language=en_US)
- [Apple HDR video metadata technote TN3145](https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata)
- [Dolby Vision Profile 10](https://professionalsupport.dolby.com/s/article/Introduction-to-Dolby-Vision-Profile-10)
- [Dolby Vision Profile 20](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Profile-20-FAQ)
- [Apple HLS authoring specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/)

The current bridge copies compressed packet bytes, so Dolby RPU NAL units should remain in the samples unless a bitstream conversion drops them. It also synthesizes `dvcC` or `dvvC` from FFmpeg's Dolby Vision configuration side data and forwards basic color primaries, transfer function and matrix. It does not currently construct mastering display, content-light-level or `amve` extensions. Those are separate preservation gaps even when Dolby Vision decoding succeeds.

### Why Profile 5, 8.1 and 8.4 are not visual equivalence references

Correct Dolby Vision playback does not require Profile 5, Profile 8.1 and Profile 8.4 encodes to render pixel-identically. Profile 5 uses Dolby's IPT color representation and has no conventional HDR10/HLG-compatible base presentation. Profile 8.1 and 8.4 carry PQ/HDR10-compatible and HLG-compatible base presentations respectively. They may also have been created through different mastering and metadata-generation paths. In Dolby's documented Resolve workflow, existing metadata can be preserved for Profile 5 while conversion to Profile 8.1 or 8.4 regenerates per-frame metadata and discards the prior metadata in that workflow. A shared content title therefore does not imply shared coded pictures or shared RPU values.

Consequently, Profile 8.1 or 8.4 looking different from Profile 5 does not establish fallback, and looking similar does not establish that RPU metadata was applied. Profile 5 displaying plausible color is stronger evidence of Dolby-aware interpretation because its base is not a normal HDR10 or HLG presentation, but it still does not prove every dynamic-metadata operation or trim was applied.

The usable black-box reference is the same exact Profile 8 file played through AVPlayer twice: once with `appliesPerFrameHDRDisplayMetadata` at its default `true`, and once with it set to `false`. Apple documents that property as controlling application of the source's per-frame HDR display metadata. Only a clip whose two AVPlayer paths visibly differ has diagnostic power for this question. Enchron's sample-buffer path should then be compared against both AVPlayer references at the same timestamp, display conditions and presentation size on a physical Vision Pro. A captured screenshot or mirrored view may itself be tone-mapped and is not sufficient evidence by itself.

Sources:

- [Dolby Vision encoding of mezzanine assets](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Encoding-of-mezzanine-assets)
- [Dolby Vision encoding using DaVinci Resolve Studio](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Encoding-using-Blackmagic-Design-DaVinci-Resolve-Studio-AQs)
- [Apple HDR video guidance](https://developer.apple.com/news/?id=rwbholxw)

## Existing fixture inventory

The retained Dolby Vision library contains six `Patterns of Nature` MP4 files:

- Profiles 5, 8.1 and 8.4;
- HD and UHD;
- Dolby Vision levels 1 and 6;
- 24 fps throughout;
- E-AC-3 JOC audio throughout.

This preserves a small Level 1 set for routine structure tests and a Level 6 set for 4K device validation, but it remains one content family. It does not establish diverse RPU behavior, CM metadata generations, sample-entry variants, frame rates, corruption/fallback behavior or Profile 20. A raw atom scan finds `dvvC` but no `amve` in the two retained Profile 8.4 files, so they cannot establish Apple's Profile 8.4 ambient-viewing-environment preservation requirement. The added official Dolby `Glass Blowing` Profile 8.1 sample contributes a second content family, `hev1`, Level 5 and 59.94 fps, but still needs extended RPU-metadata inspection before it can be assigned a specific visible-trim claim.

The current AV1 library includes a small 8-bit all-intra AOM fixture repackaged as IVF, Matroska, MP4 and WebM, an AV1-plus-FLAC Matroska fixture, and real 4K/8K panoramic AV1 files. It does not yet constitute complete M5 AV1 configuration coverage. “Complete” must be bounded by configurations for which the M5 Vision Pro can allocate a hardware decoder; Apple's public specification does not promise every AV1 profile, bit depth, chroma format, level and resolution.

The investigation added a small Apple sample-project MV-HEVC MOV under `TestMedia/Samples/Spatial/MVHEVC-Apple-Official`. It contains two HEVC Main10 views, rectilinear spatial metadata and AAC-LC audio. Six FATE ProRes vectors under `TestMedia/TestVectors/Upstream/FATE/ProRes` cover 422 Proxy, LT, Standard, HQ and two 4444 alpha/transparency inputs; these are structural inputs only. Positive professional-playback and 4444 XQ coverage comes from two ARRI camera originals under `TestMedia/Samples/Professional/ProRes`: ProRes 422 Standard and ProRes 4444 XQ, both with 24-bit five-channel PCM and timecode.

## Audio decode boundary and codec inventory

Apple lists FLAC as a supported audio playback format on both M2 and M5 Macs, but does not list FLAC in the Media Engine hardware-acceleration capabilities. Apple documents `kAudioFormatFLAC` and exposes FLAC in the current macOS AudioToolbox decoder-format list. The evidence supports “Apple supplies a FLAC decode path,” not a claim that M2 or M5 definitely has, or definitely lacks, a dedicated FLAC hardware block.

The product decision is to keep one media boundary: FFmpeg performs demuxing and packet normalization only; it does not decode FLAC or any other audio codec. Compressed audio is assembled into `CMSampleBuffer` values and submitted to `AVSampleBufferAudioRenderer`; source PCM is described and submitted as PCM rather than decoded by FFmpeg. If the renderer rejects a correctly assembled codec on the target device, Enchron reports that format as unsupported instead of introducing a private FFmpeg-to-PCM fallback.

This design is internally consistent, but it does not turn Apple's general playback-format list into an `AVSampleBufferAudioRenderer` contract. Apple publishes no per-codec acceptance query for this renderer, so each promised compressed format still needs an actual visionOS device fixture. `kAudioFormatProperty_DecodeFormatIDs` is useful preflight evidence, not proof that the sample-buffer renderer accepts the same format.

The minimum audio inventory to account for is:

- Linear PCM, AAC-LC, HE-AAC v1, HE-AAC v2, xHE-AAC/USAC, AC-3, E-AC-3, E-AC-3/JOC, MP3, ALAC and FLAC;
- APAC as a separate Apple spatial-audio investigation because demuxer recognition and codec-private-data transfer are not yet established;
- Opus as an explicit device-validation case rather than an assumed promise;
- Vorbis, DTS/DTS-HD, Dolby TrueHD and AC-4 as unpromised until both a public platform representation and renderer evidence exist.

Correct demux-only delivery still requires the exact `AudioStreamBasicDescription`, codec magic cookie/private data, channel layout, packet boundaries, packet descriptions, sample sizes, PTS and packet duration. The current bridge's fixed Opus duration assumption and mono/stereo-only channel-layout construction are therefore correctness gaps, especially for E-AC-3/JOC and other multichannel material. Both the initial and replacement audio renderers also set `allowedAudioSpatializationFormats` to `.monoAndStereo`; that is a deliberate spatialization restriction which must be reconsidered separately from codec decoding if multichannel or Atmos presentation is claimed.

Sources:

- [M2 MacBook Air specifications](https://support.apple.com/en-us/111867)
- [M5 MacBook Pro specifications](https://www.apple.com/macbook-pro/specs/)
- [Audio File Types](https://developer.apple.com/documentation/audiotoolbox/1576497-audio-file-types)
- [AudioToolbox decoder format identifiers](https://developer.apple.com/documentation/audiotoolbox/kaudioformatproperty_decodeformatids)

## Fixture acquisition

The detailed source, license, size, checksum and `ffprobe` findings are recorded in [Playback codec sample sources, 2026-08-06](./playback-codec-sample-sources-2026-08-06.md).

Apple's public Dolby Vision Profile 20 HLS example is now preserved locally, without transcoding or remuxing, under `TestMedia/Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS`. The selected 1080p rendition is MV-HEVC Main10 `dvh1`, Dolby Vision Profile 20 Level 3 with two coded views and RPU; the two downloaded audio renditions are AC-3 5.1 and E-AC-3/JOC 5.1. The original master names renditions that are not all present locally, so local tests must open the downloaded rendition playlists directly.

Dolby's Browser Test Kit supplies Profile 5, 8.1 and 8.4 archives across 24, 25, 30, 50 and 120 fps, but the archives range from roughly 0.54 GB to 2.05 GB. Existing RPU metadata should be inventoried first, followed by downloading only a case that adds a missing metadata behavior.

Dolby Vision over AV1 is now formally Profile 10, and the official clear-CMAF Profile 10.0, 10.1 and 10.4 fixtures and manifests are preserved under `TestMedia/Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby`. This corrects the wording “future format”: it is an existing format with available official samples whose Enchron implementation remains deferred. FFmpeg 8.0.1 recognizes the Profile 10.1 and 10.4 samples as AV1 with Dolby Vision configuration side data, while the Profile 10.0 `dav1` sample entry is currently reported as an unknown codec.
