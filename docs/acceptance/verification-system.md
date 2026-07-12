# 验收系统：macOS PlaybackCore

这里规定两条 H.264 video-only sample-buffer 路线怎样在 macOS 上被证明。设计规格见 `../core-spec.md`，fixture 规则见 `../fixtures.md`。

## 证明对象

Apple Sample Reference Path 使用 `AVAssetReader` 产生 storage-format compressed `CMSampleBuffer`，直接进入 Renderer Input Coordination。它证明 sample 之后的 AVFoundation 与 RealityKit 播放管线成立。

PlaybackCore Target Path 使用 FFmpeg demux adapter、Demux Envelope Stream 和 CoreMedia Sample Assembly 产生 compressed `CMSampleBuffer`，再进入相同的 Renderer Input Coordination。它证明 PlaybackCore 自己的解封装接入和 sample 组装能够驱动同一条后半段播放管线。

`AVAssetReader` 不是 Demux Contract adapter。参考路径绕过节点 3 到节点 6，不能产生这些节点的 operation、record 或成功证据。

## 共同 seam

两条路线在 Renderer Input Coordination 的输入汇合。每个输入 item 携带 `mediaSessionID`、`sampleProvenance`、output kind、`CMSampleBuffer`、timing 摘要和 attachment 摘要。

`appleReference` provenance 指向 fixture、asset track 和 AVAssetReader output。`playbackCore` provenance 指向 Track Model、源 Demux Envelope、stream epoch 和 format revision。

两条路线分别运行于独立 Media Session 和 renderer graph。它们复用相同的 renderer 创建、readiness、backpressure、enqueue、synchronizer、`VideoPlayerComponent(videoRenderer:)`、video entity 和 `RealityView` 实现。

## Vertical slices

第一个 tracer bullet 证明一个 ready compressed video sample 的结构事实可记录，sample 被 `AVSampleBufferVideoRenderer` 接受，active renderer 被写入 `VideoPlayerComponent`，video entity 进入 macOS Playback Lab 的 active `RealityView`。它只证明 seam 已经接通。

Apple Sample Reference Path slice 继续读取同一个短小 fixture 的全部 video sample，根据 renderer readiness 输送，处理 backpressure，用 synchronizer 推进时间线。完成时 Agent 能观察 video entity 中的画面连续推进，renderer 没有 decode failure。

PlaybackCore Target Path slice 使用同一个 fixture，真实推进节点 2 到节点 9。完成时目标 sample 能追溯到源 Demux Envelope 和 Track Format Snapshot，进入参考路径已经证明的同一套后半段实现，Agent 能观察相同的连续播放结果，renderer 没有 decode failure。

其他媒体能力和完整播放结束语义不进入当前完成边界。

## 对照规则

两条路线固定使用同一个 `fixtureID` 和 file hash。比较的是规范化的 sample facts：codec、coded dimensions、format description、PTS、DTS、duration、sync state、data readiness，以及 fixture 明确声明为稳定的 sample 数量和顺序。

两条路线不要求 CoreMedia 对象 identity、内存布局或 encoded payload 逐字节相同。可见播放不能替代 sample 结构证明；sample 结构正确也不能替代真实可见播放。每个验证用例只有一个预期结果。

当参考路径通过而目标路径失败时，首先检查 Renderer Input Coordination 之前的 FFmpeg adapter、Demux Envelope 和 CoreMedia Sample Assembly。当两条路线都失败时，首先检查共同后半段实现或 fixture。

## 证据层级

L1 核心事实层验证 PlaybackCore 自己产生的 Container Open Snapshot、Track Model、Demux Envelope、CoreMedia sample facts、节点 record 和 Debug Snapshot。主要证明方式是 macOS test、contract fixture、fake sink 和结构化断言。

L2 承载集成层验证真实 macOS framework 与 App 承载，包括 `AVAssetReader` reference sample、`AVSampleBufferVideoRenderer`、`AVSampleBufferRenderSynchronizer`、`VideoPlayerComponent(videoRenderer:)`、RealityKit Entity、`RealityView` 和可见连续播放。主要证明方式是 macOS Playback Lab、结构化运行记录、日志和 Agent 观察。

L2 不能替代目标路径节点 3 到节点 6 的 L1 证据。Debug Snapshot 是节点 record 和当前状态的派生投影，不能为被绕过的节点制造事实。

## 节点推进

每个实际启动的节点 operation 只有 `succeeded`、`failed` 和 `terminatedByCleanup` 三种结果。失败不会交给下一个节点补救；未启动的节点不制造运行结果。

Apple Sample Reference Path 只启动参考 sample source 和节点 7 到节点 9。PlaybackCore Target Path 按节点 2 到节点 9推进。

节点 7 的成功表示 renderer graph、synchronizer 和输入记录已经建立，并且连续 sample delivery 没有进入不可恢复失败。节点 8 的成功表示 `VideoPlayerComponent` 引用当前 active renderer 并挂到当前 video entity。节点 9 的成功表示该 entity 已进入 active `RealityView`，且当前 slice 要求的帧推进可被观察。

## 记录规则

每个节点记录输入属于哪个 Media Session、来自哪个上游事实、结果和下游边界。节点内部字段只有在影响验收结论、跨节点定位或用户可见结果时才提升为稳定诊断事实。

Renderer Input Record 区分 `accepted`、`deferredByBackpressure`、`rejectedAsStale` 和 `failed`。enqueue accepted 与 decode success 是不同事实。Presentation Binding Record 区分 entity attach 与可见帧推进。

缺失事实使用 `none`、`unknown`、`notExposed` 或 `unsupported`，不能静默消失。所有证据和日志默认使用 privacy-safe locator 摘要。
