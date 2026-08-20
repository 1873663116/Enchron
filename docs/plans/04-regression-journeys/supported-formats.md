# Enchron 支持的媒体格式范围

> 面向产品负责人。主表只写格式名与事实陈述，代码位置以脚注形式附后。结论均来自当前分支的构建产物与源码，非 FFmpeg 默认值的推测。

- 版本：Enchron @ `FFmpeg 9.0.1` vendored 构建 `apac-passthrough-v1-ffmpeg-9.0.1`[^1]
- 播放架构：自带 FFmpeg 只做解封装，视频以压缩样本经 VideoToolbox 硬解。AC-3、E-AC-3 和 APAC 音频走压缩透传，其余音频由 FFmpeg 解为 PCM 再送系统[^2]
- 浏览入口的可见范围由文件发现策略另行收敛，并不等同于解封装能力[^3]

---

## 1. 视频编码

视频一律走压缩样本路径，未进入下表的编码在 `codec_type` 即被判为不可渲染并以“Unsupported codec”结束[^4]。下表“支持状态”的含义：完整支持＝可建出 `CMVideoFormatDescription` 并送解码；降级支持＝解封装成功但以另一种呈现方式解码；明确拒绝＝检测到组合后主动报错；代码中无路径＝未在 `codec_type` / Dolby Vision 分支中出现。

| 格式名 | 支持状态 | 判定依据 |
|---|---|---|
| H.264 / AVC (`avcC`, Annex-B) | 完整支持 | `avcC` 与 Annex-B 均有建格式分支，Annex-B 自动转为长度前缀[^5] |
| HEVC / H.265 (`hvcC`) | 完整支持 | `hvcC` 建格式，主路径 `kCMVideoCodecType_HEVC`[^5] |
| HEVC 10-bit / HDR10 (PQ) / HLG | 完整支持 | 色彩与静态 HDR 扩展从 `AV_PKT_DATA_MASTERING_DISPLAY_METADATA` / `CONTENT_LIGHT_LEVEL` 写入 `CMFormatDescription`[^6] |
| AV1 (`av1C`, dav1) | 完整支持 | `dav1` 标签归一为 `AV_CODEC_ID_AV1`，`av1C` 按规范重建或直传[^7] |
| Dolby Vision Profile 5 (HEVC, IPT-PQ, 全域) | 完整支持 | 可用 Dolby Vision 配置携带 `dvcC`，VideoToolbox 以 `kCMVideoCodecType_DolbyVisionHEVC` 解码，色彩常量强制为 BT.2020/PQ/全域[^8] |
| Dolby Vision Profile 8.1 (HEVC, 向后兼容 HDR10) | 完整支持 | 同上，兼容标识 `1` 触发 BT.2020/PQ/ITU-R 2020 矩阵补全，以 `dvvC` 写入[^8] |
| Dolby Vision Profile 8.4 (HEVC, 向后兼容 HLG) | 完整支持 | 同上，兼容标识 `4` 补全为 HLG 传递函数[^8] |
| Dolby Vision Profile 10 (AV1) | 完整支持 | 仅 `dv_profile==10` 且无增强层的 AV1 视为可用，以 `dvvC` 写入[^8] |
| Dolby Vision Profile 7.6 双层 (BL+EL+RPU) | 降级支持 — 丢弃增强层与 RPU，按 HDR10 解码基座层 | 识别为 `PBDOVIDeclarationHEVCDualLayer` 后启用 `dovi_split` bitstream filter `mode=bl`，并对 MP4 的错位参数集重排到下一 IRAP 前，不向 VideoToolbox 宣告 Dolby Vision[^9] |
| Dolby Vision 未知形态 | 明确拒绝 | `PBDOVIDeclarationUnknown` 时直接报错 “Unknown Dolby Vision declaration shape”[^10] |
| Apple ProRes 422 Proxy / LT / 422 / HQ / 4444 / 4444 XQ | 完整支持 | `apco/apcs/apcn/apch/ap4h/ap4x` 六标签分别映射到对应 `kCMVideoCodecType_AppleProRes*`，不依赖 `hvcC/avcC`[^11] |
| MV-HEVC (多视点立体) | 完整支持 | `kCMVideoCodecType_HEVC` 子类型上通过 `TagCollection` 数量 >1 判定，扩展携带视差与视点打包信息[^12] |
| 全景与立体打包 (Equirectangular / Half-Equirectangular / Rectilinear, Side-by-Side / Top-Bottom) | 完整支持 | 球面 `AV_PKT_DATA_SPHERICAL` 与立体 `AV_PKT_DATA_STEREO3D` 映射为 `ProjectionKind` / `ViewPackingKind` 等扩展[^13] |
| VP9 / VP8 / MPEG-2 / MPEG-4 Part 2 / VC-1 / Theora / WMV1-3 | 解封装可读，视频解码代码中无路径 — 明确拒绝 | `codec_type` 未覆盖，分发到 “Unsupported codec is not available for compressed sample rendering”[^4] |
| VVC / H.266 / EVC / AVS2/3 | 解封装可读，视频解码代码中无路径 — 明确拒绝 | 同上，虽有 `CONFIG_VVC_DEMUXER/DECODER` 但未接入 VideoToolbox 分支[^4] |

