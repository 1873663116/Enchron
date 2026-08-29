# 远程来源的连接与浏览

本特性覆盖用户添加一台服务器、浏览它的目录、并从中打开一个视频的完整流程。远程来源有三种：SMB、WebDAV、Emby。SMB 与 WebDAV 的入口在 Files 页的来源侧栏；Emby 有自己独立的导航页签。无论哪种来源，远程字节都一律经由 MediaSource 的回环端点进入播放核心，依据见 [ADR 0020](../../../../docs/archive/adr/0020-media-byte-stream-is-the-single-byte-entry.md)。

## Sub-features

- 添加来源。路径是 More → Add → 选择类型 → 填写地址与凭据 → Connect。
- 浏览。共享或目录逐层展开，其中的视频以网格卡片呈现。
- 打开播放。点击远程卡片进入播放器，字节经回环端点传输。
- 凭据失败、找不到服务器、地址格式错误这几类失败各自给出可区分的下一步提示。
- 当证书无法验证时，App 在连接阶段弹出询问，展示地址、证书名、指纹与有效期；在播放阶段永远不会弹出询问。

## How to get to it (user POV)

用户点击 Files 页左侧来源侧栏顶部的 More 按钮打开菜单，再点 Add 展开来源类型列表。连接成功后，该来源出现在侧栏中，点击它即进入其根目录。Emby 不在这个侧栏里，它由底部导航的 Emby 页签进入。

## Driving it with the controller

Preconditions: 会话已建立；目标 SMB/WebDAV 服务器已用带凭据的方式探活确认正常（匿名探测的结果不作数，原因见 Gotchas）。

SMB 与 WebDAV 的连接表单可以全程用合成输入驱动，因为所有字段都带标识：

```sh
C() { python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
      --output-directory <dir> "$@"; }
C tap --identifier FileBrowsing-SourcesSidebar-sourceMore
C tap --identifier FileBrowsing-SourcesSidebar-add
C tap --label SMB
C typeText --identifier FileBrowsing-SourceConnection-smb-address  --text <host>
C typeText --identifier FileBrowsing-SourceConnection-smb-username --text <user>
C typeText --identifier FileBrowsing-SourceConnection-smb-password --text <secret>
C tap --identifier FileBrowsing-SourceConnection-smb-connect
```

WebDAV 表单使用同一套字段后缀，前缀换成 `FileBrowsing-SourceConnection-webDAV-`。SMB 表单另有访客开关 `FileBrowsing-SourceConnection-smb-guest`。两种表单都包含 `name`、`address`、`username`、`password`、`connect` 与 `cancel` 这些字段。

在证书信任询问出现之前，连接表单应当已经先从层级中消失。询问上的按钮是 `FileBrowsing-CertificateTrust-trust` 与 `FileBrowsing-CertificateTrust-cancel`。点信任后连接继续进行；点取消后连接终止。之后再次打开同类型的连接表单时，名称、地址、用户名和 SMB 访客开关的值都会保留，只有密码为空。

`typeText` 必须带 `--identifier` 参数，runner 会先点中该字段再输入。首次用凭据连接成功后，系统会弹出"保存密码?"对话框，用 `tap --label '以后'` 可以合成方式把它关掉。

浏览目录时，用 `tap --label '<名字>, folder'` 逐层进入。远程网格卡片的标识前缀是 `FileBrowsing-grid-video-<文件名>`，本地库卡片的前缀是 `MediaLibrary-grid-video-<文件名>`，两者属于不同的标识族。

Emby 一侧的驱动方法见 [emby-library.md](emby-library.md)。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 适配器把浏览阶段报告的文件大小只用于显示与排序，实际取字节时以服务端当场的回答为准；对一台 SMB 服务器只维持一条连接，播放时不新建第二条 | 模拟器单测（SMBDataSourceAdapterTests 等） |
| 结构 | 播放入口只接受 `PlaybackAddress`，传入裸网络地址会直接编译不过 | 类型系统 + `verify_media_byte_stream.py` |
| 结构 | 证书询问会等待已有 sheet 完成收起后才出现；表单退出时只清除密码；明文连接只在 ATS 明确拦截或同一端点 TLS 握手成功时才提示添加 `https://` | `CertificateTrustPromptTests`、`SourceConnectionDraftTests`、`RemoteConnectionFailureDiagnoserTests`、`WebDAVDataSourceAdapterTests`、`EmbyClientTests` |
| 物理 | 侧栏出现该来源、目录能列出内容、卡片打开后诊断串显示 `lifecycle=Playing` 且截图非纯色 | 真机，用本文的控制器序列驱动 |
| 物理 | 证书询问出现前连接表单已消失；信任与取消按钮都能按 identifier 命中；取消后重开表单时只缺密码 | 真机，用本文的控制器序列驱动 |
| 感知 | 不适用 | |

## 证明的终态

连接成功的终态是面包屑显示 `<类型> · <地址>`，且侧栏新增该来源条目。浏览成功的终态是 `FileBrowsing-FilesScreen-itemCount` 与实际卡片数一致。打开播放的终态与 [clean-state-playback.md](clean-state-playback.md) 相同，即诊断串 lifecycle 达到稳态，且全分辨率截图非纯色。

## Gotchas

- 侧栏来源条目上的删除按钮、图标与文本共享同一个 identifier，因此 `tap --identifier` 会命中删除按钮。要选中来源本身，应按 label 或 `--index` 定位。
- 从播放器退出后，浏览位置回到 Media Library 根，而不是进入播放前所在的目录；要重进远程目录，必须从侧栏重新逐层进入。
- `smbutil view -N`（匿名方式）在这台服务器上返回 Authentication error，但这不代表 SMB 不可用，带凭据枚举是正常的。判断服务端可用性时不要用匿名探测。
- TLS 探测只能证明同一 `host:port` 上能建立握手。DNS、TCP、代理、HTTP 状态码、认证失败、TLS 握手失败和超时这些情形仍各自保留原始错误。
