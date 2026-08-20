# Emby 媒体库

Emby 是媒体服务器来源：它提供媒体实体、元数据与服务器端观看状态，界面与 Files 页的目录浏览完全分开。播放走 direct play，字节仍经回环端点。观看进度的权威是服务器，不落本地盘。

## Sub-features

- 首页海报墙与"接下来看"横条。
- 系列详情、季选择、剧集列表。
- 单集详情的 Resume 与 Play from Beginning。
- 播放进度回报服务器（`ViewingStateAuthority.mediaServer`）。
- 封面走服务器图片接口，按 image tag 作键落盘。

## How to get to it (user POV)

底部导航的 Emby 页签进入首页。点海报进系列详情，点"接下来看"的剧照卡直接进单集详情。单集详情上有 Resume 与 Play from Beginning 两个按钮。

## Driving it with the controller

**Emby 界面一律不发合成滑动**，见下方 Gotchas。可达路径只有点击：

```sh
C tap --identifier Emby-Navigation-Tab
C tap --identifier Emby-StillCard-<id>          # 首页"接下来看"，直达单集详情
C tap --identifier Emby-Detail-PlayFromBeginning
```

系列详情页（`Emby-PosterCard-<id>` 进入）的剧集卡 `Emby-Episode-<id>` 位于窗口折叠线以下，合成输入够不到，因此不要走这条路。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | direct play 地址携带 api_key 且只活在字节源对象内部，播放层拿到的是回环句柄 | 模拟器单测（EmbyPlaybackBridgeTests） |
| 结构 | 目录内容与观看进度不落本地盘；图片按 image tag 作键 | `verify_media_byte_stream.py` |
| 物理 | 详情页从服务器实时取到剧集表；播放后诊断串 `lifecycle=Playing` 且截图非纯色 | 真机 |
| 物理 | 打开耗时（点击到出画） | 真机，当前实测约 45 秒，阶段三预读的目标 |
| 感知 | 不适用 | |

## 证明的终态

详情页出现 `Emby-Episode-<id>` 或 `Emby-Detail-Resume`，说明服务器实时应答成功（海报可能来自本地 Artwork 缓存，不能作为连通性证据）。播放终态同 [clean-state-playback.md](clean-state-playback.md)。

打开缓慢时用 PlaybackCore 的 live debug 通道区分"卡住"与"正在拉流"：`tmp/playbackcore-live-debug/current.json` 指向的 `events.jsonl` 只有 `source.acquired` 与 `open.admitted` 两条说明堵在 reader open；而服务器日志显示按 1 MiB 顺序拉流且节奏接近片源码率，说明已在播放，只是诊断串还没翻面。2026-08-16 一次误判即出自只读一次状态快照。

## Gotchas

- Emby 滚动视图接受带 `--identifier` 的合成滑动（`Emby-library-list`、`Emby-Home`、`Emby-Detail-<id>` 均已实证）。此前记为「Emby 滑动杀 runner」是误归因：杀会话的是省略 identifier 的滑动，与 Emby 无关，Emby 只是恰好在屏。规则见 references/enchron.md。
- 海报横条只有可视区内的卡可点，靠右的卡 tap 返回 False。
- 系列详情页顶部 label 为 `Play button on a TV, filled` 的图标按钮没有 identifier，点按无可观察效果，疑似产品缺陷待根因。
- Emby 服务器地址会漂移。`Tests/EmbyServerCredentials.local.json` 与 `.env` 里的值使用前先探活。
