# Spec：播放核心

这是播放核心的活跃设计规格，覆盖系统行为、接口边界、数据主线、产品播放形态和稳定约束。历史理由保存在 `archive/adr/`，验收方法见 `acceptance/verification-system.md`，当前验收事实见 `acceptance/evidence.md`。

## 目标

播放核心负责把 Demux Contract 输出的压缩音视频样本送入 Apple sample-buffer / RealityKit 播放路径，并暴露一个 UI 无关、SwiftUI 无关的 Swift Package。当前 MVP 使用 FFmpeg demux adapter；mpv 是契约稳定后的候选 adapter，不是核心所有权的一部分。

播放核心必须做到：

- 使用系统硬解路径播放压缩视频样本。
- 保留、解析、合并并传递投影、立体布局、High Dynamic Range (HDR) 和色彩 metadata。
- 输出 RealityKit 视频实体和字幕实体。
- 提供稳定控制面、状态面、实体面和诊断面。
- 支撑 Window、Docked Immersive、Panorama 和 Portal 四种产品播放形态。
- 在进入真机前，通过 L1 和 L2 验证所有可以在 host 或 visionOS 模拟器中证明的逻辑、metadata 和调试字段。

播放核心不做这些事：

- 不 import SwiftUI。
- 不持有播放列表、下一集、续播策略、网络缓存或正式 UI。
- 不提供用户可调 HDR tone mapping。
- 不处理 Apple 空间视频、Multiview High Efficiency Video Coding (MV-HEVC) 或 Apple Immersive Video。
- 不支持 Digital Rights Management (DRM) 或受保护内容。
- 不让 FFmpeg 或 mpv 的内部对象穿透 Demux Contract；adapter 可以依赖各自 provider，核心模块不得依赖它们。
- 当前阶段不运行视觉 scanner，不建立 `PanoramaScannerLab`，不要求 classifier 跑分或生产采样 adapter。

## 公开接口

播放核心有三组运行接口和一个诊断接口。

| 接口面 | 方向 | 职责 |
|---|---|---|
| 控制面 | App 到 Core | `open(source:)`、`close()`、`play()`、`pause()`、`seek(to:)`、逐帧、轨道选择、投影和立体布局覆盖。 |
| 状态面 | Core 到 App | 生命周期、时间线、buffering、轨道、detected / effective projection、detected / effective stereo layout 和事件流。 |
| 实体面 | Core 到 Scene | 视频实体和字幕实体。 |
| 诊断面 | Core 到 Test / 验证 App / Logs | 稳定 Debug Snapshot JSON。 |

控制面不提供 `setMode`。产品播放形态由 App Adapter 根据当前投影、当前立体布局、`desiredViewingMode`、`desiredImmersiveViewingMode`、SwiftUI scene container 和 `RealityView` binding 组合。

生命周期状态固定为：

`idle`、`opening`、`ready`、`playing`、`paused`、`ended`、`failed`

`open` 与 `close` 在任何状态可调用。`play`、`pause`、`seek`、选轨和呈现维度覆盖只在有媒体会话时有效；没有媒体会话时按空操作处理。

`seek(to:)` 接收秒，核心负责换算为 `CMTime`，并执行 mpv seek、renderer flush 和 synchronizer 恢复的固定时序。连续 seek 采用最后一次请求优先：旧请求可以被取消或合并，最后一次请求必须完成或进入 `failed`。

`.ended` 表示用户可见的呈现时间线结束。mpv EOF 只表示输入结束；核心必须等 renderer drain 后才进入 `ended`，并且每次播放结尾最多触发一次 `.ended`。

稳定接口细则如下：

