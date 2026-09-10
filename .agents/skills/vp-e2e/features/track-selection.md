# 音轨与字幕切换

本特性覆盖播放中更换音轨或字幕轨的行为。切换选择应当即时生效，既不中断播放也不重开媒体会话；选择结果写向何处由 Viewing State Authority 决定：本地来源写入 Enchron 持久化，Emby 来源回报给服务器。

## Sub-features

- 音轨切换，包括多条同名音轨之间的切换。
- 音轨在打开、预热、播放、跳转或 renderer 失败时退休后，视频仍继续播放并可继续跳转。
- AC-3 与 E-AC-3（含 JOC）采用压缩直递；其余 FFmpeg 可解码的音轨则以保留原采样率和声道布局的交错 Float32 PCM 播放。
- 字幕轨的切换与关闭。
- 外挂字幕的加载，来源包括本地同目录文件、远程来源与 Emby 的 external stream。
- 轨道选择在跳转与呈现切换之后仍然保持。

## How to get to it (user POV)

用户在播放中唤出控件，顶部的 More 菜单最多展开四项：Subtitles、Audio Track、Playback Speed、Episodes（`Modules/Playback/Views/WindowPlayerDeck.swift:410-438`）。Subtitles、Audio Track、Episodes 只在对应内容存在时才出现，Playback Speed 恒定可见。本特性覆盖前两项，各自展开为可选的轨道列表。

## Driving it with the controller

Preconditions: 会话已建立；已使用时长足够的多音轨片源起播（见 Gotchas 中的 120 秒样片）。

菜单的存活时间不超过两次控制器往返，因此必须直接读取 `tap` 命令自身返回的层级，而不能再额外发送一次 snapshot：

```sh
C app-command --verb toggleControls
C tap --identifier PlayerUI-TopAction-more
C tap --identifier PlayerUI-menu-audio      # 返回的层级里就有轨道条目
C tap --label '<轨道 label>' --index <n>
```

Subtitles 菜单项有 identifier（`PlayerUI-menu-subtitles`），Audio Track 菜单项也有（`PlayerUI-menu-audio`）；但两者之下的轨道条目都没有 identifier，只能按 label 命中。遇到同名条目（例如两条 `und · aac · 2ch`）时，用 `--label` 加 `--index` 的组合来区分。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 切换后的 `PlaybackSessionReport` 携带新的轨道 ID；本地来源写入 MediaStateStore，Emby 来源立即回报服务器 | 模拟器单测（TrackSelectionPreferenceTests） |
| 结构 | 音轨失败后 `audioRetired=true` 且 `hasAudio=false`，反复跳转不抛出致命错误，且视频样本继续投递 | PlaybackCore 单测（`retiredAudioStaysNonfatalAcrossRepeatedSeeks`、`audioRendererFailureRetiresAudioAndVideoContinues`） |
| 结构 | DTS、TrueHD、Vorbis 均产出交错 Float32 PCM，保留采样率、标准 CoreAudio 声道布局标签和单调时间戳；TrueHD 的细碎子帧聚合之后才进入 CoreMedia；AC-3/E-AC-3 仍为压缩直递 | PlaybackCore 单测（`ffmpegDecodedAudioProducesInterleavedFloatPCMWithDeclaredLayout`、`trueHDSubframesAreAggregatedBeforeTheyReachCoreMedia`、`generatedAudioCodecMatrixProducesEveryRegisteredAudioFormat`、`dolbyDigitalPlusAtmosKeepsItsSixChannelCompressedLayout`） |
| 结构 | FFmpeg 没有对应解码器的声明编码会以编码名被拒绝，并由会话记录为音轨退休 | PlaybackCore 单测（`ffmpegUndecodableAudioNamesTheCodecInsteadOfGuessing`、`retiredAudioStaysNonfatalAcrossRepeatedSeeks`） |
| 结构 | 字幕 cue 的文本与时刻正确 | PlaybackCore 单测（SubtitleProviderTests） |
| 物理 | 诊断串中 `audioTrack` 或 `subtitleTrack` 发生变更，同时 `lifecycle=Playing`、`session` 保持不变、`audioRendererStatus=rendering` | 真机 |
| 物理 | 不支持或运行中失败的音轨显示感叹号；诊断串为 `audioRetired=true`，`lifecycle` 不进入 Failed，跳转后视频继续推进 | 待做：不支持音频真机样片 |
| 物理 | Emby《Furiosa》的 TrueHD 8 声道音轨输出 4,800 帧、100 ms 的交错 PCM 缓冲；`audioRendererStatus=rendering`、`muted=false`、`volume=1`、`error=none`，并达到 `hasSufficientMediaDataForReliablePlaybackStart=true` | 真机证据 `audio-silence-fix-20260817/final-auto-recovery/furiosa-truehd/` |
| 物理 | TrueHD seek 后音视频先建立约 6 秒的领先量；交付落后达到 0.5 秒时，时间线以 `deliveryLagRecovery` 自动暂停，重新预滚后恢复，视频领先量回到 5.416 秒，音频领先量回到 5.453 秒 | 真机证据 `audio-silence-fix-20260817/final-auto-recovery/furiosa-truehd/post-seek-4-after-recovery/snapshot.json` |
| 物理 | 同一片源切至 AC-3 后保持同一媒体会话，轨道切为 `audio.2`，压缩缓冲时长 32 ms，renderer 继续处于 rendering | 真机证据 `audio-silence-fix-20260817/final-100ms/furiosa-ac3-control/` |
| 感知 | TrueHD、DTS、AAC、FLAC、AC-3 与 E-AC-3 的实际可闻性、音质及多声道头动空间化 | 待佩戴者验收 |

## 证明的终态

终态是诊断串里的 `audioTrack` 由 1 变为 2（或字幕轨发生相应变化），且在同一次读取中 `session` 与切换前一致、`lifecycle=Playing`、`actualRate=1.0`。如果会话 ID 发生了变化，说明媒体会话被重开，即判定为失败。跳转之后再读取一次诊断串，轨道选择仍应保持。

音轨退休场景的终态是 `audioRetired=true`、`lifecycle` 保持在 Playing 或 Paused、视频时间继续推进；再次跳转后仍保持同一会话，且视频到达目标位置。

## Gotchas

- 时长过短的片源可能在多级菜单操作尚未完成时就自然播放结束（诊断串进入 `lifecycle=Ended`），导致取证失效，因此取证应选用时长充足的样片。`TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-120s.mp4` 是一条 120 秒的双音轨样片，适合这条测试。
- 轨道的 label 由容器元数据决定，未标注语言的轨道显示为 `und`；多条轨道同名时只能靠 index 区分。
