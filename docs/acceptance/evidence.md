# 验收证据账本

这里只记录当前 PlaybackCore 源码与当前 fixture 下已经发生的验证事实。设计声明不能代替 Evidence ID。xr-fork 的历史 evidence 只在 `docs/migration/xr-fork-fusion-map.md` 中作为迁移输入，不参与当前状态推导。

当前最终架构是 FFmpeg Compressed 产品主线与 Apple Compressed 对照层。包含 FFmpeg Decoded 的旧证据只保留历史事实，不再代表当前 route matrix。

## 记录格式

每条记录包含 Evidence ID、case、route、layer、source / fixture、environment、artifact、result、limits 和 supersedes。状态取 `verified`、`failed`、`blocked`、`stale` 或 `invalidated`。

## 当前证据

### E-L1-CORE-CONTRACTS-20260713

- Case：Media Session、records、operation、Snapshot、Provider / renderer seam 与控制状态机。
- Route：route-neutral；覆盖 Apple Compressed 对照层与 FFmpeg Compressed 主线的 compressed input contract。
- Layer：L1 macOS host tests。
- Result：`verified`。当前源码执行 `swift test` 为 47/47 通过。用例覆盖双路线 Provider provenance、slot rejection、不可恢复 failure 后 slot release、renderer terminal failure、control rejection、Snapshot、event observer、Provider → renderer sink、format revision、flush epoch、binding uniqueness、seek、cold switch、音视频结束协调、完整 cleanup barrier，以及音轨枚举、选择、音量和静音状态。Stereo 用例覆盖两条路线首帧前覆盖、播放中 mono / side-by-side / over-under 热切换、清除覆盖后等待 source format、跨 Provider `formatChanged` / `flush` reset、cold switch / reopen 保留显式选择、外部 open 恢复 source default，以及取消的旧命令不能污染新 Media Session；所有热切换都要求 session、renderer、timeline 与 route 保持不变。
- Artifact：`Tests/PlaybackCoreTests/PlaybackCoreTests.swift`；执行入口 `swift test`。
- Limits：fake sink 不证明 Apple renderer、RealityKit 或可见画面。

### E-L2-THREE-ROUTES-20260713

- Case：三条 route 在同一 macOS App 进程中分别持续出帧。
- Route：Apple Compressed、FFmpeg Compressed、FFmpeg Decoded。
- Layer：L2 macOS。
- Source：restricted fixture summary `HDR10.MP4`。
- Result：`stale`。该结果证明旧三路线实现曾经运行，但 FFmpeg Decoded 已从当前源码删除，不能用于当前双路线完成声明。
- Artifact：[2026-07-13-route-probe.json](runs/2026-07-13-route-probe.json)。
- Limits：不证明 Vision Pro HDR 观感；每条 route 只由自己的行关闭。

### E-L2-FFMPEG-COMPRESSED-HLG-TS-20260713

- Case：FFmpeg Compressed 主线播放 MPEG-TS Annex-B HEVC Main10 HLG，并完成 seek 后音视频恢复。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Source：`test/HLG/01. TS Files/01...HLG_HDR.ts`，4K HEVC Main10、AAC。
- Result：`verified`。Provider 将 Annex-B VPS/SPS/PPS 建成 `hvcC` format description，将 packet 转成 4-byte length-prefixed sample；renderer error none、displayed pixel buffer true，HLG/BT.2020 signaling 可见，seek 后 audio/video 当前 epoch 均产生目标 PTS 后 sample。
- Artifact：[2026-07-13-ffmpeg-compressed-hlg-ts.json](runs/2026-07-13-ffmpeg-compressed-hlg-ts.json)。
- Limits：只关闭这一份 TS fixture 的详细 Annex-B / seek case；素材全集覆盖由下一条独立证据记录。

### E-L2-FFMPEG-COMPRESSED-TEST-MEDIA-20260713