| 范围 | 语义 |
|---|---|
| `stepForward()` / `stepBackward()` | 逐帧由播放核心自己实现，不依赖 mpv 自带 frame-step。 |
| `setRate(_:)` | 直接设置 `AVSampleBufferRenderSynchronizer` 速率；非法 rate 进入错误面。 |
| 轨道选择 | audio track 使用 mpv `aid`；subtitle track 使用 mpv `sid`；关闭字幕传 `nil`。 |
| `isBuffering` | 播放途中数据供不上时为 true，生命周期状态仍是 `playing`。它不同于打开阶段的 `opening`。 |
| `chapters` | 来自媒体章节；跳章节复用 `seek(to:)`，播放核心不新增章节跳转 API。 |
| 音频会话与中断 | `AVAudioSession` 配置和中断事件归播放核心。中断开始切到 `paused` 并发 `.interruptionBegan`；中断结束发 `.interruptionEnded(shouldResume:)`，是否恢复由 App 决定。 |
| 音量与静音 | 不进入播放核心控制面，交给系统音量和产品 UI。 |

## 数据主线

主数据流是：

```text
demux provider container open snapshot
→ Track Model
→ demux adapter 解封装
→ 压缩音视频 packet
→ CMBlockBuffer
→ CMSampleBuffer
→ AVSampleBufferVideoRenderer / AVSampleBufferAudioRenderer
→ AVSampleBufferRenderSynchronizer
→ VideoPlayerComponent
→ RealityView
```

稳定约束：

- demux adapter 负责解封装；最终视频解码和播放输出由 Apple media 路径负责。
- Container Open Snapshot 记录 demux provider 打开容器后可观察的媒体结构事实；播放许可、packet、sample、frame 和 renderer 事实由后续阶段处理。
- Swift 侧必须把 provider 数据复制成自己的 envelope，不能跨回调生命周期持有 FFmpeg 或 mpv 内部对象。
- 视频和音频都进入 Apple sample-buffer renderer，并由同一个 `AVSampleBufferRenderSynchronizer` 管理时间线。
- 送帧由 renderer readiness 驱动。播放核心按 `isReadyForMoreMediaData` 喂样本；renderer 不要数据时，队列自然形成 backpressure。
- 播放核心不提供公开 `suspend()` / `resume()`。前端进入后台或关闭沉浸空间时调用 `pause()`；presentation transition 内部可以短暂暂停 renderer delivery，但这不是 App API。
- 参数集、extradata、presentation timestamp (PTS)、decode timestamp (DTS)、duration、keyframe、轨道 metadata、投影 metadata、立体布局 metadata、HDR 与色彩 metadata 都是 sample-buffer 路径的一部分。
- format description 失效或改变时，核心必须 flush renderer，并重建格式描述。
- 系统硬件不能解码的编码就是不支持，返回 `unsupportedCodec`。

字幕不走纯文本 UI 通道。播放核心按时间线产出字幕 bitmap 或等价图片纹理，并通过字幕实体交给场景摆放。

## 呈现维度

`Projection` 表达画面几何：

- `rectilinear`
- `halfEquirectangular`
- `equirectangular`
- `fisheye`
- `unknown`

`rectilinear`、`halfEquirectangular` 和 `equirectangular` 对齐 `CMFormatDescription.Extensions.Value.ProjectionKind`。`fisheye` 表示通用鱼眼或双鱼眼检测值，不等同于 Apple Immersive Video 专用的 `kCMProjectionType_Fisheye`。在通用鱼眼的系统投影或 dewarp 路径被证明前，它默认按 Window 打开，并在诊断中记录禁用原因。

`StereoLayout` 表达 view packing：

- `mono`
- `sideBySide`
- `overUnder`
- `unknown`

`desiredViewingMode` 由 `StereoLayout` 派生。`mono` 和 `unknown` 对应 `.mono`；`sideBySide` 与 `overUnder` 对应 `.stereo`。`viewPackingKind` 只在明确 `sideBySide` 或 `overUnder` 时写入。这里的 `desiredViewingMode` 指 RealityKit `VideoPlaybackController.ViewingMode`，只表达 mono 或 stereo。

`desiredImmersiveViewingMode` 指 RealityKit `VideoPlayerComponent.desiredImmersiveViewingMode`，保留 `full`、`progressive` 和 `portal`。它只用于当前 `effectiveProjection` 是全景投影的展示路径。Window 与 Docked Immersive 是平面展示，不设置 `desiredImmersiveViewingMode`。SwiftUI `ImmersionStyle` 属于 `ImmersiveSpace`，不属于 `VideoPlayerComponent`。

## 产品播放形态

