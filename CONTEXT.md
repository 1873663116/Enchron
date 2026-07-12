# PlaybackCore 术语表

本术语表只定义当前 macOS video-only 播放主线使用的项目概念；设计与行为以 `docs/core-spec.md` 为准。

**播放核心**:
本仓库要建立并测试的主体。它拥有 provider-neutral Demux Contract、CoreMedia Sample Assembly、Renderer Input Coordination、RealityKit binding 和诊断事实。
_Avoid_: 完整播放器、产品 App

**macOS Playback Lab**:
当前验证 App。它打开 fixture，选择 sample 路线，把 renderer-backed video entity 放入 `RealityView`，向 Agent 暴露结构化事实和真实可见播放。
_Avoid_: 产品 UI

**Apple Sample Reference Path**:
验证专用路线。它使用 `AVAssetReader` 产生 storage-format compressed `CMSampleBuffer`，绕过节点 3 到节点 6，直接进入 Renderer Input Coordination，用于先证明共同后半段播放管线。
_Avoid_: AVAssetReader adapter、产品播放路线

**PlaybackCore Target Path**:
当前要成立的目标路线。FFmpeg demux adapter 产生 Demux Envelope，PlaybackCore 组装 compressed `CMSampleBuffer`，再进入与参考路径相同的 Renderer Input Coordination 和 RealityKit 呈现实现。
_Avoid_: FFmpeg 播放路线、自定义解码路线

**媒体会话 (Media Session)**:
一次打开媒体的稳定身份和状态容器。节点记录、播放状态和 Debug Snapshot 都归属于具体 Media Session。

**打开操作 (Open Operation)**:
PlaybackCore Target Path 接受一次 `open(source:)` 后创建的父级执行记录。它归拢节点推进、失败和 cleanup，不是公开 API 或单个节点记录。

**轨道模型 (Track Model)**:
PlaybackCore 对 demux provider 原始轨道事实的稳定解释。当前 slice 只选择一条 H.264 video track。

**Demux Envelope Stream**:
PlaybackCore 接收 provider-neutral 解封装事实的事件流。每个 video packet envelope 保留 Media Session、Track Model、payload 所有权、byte format、codec config、timing、keyframe、stream epoch 和 format revision。

**Track Format Snapshot**:
一条轨道在某个 `formatRevision` 下的不可变格式事实。packet 明确引用对应 snapshot，不依赖可变的隐式共享状态。

**CoreMedia Sample Assembly**:
把 H.264 Demux Envelope 转换成 compressed video `CMSampleBuffer`。它建立 format description、block buffer、timing 和 sample attachments，不负责 renderer enqueue。

**Renderer Input Coordination**:
两条 sample 路线的共同 seam。它把 compressed `CMSampleBuffer` 送入 `AVSampleBufferVideoRenderer`，管理 readiness、backpressure、synchronizer 和 renderer error。

**RealityKit renderer binding**:
把 active `AVSampleBufferVideoRenderer` 写入 `VideoPlayerComponent(videoRenderer:)`，并把 component 挂到当前 Media Session 的 video entity。

**RealityView presentation**:
macOS Playback Lab 把 renderer-backed video entity 放入 active `RealityView`，记录 entity attach 和可见帧推进。

**首个 tracer bullet**:
一个 ready compressed sample 被 renderer 接受，active renderer 绑定到 `VideoPlayerComponent`，video entity 进入 `RealityView`。它证明 seam 已接通，不代表播放主线已经完成。

**macOS video-only 播放主线成立**:
同一个短小 H.264 contract fixture 分别通过 Apple Sample Reference Path 和 PlaybackCore Target Path 连续呈现；目标 sample 可追溯，renderer 没有 decode failure，Agent 能观察 video entity 中的帧推进。

**Debug Snapshot**:
由节点记录、当前播放状态和 macOS Playback Lab presentation facts 派生的稳定诊断 JSON。它不能替代节点记录，也不能为被绕过的节点制造成功事实。