- Case：FFmpeg Compressed 在同一个 macOS Playback Lab 进程中逐个打开本地测试素材全集并持续出帧。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Source：`/Users/xiongzhipeng/Desktop/test` 下当前枚举到的 82 个媒体文件。
- Result：`verified`。最终 run `20260713T064429Z-67774` 完成并通过 82/82。每个文件均得到当前 Media Session 的 accepted renderer input 与 displayed pixel buffer，renderer / display failure 均为 0，并单独记录最终关闭结果，不由前一文件推断。覆盖 `av01` 6 个、`avc1` 4 个、`dvh1` 4 个、`hvc1` 67 个和 `mp4v` 1 个。69 个存在可解码音轨的文件全部建立 selected audio track 并产生 PCM sample；13 个没有可解码音轨的文件不暴露伪音轨。IVF 中原始 AV1 Sequence Header OBU 会先重建为合法 `AV1CodecConfigurationRecord`，对应样本能够真实出画面。
- Artifact：[2026-07-13-final-ffmpeg-compressed-test-media-coverage.json](runs/2026-07-13-final-ffmpeg-compressed-test-media-coverage.json)。
- Limits：证明本机当前素材集合的播放承载，不证明 Vision Pro 画面观感或未来未见容器。FFmpeg 当前没有 Apple Positional Audio Codec (`apac`) decoder；集合中的 Apple 文件同时有可用 AAC 轨并已选择 AAC，若未来来源只有 `apac`，当前行为将是 video-only。

### E-L2-FFMPEG-COMPRESSED-HEV1-NORMALIZATION-20260713

- Case：来自 `hev1` 轨道、参数集已进入 `hvcC` 且 packet 不重复携带参数集的 8K HEVC 文件。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Result：`verified`。Provider 保留 source tag `hev1` 作为来源事实，并用 `hvc1 + hvcC` 建立 renderer sample contract；displayed pixel buffer true、audio enqueue 持续、renderer error none。直接宣称 `hev1` 的实验在两条路线均未出画面，因此没有保留。
- Artifact：[2026-07-13-ffmpeg-compressed-apmp-8k.json](runs/2026-07-13-ffmpeg-compressed-apmp-8k.json)。
- Limits：该文件没有 APMP projection boxes，只证明 HEVC/sample 标准化，不证明沉浸投影。

### E-L2-APMP-PROJECTION-TWO-ROUTE-20260713

- Case：真实 Apple Projected Media Profile (APMP) 的 equirectangular projection 从容器进入两条路线的 compressed `CMFormatDescription`、renderer 与 RealityKit binding。
- Routes：Apple Compressed、FFmpeg Compressed，各自独立运行。
- Layer：L2 macOS sample / renderer contract。
- Source：Apple 官方 APMP 转换示例生成的本地 5 秒 monoscopic HEVC fixture；CoreMedia 独立检查得到 `ProjectionKind = Equirectangular`，且不是 external spherical tag compatibility path。
- Result：`verified`。Apple Compressed 保留系统 format description 的 `Equirectangular`；FFmpeg 8.0.1 从 `vexu` 解析 Spherical Mapping，PlaybackFFmpegBridge 将 projection、可见 view packing、baseline 与 field-of-view 写回重建的 format description。两条路线的首个样本都记录 `projectionKind = Equirectangular`，renderer error none、displayed pixel buffer true、RealityKit 与 Presentation Binding active。
- Artifact：[2026-07-13-apmp-projection-two-route.json](runs/2026-07-13-apmp-projection-two-route.json)。
- Limits：关闭 projection metadata handoff 与 macOS displayed frame，不替代 Vision Pro 上 Panorama / Portal 的实际空间投影视觉结论。

### E-L2-RUNTIME-CONTROL-20260713

- Case：pause、single seek、consecutive seek、setRate、cold route switch、play、close 与 reopen。
- Route：Apple Compressed → FFmpeg Compressed。
- Layer：L2 macOS。
- Result：`verified`。seek 保持 Media Session 并推进 Stream Epoch；连续 seek 中旧请求以稳定的 superseded 结果终止，最终 Snapshot 和画面时间落在最新目标；0.5 rate 跨 cold switch 保留；close 等待 flush completion；reopen 创建新 Media Session 并重新得到 displayed frame。增强 typed Snapshot 后又在当前源码上重跑 snapshot、rate、pause、seek、close 与 reopen，所有 acknowledgement 为 `completed`。
- Artifact：[2026-07-13-runtime-control.md](runs/2026-07-13-runtime-control.md)。
- Limits：不证明 visionOS scene lifecycle。

