# 缓存与 Artwork

两类持久化产物：Container Index Cache 保存远程媒体的容器索引，Artwork 保存每个媒体的一张画面。两者都无自动上限，由用户在设置页查看用量并手动清除。

## Sub-features

- Container Index Cache：远程来源第二次打开同一文件时，索引不再走网络。
- 仅远程来源写索引缓存，本地播放不写。
- Artwork 在退出播放时从当前显示画面捕获，覆盖旧的，额外读取为零。
- Emby 封面走服务器图片接口，按 image tag 作键，不经回环端点。
- 设置页两行分别显示用量并提供清除。

## How to get to it (user POV)

用户不主动触发这两件事。设置页的 Storage 与 Privacy 分组里有 Container Index Cache 与 Playback Progress 两行，各显示用量与清除动作。Artwork 表现为媒体卡片上的画面。

## Driving it with the controller

设置页分组标识是 `Settings-StoragePrivacy-group`，行内标识以 `Apps/Enchron/Screens/SettingsScreen.swift` 的 item id 为准（`clear-container-index-cache`、`clear-progress`）。

索引缓存的证明不靠界面，靠对比两次打开的网络读取：清缓存后打开一次远程文件，退出，再打开一次，比较服务器侧收到的请求。Emby 与 WebDAV 服务器日志都能直接读到 Range 序列。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 索引按 Content Revision 作键，打开失败时丢弃不落盘 | 模拟器单测（SMBDataSourceAdapterTests 覆盖索引缓存） |
| 结构 | 内存中的 Artwork 必为硬盘中已有；写盘失败不更新内存 | 模拟器单测 |
| 结构 | 本地来源无回环句柄因此不写索引缓存 | `verify_media_byte_stream.py` |
| 物理 | 同一远程文件第二次打开，服务器侧不再出现索引区间的请求 | **待建**，需要服务器日志比对的取证脚本 |
| 物理 | 退出播放后该媒体卡片显示刚才的画面 | **待建** |
| 感知 | 不适用 | |

## 证明的终态

索引缓存：第二次打开时服务器日志缺少头部与尾部索引区间的请求，只剩播放位置附近的顺序读。Artwork：退出后卡片画面与退出瞬间的显示帧一致。

两条物理判据当前都没有自动化入口，是这份地图里最明确的缺口。

## Gotchas

- Container Index Cache 的边界是 `PlaybackRuntime.open` 期间的读取，容器解析为建立轨道而读的头部字节也会随索引保存，因此它比"纯索引"略大。
- 缓存无自动上限是产品语义不是缺陷，不要按容量策略去测它。
