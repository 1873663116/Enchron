# PlaybackCore

PlaybackCore 是独立于具体解封装实现的 Apple 平台播放核心实验仓库。

当前阶段先在 macOS 上证明 compressed `CMSampleBuffer` 的正确组装、
`AVSampleBufferVideoRenderer` 输入和 RealityKit `VideoPlayerComponent` 呈现。

## 当前验证顺序

1. Apple Sample Reference Path 使用 `AVAssetReader` 产生 compressed `CMSampleBuffer`，建立完整的 macOS sample-buffer 后半段播放管线。
2. FFmpeg demux adapter 负责容器、轨道和 packet 事实，PlaybackCore 从 Demux Envelope 组装 compressed `CMSampleBuffer`。
3. 两条路线从 Renderer Input Coordination 开始复用相同的 renderer、synchronizer、`VideoPlayerComponent`、RealityKit Entity 和 `RealityView` 实现。
4. 同一个短小 H.264 video-only fixture 分别通过两条路线连续呈现后，macOS sample-buffer 播放主线成立。

## 仓库边界

- PlaybackCore 拥有 Demux Contract、Sample Assembly、renderer coordination、RealityKit entity 和诊断事实。
- FFmpeg 是当前 Demux Contract adapter，不拥有 CoreMedia 或 RealityKit 语义。
- `AVAssetReader` 是验证专用的 Apple sample provider，不是 Demux Contract adapter，也不为节点 3 到节点 6 提供成功证据。
- macOS Playback Lab 是当前验证承载，Agent 在这里检查结构化事实和真实可见播放。
- 正式产品 App 不属于本仓库。

## 文档入口

- `CONTEXT.md`：项目术语。
- `ARCHITECTURE.md`：目标模块与 seam。
- `docs/core-spec.md`：当前 macOS PlaybackCore 设计规格。
- `docs/acceptance/verification-system.md`：两条 sample-buffer 路线的证明模型。
- `docs/acceptance/nodes/`：可复用的节点对象与完成条件。

## License

PlaybackCore 使用 MIT License，详见 `LICENSE`。