### E-L2-VISIONOS-SIM-ADAPTER-20260713

- Case：visionOS App scene 与 RealityKit presentation adapter 启动。
- Route：未打开 source；route selector 可见 Apple Compressed、FFmpeg Compressed 与 FFmpeg Decoded。
- Layer：L2 visionOS Simulator 差分验证。
- Environment：Apple Vision Pro Simulator，xrOS 27.0。
- Result：`stale`。`PlaybackLabVision` 曾构建、安装并启动为 `com.xiongzhipeng.PlaybackLabVision`；运行截图证明当时的 scene 和 RealityKit 容器实际呈现，但截图中的三路线 UI 已被当前双路线源码取代。
- Artifact：[2026-07-13-visionos-simulator.md](runs/2026-07-13-visionos-simulator.md)；XcodeBuildMCP build/run result，process `1761`，运行截图 `800 × 450`。
- Limits：未选择视频；不证明 sample 播放、Vision Pro scene lifecycle、HDR / EDR 观感或设备性能。该历史 run 的最终 generic Simulator build 曾在 FFmpeg x86_64 archive 中缺少 platform load command 的汇编对象上给出 linker warning，同时 build、install 与 arm64 Simulator launch 通过；该 warning 不被写成消失，也不能把该结果沿用到当前 adapter。

### E-L1-VISIONOS-DEVICE-BUILD-20260713

- Case：旧 presentation topology 下的双路线、共享音频控制与四种 presentation adapter 编译并链接为 visionOS device App。
- Route：route-neutral App integration。
- Layer：L1 visionOS generic device build。
- Environment：XROS 27.0 SDK，deployment target visionOS 26.0，arm64，code signing disabled。
- Result：`stale`。该 generic visionOS build 曾通过，但它编译的是已经废弃的独立 Portal Window / Fixed Immersive Screen / 多 ImmersiveSpace presentation 模型；不能证明当前单窗口、单 ImmersiveSpace 规格。
- Artifact：[2026-07-13-visionos-device-build.md](runs/2026-07-13-visionos-device-build.md)。
- Limits：build 不证明 App 在设备启动、真实 scene transition、投影结果、音频输出或 HDR 观感。

### E-L1-VISIONOS-PRESENTATION-CONTRACT-20260713

