# 节点 9：RealityView Presentation

## 作用与边界

节点 9 由 macOS 或 visionOS App Adapter 把节点 8 的 renderer-backed video entity 加入 active `RealityView`。它记录 presentation provenance、entity attach、scene lifecycle 和 displayed-frame observation，不负责 sample 或 component binding。

## Presentation context

App Adapter 提供：

- Media Session ID 和节点 8 binding identity。
- platform 与 App Adapter kind。
- active `RealityView` identity。
- scene container / lifecycle（平台可用时）。
- entity attached state。
- Presentation Binding ID。
- last attach / detach / migration summary。

这些是 App Adapter facts，不能由 core 猜测。验证 Lab 可以采集额外 displayed pixel buffer、rendering status 或 screenshot observation，但必须保留 provenance。

visionOS 当前只建立一个 Playback Window `RealityView` 和一个使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace`，并由正交状态派生以下产品形态：

| Presentation | Scene container | Desired immersive mode | Meaning |
|---|---|---|---|
| Flat Window | playback `WindowGroup` | 无 | runtime planar mesh + `VideoMaterial` 位于唯一 window `RealityView`；来源全景 metadata 不被改写。 |
| Portal Window | 同一个 playback `WindowGroup` | `.portal` | 全景 entity 在同一个 window `RealityView` 中切换为 Portal。 |
| Docked | 唯一 Playback `ImmersiveSpace` | 无 | runtime planar mesh + `VideoMaterial` 位于保留 RCP `world/screen` authored transform 的纯 runtime docking anchor；Scene Content 为 `customScene`。 |
| Panorama | 同一个 Playback `ImmersiveSpace` | `.progressive` | `VideoPlayerComponent` 位于 black panorama root；全部 RCP 自制场景隐藏，且不使用 docking anchor。 |

## 稳定规则

- presentation 与 renderer binding 属于同一 Media Session。
- 任意稳定时刻只有一个 active final Presentation Binding。
- Projection Intent、Placement 与 Scene Content 只能推导 Candidate Product Shape；只有 active video entity、目标容器、parent / binding、Effective Projection、所需 actual mode 与 settled renderer 全部成立时才能写 Presented Product Shape，否则为 `none` / Not Presented。
- scene / RealityView 尚未 ready 时不能写成 succeeded。
- Scene Lifecycle 在唯一 ImmersiveSpace 已 attached 且目标 Scene Content ready 后进入 `open`；该条件不要求存在 Media Session 或 video entity。
- presentation transition 只有在目标 `RealityView` 已 attached、entity parent 正确且 Presentation Binding 已回填后才能 settled。
- 跨 surface transition 先完成目标 binding，再在目标 view 请求所需 mode；必要 acknowledgement 必须属于当前 Media Session、当前 Entity 与目标 view identity。旧 surface 的迟到事件无效，打开超时后的迟到 surface 必须被拒绝并关闭。
- Flat / Portal 稳态要求 Playback Window open；Docked / Panorama 稳态要求 Playback Window closed。Docked 使用平面网格，不经过 `.portal`；Panorama 与 RCP docking anchor 无关。
- cold switch / cleanup 后旧 binding 不再代表当前播放。
- entity attached、首帧、displayed pixel buffer、持续推进和颜色正确是不同事实。
- requested presentation、desired immersive mode、actual immersive mode、RenderingStatus 和 transition settled 分别记录；Simulator 中不可观察的 hardware-only actual state 使用 `unknown` 或 `notAvailable`。

## 平台边界

macOS Playback Lab 使用真实 RealityKit 与相同 renderer binding，承担主要 L2 播放承载验证。visionOS Simulator 只补 macOS 不存在的 scene lifecycle、API availability 或 spatial placement。Vision Pro 只验收真实设备显示、HDR / EDR 观感和设备专属连续性。

visionOS 验收必须分别证明 Playback Window lifecycle、Scene Lifecycle、Scene Content 与 video binding。打开空 Playback Window 或自制 Scene 不得创建或改变 Media Session；Control Window 不得包含 `RealityView`，Playback Window 与 Playback Immersive Space 不得承载 SwiftUI 播放控件、attachment 或遮挡画面的 overlay。UI 只暴露当前产品允许的命令；代码驱动集成回归只替代输入端，不建立额外转换编排。

## 完成条件

唯一完成条件：当前 renderer-backed entity 已加入 App Adapter 报告的 active `RealityView`，Presentation Binding Record 可追溯到同一 Media Session 与节点 8 binding。这个节点完成只证明 presentation binding，不单独证明 Presented Product Shape、fresh displayed pixel、持续时间推进或视觉正确；这些由上层 case 联合验证。

## 验收方向

L2 分别验证 attach、first displayed frame、sustained progress、detach / close 和 same-process reopen。代码驱动集成回归为每次运行生成唯一 run ID，并对每个 case 捕获当前 Media Session、renderer、sample count 和 time baseline；只有目标 scene attached、transition settled、RenderingStatus ready、当前 renderer 在转换后产生 displayed-pixel observation 且 sample / time 相对 baseline 推进时才通过。cold route switch 必须建立新的 Media Session / renderer 并产生 fresh sample / pixel，不能沿用旧路线结果；最终 close 等待 cleanup 后才写 `completed = true`，所有独立 case 通过后才写 `passed = true`。固定 sleep 只可用于 polling / timeout。

Simulator flat fixture 只证明 Flat / Docked scene wiring、entity ownership 与 desired state；APMP fixture 才能证明 Portal / Panorama projection。实际空间观感、HDR / EDR、可听输出与主观同步仍由已佩戴、已解锁的 Vision Pro 独立验收；任何设备签名、安装或启动都必须先取得操作者针对本次运行的明确确认，HDR 对照固定同一 fixture 与同一 `CMTime`。
