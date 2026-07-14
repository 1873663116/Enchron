# Spec：PlaybackCore audio-video sample-buffer library

这是 PlaybackCore 的唯一活跃规格。它定义 Media Session、两条 compressed video Provider、共享音频、renderer graph、控制、format override 与诊断。产品 App、SwiftUI scene、RealityKit entity 和空间呈现不属于本规格。

## 目标与范围

PlaybackCore 接受一个可读取的媒体 URL 和显式 Playback Route，创建 Media Session，并产出由同一个 AVSampleBufferRenderSynchronizer 管理的视频与音频 renderer。

当前支持：

- Apple Compressed 对照路线与 FFmpeg Compressed 产品路线。
- FFmpeg 音频轨道发现、选择、解码和 Linear PCM 输出。
- compressed video 与 Linear PCM audio 的共享时间线。
- open、close、reopen、play、pause、seek、rate、volume、mute、audio track selection 和 cold route switch。
- Projection 与 Stereo 的显式 sample-format override。
- 版本化 records、Debug Event Stream 与 DebugSnapshotV1。
- macOS 与 visionOS library 构建。

当前不支持 subtitle、chapter、playlist、resume persistence、network cache、DRM 或产品 presentation orchestration。

## 所有权

调用方拥有 URL 的长期授权与来源发现。PlaybackCore 只在当前 Media Session 生命周期内读取来源。

PlaybackCore 拥有 Provider、sample、audio decoder、renderer graph、timeline、控制状态和诊断事实。调用方不能直接修改内部节点或 renderer queue。

PlaybackCore 把 active video renderer 交给 App Adapter。App Adapter 拥有 renderer consumer、entity、scene 和用户交互。调用方可以回填带 provenance 的 binding facts；核心不得由此推测产品呈现成功。

## Open admission 与 Media Session

同一时刻只有一个 Current Media Slot。accepted open 创建新的 Media Session ID；被占用时的 open 必须被拒绝且不创建会话。

Media Session 的 source、route、initial time、initial paused state 和 initial rate 创建后不可变。close 或不可恢复 failure 必须完成 Provider cancel、renderer request stop、rate reset、audio/video flush、binding invalidation 与 stale rejection 后才释放槽位。

## Provider 与 sample

Apple Compressed 使用 AVAssetReaderTrackOutput(outputSettings: nil) 交付 storage-format compressed sample。FFmpeg Compressed 自行解封装并创建等价 compressed CMSampleBuffer。

Provider event 必须携带 Media Session ID、route、track identity、Stream Epoch 与 Format Revision。裸 CMSampleBuffer 不是完整接口。

两条路线在进入 Renderer Input Coordination 前必须形成一致的 sample ownership、timing、format description、sync attachment 与 end/error 语义。系统不自动选择路线，也不在失败后 fallback。

## Audio

两条视频路线共用 FFmpeg Audio Track Provider。选中音轨被解码和重采样为交错 Float32 Linear PCM，并交给 AVSampleBufferAudioRenderer。

audio renderer 与 video renderer 必须加入同一个 synchronizer。音轨切换、seek、pause、rate、close 与 failure cleanup 不得产生第二条时间线。

## Renderer Input Coordination

video 与 audio lane 各自按 renderer readiness 输送；not-ready 是 backpressure，不是失败。首次 enqueue 前必须先以首个有效 PTS 配置 synchronizer timeline。

seek、format change、route switch 和 close 必须使旧事件世代失效。旧 Media Session、Stream Epoch 或 Format Revision 的迟到事件只能记录为 stale，不得更新当前状态。

ended 只有在所有 active lane 都结束且 synchronizer time 越过较晚 presentation end 后发布。

## Projection 与 Stereo override

Projection 与 Stereo override 位于两条 Provider 汇合后的共享 sample-format seam。它们可以重建 CMFormatDescription，但必须保留 compressed payload、timing、attachments、color、HDR / Dolby Vision signaling、Media Session、Stream Epoch、renderer graph 与 timeline。

override 递增 Format Revision。新 revision 被当前 renderer 接受前，核心不能把 override 记录为稳定生效。

## 控制

所有运行控制都作用于当前 Media Session。无 active session、seek 进行中、cleanup 尚未完成或命令目标已过期时必须显式拒绝。

cold route switch 保存时间、paused state、preferred rate、volume、mute、选中音轨和 format override，关闭旧会话后创建新 Media Session。它不是同一会话内的热切换。

## 状态与诊断

公开状态至少区分 idle、loading、ready、playing、paused、ended 与 failed。

DebugSnapshotV1 至少包含 source、session、route、lifecycle、operations、Provider Open Snapshot、Video Track Model、epochs、sample counts、renderer graph、audio tracks、timeline、controls、binding facts、color / HDR signaling 与错误。

Snapshot 是稳定 records 的投影，不自动构成验收证据。缺失或平台不可观察的字段必须保留 typed availability，不能猜测默认值。

## 完成条件

PlaybackCore library 完成只由核心接口证明：

1. 两条 Provider 各自满足 open、sample、seek、end、failure 与 cleanup 合同。
2. video 与 audio renderer 属于同一 graph 和 synchronizer。
3. play、pause、seek、rate、volume、mute、track selection、reopen、route switch 和 close 具有确定状态语义。
4. stale callback、superseded operation、renderer failure 与 cleanup barrier 可由自动测试证明。
5. Swift Package 在声明的平台上构建，核心测试通过。

可见画面、可听输出、HDR 观感、RealityKit、窗口和空间呈现属于消费方验收，不是本仓库完成声明。
