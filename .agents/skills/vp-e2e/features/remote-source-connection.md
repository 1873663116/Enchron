# 远程来源的连接与浏览

用户添加一台服务器，浏览它的目录，并从中打开一个视频。三种远程来源：SMB、WebDAV、Emby。前两种在 Files 页的来源侧栏，Emby 有自己的导航页签。远程字节一律经 MediaSource 的回环端点进入播放核心，见 [ADR 0020](../../../../docs/adr/0020-media-byte-stream-is-the-single-byte-entry.md)。

## Sub-features

- 添加来源：More → Add → 类型 → 填写地址与凭据 → Connect。
- 浏览：共享或目录逐层展开，视频以网格卡片呈现。
- 打开播放：远程卡片进入播放器，字节经回环端点。
- 凭据失败、找不到服务器、地址格式错误各自给出可区分的下一步。
- 证书无法验证时在连接阶段询问，展示地址、证书名、指纹、有效期；播放阶段永不询问。
- 该地址此前批准过另一张证书时，询问改述为证书更换并列出上次批准的指纹。
- 地址会把凭据以明文送上公网时，连接前询问一次；批准按主机记住，此后不再问。

## How to get to it (user POV)

Files 页左侧来源侧栏顶部的 More 按钮打开菜单，Add 展开来源类型列表。连接成功后该来源出现在侧栏，点击即进入其根目录。Emby 不在此列，它由底部导航的 Emby 页签进入。

## 地址形态的验证边界

明文 HTTP 的放行按地址段判定，因此每一类地址段要各验一次，而模拟器与真机能验的类别不同。

- **模拟器与宿主 Mac 共用网络栈**，宿主的 Tailscale 隧道对它直接可用，`100.64.0.0/10` 这类 CGNAT 地址在模拟器上连得通。CGNAT 段的连通性验证只在模拟器上做。
- **真机不验 CGNAT 段**。Vision Pro 要连 Tailscale 地址得先装 Tailscale 客户端，佩戴者不会这么做。真机验证的地址形态限于局域网 IP 与 `.local` 名字。
- **明文警告与地址分类是纯本地判定**，不发包，与地址可达与否无关。公网 IP 与域名这两类只验警告是否出现，不要求连得上，模拟器与真机都能验。
- **一台 Emby 同时是多个地址**。服务器监听 `*:8096` 时，发往该机任一地址的连接都由它接收，因此回环、局域网 IP、CGNAT 地址与 `.local` 名字指向同一个实例，不改服务器就能覆盖四类地址段。
- **自签名 HTTPS 用临时 TLS 前置代理造**，它解密后转发给真实 Emby，服务器配置不变。换一张证书重启即得到指纹变更场景。

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

证书信任询问出现前，连接表单应先从层级中消失。询问按钮为
`FileBrowsing-CertificateTrust-trust` 与 `FileBrowsing-CertificateTrust-cancel`。
点信任后连接继续；点取消后连接终止。明文暴露询问走同一个队列与同一个弹窗，
按钮为 `FileBrowsing-CleartextExposure-proceed` 与 `FileBrowsing-CleartextExposure-cancel`；
两种询问因此不会同时出现。再次打开同类型表单时，名称、地址、用户名和
SMB 访客开关保留，密码为空。

`typeText` 必须带 `--identifier`，runner 自己先点再输。首次凭据连接后系统弹"保存密码?"，`tap --label '以后'` 可合成关掉。

浏览用 `tap --label '<名字>, folder'` 逐层进入；远程网格卡片的标识前缀是 `FileBrowsing-grid-video-<文件名>`，本地库是 `MediaLibrary-grid-video-<文件名>`，两者不同族。

Emby 侧见 [emby-library.md](emby-library.md)。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 适配器把浏览所报大小只用于显示与排序，取字节时以服务端当场回答为准；SMB 一台服务器一条连接，播放不新建第二条 | 模拟器单测（SMBDataSourceAdapterTests 等） |
| 结构 | 播放入口只接受 `PlaybackAddress`，裸网络地址编译不过 | 类型系统 + `verify_media_byte_stream.py` |
| 结构 | 证书询问等待已有 sheet 完成收起；表单退出只清除密码；明文连接仅在 ATS 明确拦截或同一端点 TLS 握手成功时提示添加 `https://` | `CertificateTrustPromptTests`、`SourceConnectionDraftTests`、`RemoteConnectionFailureDiagnoserTests`、`WebDAVDataSourceAdapterTests`、`EmbyClientTests` |
| 物理 | 侧栏出现该来源、目录列出内容、卡片打开后诊断串 `lifecycle=Playing` 且截图非纯色 | 真机，本文的控制器序列 |
| 物理 | 证书询问前连接表单已消失，信任与取消按钮可按 identifier 命中；取消后重开表单只缺密码 | 真机，本文的控制器序列 |
| 感知 | 不适用 | |

## 证明的终态

连接成功的终态是面包屑显示 `<类型> · <地址>`，侧栏新增该来源条目。浏览的终态是 `FileBrowsing-FilesScreen-itemCount` 与实际卡片数一致。打开播放的终态与 [clean-state-playback.md](clean-state-playback.md) 相同：诊断串 lifecycle 稳态加非纯色全分辨率截图。

## Gotchas

- 侧栏源条目的删除按钮、图标与文本共享同一 identifier，`tap --identifier` 命中删除按钮；选中来源要按 label 或 `--index`。
- 从播放器退出后浏览位置回到 Media Library 根，不回到进入播放前的目录，重进远程目录要从侧栏重走。
- `smbutil view -N`（匿名）在这台服务器上返回 Authentication error，不代表 SMB 不可用；带凭据枚举正常。判断服务端可用性不要用匿名探测。
- TLS 探测只证明同一 `host:port` 能建立握手。DNS、TCP、代理、HTTP 状态码、认证失败、TLS 握手失败和超时仍保留原始错误。
