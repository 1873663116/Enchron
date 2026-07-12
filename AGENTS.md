# 协作准则

## 当前阶段

本仓库先证明 macOS sample-buffer 播放主线，不直接实现完整 visionOS 播放器。
实现顺序以 `README.md` 的验证顺序为准。

FFmpeg 和 mpv 都是解封装 adapter。播放核心的领域模型、CoreMedia sample 组装、
renderer graph、RealityKit entity 和诊断接口不得依赖某个 adapter 的内部对象。

## 默认入口

- 术语先看 `CONTEXT.md`。
- 战略和当前验证顺序先看 `README.md`。
- 模块地图看 `ARCHITECTURE.md`。

当前代码现实来自源码、测试和运行证据。当前设计规格来自 `docs/core-spec.md`；
当前验证模型来自 `docs/acceptance/verification-system.md`。

## 修改边界

先建立最小 macOS Playback Lab 和 provider-neutral Demux Contract。
在 FFmpeg video-only vertical slice 成立前，不扩展音频同步、字幕、seek、HDR、
Apple Projected Media Profile、Portal 或 mpv adapter。

每个验证用例只有一个预期结果。`AVPlayer` 只作为用户可见基准；
`AVAssetReader` sample-buffer 路径才是 renderer harness 的已知正确基准。

