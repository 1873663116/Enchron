# Spec：macOS PlaybackCore

这是播放核心的活跃设计规格。当前只设计并证明 macOS 上的 H.264 video-only sample-buffer 播放主线。

## 目标

PlaybackCore 使用 provider-neutral Demux Contract 接收解封装事实，把 H.264 packet 组装成 compressed `CMSampleBuffer`，送入 `AVSampleBufferVideoRenderer`，再通过 RealityKit `VideoPlayerComponent(videoRenderer:)` 和 video entity 在 macOS `RealityView` 中播放。

第一套 demux adapter 使用 FFmpeg。FFmpeg 负责容器、轨道和 packet 事实，不拥有 CoreMedia、AVFoundation renderer 或 RealityKit 语义。

当前阶段只实现 H.264 video-only 本地文件播放，不预留其他媒体能力的接口。

## 两条播放路线

Apple Sample Reference Path 使用 `AVAssetReader` 从 contract fixture 读取 storage-format compressed `CMSampleBuffer`，直接进入 Renderer Input Coordination。它用于先建立完整的 macOS 后半段播放管线。

PlaybackCore Target Path 使用 FFmpeg demux adapter 打开同一个 fixture，建立 Container Open Snapshot、Track Model 和 Demux Envelope Stream，由 CoreMedia Sample Assembly 组装 compressed `CMSampleBuffer`，再进入相同的 Renderer Input Coordination。

`AVAssetReader` 不是 Demux Contract adapter。Apple Sample Reference Path 绕过节点 3 到节点 6，不为这些节点产生 operation 或成功记录。

两条路线分别运行于独立 Media Session 和 renderer graph。它们复用相同的 renderer readiness、backpressure、enqueue、synchronizer、RealityKit binding 和 `RealityView` 承载实现，不共享运行时对象。

## 当前接口

PlaybackCore 对 macOS Playback Lab 暴露控制面、状态面、实体面和诊断面。

控制面当前只要求 `open(source:)`、`close()`、`play()` 和 `pause()`。状态面说明生命周期、当前时间、sample delivery、renderer 状态和失败。实体面交出 renderer-backed video entity。诊断面输出稳定的 Debug Snapshot。

生命周期状态为 `idle`、`opening`、`ready`、`playing`、`paused`、`ended` 和 `failed`。当前 vertical slice 不要求完成 renderer drain 后的 `.ended` 语义，但状态集合保持稳定。

## 数据主线

PlaybackCore Target Path 的数据主线是：

```text
Media Source
→ FFmpeg demux adapter
→ Container Open Snapshot
→ Track Model
→ Demux Envelope Stream
→ CoreMedia Sample Assembly
→ compressed CMSampleBuffer
→ Renderer Input Coordination
→ AVSampleBufferVideoRenderer
→ AVSampleBufferRenderSynchronizer
→ VideoPlayerComponent(videoRenderer:)
→ renderer-backed video entity
→ macOS RealityView
```

Demux Envelope 必须保存当前 Media Session、Track Model、packet bytes、byte format、codec config、PTS、DTS、duration、timebase、keyframe 和 format revision。离开 FFmpeg callback 后仍会使用的数据必须由 adapter 或播放核心稳定持有。

CoreMedia Sample Assembly 必须建立 `CMVideoFormatDescription`、`CMBlockBuffer`、`CMSampleTimingInfo` 和 compressed `CMSampleBuffer`。H.264 payload、参数集、PTS、DTS、duration 和 sync attachment 必须满足 Apple renderer 输入要求。

Renderer Input Coordination 根据 renderer readiness 输送 sample，把 backpressure 视为正常控制信号，记录 enqueue 与 decode failure，并由 `AVSampleBufferRenderSynchronizer` 驱动播放时间线。

RealityKit binding 把当前 active `AVSampleBufferVideoRenderer` 写入 `VideoPlayerComponent(videoRenderer:)`，并把 component 挂到当前 Media Session 的 video entity。macOS Playback Lab 将该 entity 加入 active `RealityView`。

## 诊断事实

每个实际启动的节点记录自己的输入归属、成功或失败结果和下游边界。Debug Snapshot 从这些节点记录、当前播放状态和 macOS Playback Lab 的 presentation facts 派生，不能替代节点记录，也不能为被绕过的节点制造成功事实。

Apple Sample Reference Path 的 sample provenance 包含 fixture、asset track 和 AVAssetReader output。PlaybackCore Target Path 的 sample provenance 包含 Track Model、Demux Envelope、stream epoch 和 format revision。

## 完成边界

首个 ready compressed sample 被 renderer 接受，active renderer 绑定到 `VideoPlayerComponent`，video entity 进入 `RealityView`，是实现期 tracer bullet，不是阶段完成。

当前阶段完成要求同一个短小 H.264 video-only contract fixture 分别通过 Apple Sample Reference Path 和 PlaybackCore Target Path 连续呈现。Agent 必须能在 macOS Playback Lab 中观察视频帧推进；两条路线都不能出现 renderer decode failure；目标路线的 sample 必须能追溯到源 Demux Envelope 和 Track Format Snapshot。

两条路线比较 codec、coded dimensions、format description、PTS、DTS、duration、sync state、data readiness 和稳定 fixture 定义的 sample 顺序。验收不要求 CoreMedia 对象 identity、内存布局或 encoded payload 逐字节相同。
