# 协作准则

## 当前阶段

本仓库当前设计并证明 macOS 与 visionOS 共用的双路线音视频 sample-buffer 播放系统。
实现顺序以 `README.md` 的验证顺序为准。

两条显式视频路线是 Apple Compressed 和 FFmpeg Compressed。当前只做冷切换；
不实现能力探测、自动选路或失败回退。

## 默认入口

- 术语先看 `CONTEXT.md`。
- 战略和当前验证顺序先看 `README.md`。
- 模块地图看 `ARCHITECTURE.md`。

当前代码现实来自源码、测试和运行证据。当前设计规格来自 `docs/core-spec.md`；
当前验证模型来自 `docs/acceptance/verification-system.md`。

## 修改边界

两条路线必须在 `VideoSampleProvider` 处分流，并复用同一个 Renderer Input Coordination、
renderer、synchronizer 与 RealityKit binding。不要为每条路线复制播放器。

macOS `PlaybackLab` 证明播放链路能否持续出帧；`PlaybackLabVision` 负责 Vision Pro
真机的可见播放和 HDR 观感验收。macOS 画面不能替代 visionOS HDR 证据。

每个验证用例只有一个预期结果。不同路线的成功证据分别记录，不能由一条路线的结果推断另一条。
