# 协作准则

## 当前阶段

本仓库只设计并证明 macOS H.264 video-only sample-buffer 播放主线。
实现顺序以 `README.md` 的验证顺序为准。

FFmpeg 是当前 Demux Contract adapter。播放核心的领域模型、CoreMedia sample 组装、
renderer graph、RealityKit entity 和诊断接口不得依赖 FFmpeg 内部对象。

## 默认入口

- 术语先看 `CONTEXT.md`。
- 战略和当前验证顺序先看 `README.md`。
- 模块地图看 `ARCHITECTURE.md`。

当前代码现实来自源码、测试和运行证据。当前设计规格来自 `docs/core-spec.md`；
当前验证模型来自 `docs/acceptance/verification-system.md`。

## 修改边界

先建立 Apple Sample Reference Path 的完整 macOS 后半段播放管线，再让
PlaybackCore Target Path 通过相同的 Renderer Input Coordination seam 复用它。
当前不预留其他媒体能力的接口。

每个验证用例只有一个预期结果。`AVAssetReader` 是验证专用 sample provider，
不是 Demux Contract adapter，也不为节点 3 到节点 6 提供成功证据。
