# PlaybackCore 规格

这是 PlaybackCore 的唯一活跃规格。它定义产品所依赖的媒体接入、sample-buffer、renderer、控制、轨道和诊断行为；产品 UI、RealityKit entity、窗口与空间呈现属于 Enchron。

## 目标与边界

PlaybackCore 接受一个 Media Source，读取容器并建立 Media Session。它解封装音视频，组装保留原始编码、时间信息和格式信令的 `CMSampleBuffer`，交给 Apple AVFoundation 的 sample-buffer renderer。

PlaybackCore 不解码音视频，不拥有 HDR / Dolby Vision 映射、自定义画面处理或画面参数。公开接口不暴露 FFmpeg、AVAssetReader 或其他实现路线，也不在失败后静默切换播放路径。

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

Video 与 audio 分别通过 AVFoundation Receiver 的 async enqueue 输送；等待 enqueue 是 backpressure，不是失败。首次 enqueue 前以首个有效 presentation time 配置共享 synchronizer timeline。

每个 Media Session 使用一个 renderer graph。Video renderer、可选 audio renderer 和 synchronizer 属于同一 graph；seek、format change、close 和 failure 必须取消旧 delivery task、flush 受影响的 Receiver、使旧输入失效并留下明确记录。

public ended 只有在所有 active media lane 结束且 synchronizer time 越过最终 presentation end 后发布。renderer error、sample contract failure 和无法恢复的 provider failure必须终止当前会话，不能由隐藏 fallback 掩盖。

## Projection 与 Stereo override

PlaybackCore 报告来源检测到的 projection 与 stereo facts。调用方可以显式覆盖有效 projection 或 stereo layout；override 只重建 format description，保留 compressed payload、timing、attachments、color、HDR / Dolby Vision signaling、Media Session 和 renderer graph。

新 Format Revision 被当前 renderer 接受前，override 不能报告为稳定完成。

## 控制

公开控制至少包含 open、close、reopen、play、pause、seek、rate、volume、mute、audio track selection、subtitle track selection 以及 projection/stereo override。

所有控制只作用于当前 Media Session。无 active session、cleanup 未完成、目标 session 已过期或互斥操作进行中时必须显式拒绝。seek 与 reopen 保留调用方可观察的播放意图，但不得产生第二条 timeline。

## 状态与诊断

公开状态至少区分 idle、loading、ready、playing、paused、ended 与 failed。一次产品播放启动中的 source、session、provider、sample、renderer input、control、track selection、cleanup 和 error 事实使用同一关联身份。

PlaybackCore 发布结构化事件和版本化 Debug Snapshot，供 Enchron 投影和 OSLog 记录。Snapshot 是 records 的当前投影，不是第二套状态机，也不能单独证明可见画面、可听输出或产品呈现。

## 完成条件

PlaybackCore 完成需要同时证明：

1. 公开接口只有一条产品 sample-buffer 路径，没有 route selection、decoded pixel 或 PCM product path。
2. 真实 container 可以稳定输出满足合同的 compressed audio/video sample，并正确处理 B-frame、seek、format change、end、failure 与 cleanup。
3. audio/video renderer 属于同一 graph 和 synchronizer，控制与轨道切换具有确定语义。
4. stale callback、superseded operation、renderer failure 和 cleanup barrier 有自动测试。
5. library 在 macOS 与 visionOS 构建，当前测试通过；真实媒体和 AVFoundation renderer 证据按验证规则记录。

RealityKit binding、最终画面、HDR 观感、空间呈现和产品交互由 Enchron 验收，不是本仓库单独完成的声明。
