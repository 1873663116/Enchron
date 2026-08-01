# PlaybackCore 规格

这是 PlaybackCore 的唯一活跃行为规格。它定义 Enchron 所依赖的媒体接入、sample、renderer、控制、轨道、Playback Lifecycle 和诊断合同；来源长期授权、产品策略、RealityKit entity、Playback Presentation 与 SwiftUI 属于 Enchron App。

本文件不拥有一套独立验证体系。完整产品链的节点 01–09、分层门槛与证据规则统一位于 `docs/acceptance/`；节点可以由不同模块实现，但不能按模块拆成互不相连的文档。

## 目标与边界

PlaybackCore 接受一个 Media Source，读取容器并建立 Media Session。它解封装音视频，组装保留原始编码、时间信息和格式信令的 `CMSampleBuffer`，交给 Apple AVFoundation 的 sample-buffer renderer。

PlaybackCore 不解码视频，不拥有 HDR / Dolby Vision 映射、自定义画面处理、产品画面参数或 Playback Presentation。公开产品接口不暴露 FFmpeg、AVAssetReader 或其他验证路线，也不在失败后静默切换路径。

## Media Session

同一时刻只有一个 Current Media Slot。accepted open 创建新的 Media Session；槽位被占用时必须拒绝新 open，close 或不可恢复 failure 完成 cleanup 后才能释放。

Media Session 的 source、initial time、paused state 和 preferred rate 创建后保持稳定。旧 session、旧 Stream Epoch 或旧 Format Revision 的迟到事件只能记录为 stale，不得更新当前状态。

## Container 与轨道

Provider 打开来源后形成不可变的 container、duration、seekability、track、codec、timing、color、HDR、projection 和 stereo facts。不存在的事实、当前未知的事实与 provider 未暴露的事实必须区分，不能用默认值猜测。

轨道模型至少覆盖 video、audio 和 subtitle 的稳定身份、来源映射、格式事实、选择状态与不选择原因。App 使用稳定 track identity，不依赖 FFmpeg stream index、AVAsset track identity 或 UI index。

## Compressed sample

Video sample 保留 compressed payload、PTS、DTS、duration、keyframe/dependency attachments、codec configuration、color、HDR / Dolby Vision、projection 和 stereo signaling。

Audio sample 保留 compressed payload、时间信息、codec configuration、channel layout 与 sample-rate facts，并交给 `AVSampleBufferAudioRenderer`。PlaybackCore 不把音频解码为自有 PCM 路线。

Provider 私有对象和裸 pointer 不进入 sample interface。seek、reopen、format change 和 cleanup 建立新的事件世代；旧世代 sample 不得进入当前 renderer graph。

Subtitle 轨道提供可选择的稳定身份和带时间范围的字幕数据接口；字幕如何显示属于 Enchron。Chapter 等 container metadata 作为只读媒体事实提供，不进入 renderer graph。

## Renderer Input Coordination

Video 与 audio 分别通过 AVFoundation Receiver 输送。生产 Receiver 使用 `enqueueImmediately`，PlaybackCore 依据共享 synchronizer 的当前时间和请求目标限制最多一秒的 renderer 提前量；这个限制必须产生异步等待并响应 cancellation，不能把整个媒体无界地送入 renderer。首次 enqueue 前以首个有效 presentation time 配置共享 synchronizer timeline。Decoder bootstrap 期间 timeline 保持停止，当前 epoch 从可解码起点到第一个到达或越过请求 decode time 的 video sample 必须先被 renderer 接受；越过请求时间的 sample 不要求与请求时间戳恰好相等，也不能在停止的 timeline 上等待一个依赖播放时钟前进的 Receiver readiness。存在已选择音轨时，当前 audio epoch 还必须在 timeline 停止期间向同一 renderer graph 提交覆盖启动时间的音频，并形成至少 0.25 秒的可播放提前量。Video bootstrap 与 audio preroll 都完成后才应用目标 rate，并继续执行同一提前量限制。普通暂停以及以相同 rate 恢复不 flush audio Receiver；只有 seek、轨道切换、format change、close、renderer 明确要求或 failure 才丢弃相应的旧音频输入。

