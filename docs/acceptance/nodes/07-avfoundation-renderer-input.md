# 节点 7：Renderer Input Coordination

## 作用与边界

节点 7 是 Apple Sample Reference Path 与 PlaybackCore Target Path 的共同 seam。它把 compressed video `CMSampleBuffer` 送入 `AVSampleBufferVideoRenderer`，管理 renderer readiness、backpressure、enqueue、`AVSampleBufferRenderSynchronizer` 时间线和 renderer error。RealityKit binding 与 `RealityView` presentation 分别由节点 8 和节点 9 记录。

节点 7 不重新组装 `CMSampleBuffer`，也不改变 sample 的媒体内容。

## 输入

每个输入 item 包含 `mediaSessionID`、`sampleProvenance`、compressed video `CMSampleBuffer`、PTS、DTS、duration 和 sample attachment 摘要。

`appleReference` provenance 包含 `fixtureID`、asset track identity 和 AVAssetReader output identity。它不包含伪造的 Track Model、Demux Envelope 或节点 6 记录。

`playbackCore` provenance 包含 `trackModelID`、`sourceEnvelopeID`、`streamEpoch` 和 `formatRevision`。

节点 7 只接受当前 Media Session 的输入。PlaybackCore Target Path 还必须拒绝旧 `streamEpoch`、无法解析 format revision 或 cleanup 后到达的 sample。

## Renderer graph

当前 renderer graph 只包含 `AVSampleBufferVideoRenderer` 和 `AVSampleBufferRenderSynchronizer`。两条路线分别创建独立 renderer graph，但使用相同的构造和配置代码。

sample delivery 由 renderer readiness 驱动。renderer 不需要更多数据时，节点 7 停止取样并等待恢复；backpressure 是正常控制信号，不是播放失败。输入不能无界排队。

Renderer Input Record 区分 `accepted`、`deferredByBackpressure`、`rejectedAsStale` 和 `failed`。enqueue accepted 与 decode success 是两个不同事实。decode failure 必须形成可追溯失败记录。

## 输出与推进

节点 7 输出 Renderer Input Record 和 active renderer graph。

`succeeded` 表示 renderer graph 与 synchronizer 已建立，sample delivery 已开始，并且当前 slice 要求的输入没有进入不可恢复失败。`failed` 表示 renderer 创建、enqueue、timeline 或 decode 失败。`terminatedByCleanup` 表示 cleanup 终止当前 input operation。

节点 7 成功后，节点 8 才能消费 active video renderer。

## 验收方向

L1 使用 fake renderer sink 验证 provenance、路由、readiness、backpressure、stale rejection 和失败记录。

L2 使用 macOS Playback Lab 分别运行 Apple Sample Reference Path 与 PlaybackCore Target Path，证明连续 video sample 进入真实 `AVSampleBufferVideoRenderer`，synchronizer 推进时间线，backpressure 可恢复，renderer 没有 decode failure。

具体 renderer API 形态、测试拆分和恢复用例由实现阶段使用 `$tdd` 决定。
