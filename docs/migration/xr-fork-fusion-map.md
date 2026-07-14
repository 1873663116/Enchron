# xr-fork → PlaybackCore 融合映射

本文件是迁移审计记录，不是运行规格。当前行为以源码、测试和运行证据为准；当前设计以 `docs/core-spec.md` 为准；当前验证模型以 `docs/acceptance/verification-system.md` 为准。

## 融合结论

PlaybackCore 保留 xr-fork 已形成的 Media Session、Track Model、事件世代、格式版本、节点事实记录、Debug Snapshot、Renderer Input Coordination、RealityKit binding、scene presentation 与 L1 / L2 / L3 验证边界，但不迁移以下旧前提：

- mpv 是唯一解封装实现。
- FFmpeg 只能作为实验依赖。
- 把 FFmpeg Decoded 或 uncompressed sample 当成当前正式第三条路线。
- 不建立 macOS App。
- visionOS Simulator 是所有 RealityKit 集成的默认 L2 环境。
- 为 Portal、Fixed Immersive Screen、Docked 和 Panorama 分别建立窗口或 `ImmersiveSpace`。
- Scene open 自动创建或迁移播放器，或由 probe 维护另一套呈现转换。
- 把 SwiftUI 播放控件放进 Playback `RealityView`、attachment 或沉浸空间。

当前路线只有 Apple Compressed 与 FFmpeg Compressed。两条路线在 `VideoSampleProvider` 处分流，输出统一的 compressed Video Sample Stream，并复用同一个 Renderer Input Coordination、renderer、synchronizer 与 RealityKit binding。macOS Playback Lab 是可见播放与 RealityKit 集成的主要 L2 环境；visionOS Simulator 只补充平台独有的 scene / API 集成，Vision Pro 只承担设备显示、HDR 观感和其他无法等价观察的事实。

## visionOS presentation 迁移边界

