# PlaybackCore 术语表

**媒体来源（Media Source）**：
一次 open 的输入，包含 locator、来源证明、可安全记录的摘要和读取访问要求。媒体来源不是播放会话。

**播放路线（Playback Route）**：
把媒体来源转换成 Video Sample Stream 的显式实现选择。当前取值是作为对照层的 Apple Compressed，以及作为产品主线的 FFmpeg Compressed。

**媒体会话（Media Session）**：
一次被接受的 `open → playback lifecycle → close / failed` 的身份边界。来源、路线和后续所有节点事实都归属于同一个 Media Session。

**当前媒体槽位（Current Media Slot）**：
PlaybackCore 当前允许占用的唯一 Media Session 位置。它用于 open admission 和 stale update rejection。

**Provider Open Snapshot**：
选定 Video Sample Provider 打开来源后，对容器、时长、视频轨、codec 和可见 metadata 的不可变事实快照。

**Video Track Model**：
PlaybackCore 根据 Provider Open Snapshot 建立的稳定视频轨身份、来源映射、格式事实和选择结果。

**Video Sample Provider**：
将来源和选定视频轨转换为 route-owned event，并最终交付 compressed `CMSampleBuffer` 的深层模块接口。

**Route Media Event**：
Provider 产生的 sample、format changed、flush、end 或 error 事件。事件必须带 Media Session、track、route、stream epoch 和 format revision 归属。

**Stream Epoch**：
区分 seek、reset、reopen 或 cleanup 前后事件世代的单调身份。旧 epoch 的事件不能更新当前播放事实。

**Format Revision**：
区分同一视频轨不同格式版本的身份。它与 Stream Epoch 表达不同事实。

**Video Sample Stream**：
节点 6 输出的可追溯 video sample 与 control marker 流。sample 是 compressed `CMSampleBuffer`。

**Audio Track Provider**：
独立于两条视频路线的共享 FFmpeg 音频模块。它枚举并选择音轨，解码和重采样后输出 Linear PCM；它不是第三条 Playback Route。

**Linear PCM Sample Stream**：
选中音轨经 FFmpeg 解码并重采样得到的交错 Float32 Linear PCM `CMSampleBuffer` 流。它与视频 sample 共享 Media Session、Stream Epoch 和 synchronizer 时间线。

**Renderer Input Coordination**：
compressed Video Sample Stream 与 Linear PCM Sample Stream 到 Apple renderer graph 的稳定深层模块。它统一管理 timeline、readiness、backpressure、enqueue、flush、end 和 renderer error。