- Case：当前独立 Control Window、单一 Playback Window、单一 progressive Playback `ImmersiveSpace`、四种派生 Shape、统一 `PresentationCommand` 与固定 49-case 回归合同。
- Route：Apple Compressed、FFmpeg Compressed；各路线的播放结果仍须分别成立。
- Layer：L1 host contract tests 与 generic visionOS build。
- Environment：arm64e macOS host tests；XROS 27.0 SDK、visionOS 26.0 deployment target、generic visionOS destination、code signing disabled。
- Scene asset：`Sources/PlaybackLabVision/Fixtures/Immersive_Space.reality`，regular file，43,746,155 bytes，SHA-256 `4449b75f4074bbba2799bc4f99e2d4879ffe8bd77dd9b21abda1528519d55ecd`；与 `/Users/xiongzhipeng/Applications/EnchronWorkspace/Xrplay_scene/Immersive Space/Immersive Space/Immersive_Space.reality` 字节相同。
- Result：`verified`。在同一 working tree 上，`swift test` 47/47 通过；presentation domain、video sample format override 与 presentation command contract 三个门禁均为 `GREEN`；`PlaybackLabVision` 针对 `generic/platform=visionOS`、XROS 27.0 SDK、visionOS 26.0 deployment target、`CODE_SIGNING_ALLOWED=NO` 的编译和链接为 `BUILD SUCCEEDED`。49-case manifest 的缺失、重复、未知 ID 会令 `completed = false`；证据判定对未知 source access、Candidate / Presented Shape 与 container binding 不一致、Projection / Stereo 暗变、Scene open / close 替换 audio graph、cleanup 残留以及错误类型均 fail closed。设备结果还会写入 Git / worktree、Xcode / SDK、设备 OS 与三份 fixture / Reality asset SHA-256 provenance。
- Artifact：[current visionOS presentation contract](runs/2026-07-13-current-visionos-presentation-contract.md)、`Tests/VisionPresentationDomainTests.swift`、`Tests/VisionPresentationCoordinatorTests.swift`、`Tests/VisionRegressionPlanTests.swift`、`Tests/VisionRegressionEvidenceTests.swift`、`Tests/VideoSampleFormatOverrideTests.swift`、`script/check_vision_presentation_contract.sh`、`script/test_vision_presentation_domain.sh` 与 `script/test_video_sample_format_override.sh`。
- Limits：本轮没有启动 Simulator 或 App，没有签名、安装或启动 Vision Pro，也没有产生 49-case 设备运行结果。主机测试与 generic build 证明合同、状态转换顺序、证据判定、编译和资源打包，不证明真实 RealityKit acknowledgement、scene transition、Entity binding、displayed pixel、空间投影、音频输出或 Window Bar；这些仍须在操作者针对本次运行明确确认设备现场后验证。

### E-L1-VISIONOS-SIGNED-INSTALL-20260713

- Case：旧 presentation topology 下的双路线、投影 metadata handoff、共享音频控制和四种 presentation adapter 签名并安装到物理 Vision Pro。
- Layer：L1/L2 entry gate；不作为设备呈现成功证据。
- Environment：物理 Vision Pro connected，XROS 27.0 SDK，visionOS 26.0 deployment target，Apple Development 签名与自动 provisioning。
- Result：`stale`。旧 presentation topology 下 signed build、安装和 fixture copy 曾成功；当前单窗口 / 单 ImmersiveSpace adapter 尚未重新执行，因此本条只保留为设备入口历史。
- Artifact：[2026-07-13-visionos-device-install.md](runs/2026-07-13-visionos-device-install.md) 与 `script/probe_vision_device.sh`。
- Limits：本轮明确没有启动设备 App，也没有运行代码驱动呈现回归；因此没有登记 scene transition、actual mode、displayed frame、可听音频或观感为通过。

### E-L2-LIVE-DEBUG-20260713

- Case：常驻 App 的 Snapshot、JSONL event、command inbox 与 completion acknowledgement。
- Layer：L2 macOS。
- Result：`verified`。命令无需重启 App；completed / failed acknowledgement 可区分；cleanup 尾事件同步落盘；Snapshot 不包含完整 source path。
- Artifact：[live-debug.md](live-debug.md) 与 [runtime control run](runs/2026-07-13-runtime-control.md)。
- Limits：这里只证明 macOS Lab adapter 的 inbox。旧 presentation topology 的 visionOS App 曾签名安装，但该历史入口已标为 stale，当前单窗口 / 单 ImmersiveSpace adapter 尚未签名安装，也未登记设备侧外部 command inbox。

### E-L2-APPLE-COMPRESSED-DOVI-P5-20260713

- Case：Apple Compressed Dolby Vision Profile 5 displayed frame。
- Route：Apple Compressed。
- Layer：L2 macOS。
- Source：本地 restricted fixture，文件名见 `dolby-vision-apple-compressed.md`。
- Result：`verified`。storage sample 保留 `dvh1 + hvcC + dvcC`，renderer 无错误并产生 displayed pixel buffer。
- Artifact：`script/probe_dolby_vision_compressed.sh` 输出与 `dolby-vision-apple-compressed.md`。
- Limits：不证明 Vision Pro 观感。

### E-L2-APPLE-COMPRESSED-DOVI-P81-20260713

