# Spec：PlaybackCore audio-video playback core

这是 PlaybackCore 的活跃设计规格。它定义系统行为、接口、两条播放路线、稳定 records、运行控制、RealityKit 边界和诊断面。节点的证明方式见 `acceptance/verification-system.md`；当前完成状态只从 `acceptance/evidence.md` 读取。

## 目标与范围

PlaybackCore 接受一个系统授权的本地媒体来源和一条显式 Playback Route，产出由同一个 `AVSampleBufferRenderSynchronizer` 管理的视频 renderer 与音频 renderer；App Adapter 将视频 renderer 绑定为 RealityKit video entity，并把 binding / presentation facts 回填给核心。系统必须同时提供可操作的播放器控制和可实时观察的播放状态。

当前必须支持：

- FFmpeg Compressed 产品主线与 Apple Compressed 对照层。
- 至少一个可选择的音频轨道、FFmpeg 音频解码、Linear PCM sample、`AVSampleBufferAudioRenderer` 与音视频共享时间线。
- 两条路线的 compressed `CMSampleBuffer` 共用一个 Renderer Input Coordination。
- `open`、`close`、`play`、`pause`、`seek`、`setRate` 和 cold route switch。
- 进度、拖动 seek、倍速、音量、静音、reopen、音频轨道选择，以及 macOS / visionOS 上等价的用户控制入口。
- 单一 Playback Window、单一使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace`，以及由 Projection、Placement 与 RealityKit viewing mode 派生的 Flat Window、Portal Window、Docked、Panorama；Stereo 与 Scene Lifecycle 保持正交。
- Media Session、Provider Open Snapshot、Video Track Model、Route Media Event、Video Sample、Renderer Input、RealityKit Binding 与 Presentation Binding records。
- macOS 与 visionOS 共用核心；macOS 是主要 L2 播放 / RealityKit 验证面。
- 版本化 Debug Snapshot、结构化 Debug Event Stream 和 evidence export。
- 保留可观察的 codec、timing、color、HDR 与 Dolby Vision signaling，不自行增加经验性 tone mapping。

当前不实现：

- 自动能力探测、自动路线优先级或失败后隐藏 fallback。
- subtitle entity、chapters、播放列表、续播、网络缓存或 Digital Rights Management (DRM)。
- Apple Spatial Video、Multiview High Efficiency Video Coding (MV-HEVC) 或 Apple Immersive Video。
- 视觉 scanner、环境光、缩略图、播放列表或发行级产品外壳；visionOS 验收 App 的播放与呈现控制必须是完整、产品化的可操作入口。

这些非目标可以进入 future spec，但不能作为当前 video core 完成声明的一部分。

## 公开接口面

PlaybackCore 有控制面、状态面、实体面和诊断面。核心不 import SwiftUI。

| Interface | Direction | Stable responsibility |
|---|---|---|
| Control | App → Core | `open(source:route:)`、`close()`、`reopen()`、`play()`、`pause()`、`seek(to:)`、`setRate(_:)`、`setVolume(_:)`、`setMuted(_:)`、`selectAudioTrack(_:)`、`switchRoute(to:)`。 |
| Presentation Control | SwiftUI / tests → App Adapter | 同一个公开 `PresentationCommand`；表达窗口、Scene、Placement、Projection 与 Stereo 的产品意图，并负责 acknowledgement、binding 交接与失败回滚。 |
| State | Core → App | lifecycle、route、time、duration、rate、audio tracks、selected audio track、volume、mute、presentation dimensions、current error 和离散 playback events。 |
| Renderer | Core → App Adapter | 当前 Media Session 的 video renderer；audio renderer 与 video renderer 由核心加入同一个 synchronizer。App Adapter 用同一 video renderer 建立唯一 active RealityKit 呈现器：平面 `VideoMaterial` 或沉浸 `VideoPlayerComponent`。 |
| Binding facts | App Adapter → Core | component / entity identity、RealityKit binding、`RealityView` presentation 与平台 provenance。 |
| Diagnostics | Core → tests / Lab / logs | Debug Event Stream、`DebugSnapshotV1`、privacy-safe evidence export。 |

产品 scene、`RealityView`、窗口和沉浸空间由 App Adapter 管理。App Adapter 不直接控制 Provider、renderer queue 或内部节点状态。

## 来源与 open admission

`MediaSource` 至少包含：

- `locator`：本地 `file` URL 或未来等价 locator。
- `provenance`：例如 `systemFileImporter`、`documentOpen` 或 `testAutomation`。
- `privacySafeSummary`：可进入日志与 evidence 的摘要。
- `accessRequirement`：本次读取是否需要 security-scoped access。

PlaybackCore 同一时刻只有一个 Current Media Slot。accepted open 创建新的 Media Session ID 并占用槽位；rejected open 不创建 Media Session，必须形成 Open Rejection Record。`close()` 或不可恢复 failure 触发的 Provider cancel、renderer flush 与 binding invalidation 完成后才释放槽位。

App Adapter 拥有长期文件授权。PlaybackCore 只拥有当前 Media Session 的读取生命周期。visionOS cold switch 复用同一来源时，App Adapter 在新会话接管前不得释放 security-scoped access。

## Media Session 与 Open Operation

Media Session 是一次 `accepted open → playback lifecycle → close / failed` 的身份边界。以下事实创建后不可变：

- Media Session ID。
- Media Source Record。
- selected Playback Route。
- initial presentation time 和 initial paused state。

Open Operation 是一次 accepted open 推进节点 2–9 的父级内部记录，state 为 `running`、`completed`、`failed` 或 `terminatedByCleanup`。第一轮 completed 边界是 active `RealityView` 已承载当前 renderer-backed video entity，并且 Debug Snapshot 可以解释整条归属链；连续播放和 displayed frame 是后续独立事实。

旧 Media Session、旧 Stream Epoch 或 cleanup 后 callback 不能更新 Current Media Slot。它们可以作为 stale diagnostic 被记录。

## 生命周期

公开 lifecycle 固定为：

`idle`、`opening`、`ready`、`playing`、`paused`、`ended`、`failed`

- `idle`：没有 active Media Session。
- `opening`：open 已接受，尚未达到 ready boundary。
- `ready`：renderer graph、RealityKit Renderer Binding 与当前 active `RealityView` 的 Presentation Binding 已建立，timeline 可开始或已停在初始位置。只有 renderer graph 或节点 8 binding 时仍是 `opening`。
- `playing`：synchronizer rate 非零，播放时间线正在推进。
- `paused`：active Media Session 存在，synchronizer rate 为零。
- `ended`：video input 已结束；存在选中音轨时 audio input 也已结束；synchronizer time 已越过两条 active lane 最后一个 accepted sample 的最晚呈现终点。
- `failed`：active Media Session 出现不可恢复错误；错误和失败节点已经记录。

任一 Provider end 都不是公开 `.ended`。`.ended` 必须等待 active video/audio lane 的 renderer-drain 可观察 surrogate，并且每个 Stream Epoch 最多产生一次。

## 两条 Playback Route

| Route | Provider ownership | Node 6 output | Node 7 preprocessing |
|---|---|---|---|
| Apple Compressed | `AVAssetReaderTrackOutput(outputSettings: nil)` 读取 storage-format samples。 | compressed `CMSampleBuffer`。 | 无 pixel transfer，直接进入 readiness / enqueue。 |
| FFmpeg Compressed | FFmpeg 打开容器、选择视频流、复制 packet、建立 format description 和 compressed sample。 | compressed `CMSampleBuffer`。 | 无 pixel transfer，直接进入 readiness / enqueue。 |

两条路线必须通过同一个 `VideoSampleProvider` interface 输出 Route Media Event。任何 AVFoundation / FFmpeg object 都不能穿透 Provider seam。

一次 Media Session 只绑定一条路线。路线切换是 cold switch：记录当前 time、rate / paused state 和来源，cleanup 旧会话，再创建新会话。当前不存在同一会话内 hot swap，也不存在 Provider 失败后的自动 fallback。

## Provider Open Snapshot

Provider prepare 成功后产出不可变 Provider Open Snapshot，至少记录：

- schema version、Media Session ID、route 和 source summary。
- provider kind 与 open result。
- container / demuxer summary、duration、seekability。
- observed video tracks；当前第一版至少有一个 selected video track。
- codec、codec tag / media subtype、coded dimensions、nominal frame rate、timebase。
- extradata / codec configuration summary。
- color primaries、transfer function、YCbCr matrix、range、projection、view packing 和可见 HDR signaling。
- Provider 没有暴露的事实使用 `notExposed`，不能写成 `unknown` 掩盖 seam 缺口。

Snapshot 只记录 open-time structure，不记录连续 sample、renderer 或 displayed frame。

## Video Track Model

PlaybackCore 从 Provider Open Snapshot 建立自己的 Video Track Model。每条 track 至少包含 opaque `videoTrackID`、raw source mapping、codec facts、dimensions、timing basis、format facts、selected 和 not-selected reason。

第一版选择一个 primary video track。没有可用 primary video track 时节点 4 失败。Video Track Model ID 不等于 AVAsset track identity、FFmpeg stream index 或 UI row identity。

## Route Media Event Stream

Provider 只为 selected video track 建立事件流。事件类型为：

- `sample`：带 `CMSampleBuffer` payload 或 Provider 内部尚未标准化的 sample payload。
- `formatChanged`：创建新的 Format Revision。
- `flush`：使旧 Stream Epoch 的后续输入失效。
- `end`：输入结束，不等于 public ended。
- `error`：包含 source、code、message、recoverability 和 route provenance。

每个事件必须携带 Media Session ID、route、Video Track ID、Stream Epoch、Format Revision 和 privacy-safe source identity。FFmpeg packet bytes 必须在跨过 C callback / read 生命周期前复制或转移所有权；Apple storage sample 的 CoreMedia ownership 必须在 Provider 生命周期内有效。

Stream Epoch 用于 seek、reset、reopen 和 cleanup 隔离；Format Revision 用于同一 track 格式变化。两者不能合并成一个版本号。

## Video Sample Stream

节点 6 把 Route Media Event 标准化为 `videoSample` 或 `controlMarker`。

每个 video sample 至少记录：

- Media Session ID、route、Video Track ID、source event ID。
- input kind：compressed。
- Stream Epoch、Format Revision。
- PTS、DTS、duration、sample count 和 sync / dependency summary。
- format description identity、compressed media subtype、dimensions。
- color / HDR / projection summary 和 payload ownership。

Apple Compressed 对 storage sample 做合同验证后交付；FFmpeg Compressed 将不同容器的 packet 与 codec configuration 标准化为 compressed sample。每条路线的生产证据独立记录。

## Shared Audio Lane

音频独立于两条 Video Sample Provider，并由两条路线共享同一个 FFmpeg Audio Track Provider。Provider 枚举可解码音轨并保留 raw stream index、codec、language、sample rate 和 channel count；没有可解码音轨时记录为空目录，不创建伪音轨，也不使只有视频可用的媒体播放失败。

选中的压缩音轨由 FFmpeg 解码并重采样为交错 Float32 Linear PCM `CMSampleBuffer`，交给 `AVSampleBufferAudioRenderer`。每个 PCM sample 至少保留 Media Session ID、Stream Epoch、raw stream index、PTS、duration、sample rate、channel count、sample count 和 ownership；audio renderer、video renderer 与 synchronizer 必须记录相同 graph ID 和 Media Session ID。

seek 在目标时间重建 audio input，并与 video epoch、renderer flush 和 synchronizer target time 一起恢复。音轨选择是事务：在当前时间准备新轨、替换 audio input 并恢复之前的 rate / paused state；若新轨准备失败，必须恢复旧轨、旧 renderer input 和旧时间线状态，只有恢复也失败时才使会话 terminal failed。

## Renderer Input Coordination

节点 7 拥有 video/audio renderer graph、两条 delivery queue、共享 timeline、backpressure、flush、end 和 error mapping。它的 public interface 不暴露两条视频 Provider adapter 或 FFmpeg 私有音频对象。

稳定规则：

- 首个有效 video sample 的 PTS 必须在第一次 video enqueue 前建立 synchronizer timeline。
- compressed video sample 不经过 pixel transfer；audio input 只接受 Linear PCM sample。
- video 与 audio delivery 分别由各自 renderer readiness 驱动；`isReadyForMoreMediaData == false` 是正常 backpressure。
- 不允许无界 enqueue；每个 accepted / deferred / stale / failed video input 都形成 Renderer Input Record，audio input 的对应事实进入 Audio Renderer State Record。
- seek、format change、route switch、audio track switch 和 cleanup 必须真实作用于对应 renderer queue，不得只改状态字段。
- renderer graph 只接受当前 Media Session 和当前 Stream Epoch 的 input。
- renderer error 和 requires-flush condition 必须进入稳定错误面。

Renderer enqueue、renderer rendering、displayed pixel buffer、连续帧推进和颜色正确是五个独立事实。

## 运行控制

外部控制先形成 Control Request，再经过 Request Admission；rejected request 形成 Rejection Record。open、play、pause、setRate、seek、switchRoute 和 close 形成 Runtime Operation；volume、mute 和 audio-track transaction 形成对应 renderer state / Debug Event；reopen 是等待旧 cleanup 后的新 Open Operation。详细语义见 `acceptance/runtime-control.md`。

- `play()`：当前 timeline 已建立时设置目标 rate，完成边界是 synchronizer action 被记录。
- `pause()`：将 synchronizer rate 设为零，完成边界是 timeline action 被记录。
- `setRate(_:)`：验证 rate 后设置 synchronizer；非法值明确 rejected 或 failed。
- `seek(to:)`：先让 active Provider seek / rebuild stream，递增 Stream Epoch，flush renderer，再用目标 time 恢复 synchronizer。连续 seek 采用最后一次请求优先。
- `setVolume(_:)`：验证范围后更新 active audio renderer，并记录当前值；无 audio renderer 时保留偏好但不能伪造已输出声音。
- `setMuted(_:)`：更新 active audio renderer mute state 并记录当前值。
- `selectAudioTrack(_:)`：按 Shared Audio Lane 的事务边界替换音频输入；失败时先恢复旧轨和播放状态。
- `switchRoute(to:)`：执行 cold switch；旧 operation 被完成或 terminated，新会话独立 open，并迁移 time、preferred rate / paused state、volume、mute 与可匹配音轨选择。
- `reopen()`：等待旧会话 Provider cancel 与 renderer flush 完成，再以同一 source、route 与 access requirement 创建新 Media Session；它不复用旧 graph 或旧 node records。
- `close()`：停止 delivery、取消 Provider、flush audio/video renderer、使 binding / presentation 失效；cleanup barrier 完成后才释放 current slot。

seek 进行中，更新的 seek request 可以 supersede 旧 seek；其他依赖 timeline 的控制明确 rejected 为 `operationInProgress(.seek)`。close 与 cold route switch 可以终止 seek 并进入 cleanup，不能与旧 seek callback 共同更新当前事实。

当前核心不默认 loop。loop 和下一媒体属于 App policy。

## RealityKit 与 App Adapter

节点 8 由 App Adapter 将核心提供的 renderer 交给唯一 active RealityKit 呈现器，再把 identity 与 active state 回填给 PlaybackCore。Flat Window 与 Docked 使用运行时平面网格上的 `VideoMaterial(videoRenderer:)`；Portal Window 与 Panorama 使用 `VideoPlayerComponent(videoRenderer:)`。renderer、呈现器、entity、route 和 binding identity 必须属于同一个 Media Session；切换时必须先解除旧呈现器，任意稳定时刻只有一个 active binding 消费当前 renderer。

节点 9 由 App Adapter 把 renderer-backed entity 放入 active `RealityView`。macOS Playback Lab 和 visionOS Playback Lab 都使用这一接口。`RealityView` identity、scene lifecycle、entity attached state 与 presentation binding 由 App Adapter 回填，provenance 不能冒充 core fact。

PlaybackCore 不负责调用 SwiftUI 的 open / dismiss scene，也不把产品形态压成一个 `setMode` enum。它负责 detected / effective projection、stereo、audio-video timeline 与可迁移 renderer；App Adapter 必须实际实现以下 presentation，并将 RealityView placement、scene container、scene lifecycle 与 transition 回填。

visionOS App Adapter 只建立三个系统容器：独立 Control Window、单一 Playback Window，以及单一 Playback `ImmersiveSpace`。Control Window 只承载文件入口、播放控制、路线冷切换和呈现操作，不包含 `RealityView`，并提供显式 Open Playback Window 操作。Playback Window 只有一个 content-only `RealityView`，Flat Window 与 Portal Window 在这里复用同一 Entity、同一 binding 和标准可移动 Window Bar。Playback Window 与 Playback Immersive Space 内不得再放 SwiftUI 播放控件、toolbar、attachment 或遮挡画面的 overlay；系统 Window Bar 不属于播放控件，必须保持可用。Playback `ImmersiveSpace` 使用 `.progressive(0...1, initialAmount: 1)`；它在 `customScene` 与 `blackPanorama` 两种内容角色间切换，不建立 Docked、Progressive、Full 三个并行空间。App 启动只打开 Control Window。

产品播放形态不是核心 `setMode` 枚举。App Adapter 先从 Projection Intent、Playback Placement 与 Scene Content 推导 Candidate Product Shape；这只是目标组合，在没有媒体或转换中仍可存在。只有 active video entity 已进入 attached 的目标容器并具有正确 parent / Presentation Binding、Effective Projection、该形态要求的 actual mode，且 renderer settled，才能提交 Presented Product Shape；否则公开状态必须是 `none` / Not Presented。Stereo Layout 与 Scene Lifecycle 保持独立，不参与候选形态判定：

| Product Playback Shape | Presentation Geometry | Placement / Scene Content | `desiredImmersiveViewingMode` |
|---|---|---|---|
| Flat Window | runtime planar mesh + `VideoMaterial` | Playback Window 的唯一 `RealityView` | 不参与判定 |
| Portal Window | `VideoPlayerComponent` 使用来源全景投影 | 同一个 Playback Window `RealityView` | `.portal` |
| Docked | runtime planar mesh + `VideoMaterial` | open `ImmersiveSpace` 的 `customScene`；平面 entity 挂到保留 RCP `world/screen` authored transform 的纯 runtime docking anchor | 不参与判定 |
| Panorama | `VideoPlayerComponent` 使用来源全景投影 | 同一个 `ImmersiveSpace` 的 `blackPanorama`；全部 RCP `customScene` 内容隐藏，且不使用 docking anchor | `.progressive` |

`.full` 不构成第五种产品形态，也不在第一版 UI 或自动回归中作为独立入口。这里出现的两个 `.progressive` 都是平台 API 状态而不是产品形态：Panorama 使用 `VideoPlayerComponent.ImmersiveViewingMode.progressive`，Playback Immersive Space 使用 progressive `ImmersionStyle` 且 initial amount 为 1；用户可以用 Digital Crown 降低空间覆盖度。`desiredSpatialVideoMode` 不属于本项目的普通 mono / side-by-side / over-under 路线。

Detected Projection 是 Provider open 记录的来源事实：Rectilinear、Half Equirectangular、Equirectangular、无投影标记或平台支持的其他来源投影。Apple Compressed 创建 `AVURLAsset` 时启用 external spherical tag 解析；系统从兼容 Spherical v1/v2 标签合成的 format-description projection 必须保留 synthesis provenance，不能冒充文件原生 APMP。第一版 App Projection Intent 是 `flat` 与用户可明确选择的 `panoramic360`（当前代码内部名称仍为 `sourcePanoramic`）；核心 sample-format seam 同时支持 Half Equirectangular，供后续 180° UI 使用。

Projection Intent 同时决定 Presentation Geometry 与必要的 Effective Projection。`flat` 使用运行时平面网格与 `VideoMaterial`，并清除 App 注入的 projection override；`panoramic360` 使用 `VideoPlayerComponent`，优先采用来源或系统合成的 Equirectangular 标记，缺失时才在两条 Provider 汇合后的 renderer 输入边界补充 `Equirectangular`。该 override 只重建 `CMFormatDescription`，不修改媒体文件、compressed payload、timing、attachments、HDR / Dolby Vision signaling、Stream Epoch、Media Session、renderer graph、timeline 或 rate；它递增 Format Revision，且 Detected Projection 与 Effective Projection 必须分别记录。只有新 revision 已被同一 renderer 接受、目标 Entity/binding 成立、RealityKit actual mode 已确认且画面继续推进后，App Adapter 才提交 Projection Intent。

Scene Lifecycle 与播放器独立。Scene 可以在媒体之前打开。`openScene` 只打开唯一 Immersive Space 并显示 `customScene`；它不创建 Media Session、不迁移 video binding，也不自动 Dock。已有 Window 播放时，Open / Close Scene 都不得迁移 Entity、替换 renderer 或改变 Media Session。`closeScene` 只在当前 binding 位于 Playback Window 时提供；Docked 必须先执行 Window，Panorama 必须先执行 Portal，随后才会出现 Close Scene。Custom Scene Intent 是独立事实：进入 Panorama 前保存该意图；退出到 Portal 或在 Panorama 中关闭媒体时，必须先清除 `blackPanorama`，原本要求打开则恢复 `customScene`，原本要求关闭则关闭 Immersive Space。

用户可见操作由 SwiftUI 根据当前派生形态提供，不把所有结果形态做成一个 mode picker：

| Current shape | Primary user operations |
|---|---|
| Flat Window | Open / Close Scene；Scene open 时可 Dock；高级面板可选择全景投影。 |
| Portal Window | Open / Close Scene；可展开为 Panorama；不显示 Dock。 |
| Docked | 回到 Window；高级面板可直接选择全景投影进入 Panorama；不显示 Portal。 |
| Panorama | 回到 Portal；高级面板选择 Flat 时回到 Flat Window；不显示 Dock。 |

所谓非法操作不是另一套需要 PlaybackCore 穷举的运行状态机。Portal / Panorama 中的 Dock、Scene closed 时的 Dock、Docked 中的 Portal 等意图不进入产品 UI；对应按钮不存在或 disabled。代码驱动回归也只执行产品公开的合法用户意图。少量 UI smoke 负责证明按钮可见性和 disabled 状态。

跨 surface 命令必须使用 target-first transaction：先打开目标容器，再把同一个 Entity 迁入并建立目标 Presentation Binding，解除旧 Presentation Geometry 并绑定目标呈现器，然后在目标 surface 请求所需 RealityKit mode；只有必要的 mode acknowledgement 来自当前 Media Session、当前 Entity 和目标 view identity，且目标 renderer settled 后，才能关闭来源容器。旧 surface 的迟到事件必须被忽略；打开请求超时后的迟到 surface 必须被拒绝并关闭。Flat / Portal 稳态要求 Playback Window open；Docked / Panorama 稳态要求 Playback Window closed，避免多余 Window Bar。Docked 是平面网格停靠，不使用 `.portal`；Panorama 不使用 RCP docking anchor。

`showWindow` 不是任意跨形态跳转：它按当前 Projection 把 Docked 恢复为 Flat Window，或把 Panorama 恢复为 Portal Window。高级 Projection 覆盖从 Docked 选择全景时进入 Panorama，从 Panorama 选择 rectilinear 时进入 Flat Window；两条路径仍由同一个公开命令处理 acknowledgement、binding 交接与回滚。

Stereo Layout 是独立高级呈现维度，取值 `mono / sideBySide / overUnder`。每种产品形态都允许独立切换 Stereo；切换不得改变 Projection、Playback Placement、Scene Lifecycle、Scene Content 或产品形态。两条 Provider 汇合后、renderer enqueue 前的共享 sample-format seam 负责产生 effective `viewPackingKind` 与左右眼 presence；它保留 payload、timing、attachments、projection、HDR / Dolby Vision signaling。热切换只短暂 quiesce video input，递增 Format Revision，不伪装成 seek，不 flush renderer，不重建 Provider，也不改变 Stream Epoch、renderer graph、timeline 或 rate。App 只有在新 revision 的 sample 已被同一 renderer 接受且 RealityKit `ViewingModeDidChange` 已确认后，才提交 Stereo Layout；`desiredViewingMode` 或 UI requested state 单独都不算成功。

SwiftUI 控件与自动回归只调用同一个公开 `PresentationCommand`。命令表达 `openPlaybackWindow`、`closePlaybackWindow`、`openScene`、`closeScene`、`showWindow`、`dock`、`showPanorama` 和 Stereo / Projection override 等产品意图；它统一负责必要的 RealityKit acknowledgement、scene 交接、Entity binding、renderer settle 与失败回滚。回滚顺序固定为 ensure source containers → restore intent and binding → request / await source mode → await source settled → close failed target → validate exact lifecycle / facts；命令失败与 `rollbackFailed` 必须同时保留，不能用 desired snapshot 冒充恢复成功。测试只在输入端代替 UI，不持有 probe 专属的呈现编排。

scene lifecycle、Scene Content、requested / active binding、desired / actual viewing mode、RenderingStatus、displayed pixel buffer 和人工观感是独立事实。Simulator 可以把 hardware-only actual state记录为 `unknown` / `notAvailable`；不得用 Scene open 冒充 Docked，不得用 desired state 冒充设备 actual state。

## Color、HDR 与 Dolby Vision

PlaybackCore 不自行调节曝光，也不提供 tone-mapping knob。它负责保留和记录：

- color primaries、transfer function、YCbCr matrix 和 range。
- mastering display、content light level、ambient viewing environment 等可见 metadata。
- compressed format 的 sample-description atoms，例如 `hvcC`、`dvcC`、`dvvC` 和 `amve`。
- Apple renderer 暴露的 displayed pixel buffer 与 format description 上可观察的 color / HDR attachments；这是 renderer 输出事实，不是第三条 Provider 路线。

metadata 的缺失、冲突和 Provider 不暴露必须可区分。Apple runtime、container / sample description、bitstream 和 inferred/default 是不同 provenance，不能用单一 `isHDR` 布尔替代。

macOS 可以证明 metadata contract、sample delivery、renderer 和 displayed pixel buffer，不能证明 Vision Pro HDR / EDR 观感。Dolby Vision Profile 5、8.1、8.4 的 Apple Compressed 真机结论见 `acceptance/dolby-vision-apple-compressed.md`。

## Debug Event Stream 与 Snapshot

每个节点、Open Operation 和 Runtime Operation 在状态边界发布结构化 Debug Event。事件至少包含 schema version、sequence number、timestamp、Media Session ID、route、node / operation、kind、outcome 和 privacy-safe details。默认不逐帧打印；sample heartbeat 采用聚合计数和最近 sample 摘要。

`DebugSnapshotV1` 由当前稳定 records 派生，至少包含：

- source、session、route、lifecycle、Open / Runtime Operation。
- Provider Open Snapshot 和 Video Track Model 摘要。
- stream epoch、format revision、sample counts、last timing、input kind。
- renderer graph、timeline、readiness、backpressure、flush、enqueue 和 error。
- available audio tracks、selected raw stream index、PCM count / timing、volume、mute、audio renderer state，以及 audio/video renderer 与 synchronizer 的 graph identity。
- RealityKit binding、presentation binding 和 App Adapter provenance。
- color / HDR / Dolby Vision signaling。
- platform-only placeholders 和当前 evidence correlation IDs。

未实现或不可观察字段仍保留 typed missing state。Snapshot 是当前状态投影，不替代 node record，也不自动构成 acceptance evidence。

## 完成边界

PlaybackCore 与验收 App 完成需要：

1. FFmpeg 主线与 Apple 对照层各自通过 Provider / sample / renderer / RealityKit 合同，并共享同一条音频实现。
2. 有音频媒体在 macOS L2 产生可听输出；音频与视频 renderer 属于同一 Media Session 和 synchronizer；play、pause、seek、rate、close、reopen 和冷切换后保持同步。
3. 音频轨道发现、选择、音量和静音具有核心操作、macOS UI、visionOS UI、Snapshot 和独立证据。
4. seek、进度、倍速、reopen 与轨道选择可由普通观看者在两个 App 中直接操作；只存在 CLI 或内部方法不算完成。
5. Flat Window、Portal Window、Docked 和 Panorama 均有实际 App Adapter 实现、按当前形态裁剪的可见控制、transition state、唯一 active binding 与 Simulator scene/API 证据；Docked 使用 RCP `world/screen` 的运行时 transform 建立纯 Entity anchor，Portal 与 Flat 复用同一个 window `RealityView`，Panorama 与 Docked 复用同一个使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace`。
6. Debug Event Stream 与 `DebugSnapshotV1` 覆盖音频、控制和 presentation transition，并可由运行中的 App 实时读取。
7. macOS 无法等价覆盖的 visionOS adapter 在 Simulator 通过；Vision Pro 只完成真实设备显示、HDR / EDR、真实听感和设备专属连续性。

旧 xr-fork evidence 只证明旧实现曾可行。除非在当前源码、fixture 和 evidence ledger 下重新产生证据，否则不能声明当前 PlaybackCore 已通过相同条目。
