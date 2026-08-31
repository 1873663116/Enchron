# 缓存与 Artwork

这里涉及两类持久化产物：Container Index Cache 保存远程媒体的容器索引；Artwork 为每个媒体保存一张画面。这两类产物都没有自动的容量上限，由用户在设置页查看用量并手动清除。

## Sub-features

- Container Index Cache：当远程来源第二次打开同一个文件时，容器索引不再走网络读取。
- 只有远程来源会写入索引缓存，本地播放不会写入。
- Artwork 在用户退出播放时从当前显示的画面捕获，新画面覆盖旧画面，整个过程不产生额外的读取。
- Emby 的封面走服务器的图片接口获取，以 image tag 作为键，不经过回环端点。
- 设置页中有两行条目，分别显示各自的用量并提供清除操作。

## How to get to it (user POV)

用户不会主动触发缓存与 Artwork 这两件事。在设置页的 Storage 与 Privacy 分组里，有 Container Index Cache 与 Playback Progress 两行，各自显示用量并提供清除动作。Artwork 对用户的表现形式是媒体卡片上显示的画面。

## Driving it with the controller

Preconditions: 会话已经建立；使用的远程来源必须能读到服务器日志（Emby 或 WebDAV）。

设置页分组的标识是 `Settings-StoragePrivacy-group`；行内的标识以 `Apps/Enchron/Screens/SettingsScreen.swift` 中定义的 item id 为准，即 `clear-container-index-cache` 与 `clear-progress`。

索引缓存的证明不依赖界面，而是依赖对比两次打开时的网络读取：先清除缓存，打开一次远程文件，退出，再打开一次，然后比较这两次打开期间服务器侧收到的请求。Emby 与 WebDAV 的服务器日志都能直接读到 Range 请求序列。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 索引以 Content Revision 作为键；打开失败时索引被丢弃，不写入磁盘 | 模拟器单测（SMBDataSourceAdapterTests 覆盖索引缓存） |
| 结构 | 内存中的 Artwork 必须是硬盘上已经存在的；写盘失败时不更新内存 | 模拟器单测 |
| 结构 | 本地来源没有回环句柄，因此不会写入索引缓存 | `verify_media_byte_stream.py` |
| 物理 | 同一个远程文件第二次打开时，服务器侧不再出现索引区间的请求 | `verify_container_index_reuse.py`，按该脚本头部说明的协议在真机上打开两次后判读 Emby 日志 |
| 物理 | 退出播放后，该媒体的卡片显示刚才退出前的画面 | **待建** |
| 感知 | 不适用 | |

## 证明的终态

对于索引缓存，终态是第二次打开时服务器日志中缺少针对头部与尾部索引区间的请求，只剩下播放位置附近的顺序读取。对于 Artwork，终态是退出播放后卡片上的画面与退出瞬间的显示帧一致。

这两条物理判据当前都没有自动化入口，是这份地图里最明确的缺口。

## Gotchas

- Container Index Cache 的边界由 `PlaybackRuntime.open` 期间的读取界定；容器解析为了建立轨道而读取的头部字节也会随索引一起保存，因此缓存比"纯索引"略大。
- 缓存没有自动上限是产品语义，不是缺陷，因此不要按容量策略去测试它。