- Case：Apple Compressed Dolby Vision Profile 8.1 displayed frame。
- Route：Apple Compressed。
- Layer：L2 macOS。
- Source：本地 restricted fixture。
- Result：`verified`。storage sample 保留 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer。
- Artifact：`script/probe_dolby_vision_compressed.sh` 输出与 `dolby-vision-apple-compressed.md`。
- Limits：不证明 Vision Pro 观感。

### E-L2-APPLE-COMPRESSED-DOVI-P84-20260713

- Case：Apple Compressed Dolby Vision Profile 8.4 displayed frame。
- Route：Apple Compressed。
- Layer：L2 macOS。
- Source：本地 restricted fixture。
- Result：`verified`。storage sample 保留 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer；fixture 本身未观察到 `amve`。
- Artifact：`script/probe_dolby_vision_compressed.sh` 输出与 `dolby-vision-apple-compressed.md`。
- Limits：不证明 Vision Pro 观感。

### E-L2-FFMPEG-COMPRESSED-DOVI-P5-20260713

- Case：FFmpeg Compressed Dolby Vision Profile 5 displayed frame。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Result：`verified`。Provider 建立 `dvh1 + hvcC + dvcC`，renderer 无错误并产生 displayed pixel buffer，音频 sample 持续 enqueue。
- Artifact：[2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json](runs/2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json)。
- Limits：不证明 Vision Pro 观感。

### E-L2-FFMPEG-COMPRESSED-DOVI-P81-20260713

- Case：FFmpeg Compressed Dolby Vision Profile 8.1 displayed frame。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Result：`verified`。Provider 建立 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer，音频 sample 持续 enqueue。
- Artifact：[2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json](runs/2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json)。
- Limits：不证明 Vision Pro 观感。

### E-L2-FFMPEG-COMPRESSED-DOVI-P84-20260713

- Case：FFmpeg Compressed Dolby Vision Profile 8.4 displayed frame。
- Route：FFmpeg Compressed。
- Layer：L2 macOS。
- Result：`verified`。Provider 建立 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer，音频 sample 持续 enqueue。
- Artifact：[2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json](runs/2026-07-13-ffmpeg-compressed-dolby-vision-fhd.json)。
- Limits：不证明 Vision Pro 观感。

### E-L3-APPLE-COMPRESSED-DOVI-P5-20260713

- Case：Profile 5 与系统播放器观感一致。
- Route：Apple Compressed。
- Layer：L3 Vision Pro。
- Result：`verified`，由用户在 Vision Pro 上人工验收。
- Artifact：`dolby-vision-apple-compressed.md`。
- Limits：人工观感证据；不推断其他 route。

### E-L3-APPLE-COMPRESSED-DOVI-P81-20260713

- Case：Profile 8.1 与系统播放器观感一致。
- Route：Apple Compressed。
- Layer：L3 Vision Pro。
- Result：`verified`，由用户在 Vision Pro 上人工验收。
- Artifact：`dolby-vision-apple-compressed.md`。
- Limits：人工观感证据；不推断其他 route。

### E-L3-APPLE-COMPRESSED-DOVI-P84-20260713

- Case：Profile 8.4 与系统播放器观感一致。
- Route：Apple Compressed。
- Layer：L3 Vision Pro。
- Result：`verified`，由用户在 Vision Pro 上人工验收。
- Artifact：`dolby-vision-apple-compressed.md`。
- Limits：人工观感证据；不推断其他 route。

## 尚未关闭

- 可听设备输出与主观音视频同步；音轨发现、解码、`AVSampleBufferAudioRenderer`、共享 synchronizer 和双路线控制链路已有下方 L2 证据。
- visionOS 真机上的进度 / seek、倍速、音量、静音、reopen 和轨道选择用户操控；macOS 共用核心已有下方 L2 证据。
- Flat Window、Portal Window、Docked、Panorama 的单窗口 / 单 ImmersiveSpace adapter 已通过当前 working tree 的 host contract tests 与 generic visionOS build；49-case 真机回归仍未运行。旧独立 Portal Window / 多 ImmersiveSpace build 与设备 JSON 已标为 stale，不能替代当前回归。
- FFmpeg Compressed 的 Dolby Vision Profile 5、8.1、8.4 独立 L3 观感证据。
- 真实 monoscopic APMP fixture 与双路线 projection handoff 已有 L2 证据；Panorama / Portal 的实际空间投影与 actual mode 仍待真机关闭，但只有操作者针对本次运行明确确认 Vision Pro 已佩戴、解锁且可测试后才可运行代码驱动真机集成回归。