> HDR10+：按 HDR10 呈现，不宣称 HDR10+ 支持（2026-08-20 裁决：跟随 AVFoundation，其播放管线不消费 ST 2094-40 动态元数据）。HDR10+ 流必含完整 HDR10 静态元数据，忽略动态元数据即得到标准 HDR10 呈现，回退是规范内建的，无需产品侧处理。

---

## 2. 音频编码

音频分两条管线，判定点为 `audio_codec_uses_compressed_passthrough`[^14]。AC-3、E-AC-3 和 Apple APAC 走压缩透传，其余凡能找到 FFmpeg 解码器的均解为 Float32 交错 PCM（`kAudioFormatLinearPCM` / `kAudioFormatFlagsNativeFloatPacked`）后送系统[^15]。

| 格式名 | 支持状态 | 交付给系统的方式 |
|---|---|---|
| AAC-LC | 完整支持 — FFmpeg 解为 PCM | PCM[^15]。ADTS 无参流会以 100k 包 / 100MB 限额探测补全采样率与声道[^16] |
| HE-AAC v1 / v2 | 完整支持 — FFmpeg 解为 PCM | PCM，同上 |
| AC-3 (Dolby Digital) | 完整支持 — 压缩透传 | 压缩 `kAudioFormatAC3`，`mFramesPerPacket=1536`[^14][^17] |
| E-AC-3 / E-AC-3 JOC (Dolby Digital Plus / Atmos) | 完整支持 — 压缩透传 | 压缩 `kAudioFormatEnhancedAC3`，同上[^14][^17] |
| ALAC | 完整支持 — FFmpeg 解为 PCM | PCM |
| FLAC | 完整支持 — FFmpeg 解为 PCM | PCM |
| Opus | 完整支持 — FFmpeg 解为 PCM | PCM |
| Vorbis | 完整支持 — FFmpeg 解为 PCM | PCM |
| MP3 (MPEG-1/2 Audio) | 完整支持 — FFmpeg 解为 PCM | PCM |
| DTS / DCA / DTS-HD | 完整支持 — FFmpeg 解为 PCM | PCM（FFmpeg 含 `DCA_DECODER` / `DTS_DEMUXER`/`DTSHD_DEMUXER`） |
| Dolby TrueHD / MLP | 完整支持 — FFmpeg 解为 PCM | PCM，解码前按 `sampleRate/10` 帧聚合，避免 0.1s 缓冲饥饿[^18] |
| WMA / WMA Pro / WMA Lossless / WMA Voice | 完整支持 — FFmpeg 解为 PCM | PCM |
| APE / TAK / WavPack / TTA | 完整支持 — FFmpeg 解为 PCM | PCM |
| PCM 各变体 (s16/s24/s32/float, alaw/mulaw 等) | 完整支持 — FFmpeg 解为 PCM | PCM |
| Apple Positional Audio (APAC, `apac`) | 完整支持 — 压缩透传 | vendored FFmpeg 从 MOV 初始化段保留完整 `dapa` box，桥接层以 `kAudioFormatAPAC` 和该 cookie 构造格式[^19]。`mFramesPerPacket` 由 AudioToolbox 根据 cookie 推导，不使用常数[^17] |