产品播放形态不是核心 enum，也不是 Apple API enum。它描述用户看到的视频呈现结果。

| 产品播放形态 | 路由条件 | 播放承载面 | `desiredImmersiveViewingMode` |
|---|---|---|---|
| Window | 平面安全投影 | 默认 scene 中的 Window `RealityView` | 无 |
| Docked Immersive | 平面安全投影 | `ImmersiveSpace` 自制场景里的 Docked `RealityView` | 无 |
| Panorama | `halfEquirectangular`、`equirectangular` 或已验证可投影的 `fisheye` | `ImmersiveSpace` 黑场 `RealityView` | `progressive` 或 `full` |
| Portal | `halfEquirectangular`、`equirectangular` 或已验证可投影的 `fisheye` | 默认 scene 中的 Portal `RealityView` | `portal` |

概念分层如下：

| 层 | 归属 | 取值 | 说明 |
|---|---|---|---|
| 原始识别 | 核心 | `detectedProjection`、`detectedStereoLayout` | 打开视频时识别出的默认值，`open()` 后不再变化。 |
| 当前媒体呈现 | 核心 | `effectiveProjection`、`effectiveStereoLayout`、`desiredViewingMode`、`desiredImmersiveViewingMode` | 当前请求的媒体呈现值，可由用户覆盖。 |
| Scene 呈现 | App | `WindowGroup`、`ImmersiveSpace`、`ImmersionStyle` | 前端通过 SwiftUI scene 决定内容所在的系统容器和沉浸样式。 |
| RealityKit 承载 | App + RealityKit | `RealityView`、视频实体、字幕实体、`VideoPlayerComponent` binding | 视频实体实际绑定和显示的地方。 |
| 产品播放形态 | App 组合 | Window、Docked Immersive、Panorama、Portal | 用户看到的形态。 |

默认打开只在 `open(source:)` 后生效。平面安全投影指 `rectilinear`，以及只作为检测或诊断值出现的 `unknown`。当没有明确 metadata 时，核心使用 `rectilinear + mono` 作为生效默认值，并在 Snapshot 中记录 `noMetadataDefault`；metadata 缺失仍保持为缺失状态。未验证可投影的通用 `fisheye` 默认进入 Window，并记录禁用原因。`halfEquirectangular` 和 `equirectangular` 默认进入 Panorama。

播放过程中，当前形态由 `effectiveProjection`、`effectiveStereoLayout`、当前视频实体绑定的 `RealityView`、托管该 `RealityView` 的 scene 容器、`ImmersionStyle` 和 `desiredImmersiveViewingMode` 决定。`ImmersiveSpace` 可以已经打开，但视频仍然绑定在默认 scene 中的 Window `RealityView`；此时当前播放形态仍是 Window。

Open Scene / Close Scene 只管理 `ImmersiveSpace` 生命周期。Placement 只管理 active playback binding 在 Window `RealityView` 还是 Docked `RealityView`。Projection 和 Stereo 只能由识别结果或用户覆盖改变；scene 操作不得静默重写它们。

任意时刻只能有一个 active `VideoPlayerComponent(videoRenderer:)` 消费同一个 renderer。场景切换必须能在验证快照中解释当前容器、实体身份、active binding 和转场阶段。

## Metadata 识别与注入

打开时的自动识别优先级固定为：

1. Apple / CoreMedia 明确 metadata。
2. 核心从容器或码流解析出的明确 metadata。
3. 当前阶段的安全默认值。

自动识别只产出 `detectedProjection` 和 `detectedStereoLayout`。用户手动覆盖是运行时规则，不属于自动识别：覆盖值永远优先，并写入 `effectiveProjection` 或 `effectiveStereoLayout`。每次新的 `open(source:)` 都重新识别，覆盖不跨媒体保留。

自定义 sample-buffer 管线里，renderer 只看到核心构造的 `CMFormatDescription`。核心必须把原文件能得到的投影、立体布局、HDR 与色彩 metadata 补回 Apple 运行时对象。