### E-L2-AUDIO-CONTROLS-20260713

- Case：双音轨枚举与选择、PCM enqueue、volume、mute / unmute、rate、seek 后音视频恢复。
- Routes：Apple Compressed、FFmpeg Compressed、FFmpeg Decoded，各自独立运行。
- Layer：L2 macOS。
- Result：`stale`。旧三路线源码下三条路线均通过；其中 FFmpeg Decoded 已从活跃 route matrix 删除，本记录不代表当前双路线 build。
- Artifact：[2026-07-13-audio-controls.md](runs/2026-07-13-audio-controls.md) 与 `/tmp/playbacklab-route-probe.json`。
- Limits：不证明可听设备输出、主观 lip-sync、visionOS scene 或 Vision Pro 行为。

### E-L2-TWO-ROUTE-AUDIO-CONTROLS-20260713

- Case：当前双路线的 PCM enqueue、volume、mute / unmute、seek 后音视频恢复与 Media Session 连续性。
- Routes：Apple Compressed、FFmpeg Compressed，各自独立运行。
- Layer：L2 macOS。
- Result：`verified`。最终 run `20260713T063220Z-59024` 完成并通过 4/4，覆盖双音轨与纯视频两份素材 × 两条路线。双音轨素材在两条路线均切换到 stream 2 并持续产生 PCM sample；纯视频素材在两条路线均正确保持无音轨。renderer、display 与 control 检查全部通过，RealityKit 与 Presentation Binding 均有效。
- Artifact：[2026-07-13-final-playback-controls.json](runs/2026-07-13-final-playback-controls.json) 与 `Tests/PlaybackCoreTests/PlaybackCoreTests.swift`。
- Limits：不证明可听设备输出、主观 lip-sync、visionOS scene 或 Vision Pro 行为。

## 当前播放器里程碑审计

| `core-spec.md` 完成门 | 当前判定 | 直接证据 |
|---|---|---|
| 双路线 Provider / compressed sample contract | `verified` | E-L1-CORE-CONTRACTS、Apple Dolby Vision cases、E-L2-FFMPEG-COMPRESSED-TEST-MEDIA。 |
| 同一 macOS App 进程双路线 open → audio/video renderer → RealityKit → displayed frame | `verified` | E-L2-TWO-ROUTE-AUDIO-CONTROLS。 |
| control、seek、close、cold switch、stale rejection 与 reopen | `verified` | E-L1-CORE-CONTRACTS 与 E-L2-RUNTIME-CONTROL。 |
| 运行中 Event Stream、Snapshot 与外部调试 | `verified` | E-L2-LIVE-DEBUG；typed Snapshot 增强后已重跑 command inbox。 |
| 当前 visionOS App Adapter host contract / generic build | `verified` | E-L1-VISIONOS-PRESENTATION-CONTRACT；当前单窗口 / 单 ImmersiveSpace 源码已在同一 working tree 完成全部主机门禁与 code-signing-disabled 的 generic visionOS 编译、链接和 Reality asset 打包。 |
| visionOS signed install / 49-case device runtime | 尚未执行 | 旧 E-L1-VISIONOS-SIGNED-INSTALL 与现有 device JSON 均属废弃 topology；只有操作者针对本次运行明确确认设备已佩戴、解锁且可测试后，才允许签名、安装、启动和执行回归。 |
| 设备显示 / HDR 只由 Vision Pro 给结论 | 边界已落实 | Apple Compressed 三个 Dolby Vision profile 已有独立 L3；FFmpeg Compressed 三个 profile 与四种 presentation 的观感仍留在“尚未关闭”，不由 macOS / build 冒充。 |
