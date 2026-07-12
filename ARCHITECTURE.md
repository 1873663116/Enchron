# PlaybackCore 架构地图

## 模型

PlaybackCore 是 macOS video-only sample-buffer 播放核心。demux adapter 负责容器、轨道和 packet；播放核心把 provider-neutral 解封装事实组装成 CoreMedia sample；AVFoundation renderer 与 RealityKit 负责系统解码、时间线和显示。

## 两条路线

Apple Sample Reference Path 是验证专用路径：`AVAssetReader` 直接产生 compressed `CMSampleBuffer`，用于先建立 Renderer Input Coordination 之后的完整播放管线。

PlaybackCore Target Path 是目标路径：FFmpeg demux adapter 产生 Demux Envelope，PlaybackCore 自行组装 compressed `CMSampleBuffer`，再进入参考路径已经证明的后半段实现。

两条路线的共同 seam 是 Renderer Input Coordination 的输入。它们分别运行于独立 Media Session，复用相同实现和配置，不共享 renderer 或其他运行时对象。

## 模块与 seam

| 模块 | 接口与所有权 |
|---|---|
| macOS Playback Lab | 打开本地 fixture，选择播放路线，把 video entity 放入 `RealityView`，向 Agent 暴露可见播放与诊断事实。 |
| FFmpeg demux adapter | 实现 Demux Contract，输出容器、轨道、packet、格式和时间事实。 |
| Demux Envelope Stream | 把 provider facts 转换为 PlaybackCore 稳定拥有、可追溯的事件流。 |
| CoreMedia Sample Assembly | 把 H.264 Demux Envelope 转换为 compressed `CMSampleBuffer`。 |
| Apple Sample Reference Path | 使用 `AVAssetReader` 提供 Apple 生成的 compressed `CMSampleBuffer`，绕过 Demux Contract 和 Sample Assembly。 |
| Renderer Input Coordination | 两条路线的共同 seam；负责 readiness、backpressure、enqueue、synchronizer 和 renderer error。 |
| RealityKit binding | 把 active `AVSampleBufferVideoRenderer` 写入 `VideoPlayerComponent(videoRenderer:)` 并挂到 video entity。 |
| RealityView presentation | 把 renderer-backed video entity 放入 macOS App 的 active `RealityView`，记录 attach 和可见播放事实。 |

## 文档边界

`docs/core-spec.md` 是唯一设计规格。`docs/acceptance/verification-system.md` 规定怎样证明两条路线。`docs/acceptance/nodes/` 定义每个节点的输入、输出和完成边界。`docs/fixtures.md` 规定 contract fixture。