每个 Media Session 使用一个 renderer graph。Video renderer、可选 audio renderer 和 synchronizer 属于同一 graph；seek、format change、close 和 failure 必须取消旧 delivery task、flush 受影响的 Receiver、使旧输入失效并留下明确记录。

public ended 只有在所有 active media lane 结束且 synchronizer time 越过最终 presentation end 后发布。renderer error、sample contract failure 和无法恢复的 provider failure必须终止当前会话，不能由隐藏 fallback 掩盖。

## Projection 与 Stereo override

PlaybackCore 报告来源检测到的 projection 与 stereo facts。调用方可以显式覆盖有效 projection 或 stereo layout；override 只重建 format description，保留 compressed payload、timing、attachments、color、HDR / Dolby Vision signaling、Media Session 和 renderer graph。

新 Format Revision 被当前 renderer 接受前，override 不能报告为稳定完成。

## 控制

公开控制至少包含 open、close、reopen、play、pause、seek、rate、volume、mute、audio track selection、subtitle track selection 以及 projection/stereo override。

所有控制只作用于当前 Media Session。无 active session、cleanup 未完成、目标 session 已过期或互斥操作进行中时必须显式拒绝。seek 与 reopen 保留调用方可观察的播放意图，但不得产生第二条 timeline。

每次 seek 由调用方传入完成后的播放意图，PlaybackCore 不识别 Progress Bar、Precision Timeline 或逐帧等界面概念。保留播放意图只在 Playing 与 Paused 之间保持原状态；Ended 没有 Playing 意图，因此从 Ended seek 离开结尾时落到 Paused。显式 seek 到媒体总时长进入 Ended，但结束原因必须与自然播放结束区分，使产品层不能把 seek 到结尾误记为自然看完。

## Playback Lifecycle 与诊断

公开状态至少区分 idle、loading、ready、playing、paused、ended 与 failed；ended 进一步携带自然播放完成或 seek 到结尾的原因。一次产品播放启动中的 source、session、provider、sample、renderer input、control、track selection、cleanup 和 error 事实使用同一关联身份。

PlaybackCore 是 Playback Lifecycle 的唯一发布者。Enchron App 可以为了界面建立只读投影，但不得增加与核心竞争的 playing、paused、ended、position、track 或 seek 调度事实。

PlaybackCore 发布结构化事件和版本化 Debug Snapshot，供 Enchron 投影和 OSLog 记录。音频 renderer 投影必须区分 sample 已接受、renderer 的实际 `unknown` / `rendering` / `failed` 状态、renderer error、音量与静音；不能用 sample 数量替代 renderer 状态。Snapshot 是 records 的当前投影，不是第二套状态机，也不能单独证明可见画面、可听输出或产品呈现。

## 完成条件

PlaybackCore 完成需要同时证明：

1. 公开接口只有一条产品 sample-buffer 路径，没有 route selection、decoded pixel 或 PCM product path。
2. 真实 container 可以稳定输出满足合同的 compressed audio/video sample，并正确处理 B-frame、seek、format change、end、failure 与 cleanup。
3. audio/video renderer 属于同一 graph 和 synchronizer，控制与轨道切换具有确定语义。
4. stale callback、superseded operation、renderer failure 和 cleanup barrier 有自动测试。
5. library 在 macOS 与 visionOS 构建，当前测试通过；真实媒体和 AVFoundation renderer 证据按验证规则记录。
6. Enchron App 的 visionOS 集成验证使用真实媒体、生产 `PlaybackRuntime`、真实 audio/video renderer、共享 synchronizer 与 RealityKit consumer，证明持续可见播放、可听音频、音画同步、seek、连续 seek、快进、快退、rate、pause/resume、音量、静音、close/reopen 和长时间运行。
7. 产品 compressed sample 的 codec configuration、color primaries、transfer function、YCbCr matrix、range 与 HDR / Dolby Vision signaling 必须在 PlaybackCore 合同验证中与 visionOS App 的 displayed-frame 观察相互校验；缺失、错误或仅由来源 metadata 推断都视为未通过。

visionOS platform entry、RealityKit consumer 与验证编排由 Enchron App 承载，不改变 PlaybackCore 的 module 边界。核心行为只有在系统节点 01–09 的相应证明成立后才能进入产品完成声明；最终 Playback Presentation、HDR 观感与交互仍由 Vision Pro 验收。