> 采样率或声道数缺失的流先落入 `audio_stream_needs_more_probe`，会触发扩展探测与 ADTS 修复；仍不可用时报错 “Audio stream parameters are unavailable after extended probe”[^20]。

---

## 3. 字幕格式

字幕准入以 `subtitle_stream_is_supported` 为闸门，未列入者直接不可选[^21]。渲染分两类：文本类由 libass 光栅化为 BGRA 位图，位图类直接合成调色板位图；两者最终都以 `PBSubtitleFrameKindLibass / Bitmap` 的 BGRA 帧交付[^22]。

| 格式名 | 位置 | 支持状态 | 说明 |
|---|---|---|---|
| SubRip (SRT) | 封装内 | 完整支持 | 文本，libass 路径[^21][^22] |
| SSA / ASS | 封装内 | 完整支持 | 样式化文本，libass 完整样式与覆盖标签处理[^21][^22] |
| WebVTT | 封装内 | 完整支持 | 文本，libass 路径[^21][^22] |
| mov_text (MP4 Timed Text) | 封装内 | 完整支持 | 文本，libass 路径[^21][^22] |
| HDMV PGS (`HDMV_PGS_SUBTITLE`, SUP) | 封装内 | 完整支持 | 位图，调色板合成[^21][^22] |
| DVD VobSub (`DVD_SUBTITLE`) | 封装内 | 完整支持 | 位图[^21][^22] |
| DVB Subtitle (`DVB_SUBTITLE`) | 封装内 | 完整支持 | 位图[^21][^22] |
| SRT / VTT / ASS / SSA | 外挂边车 | 完整支持 | 文件发现 `FileFilter.externalSubtitles` 仅接受 `srt/vtt/ass/ssa`[^23]，同名或 `name.lang.ext` 关联[^24]，以独立 `PBSubtitleFrameRenderer` 渲染 |
| SUP / PGS 外挂、SSA 外挂的字体附件 | 外挂边车 | 代码中无路径 — 明确不支持 | 边车过滤器未包含 `sup`，字体回退仅内置 Helvetica Neue 与中文字体自动探测[^25] |

> 外挂字幕的匹配规则：与视频同目录、同基名或 `基名.语言` 前缀，且扩展名在 `externalSubtitles` 集合内；跨技术栈（Emby 边车、本地/SMB/WebDAV 浏览）均复用该规则[^24]。

---

## 4. 容器

FFmpeg 层 vendored 构建未裁剪解封装：`--disable-muxers` 但未禁用 demuxer，`config_components.h` 中 359 个 `CONFIG_*_DEMUXER=1`，覆盖 FFmpeg 9.0.1 全部 demuxer[^26]；协议层启用 `file/http/https/tcp/tls/rtp/rtmp/hls` 等 36 项[^27]。产品层对“可发现”的文件另作收敛。