**Renderer Graph**：
当前 Media Session 独占的 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer` 与同一个 `AVSampleBufferRenderSynchronizer`。audio renderer、video renderer 和 synchronizer 必须可追溯到同一个 graph identity。

**RealityKit Renderer Binding**：
把 active video renderer 交给唯一 active RealityKit 呈现器的绑定事实。Flat Window 与 Docked 使用运行时平面网格上的 `VideoMaterial(videoRenderer:)`；Portal Window 与 Panorama 使用 `VideoPlayerComponent(videoRenderer:)`。同一时刻只有一种呈现器消费 renderer。

**Presentation Binding**：
App Adapter 把 renderer-backed video entity 放入 active `RealityView` 后形成的 scene 承载事实。

**Control Window**：
独立承载文件入口、播放控制与呈现命令的 SwiftUI 窗口。它不包含 `RealityView`，也不把控件作为 attachment 或 overlay 放进 Playback Window / Playback Immersive Space。

**Playback Window**：
承载唯一 content-only `RealityView` 的标准 SwiftUI 窗口。Flat Window 与 Portal Window 复用它；系统 Window Bar 保持可用。

**Playback Immersive Space**：
唯一使用 progressive `ImmersionStyle` 的 `ImmersiveSpace`。它是 `customScene` 与 `blackPanorama` 的系统容器，不是名为 Progressive、Full 或 Docked 的产品形态。

**Detected Projection**：
Provider open 记录且在该 Media Session 内不再改变的来源几何：Rectilinear、Half Equirectangular（180°）、Equirectangular（360°）或无标记。Apple Compressed 可以按系统 API 解析兼容的 external spherical tags；系统合成的投影必须标明 synthesis provenance，不能冒充文件原生 APMP。

**Projection Intent**：
App Adapter 的呈现意图。第一版 UI 提供 `flat` 与明确的 360° panoramic 选择（当前内部名称为 `sourcePanoramic`）；180° effective override 已由核心支持，但尚未作为第一版独立 UI 入口。它既选择平面或沉浸呈现几何，也决定是否需要在共享 renderer 输入边界补充投影标记。

**Effective Projection**：
当前 sample format 实际交给 renderer 的几何。优先采用文件原生 APMP 或系统从 external spherical tags 合成的标记；当用户明确选择 360° 而来源无可识别投影时，App 可在共享 sample-format seam 补充 Equirectangular。该操作不改文件或 payload；返回 Flat 时清除 App override。Detected 与 Effective 必须分别记录。
_Avoid_: playback mode

**Presentation Geometry**：
App Adapter 对 renderer 输出采用的 RealityKit 几何。`planar` 是 Flat Window 与 Docked 共用的运行时平面网格；`immersive` 是 Portal Window 与 Panorama 共用的 `VideoPlayerComponent` 投影。它不是媒体来源的 Projection。

**候选产品播放形态（Candidate Product Shape）**：
仅由 Projection Intent、Playback Placement 与 Scene Content 推导的目标组合。它可以在没有媒体或转换尚未完成时存在，不能作为播放成功证据。

**已呈现产品播放形态（Presented Product Shape）**：
已经稳定呈现的用户可见结果，取值只有 Flat Window、Portal Window、Docked 和 Panorama。除候选组合正确外，它还要求 active media / video entity、目标容器 attached、正确 Entity parent 与 Presentation Binding、Effective Projection、该形态要求的 actual mode，以及 settled renderer；否则必须报告 `none` / Not Presented。它不是核心 `setMode` 枚举。
_Avoid_: Progressive mode、Full mode、Fixed Immersive Screen

**Playback Placement**：
renderer-backed video entity 当前位于 Playback Window、RCP `screen` docking 点位还是 black panorama root。只有 Docked 使用 RCP `screen`；Panorama 与该锚点没有关系。Placement 与媒体投影、Stereo Layout 和 Scene Lifecycle 是正交状态。
_Avoid_: surface mode

**Scene Lifecycle**：
唯一 Playback `ImmersiveSpace` 的 `closed / opening / open / closing / failed` 生命周期。打开 Scene 不创建或迁移播放器，也不等于进入 Docked 或 Panorama。
_Avoid_: surface lifecycle、presentation mode lifecycle

**Scene Content**：
已打开 Playback `ImmersiveSpace` 当前承载 `customScene` 或 `blackPanorama`。前者加载 RCP 场景，并以 `world/screen` authored translation、rotation、scale 建立纯 Entity runtime docking anchor；anchor 不继承 authored component 或 mesh。后者隐藏全部 RCP 场景内容，只留下黑场与全景视频，并且不使用 docking anchor。

**Custom Scene Intent**：
用户是否要求自制 Scene 保持打开的独立意图。Panorama 可以临时把 Scene Content 切为 `blackPanorama`；返回 Window 或在 Panorama 中关闭媒体时，都必须按进入前的 Custom Scene Intent 恢复 `customScene` 或关闭 Playback Immersive Space。

**Stereo Layout**：
当前视频按 `mono`、`sideBySide` 或 `overUnder` 解释的独立呈现维度。它不改变产品播放形态、投影、Placement 或 Scene Lifecycle。

**PresentationCommand**：
SwiftUI 控件与代码驱动集成回归共同调用的 App Adapter 公开命令。它按 target-first transaction 执行产品 UI 已暴露的呈现意图：准备目标容器，迁移并绑定 Entity，在目标 surface 请求所需 mode，等待必要 acknowledgement 与 renderer settle，最后处理来源容器。失败时必须先恢复真实来源容器、意图、binding、mode 与 settled 状态，再清理失败目标；rollback failure 必须公开，不能只回写 desired facts。测试端不拥有另一套呈现编排。

**Cold Route Switch**：
终止旧 Media Session，再以同一来源、时间点和暂停状态创建另一条显式路线的新 Media Session。它不是同一会话内更换 Provider。

**Open Operation**：
一次 accepted open 推进节点 2 到节点 9的父级执行记录。它是内部诊断对象，不是公开播放状态。

**Runtime Operation**：
active Media Session 上一次 accepted control request 的执行记录，例如 play、pause、seek 或 cold route switch。

**Debug Event Stream**：
运行时按发生顺序发布的结构化、privacy-safe 节点与控制事件。它用于实时调试，不是完整事件溯源数据库。

**Debug Snapshot**：
从当前稳定事实记录派生的版本化 JSON 投影。Snapshot 用于观察当前状态，不能替代节点 record 或 evidence。

**L1 核心事实层**：
通过 macOS host tests、contract fixtures 和 fake adapters 证明 PlaybackCore 自己产生的事实。

**L2 承载集成层**：
优先在 macOS Playback Lab 证明真实 Provider、Apple renderer、RealityKit binding 与可见帧推进；仅把 macOS 无法等价覆盖的 visionOS API 交给 Simulator。

**L3 真机事实层**：
在 Vision Pro 上证明真实设备显示、HDR / EDR 观感、设备性能和其他 host / Simulator 无法等价观察的事实。

**none / unknown / notExposed / unsupported**：
分别表示确认不存在、当前无法确定、上游没有通过 seam 暴露、以及已经知道但当前实现不支持。四者不能互换。
