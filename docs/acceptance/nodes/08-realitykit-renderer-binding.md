# 节点 8：RealityKit Renderer Binding

## 作用与边界

节点 8 由 App Adapter 把节点 7 的 active renderer 交给唯一 active RealityKit 呈现器，再把 binding facts 写回 PlaybackCore。Flat Window / Docked 使用运行时平面网格上的 `VideoMaterial(videoRenderer:)`；Portal Window / Panorama 使用 `VideoPlayerComponent(videoRenderer:)`。核心不 import RealityKit，也不选择 `RealityView` 或 SwiftUI scene。

## Input / output

输入是 Media Session、route、renderer graph、Stream Epoch、active renderer，以及 App Adapter 报告的 component / entity identity。输出是 RealityKit Binding Record；renderer-backed entity 由 App Adapter 持有。

record 至少包含 Media Session、route、renderer / graph privacy-safe identity、entity identity、component attached、component renderer identity summary、binding identity、active state 和 failure reason。

## 稳定规则

- renderer、component、entity、route 和 binding 属于同一 Media Session。
- component 引用节点 7 当前 active renderer。
- 任意稳定时刻同一个 renderer 只有一个 active component binding。
- renderer graph replacement 或 cold switch 后，旧 binding 不再 active。
- cleanup 后旧 entity 不代表当前播放。
- App Adapter 创建 component 与 entity，但不能创建第二个 active component 来绕过 binding record。

## 完成条件

唯一完成条件：当前 video entity 上的 component 引用当前 renderer，且 active binding record 已写回同一 Media Session。该结果不替代 renderer enqueue 或可见画面。

## 验收方向

L1 验证 identity、uniqueness、replacement 和 stale rejection。L2 分别证明真实 `VideoMaterial(videoRenderer:)` 平面 binding 与 `VideoPlayerComponent(videoRenderer:)` 沉浸 binding，并证明交接过程中不存在两个 active consumer；visionOS 复用同一核心并补平台 adapter 证据。
