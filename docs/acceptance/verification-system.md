# PlaybackCore 验证规则

本文件定义 `docs/core-spec.md` 的唯一验证系统。验证目标不是证明“代码能够构建”，而是逐层证明产品所连接的 PlaybackCore 确实能够播放。任何上层验证都不能替代尚未通过的下层门槛。

## 分层与执行顺序

### L1 — Core Contract

L1 在 PlaybackCore package 内运行，不依赖真实 RealityKit surface。`swift test` 使用确定性 fixture、fake clock 与受控 receiver seam，证明公开接口、Media Session、Provider records、sample contract、轨道、控制、Receiver async backpressure、timeline、stale rejection、failure 和 cleanup。

真实 container probe 仍属于 L1 integration：它证明 FFmpeg demux 与 compressed `CMSampleBuffer` 的 payload、timing、codec configuration、color/HDR signaling 和世代归属，但不能证明 renderer 已显示画面或输出音频。

### L2 — Enchron macOS App

L2 的主宿主是 Enchron 的 macOS App。其核心验证模式不复制播放状态机，直接使用当前 PlaybackCore public API、真实媒体、`AVSampleBufferVideoRenderer`、`AVSampleBufferAudioRenderer`、共享 synchronizer、Receiver enqueue 和真实 RealityKit consumer。

Enchron macOS App 至少提供两个独立 scenario：

1. Core scenario：直接连接 PlaybackCore，隔离产品状态、来源浏览、窗口编排和空间转换，证明核心播放。
2. App Adapter scenario：核心 scenario 通过后，改由 Enchron 的 `PlaybackRuntime` 连接同一套 renderer consumer，证明产品 adapter 没有改变时间线、sample、颜色或控制语义。

Enchron macOS L2 是声明“核心可播放”的必要条件。visionOS Simulator 只补充 macOS 不具备的 API 与 scene lifecycle，不重新承担核心首验，也不能替代 L2。

### L3 — Vision Pro

L3 使用与 L2 相同的 fixture identity 和期望，在物理 Vision Pro 上证明 visionOS 硬件解码、HDR/EDR 与 Dolby Vision 观感、设备音频、空间呈现、性能和交互。L3 不能用 generic device build、Simulator、截图或日志替代。

## 节点合同

一次播放按以下节点逐级成立；证据必须指出第一处失败节点，不能用后续 UI 现象概括整个链路。

| 节点 | 必须成立的事实 | 最低层级 |
|---|---|---|
| 1 Source Acquisition | source 可读取，身份与访问范围稳定 | L1 |
| 2 Media Session | open 被接受，session、初始时间与播放意图唯一 | L1 |
| 3 Provider Open | container、duration、seekability、轨道与 codec facts 固定 | L1 |
| 4 Track Model | video/audio 稳定身份、选择与格式事实正确 | L1 |
| 5 Media Event Stream | sample、format、flush、end、error 带正确 epoch/revision | L1 |
| 6 Compressed Sample | payload、PTS/DTS/duration、dependency、codec config、color/HDR signaling 正确 | L1 |
| 7 Renderer Input | 当前 sample 被正确 Receiver 接受，共享 timeline 推进且无 renderer error | L2 |
| 8 RealityKit Binding | active video renderer 与唯一真实 consumer 身份一致并保持 attached | L2 |
| 9 Displayed / Audible Output | displayed pixel 持续更新，音频可听且与视频同步 | L2；设备特性升到 L3 |

`Provider Open Snapshot` 中存在颜色 metadata 不等于节点 6 或节点 9 已通过。必须分别检查 sample 的 `CMFormatDescription` 与实际 displayed pixel buffer 的 color primaries、transfer function、YCbCr matrix、range 和 pixel format。

## L2 必测行为

每个会影响 sample assembly、Receiver、timeline、renderer graph 或 App Adapter 的 revision，都必须在产品 FFmpeg compressed 路线运行以下矩阵：

| 切片 | 唯一通过条件 |
|---|---|
| 启动与持续播放 | 从首个有效 PTS 建立 timeline；displayed frame 与 audible audio 持续推进至规定观察点，无 renderer error |
| Pause / Resume | 暂停期间 media time 与 displayed frame 不前进；恢复后沿同一 session 继续 |
| Seek | 单次前后 seek 到达容差内目标；旧 epoch sample 不再显示或播放 |
| 连续 Seek | 快速连续目标只提交最终未 superseded 操作，不产生第二 timeline |
| 快进 / 快退 | 前后跳转与非 1.0 rate 行为符合 public control 语义；恢复 1.0 后音画继续同步 |
| 音频控制 | volume、mute、音轨选择作用于当前 graph；切换后无旧音轨串音 |
| Close / Reopen | delivery task 取消、Receiver flush、consumer detach 与资源释放完成；reopen 建立新 session |
| End | 所有 active lane 完成且 synchronizer 越过最终 presentation end 后才发布 ended |
| 颜色与 HDR 信令 | sample 与 displayed pixel 的 primaries、transfer、matrix、range 符合 fixture oracle；HDR fixture 不允许字段缺失 |
| 稳定性 | 规定时长内 sample、displayed frame、audio 与 timeline 持续推进，内存与 task 数不无界增长 |

Apple compressed reference scenario 使用同一 fixture 与同一 L2 consumer，作为 AVFoundation 能力和期望画面的对照。它不是产品 fallback，也不能替 FFmpeg compressed scenario 出具通过结论。两条 scenario 在 Provider seam 之前可以不同；节点 7–9 的 renderer、synchronizer、RealityKit binding 和断言必须相同。

## Fixture 与证据

fixture registry 必须使用稳定 ID，记录许可、文件 hash、容器、codec、色彩/HDR、音轨、时长和各测试 oracle。本机绝对路径不是 fixture identity。最低集合覆盖 SDR、HDR10/PQ、HLG、受支持的 Dolby Vision profile、B-frame、至少双音轨和可 seek 长媒体。

registry 的机器可读入口是 `fixture-registry.json`。`acceptanceEligibility` 不是说明文字：许可未知、oracle 不完整或来源不可稳定取得的素材只能用于诊断回归，不能让完整 L2/L3 矩阵变成 `passed`。

每次证据记录必须包含：Git revision、toolchain/OS、fixture ID 与 hash、scenario、命令或 test identifier、节点结果、控制矩阵结果、首个失败边界、日志/`.xcresult`/机器可读 artifact 路径。只有当前 revision 的完整必测矩阵可以标记 `passed`；历史结果标记 `stale` 或 `reference`。

构建成功、测试数量、某一条 scenario 成功、日志中没有错误、能够拖动进度条、单帧截图或来源 metadata 正确，都不是持续播放、音频、颜色或产品呈现通过的替代品。最近一次有效证据记录在 `evidence.md`。
