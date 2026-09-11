# 真机保留清单

本文是真机（物理 Apple Vision Pro）验证保留范围的唯一依据：交互操作没有真机特例，真机只保留解码能力类——模拟器解不了、只有真机解得了或行为不同的媒体格式与编解码路径。这是 2026-08-25 的裁决（Q7 与 R5，台账 `.scratch/2026-08-25-refactor-decisions/decisions.md`）；入库的执法表述是 [docs/MERGE_EVIDENCE.md](../../../../docs/MERGE_EVIDENCE.md) 裁决表的 W3 行与 manifest 的 `realDeviceDecode` 字段。[SKILL.md](../SKILL.md) Launch 一节的两条真机内容是本清单的摘要。

一条能力想进入本清单，必须同时给出三件事：模拟器不行的技术原因（以实测为证，而不是推断）、出处（代码位置、测试或已存档证据）、验证方式与 fixture。交互类理由一律不受理。给不齐三件的候选放入存疑区，不混入正式清单。

两条 lane 的解码能力差异集中在一处：递交 `AVSampleBufferVideoRenderer` 的压缩样本由其内部的 VideoToolbox 解码，而何种编码可以递交由 `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c` 的 `codec_type()` 唯一决定。每侧环境的实测答案由 `Tests/EnchronApp/VideoDecoderAvailabilityTests.swift` 的 `videoDecoderMatrixIsRecorded` 写入容器的 `video-decoder-matrix.tsv`；本清单的模拟器侧结论出自 2026-08-21 的实测，见[模拟器 lane](simulator.md) 的能力边界一节。

## 保留清单

### Dolby Vision 原生解码（Profile 5，dvh1）

`codec_type()` 把 P5 原生声明（`dovi_declaration_shape()` 判定为 HEVCNative）映射为 Dolby Vision HEVC 专用解码器类型；模拟器没有这个解码器，整条画面链路因此只有真机能走。真机侧另有 `dolbyVisionDecoderExistsOnThisDevice` 直接断言 dvh1 解码器在场。

验证方式：`VisionProCoreRegression.xctestplan` 中的 `DeviceFixtureImportUITests/testDolbyVisionProfile5AutomaticSourcePlaybackOnVisionPro`，断言 provider 与压缩样本的子类型为 dvh1、`dvcC` atom 在场、播放持续产生画面证据。结构侧（不分 lane）由 `Packages/PlaybackCore/Tests/PlaybackCoreTests/PlaybackFFmpegBridgeTests.swift` 的 P5 桥接对齐测试看守。感知层的色彩验收归验收片单的 P5 家族（`/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/References/acceptance-clips.md`；该家族曾整程偏紫而全套自动化通过，色彩判断不能省）。

fixture：`Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4`（UHD 变体并存）。设备侧从头显的 `Desktop/TestMedia` 读取，根路径登记在 `Tests/Fixtures/fixture-registry.json` 的 `deviceMediaRoot`。

### AV1（含 Dolby Vision Profile 10）

模拟器没有 AV1 解码器；真机自 M5 起硬解。P10 的载体就是 AV1（dav1/av01 加 `dvvC`，`dovi_declaration_shape()` 的 AV1 分支），因此 P10 随 AV1 一并只在真机可播。

验证方式：`VisionProCoreRegression.xctestplan` 中的 `DeviceFixtureImportUITests/testDolbyVisionProfile10AutomaticSourcePlaybackOnVisionPro`，断言 dav1 provider、av01 压缩样本与 `dvvC` atom。testplan 之外另有 `testRealAV1360AcrossWindowDockedAndPanoramaRoundTrips` 用 7680×3840 的 AV1 全景片走四种呈现往返。感知层归 P10 家族，「能否播放本身即是信息」。

fixture：`Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.0/media-video-dav1-dav1-1.mp4`（P10.1 的 av01 变体并存）；纯 AV1 用 `Tests/Fixtures/fixture-registry.json` 的 `generated-av1-flac-avsync-10s-v1` 与 `Samples/Spatial/Panorama/insta360.mp4`。

### MV-HEVC 第二视图（空间视频立体对）

