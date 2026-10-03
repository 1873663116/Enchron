# 蓝光影片与版本

文件页面将有效蓝光 ISO、光盘根目录与 BDMV 目录显示为可进入的光盘。光盘内的单部影片直接显示为影片卡片，相关剪辑版本分别显示；附加内容和测试盘项目按内容分组。播放使用光盘规定的片段顺序和时间范围。

## Sub-features

- 本地、SMB、WebDAV 的 ISO、光盘根目录和 BDMV 入口。
- 单部影片、相关剪辑版本、附加内容与合集分组。
- 返回、前进、面包屑、内容名称搜索和浏览原始文件。
- 连续播放、音轨、字幕、倍速与自然结束。

## How to get to it (user POV)

用户在 Files 页面导入本地 ISO 或目录，或进入已连接的 SMB／WebDAV 来源，点击光盘卡片。影片卡片可直接播放；内容分组可进入。目录光盘提供 Browse Files 入口。

## Driving it with the controller

Preconditions: 已建立冻结会话，测试盘已注册于 `Tests/Fixtures/bluray-disc-registry.json`，本地素材已暂存，或远程来源已连接。选择器导入与暂存导入分别记录；暂存导入不证明系统选择器。

```sh
C snapshot
C tap --identifier MediaLibrary-grid-bluray-disc-Sintel-Bluray.iso
C snapshot
C tap --identifier MediaLibrary-grid-bluray-content-0
C snapshot --identifier PlayerUI-window-control-plane
```

来源浏览使用 `FileBrowsing-grid-bluray-disc-<文件名>` 和 `FileBrowsing-grid-bluray-content-<内部 ID>`。分组入口为 `MediaLibrary-grid-bluray-group-<kind>` 或 `FileBrowsing-grid-bluray-group-<kind>`，kind 为 videos、sequences、stillImages、additional。内部 ID 仅用于定位，选择依据是当前可见名称与时长。模拟器播放卡片通过 Device Hub 真实点击；其它操作遵循对应 lane 的命中约束。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 单片、版本、重复路线、短片段、合集与元数据命名的可见结果符合字面预期 | BluRayDiscContentTests、BluRayBrowsingTests |
| 物理 | 根页面项目数、名称、分组及返回／前进正确，无 Playlist 数字标签 | 当前产物的 Accessibility 树与截图 |
| 物理 | 用户点击选定影片后，时长与内部选择正确、时间推进、真实视频像素出现 | 诊断串、PlaybackCore 实时记录与截图 |
| 物理 | 多片段测试盘跨越所有衔接点，整片时间线单调并自然结束 | 连续运行记录与分段截图 |
| 感知 | 音质、HDR 亮度与播放舒适度 | 人工验收 |

## 证明的终态

Sintel 正片入口显示一部 14 分 48 秒影片及附加内容。受控 Sintel Edition tests 显示 75 秒与 60 秒两个版本，10 秒片段保留在附加内容。AVS 默认显示 Videos、Sequences、Still images 三个分组；进入 Sequences 后显示两个完整序列。ISO、根目录与 BDMV 入口具有相同的语义内容。播放证明同时包含选定影片、推进的整片时间线和有效像素。

## Gotchas

- 光盘不保证提供版本名称。缺少名称时使用光盘名与时长，不虚构导演剪辑等标签。
- 双版本测试盘是获得许可的受控测试剪辑，不是官方发行版本。
- 加密盘明确返回不支持。MPEG-2 是现有播放核心的编码限制，不能计入可播放项目；模拟器不能证明 Dolby Vision 层或 AV1 解码。
- 单个 M2TS 属于普通媒体读取。Emby 使用服务器提供的播放 API，不进入文件页面的光盘识别。
- 识别成功、起播状态和截图返回成功分别不足以证明实际播放；1×1 截图是取证失败。