| 容器 / 封装 | 解封装层 | 产品浏览层 | 组合结论 |
|---|---|---|---|
| MP4 / MOV / M4A / 3GP / 3G2 / MJ2 (`mov`) | 支持[^26] | 可发现[^3] | 完整支持。`hvcC/avcC/av1C/dvcC/dvvC` 完整处理；MOV 家族在流表合格时可跳过 `avformat_find_stream_info` 全量探测[^28] |
| Matroska / WebM (`matroska`) | 支持 | 可发现 (`mkv`/`webm`) | 完整支持。Dolby Vision `dvvC` 与 HDR 色彩同样写入格式描述 |
| AVI (`avi`) | 支持 | 可发现 | 完整支持 |
| MPEG-TS / M2TS (`mpegts`/`mpegtsraw`) | 支持 | 可发现 (`ts`/`m2ts`) | 完整支持。HLG 直播流亦在此路径 |
| FLV (`flv`) | 支持 | 可发现 | 完整支持 |
| ISO (UDF Blu-ray 镜像) | 支持 — 强制以 `mpegts` 重命名 demuxer 打开 | 可发现 | 降级支持。UDF 镜像（卷识别区 `BEA01`+`NSR02/03`）以 16MB `resync_size` 打开，DVD 镜像与加密盘不覆盖[^29] |
| MPEG-PS (`mpegps`) | 支持 | 未在发现列表中 | 解封装可读，但不在浏览器的可选扩展内，需通过直接路径或测试夹具进入 |
| MXF / ASF / RM / OGG / WAV / FLAC / MP3 / AIFF 等其余 340+ demuxer | 支持 | 未在发现列表中 | 解封装可读，产品未声明为用户可见的媒体库格式 |

---

## 与现有语料对照

`TestMedia` 当前约 223 个文件[^30]，覆盖与缺口如下。缺口指“声明支持但仓库内无本地样片”，不代表不支持，仅提示回归覆盖的盲点。

**已有样片的格式（抽样）**

- H.264 / HEVC / AV1 均有：`SDR` 与 `DynamicRange` 下的 `HDR10.MP4`、`HLG`、`av1-flac-avsync-10s.mkv` 等
- Dolby Vision：P5、P8.1、P8.4、P10.0/10.1/10.4 (AV1)、P7.6 双层（含 FEL ISO/M2TS/MKV/MP4）、P20 (HLS)
- ProRes：`ARRI-ALEXA-Mini` / `ARRI-AMIRA` 原片及 `ProRes RAW HQ` 样片
- 全景/立体：`360.mp4`、`insta360.mp4`、`MVHEVC` 官方样片、`180_3D`/`HNVR-158` 立体样片
- 音频：AAC、HE-AAC v1/v2 (`he-aac-v1/v2-apple-audio-toolbox.m4a`)、AC-3、E-AC-3 Atmos、APAC 官方 HLS、FLAC、Opus/Vorbis 间接通过 `av1-flac-avsync` 与编解码矩阵样片
- 字幕：`sdr-bframe-multiaudio-avsync` 的 `ASS` 内嵌与 `zh-CN.srt` 边车

**声明支持但无本地样片的格式**

FATE 定向拉取（`TestVectors/Upstream/FATE/`，44 件）已补齐 H.264/HEVC/VP9/MPEG-2 与纯 AV1、DTS 与 DTS-ES、TrueHD 与 Atmos、MP3/FLAC/ALAC/Opus/Vorbis/PCM 各变体、六种字幕格式的能力样片；封装内 DVB 位图另有本地生成样片（`sdr-bframe-multiaudio-subtitles-30s.mkv` 含 DVB 轨）。仍开放的缺口：

| 类别 | 格式 | 现状 |
|---|---|---|
| 视频 | Dolby Vision Profile 5 的 IPT 演示片的非官方变体（非测试向量） | 仅 `CM4_L3L8` 等两条测试向量，未覆盖用户自制 P5 片源的色彩边界 |
| 视频 | ProRes 4444 XQ (`ap4x`) | 有 `ap4h`/`apcn` 等，未见 `ap4x` 独立样片 |
| 音频 | WMA 系列、APE、TAK | 无样片；FFmpeg 解码器已启用但无回归输入 |
| 字幕 | 外挂 `vtt` / `ssa` / `sup` 边车 | 发现过滤器支持 `vtt`/`ssa` 但无边车样片；`sup` 纳入发现范围（2026-08-20 裁决）后同样需要样片 |

---

## 裁决记录（2026-08-20）

1. **Apple Positional Audio (APAC)**：走系统原生 `kAudioFormatAPAC` 压缩透传，保留空间元数据。

