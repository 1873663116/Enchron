---
status: accepted
date: 2026-07-16
---

# Window、Docked 与 Panorama 统一使用 VideoPlayerComponent

Enchron 的三个 Playback Presentation 统一以 `VideoPlayerComponent(videoRenderer:)` 消费同一个 PlaybackCore renderer；Window、Docked 与 Panorama 只改变 scene、transform 和 immersive mode。Window/Docked 不再维护 `ModelComponent + VideoMaterial` 产品路径，因为手工 plane 会形成第二套 mesh、宽高比、stereo 与投影解释，并使结构失败和最终画面失败难以区分。

每个 `RealityView` 拥有自己的 Video Entity；空间呈现状态转换迁移的是同一个 Media Session 与 Renderer 绑定，不假设同一个 Entity 实例能跨 Scene 搬移。Docked 将目标 Video Entity 挂到场景交付的 `PlaybackSurfaceAnchor` 下，Reality Composer Pro 不交付视频 Mesh 或材质。自动验收分别报告空间呈现结构是否符合合同，以及 RealityKit 渲染结果是否符合测试媒体中预先定义的方向和几何标记；空间尺度、舒适度、HDR/EDR 与沉浸感必须由真实佩戴者在 Vision Pro 上验收。

## 后果

- RealityKit 根据媒体及组件属性生成并更新 mesh 与 material；Enchron 只设置受支持的 desired mode、uniform scale 和 scene placement，并观察 actual mode、rendering status 与输出。
- 产品内只保留一套 RealityKit video consumer；验证工具不得重写投影算法来证明自身正确。
- 日常回归不依赖佩戴 Vision Pro；发布与里程碑仍保留真实设备体验验收。

场景侧交付边界见 [Xrplay_scene ADR-0005](../../../Xrplay_scene/docs/adr/0005-deliver-playback-surface-anchor.md)。
