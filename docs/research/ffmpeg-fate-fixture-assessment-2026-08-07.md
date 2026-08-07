# FFmpeg FATE fixture assessment

## Decision

Use selected FATE samples as Enchron's codec, parser, demuxer, extradata and malformed-edge fixtures. They can replace locally generated samples whose only purpose is proving that one compressed format can be opened and assembled. They do not replace fixtures whose oracle is an Enchron playback behavior, an Apple hardware path or wearer-visible output.

FATE is FFmpeg's regression system. Its test definitions invoke FFmpeg tools and compare frame hashes, packet checksums, probe output or remuxed output with stored references. The external `fate-suite` contains small inputs chosen to exercise those commands. This makes the inputs strong for FFmpeg-facing micro-tests, but the FATE pass result is not an oracle for Enchron's CoreMedia format construction, SampleBuffer timing, AVFoundation renderer behavior or Vision Pro presentation.

This assessment uses FFmpeg master commit `5c395992f99feb47860e4cc99a0cea2009457870` from 2026-08-07. The synchronized suite at that point contained 2,523 files and occupied about 1.25 GiB; these measurements describe that revision, not a permanent corpus limit.

## Replacement boundary

| Enchron fixture responsibility | FATE suitability | Decision |
| --- | --- | --- |
| ProRes 422 Proxy, LT, Standard and HQ decode structure | FATE has small profile-specific MOV inputs with frame-CRC tests | Replace locally generated structural versions |
| ProRes 4444 alpha and transparency | FATE has alpha and transparency inputs | Replace the locally generated structural files; current Enchron coverage checks the `ap4h` mapping, while an alpha-preservation assertion remains a distinct future test |
| ProRes 4444 XQ professional playback | The current FATE ProRes group does not provide an XQ fixture | Keep the ARRI camera original; the local generated XQ file has no unique role once the real file is covered |
| AV1 bitstream features and AV1 extradata/container edge cases | FATE has AV1 OBU/IVF vectors and Matroska/WebM extradata tests | Add selected FATE inputs; do not use one ordinary generated AV1 stream as complete AV1 coverage |
| Retired MPEG-4 Part 2 rejection | FATE has a small packed-B-frame AVI input | Replace the larger unreferenced-origin fixture; retain Enchron's rejection assertion as the product oracle |
| AV1 video plus FLAC audio on one timeline | FATE tests AV1 and FLAC primarily as codec/demux concerns, not Enchron's synchronized renderer contract | Keep the generated AV1+FLAC fixture |
| Individual FLAC coding modes, bit depths and Matroska channel/extradata handling | FATE has focused FLAC and Matroska inputs | Add selected FATE inputs for provider and format-description tests |
| Eight selectable audio codecs with an audible identity for every track | No identified FATE input provides the same multi-track frequency oracle | Keep the generated audio-codec matrix |
| A/V synchronization measurement | FATE timestamp tests do not provide Enchron's recurring white-flash and audio-pulse measurement oracle | Keep the generated synchronized fixtures |
| Embedded SubRip, ASS and DVB subtitle selection | FATE has many subtitle format and demux edge inputs, but not Enchron's known cue text, track identity and presentation-transition oracle | Keep the generated integration fixture; add FATE samples only for parser/decoder edges |
| External subtitle association and styled rendering | FATE inputs do not encode Enchron's filename association and renderer acceptance contract | Keep the generated SRT and ASS fixtures |
| HLG/PQ metadata propagation plus synchronized playback | FATE has valuable HDR metadata inputs, but not the combined SampleBuffer/display/timeline oracle | Keep the generated HLG and PQ fixtures; add focused FATE metadata samples |
| Dolby Vision configuration and RPU extraction | The suite contains small Profile 5, 7, 8.1 and 8.4 inputs; current definitions exercise Profile 7 remux preservation, Profile 8.4 configuration/RPU and dual-layer handling | Add for micro-tests |
| Dolby Vision Profiles 5, 8.1, 8.4, 10 and 20 on Apple renderers | FATE does not supply the required profile set or Apple output oracle | Keep the current official samples |
| MV-HEVC layer/view parsing and selection | FATE has raw and MOV multiview HEVC edge inputs | Add for micro-tests |
| Apple spatial-video metadata, hardware decode and spatial presentation | FATE's FFmpeg assertions do not establish these behaviors | Keep the Apple sample and Profile 20 HLS fixture |
| Panorama projection and stereo-layout presentation | Some FATE inputs carry spherical/stereo metadata, but FATE does not test Enchron's renderer graph or wearer-visible geometry | Keep Enchron's calibration and real spatial fixtures |

## Adoption rule

Select samples from the paths referenced by the matching FFmpeg FATE test definition, record the FFmpeg revision used for that selection, and run them through Enchron's own assertions. A file merely present on the server but not referenced by an active test needs its own inspection before adoption. Do not import the whole fate-suite. The desktop iCloud copy mirrors the selected media files in the workspace library so their relative paths and filenames stay identical for device import.

The adopted set is stored under `TestMedia/TestVectors/Upstream/FATE`: six ProRes MOV files, `AV1/av1-1-b8-02-allintra.ivf`, and `MPEG4-Part2/packed_bframes.avi`. Their SHA-256 values were verified against the downloaded FATE inputs before installation. The three local AV1 remuxes, the unrelated H.264/TTA file, seven generated ProRes files and the former MPEG-4 Part 2 input had no remaining unique oracle and were removed from the active library.

The FFmpeg source license does not establish a blanket license for every externally hosted sample. The FATE documentation describes how samples are uploaded and synchronized, but does not assign one corpus-wide redistribution license. This does not prevent internal evaluation, but a sample's presence on the FATE server is not evidence that Enchron may redistribute it.

## Primary sources

- [FFmpeg FATE documentation at the assessed revision](https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/doc/fate.texi)
- [FFmpeg developer documentation: regression tests and adding FATE samples](https://ffmpeg.org/developer.html#Regression-tests)
- [FFmpeg ProRes FATE definitions](https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/tests/fate/prores.mak)
- [FFmpeg HEVC, Dolby Vision and MV-HEVC FATE definitions](https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/tests/fate/hevc.mak)
- [FFmpeg Matroska, HDR, subtitle, AV1 and Dolby Vision FATE definitions](https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/tests/fate/matroska.mak)
- [FFmpeg FLAC FATE definitions](https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/tests/fate/flac.mak)
- [FATE ProRes sample directory](https://fate-suite.ffmpeg.org/prores/)
- [FATE AV1 sample directory](https://fate-suite.ffmpeg.org/av1/)
