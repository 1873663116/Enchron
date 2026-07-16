# 节点 07：Renderer Input Coordination

## 边界

节点 07 接受节点 06 的 audio/video sample，建立当前 Media Session 的 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer`、一个共享 `AVSampleBufferRenderSynchronizer` 和 Receiver delivery coordination。它不理解来源、SwiftUI 或 Playback Presentation。

## 稳定规则

- 每个 Media Session 独占一个 renderer graph；audio/video renderer 与 synchronizer 共享 graph identity。
- 首个有效 presentation time 必须在 first enqueue 前建立 synchronizer timeline。
- audio/video 分别等待 Receiver backpressure；等待不是失败，queue 不得无界增长。
- accepted、deferred、stale 与 failed input 分别记录。
- seek、format change、track switch、close 和 failure 取消旧 delivery task、flush 受影响 Receiver，并使旧 epoch/revision 输入失效。
- public ended 只在所有 active lane 结束且 synchronizer time 越过最终 presentation end 后发布。
- renderer error、sample contract failure 和无法恢复的 provider failure终止当前 session，不触发隐藏 fallback。

## 完成条件

唯一完成条件：renderer graph 与 delivery coordination 已建立，当前 video sample 被 accepted 或明确 deferred；存在 active audio 时，audio renderer 已加入同一 graph且当前 sample 被 accepted/deferred。

sample accepted、renderer rendering、displayed pixel、持续推进、可听输出与颜色正确是独立事实。

## 验收

L1 使用受控 Receiver seam 验证 timeline ordering、backpressure、stale rejection、flush、ended 和 error；macOS L2 使用真实 renderer 证明 first enqueue、displayed frame、audio progression、seek/rate/control、cleanup 和 same-process reopen。