| xr-fork / 旧 PlaybackLab 输入 | 当前处置 |
|---|---|
| 独立 Portal Window、Fixed Immersive Screen、多个 `ImmersiveSpace` | 废弃。当前只有独立 Control Window、单一 Playback Window 和单一使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace`。 |
| Progressive、Full、Docked 被当成并列 mode 或 space | 废弃。产品结果只有 Flat Window、Portal Window、Docked、Panorama；`.progressive` 只表示平台 Immersion Style / viewing mode，`.full` 不是第一版产品形态。 |
| 打开 Scene 同时创建、打开或迁移播放器 | 废弃。Scene Lifecycle 与 Media Session、Projection、Playback Placement 正交；Scene 可以在没有媒体时提前打开。 |
| 一个 mode picker 暴露全部跳转，后端维护非法 edge graph | 废弃。SwiftUI 只显示当前形态允许的意图；代码驱动回归执行相同的公开 `PresentationCommand`，核心不维护穷举非法边。 |
| SwiftUI 控件覆盖 Playback Window / Immersive Space 的画面 | 废弃。Control Window 独立承载控件，Playback Window 与 Immersive Space 是 content-only，标准 Window Bar 保持可用。 |
| probe 自行 open / dismiss scene、迁移 Entity 或判定成功 | 废弃。保留的 probe 脚本/flag 只负责授权门、启动和结果回收；SwiftUI 与测试调用同一 `PresentationCommand`，并共同等待 acknowledgement、binding、rendering、pixel 与 timeline 事实。 |

## 融合后的节点语义

| 节点 | 融合后职责 | 两路线差异是否穿透下游 |
|---|---|---|
| 1 Source Acquisition | 取得 locator、provenance、privacy-safe summary 与访问要求。 | 否 |
| 2 Media Session and Route Binding | 创建 Media Session，绑定来源、显式路线、起始时间与当前媒体槽位。 | 路线成为不可变会话事实。 |
| 3 Provider Open Snapshot | 记录选定 Provider 打开来源后能观察的容器、时长、视频轨和格式事实。 | Provider 保留原始事实，输出共同 normalized 字段。 |
| 4 Video Track Model | 建立 PlaybackCore-owned video track identity、来源映射、codec、格式与选择结果。 | 否 |
| 5 Route Media Event Stream | 记录 sample、format changed、flush、end、error，以及 `streamEpoch` / `formatRevision`。 | 事件的 provider provenance 不同，事件合同相同。 |
| 6 Video Sample Stream | 交付可追溯的 compressed `CMSampleBuffer`。 | Apple storage sample 与 FFmpeg compressed assembly 各自实现。 |
| 7 Renderer Input Coordination | 两条路线的 compressed input 共用 readiness、enqueue、timeline、backpressure、flush、end 与 error 语义。 | 否。 |
| 8 RealityKit Renderer Binding | 将 active renderer 绑定到唯一 active `VideoPlayerComponent` 与 video entity。 | 否 |
| 9 RealityView Presentation | 由 App Adapter 把 renderer-backed entity 放入 active `RealityView`，记录 scene 与可见推进事实。 | 否 |

`VideoSampleProvider` 是真实 seam，因为已有两个独立 adapter。它的稳定输出不能只是裸 `CMSampleBuffer`；最终接口还要交付 Media Session、track、route、input kind、stream epoch、format revision、timing、format 与 source provenance。具体 AVFoundation / FFmpeg 对象保持在 Provider 内部。

## 活跃文档逐项处置

| xr-fork 文档 | 处置 | PlaybackCore 落点 |
|---|---|---|
| `ARCHITECTURE.md` | 改写 | `ARCHITECTURE.md` 保留所有权地图，mpv demux seam 改为双 Provider seam，macOS 升为主要 L2。 |
| `docs/core-spec.md` | 合并后改写 | `docs/core-spec.md` 保留公开控制 / 状态 / 实体 / 诊断面、生命周期、呈现维度和 App Adapter 边界，数据主线改为两路线。 |
| `docs/fixtures.md` | 合并 | `docs/fixtures.md` 恢复 contract / seed / restricted 分类、registry schema 与分路线期望。 |
| `docs/future.md` | 迁移 | scanner、环境光、完整设备矩阵与任何 decoded / uncompressed 扩展保持未来项，不把 FFmpeg Decoded 恢复为当前正式路线。 |
| `docs/acceptance/verification-system.md` | 合并后改写 | 恢复 Open Operation、节点记录、单预期结果、L1/L2/L3 和 vertical slice；每条路线独立出证据。 |
| `docs/acceptance/runtime-control.md` | 合并后改写 | 保留 Control Request / Admission / Runtime Operation / Node Effect Plan；seek 不再写死 mpv，改为 active Provider seek。 |
| `docs/acceptance/evidence.md` | 迁移并重建 | 建立 PlaybackCore 证据账本；xr-fork evidence 只作为历史可行性，不能声明当前通过。 |
| `docs/acceptance/quadrant-review.md` | 归档，不恢复为活跃入口 | 已确认事项直接进入 spec / nodes；未决事项进入 active open-risks 或实现计划。 |
| `nodes/01-source.md` | 合并 | 保留现有节点 1，补齐稳定 records 和 route-neutral 交付边界。 |
| `nodes/02-session.md` | 合并后改写 | 保留当前显式路线和 cold switch，恢复 Media Session ID、source record、slot、rejection 与 cleanup 语义。 |
| `nodes/03-container-probe.md` | 改名义恢复 | 变为 Provider Open Snapshot，不再要求 mpv internal hook。 |
| `nodes/04-track-model.md` | 恢复并改写 | 建立视频 Track Model；共享音频由平行的 Shared Audio Lane 记录，不混入视频路线。 |
| `nodes/05-demux-event-stream.md` | 改名义恢复 | 变为 Route Media Event Stream，覆盖 Apple reader 与 FFmpeg 两种上游。 |
| `nodes/06-coremedia-sample.md` | 改名义恢复 | 变为 Video Sample Stream，描述两条路线的 compressed sample 生产方式。 |
| `nodes/06s-subtitle-renderable.md` | 延后 | 字幕不属于当前完成门；保留为后续能力。 |
| `nodes/07-avfoundation-renderer-input.md` | 扩充 | 用双路线 compressed pass-through 现实改写完整 record、backpressure、flush、end 与 failure 合同。 |
| `nodes/08-realitykit-renderer-binding.md` | 扩充 | 恢复 binding identity、唯一 active binding、graph replacement 与 cleanup 规则。 |
| `nodes/09-realityview-bridge.md` | 扩充 | macOS RealityView 成为主要 L2；visionOS scene 独有行为另作 L2-platform / L3 证据。 |

## Archive 决策逐项处置

| 旧 ADR | 处置 |
|---|---|
| 0001 AVFoundation hybrid | 保留“Apple renderer + RealityKit 是共同下游”；废除“libmpv 只解封装”。 |
| 0002 injection point B / mpv patch | 保留 compressed `CMSampleBuffer` 组装约束；废除 mpv patch 这一实现绑定。 |
| 0003 APMP injection | 迁移为 projection / stereo metadata 的待验证能力；不得把未验证假设写成已支持。 |
| 0004 core / UI decoupling | 保留 SwiftUI-free core 与 App Adapter 边界；不再要求“整包复制”作为唯一交付方式。 |
| 0005 environment lighting | 迁入 future；与当前播放核心完成门无关。 |
| 0006 hardware-only decode | 不迁移为当前功能。当前两条路线都向 Apple renderer 交付 compressed sample；若未来引入 decoded 路线，必须重新立项并明确 provenance，不能悄悄冒充当前路线。 |
| 0007 subtitle entity | 迁入 future；当前 audio-video spec 不承诺字幕。 |
| 0008 modes composed by frontend | 保留。产品形态不是 core mode enum。 |
| 0009 effective projection + scene | 保留 detected / effective 分层与产品形态判定。 |
| 0010 verification before full spec | 保留 L1/L2/L3 和证据优先原则。 |
| 0011 scanner lab | 迁入 future，作为独立实验工具。 |
| 0012 defer scanner | 保留，scanner 不阻塞当前核心。 |
| 0013 active docs consolidation | 保留真相源原则，但实际入口以当前仓库文件为准。 |

## Archive contracts、conventions 与 reports 处置

| 文档组 | 保留内容 | 废弃或改写内容 |
|---|---|---|
| `control-division.md` | synchronizer 控制呈现时间线；seek 需要 provider、renderer、synchronizer 协调；loop 属于 App。 | `aid` / `sid` 与 mpv 固定命令延后；seek 首段改为 active Provider seek。 |
| `data-pipeline-and-constraints.md` | compressed format、timing、backpressure、format change、flush 与 renderer 独占规则。 | 单一 compressed 硬解主线、mpv 默认缓存和 mpv 字幕接口。 |
| `playback-core-interfaces.md` | 控制 / 状态 / 实体 / 诊断面、七态生命周期、Shared Audio Lane 与 Debug Snapshot provenance。 | 当前阶段不迁移 subtitle、chapter API；`open` 替换语义改为显式 slot / cold switch 规则。 |
| `mode-mapping.md` | detected / effective、Projection、StereoLayout、scene 与 product shape 分层。 | 需要以当前 SDK / 实测重新核查 API 细节；不继承未验证的 APMP 通过声明。 |
| `playback-core-test-strategy.md` | L1/L2/L3、surrogate、Debug Snapshot 字段组和真实管线原则。 | L2 从“只能 visionOS Simulator”改为“macOS 等价优先，平台独有能力再到 Simulator”。 |
| `v1-goal` / `acceptance-checklist` | 公开 open 到 RealityView 的 vertical slice、可复制诊断、明确“不算通过”。 | 单 mpv 路线和当前未进入范围的 subtitle 条目。 |
| `verify-app-mode-switching.md` | scene lifecycle、placement、projection、stereo 必须分开。 | UI 形态不直接复制；按当前 Lab 最小验证需求重建。 |
| build / fixture / L3 conventions | 可重现构建、fixture registry、L3 差分证据格式。 | 自建 libmpv 拓扑和已不存在的临时产物路径。 |
| old spec / open questions | 作为风险与概念来源。 | 不作为当前设计或当前未完成状态。 |
| implementation report / evidence log | 证明旧架构曾跑通 open、seek、audio、subtitle scaffold、RealityKit binding 与 scene switching。 | 因源码、依赖和架构已变化，所有 evidence 均为 historical，不计入 PlaybackCore 当前验收。 |

## 融合完成后的代码现实

| 融合目标 | 当前落点 |
|---|---|
| 独立播放核心 | `Package.swift` 的 `PlaybackCore` library target；macOS 与 visionOS App target 只依赖该模块。 |
| 两条显式路线 | `VideoSampleProvider` 下的 Apple Compressed 与 FFmpeg Compressed adapter；路线只在 Provider 边界产生差异，并复用 Renderer Input Coordination。 |
| route-neutral records | source、session、provider open、track、route event、sample、renderer input、binding、presentation、operation 与 rejection records。 |
| renderer 深模块 | 单一 `SampleBufferPlaybackSession` 管理 timeline、readiness、backpressure、compressed enqueue、flush、seek epoch、end 和 cleanup；App Adapter 不接触 renderer queue。 |
| 运行控制 | `PlaybackCoreController` 提供 open、close、play、pause、setRate、seek 与 cold route switch；连续 seek 采用 latest-request-wins。 |
| RealityKit 边界 | 核心只提供 renderer 并记录回填事实；macOS / visionOS Adapter 创建 `VideoPlayerComponent`、entity 和 `RealityView` presentation。 |
| 实时调试 | 版本化 `DebugSnapshotV1`、同步落盘的 JSONL event stream、原子 command inbox 与 completion acknowledgement；macOS Lab 可在单一常驻进程中接受 CLI 控制。 |
| 验证真相源 | `docs/acceptance/evidence.md` 记录当前 L1、双路线 macOS L2、运行控制、Simulator adapter 和 Vision Pro Dolby Vision 证据。 |

subtitle、chapters 和未在 `docs/core-spec.md` 声明的更多产品 scene 仍属于 `docs/future.md`，不是迁移缺口，也不能由 xr-fork 历史证据冒充已经实现。当前 Projection、Stereo 与 visionOS 四种播放形态以核心规格和当前自动回归合同为准；Apple Compressed 与 FFmpeg Compressed 的 Dolby Vision Profile 5、8.1、8.4 仍需各自在 Vision Pro 上形成独立 L3 观感证据。