模拟器能解出基础层并输出正常尺寸的 pixel buffer，但请求多层输出返回 `kVTPropertyNotSupportedErr`（−12900），解码回调也不携带 `CMTaggedBufferGroup`，因此空间视频在模拟器上只有单眼画面。立体对本身，连同 `actualViewingMode=stereo` 与 `actualSpatialVideoMode=spatial` 这组判据，只在真机成立。识别路径是桥的 `PBFFmpegReaderIsMVHEVC` 与 `Packages/PlaybackCore/Sources/PlaybackCore/VideoSampleProvider.swift` 的 `lhvC` 判定。

验证方式：`VisionProCoreRegression.xctestplan` 中的 `DeviceFixtureImportUITests/testOfficialMVHEVCAutomaticMonoOverrideAndRestoreOnVisionPro`（窗口空间视频、Mono override 与恢复）与 `testAPMP180AutomaticSourcePlaybackOnVisionPro`（multiview 立体 180 全景）。

fixture：`Samples/Spatial/MVHEVC-Apple-Official/spatial_lighthouse_flowers_waves_short.mov` 与 `Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4`。

边界：SBS 与 TB 打包立体不在此列。打包片的解码是普通 HEVC，展开发生在解码后的 pixel buffer 上（`Packages/PlaybackCore/Sources/PlaybackCore/VideoSampleFormatOverride.swift`），模拟器可覆盖，[模拟器 lane](simulator.md) 的已跑通链路含 SBS 与 TB 的投影选择。

## 不保留

以下类别曾被当作或可能被误当作真机专属，逐条列明依据，防止清单被误扩：

| 类别 | 为什么不保留 | 依据 |
|---|---|---|
| 一切交互操作：控件、菜单、媒体库、设置、呈现切换、空间手势 | R5 裁决：命中与输入类证据来自 Device Hub 管线（真实注视加捏合），模拟器 lane 闭环 | [模拟器 lane](simulator.md) 的 Device Hub 一节与已跑通的四种呈现；[窗口播放表面的真实空间输入](../../../../Regression/journeys/window-spatial-input/journey.md) |
| 旧用例里 `XCTSkip` 出模拟器的呈现类回归 | 这些 skip 的理由是空间呈现与交互（如 `Tests/EnchronAppUI/Journeys/WindowPlaybackRegressionUITests.swift`、`Tests/EnchronAppUI/Spatial/SpatialHandoffUITests.swift`、`Tests/EnchronAppUI/Spatial/DockedPlacementUITests.swift` 的 "requires Apple Vision Pro"），不是解码；类别归属依本清单，用例与 testplan 的调整由其所有者执行 | R5；本清单 |
| HDR10 与 HLG | 模拟器有 HEVC 解码器，PQ 与 HLG 是结构字段（transfer token 断言不分 lane）；显示观感属感知层，由佩戴者一次性验收加参照帧体系承接，那不是任何一条 lane 的自动化保留。PlaybackCore 唯一的模拟器编译分叉只是把 hardwareDisplayFacts 标为 notAvailable（`Packages/PlaybackCore/Sources/PlaybackCore/PlaybackCoreController.swift`），两侧都不以显示硬件事实作结构判据 | 解码矩阵实测；`/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/References/README.md` |
| Dolby Vision Profile 7 双层 | VideoToolbox 在真机同样以 −12910 拒绝 P7，产品拆出基础层按 HDR10 呈现，两 lane 行为一致 | 桥的 `requires_dolby_vision_base_layer_split`；[features/picture-interpretation.md](../features/picture-interpretation.md) 的 Gotchas |
| ProRes 六种 | 真机也没有解码器，`proResHasNoDecoderOnThisDevice` 在真机实证；`Samples/Professional/ProRes` 样片只喂拒绝路径 | `Tests/EnchronApp/VideoDecoderAvailabilityTests.swift` |
| Apple Immersive Video 的拒绝 | 打开在解码之前按声明拒绝，与解码器无关，单测在任一侧成立 | `Tests/EnchronApp/PlaybackSourceAndAudioSessionTests.swift` 的 `testAppleImmersiveVideoFailsBeforePublishingAudioOrVideoPlayback` |
| FFmpeg 桥内解码的音频与字幕 | 桥自行解码产出 LPCM 与字幕结构，不经系统解码器，两 lane 等价；压缩直递的例外见存疑区 | [模拟器 lane](simulator.md) 能力边界；桥的音频与字幕支持判定 |
| 投影与立体布局的判读 | mono、SBS、TB 在 2D 截图上各自不同，结合结构化字段即可判断 | [SKILL.md](../SKILL.md) 佩戴者边界一节 |

