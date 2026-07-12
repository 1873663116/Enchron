# PlaybackCore

PlaybackCore 是独立于具体解封装实现的 Apple 平台播放核心实验仓库。

当前阶段先在 macOS 上证明 compressed `CMSampleBuffer` 的正确组装、
`AVSampleBufferVideoRenderer` 输入和 RealityKit `VideoPlayerComponent` 呈现。
visionOS 后续只承担空间承载、沉浸观看方式和真机事实验证。

## 当前验证顺序

1. `AVPlayer` 播放同一素材，建立用户可见的系统基准。
2. `AVAssetReader` 产生 Apple 基准 sample，并送入共同的 renderer harness。
3. FFmpeg 只负责解封装，PlaybackCore 从 packet 组装 compressed `CMSampleBuffer`。
4. 两条 sample-buffer 路径在同一个 macOS Playback Lab 中比较结构化事实和播放结果。
5. 核心契约稳定后，再接入独立 mpv fork 提供的 demux adapter。

## 仓库边界

- PlaybackCore 拥有 Demux Contract、Sample Assembly、renderer coordination、RealityKit entity 和诊断事实。
- FFmpeg 与未来的 mpv fork 是 Demux Contract 的 adapter，不拥有 CoreMedia 或 RealityKit 语义。
- macOS Playback Lab 是前期主要验证承载；visionOS Playback Lab 验证平台专属能力。
- 正式产品 App 不属于本仓库。

## 文档入口

- `CONTEXT.md`：项目术语。
- `ARCHITECTURE.md`：目标模块与 seam。
- `docs/core-spec.md`：从旧 mpv-first 设计迁入的核心规格，下一轮按 provider-neutral MVP 修订。
- `docs/acceptance/verification-system.md`：从旧仓库迁入的验收模型，下一轮重排 macOS 基准与 FFmpeg vertical slice。
- `docs/acceptance/nodes/`：可复用的节点对象与完成条件。