当没有明确 metadata 时，当前阶段默认 `rectilinear + mono + Window`。Debug Snapshot 必须把该来源标为 `noMetadataDefault`，并保留 scanner 占位字段 `source = "notRun"`。这个默认值是保守策略，不是媒体事实。

HDR / Color metadata 覆盖三层：

- 编码码流层，例如 Video Usability Information (VUI) 与 Supplemental Enhancement Information (SEI)。
- 封装容器层，例如 `colr`、`mdcv`、`clli`、`amve`、`dvcC` 或 `dvvC`。
- Apple 运行时对象层，例如 `CMFormatDescription` extension、`CMSampleBuffer` attachment 或 `CVPixelBuffer` attachment。

HDR / Color metadata 冲突时，核心不做复杂自动裁决。它保留 bitstream、container 与 runtime 侧原始摘要，标记 `metadataConflictStatus`，并按稳定优先级选择 `finalMetadataSource`：

```text
Apple / CoreMedia runtime metadata
→ container metadata
→ bitstream metadata
→ inferred / default
```

## App Adapter 边界

App Adapter 负责 SwiftUI scene 与空间编排：

- `WindowGroup` / `ImmersiveSpace` 打开关闭。
- Window 与 Docked Immersive 之间的实体挂载或重挂载。
- Panorama 与 Portal 之间的 scene 编排。
- `ImmersionStyle`、表冠、黑场、自制场景和调暗等 SwiftUI / scene 行为。
- loop、下一集、播放列表和正式 UI 策略。
- 将 UI 无关的 presentation context 回填给验证快照，例如 `sceneContainer`、`productShape`、`sceneLifecycleState` 和 `lastSceneTransition`。

播放核心负责：

- 播放时间线连续。
- 状态与事件上报。
- 投影、立体布局、HDR / Color metadata 写入 Apple 运行时对象。
- Core Debug Snapshot。
- 视频实体与字幕实体的 renderer / texture 绑定。

## Debug Snapshot

Debug Snapshot 是稳定诊断接口，不属于正式产品 UI。字段名不能绑定 UI 文案。未实现、平台不可得或硬件不可观测的字段必须存在。通用缺失状态使用 `unknown`；特定平台观测字段如果需要更细的不可观测原因，必须在该字段自己的取值集合中定义。

Debug Snapshot 由 Media Session 中的结构化事实、播放核心当前状态和 App Adapter 回填的 presentation context 派生。节点产出自己的事实记录；Snapshot 负责把这些事实组织成测试、验证 App、日志和证据记录可以稳定读取的 JSON。

核心只拥有播放、metadata、renderer 和 entity 事实。`sceneContainer`、`productShape`、`sceneLifecycleState` 等 scene 事实由 App Adapter 通过 UI 无关的 presentation context 回填。验证 App 可以采集和合并这些事实，但必须保留 provenance；验证 App 补充的观察事实不能冒充 App Adapter 提供的产品可复用事实。没有 App Adapter 回填时，这些字段必须是 `unknown`，不能由核心猜测。

当前阶段的 scanner 诊断是占位结构。未运行 scanner 时，字段稳定输出：

```text
source = "notRun"
classifierVersion = null
confidence = null
reasons = []
elapsedMs = null
timedOut = false
sampledFrames = 0
```

字段组至少覆盖媒体、编码与色彩、HDR / Color metadata、压缩包与样本、时间线、投影、立体布局、scanner 诊断、产品播放形态、Entity / Scene、Renderer、Loop / Ended、错误与事件、真机辅助。

## 验收边界

当前仓库验收目标是 L1 和 L2 通过。L3 是真机设备验收，验证 host 和模拟器无法证明的剩余事实。验收方法见 `acceptance/verification-system.md`，当前证据账本见 `acceptance/evidence.md`。

开放风险：

- 压缩样本格式描述上的 Apple Projected Media Profile (APMP) 注入是否被真实 Vision Pro 显示路径消费。
- 通用 `fisheye` 投影在 sample-buffer 管线中的具体支持路径，或明确保持第一版不支持系统投影。
- HDR / Extended Dynamic Range (EDR) 真实显示效果。
- 高刷新率、性能、thermal、真实听感和体感连续性。
- 播放中的产品形态切换在真机上的连续性。