2. **VP9 / MPEG-2 等 Apple 硬件解码不支持的视频编码**：一律明确拒绝，维持现状。视频支持清单的上界是 VideoToolbox 能力，不随 FFmpeg 解封装能力扩大。

3. **HDR10+**：跟随 AVFoundation——其播放管线不消费动态元数据，故不宣称 HDR10+ 支持；流内静态元数据保证按 HDR10 呈现，回退为规范内建，无需产品侧处理。

4. **外挂 SUP/PGS 位图字幕**：纳入发现范围（能支持的尽量支持）。待实现。

5. **纯音频容器**：立项为新功能「纯音频播放模式」——纯音频文件可发现、可播放；不显示视频帧，仅窗口呈现且窗口缩小，加音频频谱可视化；控件最小化（去掉画面格式与 dock，保留音轨与字幕二级菜单，字幕禁用），保留精确时间轴。实现进行中。

---

## 脚注（代码位置）

[^1]: `Packages/PlaybackCore/Scripts/build_ffmpeg.sh:5-6` `VERSION="9.0.1"` / `CONFIGURATION_REVISION="apac-passthrough-v1-ffmpeg-$VERSION"`；同脚本保存源码归档校验和、应用项目补丁并构建全部 Apple 平台切片。
[^2]: 视频 `PBFFmpegReader` → `create_compressed_format` → `CMSampleBuffer` 压缩样本；音频 `PBFFmpegAudioReader` 分 `outputsPCM` 与压缩透传两支，见 `PlaybackFFmpegBridge.c:4721`, `934`, `5309`。
[^3]: `Modules/MediaLibrary/Model/MediaBrowsing.swift:68-73` `MediaDiscoveryAdmissionPolicy.mediaFiles`；`89-91` `FileFilter.playable`。
[^4]: `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c:1399-1410` `codec_type`；`3842-3877` `PBDOVIDeclarationUnknown` 与 `compressed_codec_is_renderable` 拒绝分支。
[^5]: `PlaybackFFmpegBridge.c:1455-1461` `atom_name`；`2986-3046` `create_compressed_format` 的 `annexB` / `avcC`/`hvcC`/`av1C` 分支；`2291-2310` `video_codec_configuration_is_usable`。
[^6]: `PlaybackFFmpegBridge.c:1707-1803` `add_color_extensions`；`1818-1903` `add_static_hdr_extensions`；`1905-2011` `add_projected_media_extensions`。
[^7]: `PlaybackFFmpegBridge.c:1090-1107` `normalize_mov_codec_ids` 对 `dav1` 的归一；`1464-1522` `create_av1_configuration`。
[^8]: `PlaybackFFmpegBridge.c:1383-1397` `has_usable_dovi_configuration` / `requires_dolby_vision_base_layer_split`；`1417-1453` `add_dovi_configuration_atom`（`dvcC`/`dvvC`）；`1399-1408` `codec_type` 中 `DolbyVisionHEVC` 判定；色彩回退见 `1718-1750`。
[^9]: `PlaybackFFmpegBridge.c:1632-1681` `configure_dolby_vision_base_layer_split`（`dovi_split` BSF）；`4324-4408` `prepare_profile7_base_layer_sample_bytes` 参数集重排；`1553-1616` `video_source_facts` 跨流扫描 P7 声明；注释 `1383-1385` 说明 P7 不宣告为 Dolby Vision 的原因。
[^10]: `PlaybackFFmpegBridge.c:3843-3864` `PBDOVIDeclarationUnknown` 报错。
[^11]: `PlaybackFFmpegBridge.c:1290-1300` `prores_codec_type`；`1408` `AV_CODEC_ID_PRORES` 分支；`2614`, `2961` ProRes 跳过 extradata 引导。
[^12]: `PlaybackFFmpegBridge.c:4162-4179` `PBFFmpegReaderIsMVHEVC`。
[^13]: `PlaybackFFmpegBridge.c:1905-2011` `add_projected_media_extensions`；`3121-3135` `media_stream_projection_kind`。
[^14]: `PlaybackFFmpegBridge.c:926-966` `compressed_audio_codec` / `audio_codec_uses_compressed_passthrough`。Apple APAC 同时要求归一后的 codec ID 与 `apac` sample-entry tag，避免误收 Marian's A-pac。
[^15]: `PlaybackFFmpegBridge.c:4721-4771` `outputsPCM` 判定与 `SwrContext` 初始化；`5300-5352` `ensure_decoded_pcm_audio_format`（`kAudioFormatLinearPCM`）。
[^16]: `PlaybackFFmpegBridge.c:973-991` `fill_aac_parameters_from_adts`；`993-1028` `probe_delayed_audio_parameters`。
[^17]: `PlaybackFFmpegBridge.c:5145-5210` `audio_frames_per_packet` / `complete_apple_apac_asbd`；`5296-5369` `ensure_compressed_audio_format`。
[^18]: `PlaybackFFmpegBridge.c:4948-4993` `aggregate_truehd_decoder_packet`；`4921-4928` `decoded_audio_minimum_buffer_frames`。
[^19]: `PlaybackFFmpegBridge.c:1107-1124` `normalize_mov_codec_ids` 对 `apac` 的折叠；`Packages/PlaybackCore/Vendor/FFmpeg/Patches/0001-mov-preserve-apple-apac-dapa.patch` 让 MOV demuxer 把完整 `dapa` box 交给 `codecpar->extradata`。
[^20]: `PlaybackFFmpegBridge.c:952-957` `audio_stream_needs_more_probe`；`1030-1066` `set_audio_stream_selection_error`。
[^21]: `PlaybackFFmpegBridge.c:909-924` `subtitle_stream_is_supported`（`ASS/SSA/SUBRIP/WEBVTT/MOV_TEXT/HDMV_PGS/DVD/DVB`）。
[^22]: `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/SubtitleFrameRenderer.c:79-91` `is_bitmap_codec` / `is_text_codec`；`365-523` `create_subtitle_frame_renderer` 的 libass / 位图双路径；`668-847` `copy_ass_frame` / `copy_bitmap_frame`。
[^23]: `Modules/MediaLibrary/Model/MediaBrowsing.swift:93-95` `FileFilter.externalSubtitles` (`srt/vtt/ass/ssa`)。
[^24]: `Modules/MediaLibrary/Model/ExternalSubtitleAssociation.swift:11-27` `matching`（同基名或 `基名.语言` 前缀）；`Modules/MediaLibrary/MediaLibraryViewModel.swift:134`, `FileBrowsingViewModel.swift:529` 等多处复用。
[^25]: `SubtitleFrameRenderer.c:442-473` 字体与 `default_ass_header` 回退。
[^26]: `Volumes/Cortisol/Build/Enchron-ffmpeg-upgrade/script-build/build-decoded-audio-pcm-v1-ffmpeg-9.0.1-macos27-arm64/config_components.h:1-...` `CONFIG_*_DEMUXER=1` 计 359 项；同文件 `CONFIG_*_DECODER=1` / `CONFIG_*_PARSER=1` 全量启用。
[^27]: 同文件 `CONFIG_*_PROTOCOL=1` 36 项（含 `FILE/HTTP/HTTPS/TCP/TLS/RTP/RTMP/HLS` 等）。
[^28]: `PlaybackFFmpegBridge.c:2312-2351` `mov_stream_table_is_qualified`；`2387-2406` `read_stream_information` 的 MOV 快速路径；`2353-2385` `fill_video_color_from_codec_configuration`。
[^29]: `PlaybackFFmpegBridge.c:1133-1177` `disc_image_input_format` / `open_media_source` 的 UDF 识别与 `resync_size=16MB`。
[^30]: `TestMedia` 实际文件数 223，见 `find TestMedia -type f` 统计；`Samples` / `TestVectors` 目录结构见同路径 `README.md` 与 `References/acceptance-clips.md`。
