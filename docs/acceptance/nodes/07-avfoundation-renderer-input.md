# 节点 07：Renderer Input Coordination

## 边界

节点 07 接受节点 06 的 audio/video sample，建立当前 Media Session 的 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer`、一个共享 `AVSampleBufferRenderSynchronizer` 和 Receiver delivery coordination。它不理解来源、SwiftUI 或 Playback Presentation。

## 稳定规则

- 每个 Media Session 独占一个 renderer graph；audio/video renderer 与 synchronizer 共享 graph identity。
- 首个有效 presentation time 必须在 first enqueue 前建立 synchronizer timeline，但 timeline 保持停止，直到当前 video epoch 从可解码起点至第一个到达或越过请求 decode time 的 sample 都已被 renderer 接受；越过目标的 sample 不要求时间戳恰好相等，也不能等待只有 timeline 启动后才能形成的正常播放 backpressure。存在已选择音轨时，当前 audio epoch 也必须在停止的 timeline 上提交覆盖启动时间并具有至少 0.25 秒提前量的音频。两个条件完成后才发布目标 Playing/Paused 状态并应用目标 rate。
- 生产 audio/video Receiver 使用立即提交，PlaybackCore 分别以共享时间线限制最多一秒的提前量；异步等待不是失败，queue 不得无界增长。
- 普通暂停以及以相同 rate 恢复保留 audio Receiver 中已经排队的当前 epoch 音频，不执行没有重新定位音频 provider 与重新 preroll 配套的 flush。
- accepted、deferred、stale 与 failed input 分别记录。
- seek、format change、track switch、close 和 failure 取消旧 delivery task、flush 受影响 Receiver，并使旧 epoch/revision 输入失效。
- 自然结束只在所有 active lane 结束且 synchronizer time 越过最终 presentation end 后发布；显式 seek 到总时长发布带 `seekToEnd` 原因的 ended 并保持画面已清除，两者不能共享“自然完成”事实。
- renderer error、sample contract failure 和无法恢复的 provider failure终止当前 session，不触发隐藏 fallback。

## 完成条件

唯一完成条件：renderer graph 与 delivery coordination 已建立，当前 video sample 被 accepted 或明确 deferred；存在 active audio 时，audio renderer 已加入同一 graph且当前 sample 被 accepted/deferred。

sample accepted、renderer rendering、displayed pixel、持续推进、系统音频路由有效、可听输出与颜色正确是独立事实。音频 renderer 证据必须记录其实际 status 与 error，不能只记录 Receiver 接受数量。

## 验收

L1 使用受控 Receiver seam 验证 timeline ordering、decode time 从目标前跨到目标后但不精确相等时仍完成 bootstrap、audio 在 rate 生效前完成 preroll、普通暂停恢复不 flush 当前音频、正常提前量限制、stale rejection、必要 flush、ended 和 error；visionOS App 集成验证使用真实 renderer 证明 first enqueue、displayed frame、audio progression、seek/rate/control、cleanup 和 same-process reopen。
