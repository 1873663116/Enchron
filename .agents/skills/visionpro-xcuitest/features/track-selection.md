# 音轨与字幕切换

播放中更换音轨或字幕轨。选择要即时生效、不中断播放、不重开会话，并按 Viewing State Authority 决定写向何处：本地来源写 Enchron 持久化，Emby 来源回报服务器。

## Sub-features

- 音轨切换（含同名多轨）。
- 音轨在打开、预热、播放、跳转或 renderer 失败时退休，视频继续播放与跳转。
- AC-3 与 E-AC-3（含 JOC）压缩直递；其余 FFmpeg 可解音轨以保留采样率和声道布局的交错 Float32 PCM 播放。
- 字幕轨切换与关闭。
- 外挂字幕（本地同目录、远程来源、Emby 的 external stream）。
- 选择在跳转与呈现切换后保持。

## How to get to it (user POV)

播放中唤出控件，顶部 More 菜单里有 Subtitles 与 Audio Track 两项，各自展开为轨道列表。

## Driving it with the controller

菜单活不过两次控制器往返，必须读 `tap` 自身返回的层级，不能再发一次 snapshot：

```sh
C app-command --verb toggleControls
C tap --identifier PlayerUI-TopAction-more
C tap --label 'Audio Track'      # 返回的层级里就有轨道条目
C tap --label '<轨道 label>' --index <n>
```

Subtitles 有 identifier（`PlayerUI-menu-subtitles`）；Audio Track 与全部轨道条目没有，只能按 label 命中。同名条目（例如两条 `und · aac · 2ch`）用 `--label` 加 `--index` 组合。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 切换后 `PlaybackSessionReport` 携带新轨道 ID；本地来源写入 MediaStateStore，Emby 来源立即回报服务器 | 模拟器单测（TrackSelectionPreferenceTests） |
| 结构 | 音轨失败后 `audioRetired=true`、`hasAudio=false`，反复跳转不抛致命错误且视频样本继续投递 | PlaybackCore 单测（`retiredAudioStaysNonfatalAcrossRepeatedSeeks`、`audioRendererFailureRetiresAudioAndVideoContinues`） |
| 结构 | DTS、TrueHD、Vorbis 产出交错 Float32 PCM，保留采样率、标准 CoreAudio 声道布局标签和单调时间戳；AC-3/E-AC-3 仍为压缩直递 | PlaybackCore 单测（`ffmpegDecodedAudioProducesInterleavedFloatPCMWithDeclaredLayout`、`generatedAudioCodecMatrixProducesEveryRegisteredAudioFormat`、`dolbyDigitalPlusAtmosKeepsItsSixChannelCompressedLayout`） |
| 结构 | FFmpeg 无解码器的声明编码以编码名拒绝，并由会话记录为音轨退休 | PlaybackCore 单测（`ffmpegUndecodableAudioNamesTheCodecInsteadOfGuessing`、`retiredAudioStaysNonfatalAcrossRepeatedSeeks`） |
| 结构 | 字幕 cue 的文本与时刻正确 | PlaybackCore 单测（SubtitleProviderTests） |
| 物理 | 诊断串 `audioTrack` 或 `subtitleTrack` 变更，同时 `lifecycle=Playing`、`session` 不变、`audioRendererStatus=rendering` | 真机 |
| 物理 | 不支持或运行中失败的音轨显示感叹号；诊断串为 `audioRetired=true`，`lifecycle` 不进入 Failed，跳转后视频继续推进 | 待做：不支持音频真机样片 |
| 物理 | DTS、TrueHD、Vorbis 等解码音轨保持 `audioRendererStatus=rendering`；多声道样片的头动空间化使用声明声道布局 | 待做：对应编码与多声道真机样片 |
| 感知 | 不适用（听得到哪条轨是事实不是感受，由 audioRendererStatus 与轨道 ID 共同证明） | |

## 证明的终态

诊断串里 `audioTrack` 由 1 变为 2（或字幕轨相应变化），且同一次读取中 `session` 与切换前一致、`lifecycle=Playing`、`actualRate=1.0`。会话 ID 变了说明重开了媒体会话，即失败。跳转之后再读一次，选择仍应保持。

音轨退休场景的终态是 `audioRetired=true`、`lifecycle` 保持 Playing 或 Paused、视频时间继续推进。再次跳转后仍保持相同会话，视频到达目标位置。

## Gotchas

- 短片源会在你摆弄菜单期间自然播完（`lifecycle=Ended`），取证用时长足够的样片。`TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-120s.mp4` 是双音轨 120 秒，适合这条。
- 轨道 label 由容器元数据决定，未标语言的轨显示为 `und`，多轨同名要靠 index 区分。
