# 远程来源的连接与浏览

用户添加一台服务器，浏览它的目录，并从中打开一个视频。三种远程来源：SMB、WebDAV、Emby。前两种在 Files 页的来源侧栏，Emby 有自己的导航页签。远程字节一律经 MediaSource 的回环端点进入播放核心，见 [ADR 0020](../../../../docs/adr/0020-media-byte-stream-is-the-single-byte-entry.md)。

## Sub-features

- 添加来源：More → Add → 类型 → 填写地址与凭据 → Connect。
- 浏览：共享或目录逐层展开，视频以网格卡片呈现。
- 打开播放：远程卡片进入播放器，字节经回环端点。
- 凭据失败、找不到服务器、地址格式错误各自给出可区分的下一步。
- 证书无法验证时在连接阶段询问，展示地址、证书名、指纹、有效期；播放阶段永不询问。

## How to get to it (user POV)

Files 页左侧来源侧栏顶部的 More 按钮打开菜单，Add 展开来源类型列表。连接成功后该来源出现在侧栏，点击即进入其根目录。Emby 不在此列，它由底部导航的 Emby 页签进入。

## Driving it with the controller

SMB 与 WebDAV 表单可全程合成驱动，字段标识齐全：

```sh
C() { python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
      --output-directory <dir> "$@"; }
C tap --identifier FileBrowsing-SourcesSidebar-sourceMore
C tap --identifier plus
C tap --label SMB
C typeText --identifier FileBrowsing-SourceConnection-smb-address  --text <host>
C typeText --identifier FileBrowsing-SourceConnection-smb-username --text <user>
C typeText --identifier FileBrowsing-SourceConnection-smb-password --text <secret>
C tap --identifier FileBrowsing-SourceConnection-smb-connect
```

WebDAV 使用同一后缀集合与 `FileBrowsing-SourceConnection-webDAV-` 前缀。SMB 另有
`FileBrowsing-SourceConnection-smb-guest`；两种表单均有 `name`、`address`、
`username`、`password`、`connect` 与 `cancel`。

`typeText` 必须带 `--identifier`，runner 自己先点再输。首次凭据连接后系统弹"保存密码?"，`tap --label '以后'` 可合成关掉。

浏览用 `tap --label '<名字>, folder'` 逐层进入；远程网格卡片的标识前缀是 `FileBrowsing-grid-video-<文件名>`，本地库是 `MediaLibrary-grid-video-<文件名>`，两者不同族。

Emby 侧见 [emby-library.md](emby-library.md)。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 适配器把浏览所报大小只用于显示与排序，取字节时以服务端当场回答为准；SMB 一台服务器一条连接，播放不新建第二条 | 模拟器单测（SMBDataSourceAdapterTests 等） |
| 结构 | 播放入口只接受 `PlaybackAddress`，裸网络地址编译不过 | 类型系统 + `verify_media_byte_stream.py` |
| 物理 | 侧栏出现该来源、目录列出内容、卡片打开后诊断串 `lifecycle=Playing` 且截图非纯色 | 真机，本文的控制器序列 |
| 感知 | 不适用 | |

## 证明的终态

连接成功的终态是面包屑显示 `<类型> · <地址>`，侧栏新增该来源条目。浏览的终态是 `FileBrowsing-FilesScreen-itemCount` 与实际卡片数一致。打开播放的终态与 [clean-state-playback.md](clean-state-playback.md) 相同：诊断串 lifecycle 稳态加非纯色全分辨率截图。

## Gotchas

- 侧栏源条目的删除按钮、图标与文本共享同一 identifier，`tap --identifier` 命中删除按钮；选中来源要按 label 或 `--index`。
- 从播放器退出后浏览位置回到 Media Library 根，不回到进入播放前的目录，重进远程目录要从侧栏重走。
- `smbutil view -N`（匿名）在这台服务器上返回 Authentication error，不代表 SMB 不可用；带凭据枚举正常。判断服务端可用性不要用匿名探测。
- 证书信任提示 `CertificateTrustPrompt` 目前没有 accessibility identifier，合成驱动无法命中，见 [能力边界](../references/enchron.md)。
