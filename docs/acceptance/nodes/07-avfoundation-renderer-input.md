# 节点 7：Renderer Input Coordination

## 作用与边界

节点 7 接受 compressed Video Sample Stream 与共享 Linear PCM Sample Stream，建立当前 Media Session 的 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer`、同一个 `AVSampleBufferRenderSynchronizer` 和 delivery coordination。它不理解具体视频 Provider 或 FFmpeg 私有音频对象。

## 输入 adapter

节点 7 保留节点 6 compressed video sample，不经过 pixel transfer，直接进入 video timeline / readiness / enqueue；选中音轨的 Float32 Linear PCM sample 进入独立 audio renderer readiness / enqueue。两条 lane 只共享 synchronizer，不共享 renderer queue。

## Renderer graph

每个 Media Session 独占一个 renderer graph。video graph record 至少包含 graph ID、video renderer identity、synchronizer identity、route、Stream Epoch、graph revision、timeline configured state、rate 和 current time；存在选中音轨时，Audio Renderer State Record 必须包含相同 graph ID、Media Session ID、video renderer identity 与 synchronizer identity，以及 audio renderer identity、selected raw stream index、PCM count / timing、volume 和 mute。

## Renderer Input Record

每个 input 记录 Media Session、route、track、source sample / marker、Stream Epoch、Format Revision、input kind、action 和 outcome。outcome 为：

- `accepted`。
- `deferredByBackpressure`。
- `rejectedAsStale`。
- `failed`。

上述 Renderer Input Record 对应 video input；audio PCM delivery 由 Audio Renderer State Record 记录 accepted count、last PTS、readiness、end 和 error。两种 record 不能互相推断成功。

## Timeline 与 first enqueue

首个有效 sample 的 PTS 必须先用于 `synchronizer.setRate(_:time:)`，随后才能 first enqueue。`timelineConfiguredBeforeFirstEnqueue` 是显式 record field，不能从最终 renderer status 推断。

## Backpressure

video 与 audio delivery 分别由各自 renderer readiness 驱动。renderer not-ready 是正常控制信号；节点 7 停止对应 lane 的读取并等待下一次 readiness callback。任一 queue 都不得无界增长。只有 renderer error、requires-flush condition、sample contract / ownership failure 或无法恢复的 readiness state 才进入对应 lane 的 failure / recovery。

## Flush、seek、format change、end 与 cleanup

- seek / flush：旧 Stream Epoch 失效，停止两条旧 delivery，flush audio/video renderer，等待新 epoch sample。
- format change：停止旧 Format Revision input，flush，并等待新 format sample。
- audio track switch：在当前时间准备新轨并替换 audio input；失败时恢复旧轨、rate / paused state 与 PCM delivery。
- end：分别记录 video 与所选 audio lane 的 input end 和 last presentation end；只有两条 active lane 都结束且 synchronizer time 越过较晚边界后才发布 public ended。
- cleanup：停止两个 renderer 的 media request、rate 归零、flush audio/video renderer 和 displayed image，并拒绝之后到达的旧 input。

## 完成条件

video 节点的唯一完成条件：renderer graph 与 video delivery coordination 已建立，并且至少一个当前 compressed sample 被 accepted 或明确 deferred by backpressure。存在选中音轨时，audio lane 使用独立完成事实：audio renderer 已加入同一 graph 且至少一个当前 PCM sample 被 accepted。video sample accepted、audio sample accepted、renderer rendering、displayed pixel buffer、可听输出和 sustained progress 分别记录。

## 验收方向

L1 fake sink 验证 route-independent video dispatch、compressed sample contract、audio/video graph identity、timeline ordering、各自 backpressure、stale rejection、flush、A/V ended 和 errors。macOS L2 使用真实 renderer 证明两条 route 的 first video enqueue、PCM enqueue、displayed frame 和 sustained progress。Simulator 只补 visionOS platform-specific behavior；可听输出与主观同步仍是独立人工事实。
