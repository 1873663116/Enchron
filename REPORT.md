# 音频无声与 seek 后掉帧修复报告

## 结论

本次工作按照“先复现、后修改、再以同一指标复验”的顺序完成。

《Furiosa》的 TrueHD 8 声道路径在修复前每个 `CMSampleBuffer` 只有 40 帧、0.833 ms，约需每秒投递 1,200 个缓冲。修复后每个缓冲为 4,800 帧、100 ms，每秒约 10 个缓冲。真机状态由 `hasSufficientMediaDataForReliablePlaybackStart=false` 翻转为 `true`，renderer 保持 `rendering`，且 `muted=false`、`volume=1`、无 renderer 错误。

seek 后的视频解码领先量在修复前由 `+0.042 s` 降至 `-5.752 s`，随后降至 `-15.645 s`。修复后 seek 首次启动时建立 `+5.862 s` 领先量。设备持续负载使领先量耗尽时，状态机自动冻结时间线并同时预滚音视频，恢复后视频领先量为 `+5.416 s`，音频领先量为 `+5.453 s`。这把持续恶化的负值曲线改成了有界的自动再缓冲。

机器可观察的音频链路和 seek 恢复均已通过。由于佩戴者不在场，TrueHD 的实际可闻性、音质和多声道空间化仍待佩戴者验收，不能由 renderer 状态代替。

## 复现与判据

修复前证据位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/audio-silence-fix-20260817/pre-fix/`。

TrueHD 无声会话具有以下签名：

- 音频缓冲为 40 帧、0.833 ms，约每秒 1,200 个缓冲。
- `audioRendererStatus=rendering`、`muted=false`、`volume=1`，无错误。
- `hasSufficientMediaDataForReliablePlaybackStart=false`。
- seek 后解码落后量在 21 秒内由接近零扩大到 15.645 秒。

本地 AAC 对照为 1,024 帧、21.333 ms，视频仅落后 0.047 秒。AC-3 仍走压缩直递，单个缓冲时长为 32 ms。DTS、FLAC、Vorbis、AAC、AC-3 与 E-AC-3 的编码行为由 PlaybackCore 编解码矩阵覆盖；本轮物理设备取证覆盖 TrueHD、AAC 和 AC-3。DTS、FLAC 与 E-AC-3 尚未逐一完成佩戴者听感验收。

## 根因与修改

缺陷一的根因是 FFmpeg TrueHD 解码器暴露 40 帧子帧，而桥接层把每个子帧直接封装成 CoreMedia 缓冲。结构状态虽然正常，极高的跨层投递频率却没有形成设备音频 renderer 可依赖的预备数据。

提交 `a82ad3d` 完成以下修改：

- 使用 `AVAudioFifo` 先聚合解码帧，再统一转换为交错 Float32 PCM。
- TrueHD 采用 100 ms、4,800 帧的设备投递粒度；其他细碎解码输出以 20 ms 为下限；原本已经足够大的 AAC、FLAC 和 ProRes 音频帧保持自身边界。
- 批量读取共享 demux 包，并复用包节点，减少锁、分配和 Swift/C 边界往返。
- Debug 真机构建对 C 桥接目标启用 `-O2`，音频 reader 队列使用 `userInitiated` QoS。
- 新增 TrueHD 12,000 帧夹具断言，输出必须为 `[4800, 4800, 2400]`。

缺陷二并非只由 TrueHD 争抢造成。同一受压会话切换 AC-3 后可以快速追赶，但设备持续负载仍可能再次让音视频共同落后。真正缺失的是领先量耗尽后的自动恢复。产品此前只在 seek 目标处启动时间线，之后即使投递落后也继续推进，用户只能手动暂停等待。

提交 `cbac02c` 完成以下修改：

- visionOS 真机 seek 在启动时间线前预滚 5 秒，并把 renderer 最大领先量扩为 6 秒。
- 视频投递落后时间线达到 0.5 秒时，状态机以 `deliveryLagRecovery` 原因冻结时间线。
- 视频到达恢复终点后等待音频到达同一终点，再按原时间位置恢复速率。
- 预滚终点受媒体时长约束，片尾 seek 不会等待不存在的样本。
- 该设备策略限定在 visionOS 的生产 bounded-lead renderer，不改变 macOS 合成测试与其他 renderer 策略。

## 真机复验

最终证据位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/audio-silence-fix-20260817/final-auto-recovery/`，汇总文件为同级 `analysis.json`。

| 检查点 | 视频领先量 | 音频领先量 | 结果 |
|---|---:|---:|---|
| seek 预滚完成 | +5.862 s | +6.077 s | `actualRate=1`，TrueHD 缓冲 100 ms，sufficient=true |
| 持续播放 28 秒 | +2.706 s | +2.597 s | 领先量下降但仍为正 |
| 自动恢复触发 | 时间线固定于 3531.513 s | 音视频继续填充 | `actualRate=0`，随后自动恢复为 1 |
| 第二次恢复完成 | +5.416 s | +5.453 s | `actualRate=1`，sufficient=true |

最终截图为 `final-auto-recovery/controller/b82aa731-2c35-494c-bae7-a49f10fd03e3.png`，尺寸为 1920×1080，已排除 1×1 截图陷阱。最终 runner 已通过控制器停止，`remaining=[]`。未卸载 App，未改变权限状态。

## 验证门禁

- `swift test --package-path Packages/PlaybackCore`：运行 214 项，仅保留约定的三项基线失败：`appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`、`appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`、`controllerRejectsSecondOpenAndRecordsTheRejection`。
- `python3 Scripts/verification/run_verification_gauntlet.py --quick`：通过。日志位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/runs/20260817T075245Z-72752`。
- visionOS 真机 `build-for-testing`：通过，DerivedData 位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedDataAudioSilence-20260817`。
- visionOS 整机构建：通过，DerivedData 位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedDataAudioSilenceFinal-20260817`。
- `git diff --check`：通过。

## 限制与待验收项

自动恢复会在设备无法维持实时投递时产生一次短暂停顿。这是有界再缓冲，不再表现为持续数秒一帧；若远程吞吐长期低于媒体码率，恢复可能重复发生。

佩戴者需要完成一次最终听感验收：分别播放 TrueHD、DTS、AAC、FLAC、AC-3 与 E-AC-3，确认实际可闻、音质正常，并检查多声道头动空间化。该验收保持开放。
