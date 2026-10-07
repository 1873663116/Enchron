# 媒体服务器

Emby、Plex、Jellyfin 分别有独立 Tab、登录状态和浏览位置，共用媒体库、详情、搜索与播放界面。媒体文件由服务器提供，观看状态由当前服务器保存。

## Sub-features

- 分别连接三种服务，切换 Tab 后保留各自的导航位置。
- 浏览电影、系列、季、剧集和合集，查看详情与图片。
- 搜索、选择媒体版本、从头播放与续播。
- 播放时选择音轨和字幕，退出后刷新服务器观看进度。
- 季内连播使用当前播放所属服务的队列。

## How to get to it (user POV)

从 Emby、Plex 或 Jellyfin Tab 进入。Emby 与 Jellyfin 输入服务器地址、用户名和密码。Plex 使用浏览器账号授权，然后选择服务器。登录后的浏览和播放入口见 [Emby 媒体库](emby-library.md) 的共用控件路径。

## Driving it with the controller

Preconditions: 按索引建立当前构建的会话；目标服务健康；媒体样本已完成扫描；需要续播的样本满足该服务器的续播门槛。

```sh
C tap --identifier Emby-Navigation-Tab
C tap --identifier Plex-Navigation-Tab
C tap --identifier Jellyfin-Navigation-Tab
```

三个 Tab 内的共用浏览控件使用 `Emby-` 前缀标识。取 `Emby-Evidence` 后，先检查 `account.provider`，再检查 `serverID`、`userID` 和媒体 ID。三种服务的媒体 ID 各自独立。

Emby 与 Jellyfin 的连接控件为 `Emby-Connection-Address`、`Emby-Connection-Username`、`Emby-Connection-Password` 和 `Emby-Connection-Connect`。Plex 入口为 `Plex-Connection-SignIn`，服务器按钮为 `Plex-Connection-Server-<clientIdentifier>`。浏览器授权的外部页面由 Plex 提供。

DEBUG 启动前置可以使用 `ENCHRON_MEDIA_SERVER_KIND`（`emby`、`plex` 或 `jellyfin`），以及同前缀的 `ADDRESS`、`USERNAME`、`PASSWORD`、`TOKEN`、`LIBRARY`、`ITEM`。Plex 的 `USERNAME` 是账号 ID，`TOKEN` 是所选服务器的访问令牌。此方式属于 `injected`，不能证明真实登录操作。凭证只通过本地私有文件提供，不写入命令记录或截图。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 三种服务的凭证互不覆盖，退出一种不删除另外两种 | `EmbyServerStoreTests` |
| 结构 | Jellyfin 服务器轨道与文件轨道正确对应，外挂字幕使用服务器编号 | `EmbyClientTests`、播放桥测试 |
| 结构 | Plex 进度回报包含总时长，媒体时间单位转换正确 | `EmbyClientTests` |
| 物理 | 三个生产客户端读取同一影片，媒体字节相同，详情和海报可读取 | `MediaServerLiveIntegrationTests` |
| 物理 | 真实操作到达正确服务的详情、播放与续播终态 | Simulator／device 的 Operation 证据 |
| 感知 | 不进入自动裁决 | |

## 证明的终态

共同旅程必须分别绑定服务、服务器、账号和媒体身份。播放需有实际画面证据。进度保存需通过服务器重新读取确认。切换服务后，退出、续播与连播不得影响另一服务。

完整验收还需覆盖各服务的真实登录、断线、凭证失效、多版本选择和季内连播。正式场景及成功条件以 `Regression/` 为准。现有 Emby 场景的收据仅覆盖 Emby。

## Gotchas

- 同一文件会被各服务赋予不同 ID，刮削内容也可能不同。跨服务样本以底层文件对应。
- Plex 的 On Deck 包含未开始的下一集；Continue Watching 使用独立接口。
- Plex 接受缺少总时长的 timeline 请求，但续播位置可能不保存。
- Jellyfin 外挂字幕可能改变服务器轨道编号。服务器编号不能直接作为文件轨道编号。
- 测试服务的短片续播门槛不同。续播验证使用 16 分钟样本，分别设置并恢复状态。
- Plex 与 Jellyfin 的部署脚本分别为 `Scripts/verification/plex_test_service.py` 和 `Scripts/verification/jellyfin_test_service.py`。两者优先扫描与 Emby 共用的验证目录及代表性电影、剧集；完整云盘扫描按需执行。
