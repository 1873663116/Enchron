# Emby 媒体库

Emby 是一种媒体服务器来源。它提供媒体实体、元数据与服务器端的观看状态，其界面与 Files 页的目录浏览完全分开。播放走 direct play，但字节仍然经由回环端点进入播放核心。观看进度以服务器为权威，不落本地盘。

## Sub-features

- 首页的海报墙与"接下来看"横条。
- 系列详情页，含季选择与剧集列表。
- 单集详情页上的 Resume 与 Play from Beginning。
- 播放进度回报给服务器（对应 `ViewingStateAuthority.mediaServer`）。
- 封面经由服务器图片接口获取，按 image tag 作键落盘。

## How to get to it (user POV)

用户从底部导航的 Emby 页签进入首页。点海报进入系列详情；点"接下来看"横条上的剧照卡则直接进入单集详情。单集详情页上有 Resume 与 Play from Beginning 两个按钮。

## Driving it with the controller

Preconditions: 会话已建立；Emby 服务器地址在使用前要先探活，因为 `Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json` 与 `.env` 里记录的地址会漂移。

只要带上 `--identifier`，合成滑动在 Emby 界面上就可用；会杀掉会话的是省略 identifier 的滑动，详见 Gotchas。两条播放入口：

```sh
C tap --identifier Emby-Navigation-Tab
C tap --identifier Emby-StillCard-<id>          # 首页"接下来看"，直达单集详情
C tap --identifier Emby-Detail-PlayFromBeginning
```

另一条入口是系列详情页（通过 `Emby-PosterCard-<id>` 进入）里的剧集卡 `Emby-Episode-<id>`，点击后直接进入播放。对折叠线以下的剧集条，需要先对 `Emby-Detail-<id>` 发送带 identifier 的滑动，把它滚到可视区内再点击。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | direct play 地址携带 api_key，且该地址只存在于字节源对象内部；播放层拿到的是回环句柄 | 模拟器单测（EmbyPlaybackBridgeTests） |
| 结构 | 目录内容与观看进度都不落本地盘；图片按 image tag 作键 | `verify_media_byte_stream.py` |
| 结构 | `Emby-Evidence` 的 `artworkLoads[].alternateTagCacheKey` 与同一条的 `cacheKey` 不等，即证明 image tag 参与落盘键 | 真机／模拟器读 `Emby-Evidence` |
| 物理 | 详情页从服务器实时取到剧集表；播放后诊断串显示 `lifecycle=Playing` 且截图非纯色 | 真机 |
| 物理 | 打开耗时（从点击到出画） | 真机，当前实测约 45 秒，阶段三预读的目标 |
| 感知 | 不适用 | |

## 证明的终态

详情页出现 `Emby-Episode-<id>` 或 `Emby-Detail-Resume`，即说明服务器实时应答成功。注意海报可能来自本地 Artwork 缓存，因此海报出现不能作为连通性证据。播放的终态与 [clean-state-playback.md](clean-state-playback.md) 相同。

当打开缓慢时，用 PlaybackCore 的 live debug 通道区分"卡住"与"正在拉流"这两种状态。如果 `tmp/playbackcore-live-debug/current.json` 指向的 `events.jsonl` 里只有 `source.acquired` 与 `open.admitted` 两条事件，说明流程堵在 reader open 阶段。反之，如果服务器日志显示客户端正按 1 MiB 顺序拉流、且节奏接近片源码率，则说明实际已在播放，只是诊断串还没有翻面。2026-08-16 的一次误判正是因为只读了一次状态快照。

## 观看状态的媒体身份

本地 viewing state 的每条记录只发布 `mediaIdentity` 的 sha256，不发布原文。Emby 条目的原文是 `emby`、serverID、itemID、mediaSourceID 四段以 U+001F 相连，取 UTF-8 的 SHA-256 小写十六进制；构造在 `Modules/MediaSource/VersionedMediaIdentity.swift` 的 `MediaIdentity.emby(serverID:itemID:mediaSourceID:)`。四段值可以从 `Emby-Evidence` 的 `playbackSessions[]` 读到，但把它们摘成那个 sha256 需要真的算一次哈希，读证据的一方做不到。所以"这条 Emby 条目在本地有没有观看记录"要用两次 `diagnostics.surface-probe@1 --includeViewingStorage` 判定：播放前取一次快照，退出后再取一次并通过 `relatedResults` 把前一次内联成 `priorSnapshots[0]`，比较两次的 `viewingState.entries` 与 `viewingRecordCount`。Emby 播放走 `viewingStateAuthority == .mediaServer`（`Modules/Emby/EmbyPlaybackBridge.swift`），`PlaybackLaunchCoordinator.persistCurrentSession` 在这条分支上不写 viewing state，两次快照因此必须逐条相等。

## Gotchas

- Emby 的滚动视图接受带 `--identifier` 的合成滑动，`Emby-library-list`、`Emby-Home`、`Emby-Detail-<id>` 都已实证可用。此前记录的「Emby 滑动杀 runner」是误归因。真正杀会话的是省略 identifier 的滑动，与 Emby 无关，Emby 只是当时恰好在屏。规则见 [产品事实](../references/product.md)。
- 海报横条上只有可视区内的卡片可以点中，靠右的卡片 tap 会返回 False。
- Emby 的卡片都是 `GridCard`，它发布的 accessibility 标签是 `<title>, <variantKey>`，variantKey 取 `poster`／`episode`／`video`／`folder`；runner 的 `--label` 是精确相等匹配，所以按裸标题点卡片一定找不到元素。首页"接下来看"横条与系列详情的剧集卡是 `episode`，媒体库网格与"最近添加"的海报是 `poster`。左侧媒体库栏 `SidebarRow` 才是裸标题。
- 系列详情页按设计没有播放按钮；播放入口是选集面板里的 `Emby-Episode-<id>` 卡片，点击直接进入播放。此前记录的「顶部无 identifier 的播放图标点按无效」也是误归因。那个图标其实是导航栏的 Emby 页签 `Emby-Navigation-Tab`，并不在详情页内；已经处于该页签时再点它没有反应，这属于正确行为。
- Emby 服务器地址会漂移。使用 `Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json` 与 `.env` 里的值之前，必须先探活。