## 存疑区

以下候选有分叉线索但缺实测，补齐所缺证据之前不进入正式清单：

- **压缩音频直递（AC-3、E-AC-3 含 JOC、APAC）**。桥对这三种编码不解码而直递系统渲染器（`compressed_audio_codec()`；`Packages/PlaybackCore/Sources/PlaybackCore/AudioSampleProvider.swift` 将其标为 FFmpegCompressedAudio），系统侧解码能力从未在模拟器实测——「音频两 lane 等价」的既有表述只对 LPCM 路径成立。已有物理证据都在真机（见 [features/track-selection.md](../features/track-selection.md) 的 AC-3 证据行）。缺：音频版的解码器矩阵探针，或模拟器 lane 对多音轨 fixture 中 ac3 与 eac3 轨的可闻性实测；APAC 更是两侧均无判据，素材也只有上游向量（`TestVectors/Upstream/Apple/Audio/APAC-HLS`）。
- **P8 兼容层（hvc1 加 dvvC）的 Dolby Vision 解释**。解码本身是 HEVC，两 lane 都行；但 `dvvC` 在场时系统是否施加 DV 解释、模拟器是否忽略 RPU 造成色差，没有实测。缺：同一 fixture 在两 lane 的采帧 A/B 对比（现成阴阳样本 `Samples/DynamicRange/DolbyVision/Experiments/dvvC-ab/furyroad-with-dv.mkv` 与 stripped 版）。
- **高分辨率与高帧率上限**。8K 级样片（8192×4096 HEVC 的 `HNVR-158_H_4096p_8K_LR_180_clip.mp4`、7680×3840 AV1 的 `insta360.mp4`）只有真机侧 Real 系列用例走过，模拟器的分辨率与帧率上限从未测绘。缺：模拟器 lane 的阶梯实测。
- **Dolby Vision Profile 20**。DV 与 MV-HEVC 的组合形态，感知层有验收家族与样片（`Samples/DynamicRange/DolbyVision/Profile20/Apple-Streaming-Examples/3D-example.mp4`），自动化判据未注册。缺口不是 fixture，也不是 testplan 条目：`scenario:dynamic-range-interpretation:dolby-vision-profile-matrix` 2026-09-11 移除了它的 `dv-profile-20` case，当时记下的理由是 AVFoundation 不支持该 profile，而 Apple 的 HLS authoring specification 在 visionOS 修订条款下第 1.9c 条写 “Dolby Vision stereo video MUST be Profile 20 (MV-HEVC) and less than or equal to Level 9.”，第 1.40 条写 “Stereo video MUST be encoded using Dolby Vision Profile 20 (MV-HEVC).”，该理由不成立。缺：本 profile 在真机上的一次实测——同一片源的解码与采帧，以判定平台是否施加 DV 解释；在此之前该 case 的移除没有成立的依据。

## 执行入口

真机回归的用例入口是 `VisionProCoreRegression.xctestplan`（Physical Vision Pro 配置），保留类用例即上文逐条所列。矩阵与扫描类工装（如 `Scripts/verification/playback_mode_matrix.py`）的目标设备由 `ENCHRON_TARGET_DEVICE` 选定，实现见 `Scripts/verification/enchron_target.py`。合并证据中，W3 改动的真机特例以 manifest 的 `realDeviceDecode` 字段声明，`capability` 取本清单的条目名（标准见 [docs/MERGE_EVIDENCE.md](../../../../docs/MERGE_EVIDENCE.md)）。
