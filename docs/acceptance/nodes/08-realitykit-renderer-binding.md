# 节点 08：RealityKit Renderer Binding

## 边界

节点 08 由 Enchron App 把节点 07 的 active video renderer 交给唯一 active RealityKit consumer，并把 binding facts 与同一 Media Session 关联。PlaybackCore 不 import RealityKit，也不选择窗口或空间。

Window、Docked 与 Panorama 都使用 `VideoPlayerComponent(videoRenderer:)`。每个 `RealityView` 拥有自己的 Video Entity；Presentation transition 迁移 renderer binding，不跨 scene 搬移 Entity，也不保留 `VideoMaterial` 产品分支。这些是 App presentation adapter 的实现选择，不改变核心 renderer graph。

## Binding Record

记录 Media Session、renderer/graph identity、entity identity、component/material kind、consumer renderer identity、Playback Presentation、binding identity、active state、attach/detach provenance 与 failure reason。

## 稳定规则

- renderer、consumer、entity 与 binding 属于同一 Media Session。
- 任意稳定时刻一个 renderer 只有一个 active consumer。
- Presentation transition 先准备目标 consumer，成功后提交并释放旧 binding；失败保留旧 binding。
- renderer graph replacement、close 或 cleanup 后，旧 binding 不再代表当前播放。
- Enchron App 不得创建第二 renderer 或第二 Media Session 绕过 binding 失败。

## 完成条件

唯一完成条件：当前 RealityKit consumer 引用当前 renderer，且 active binding 可追溯到同一 Media Session。它不替代 displayed frame 或持续播放证明。

## 验收

macOS L2 证明真实 `VideoPlayerComponent` binding、唯一 consumer、detach/reopen；visionOS Simulator 补 Window/Docked/Panorama 交接与 rollback；Vision Pro 验收最终空间行为。
