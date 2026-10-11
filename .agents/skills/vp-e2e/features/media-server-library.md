# 媒体服务器

Emby、Plex、Jellyfin 分别有独立的入口显示偏好、登录状态和浏览位置，共用媒体库、详情、搜索与播放界面。设置的通用分类可选择标签栏中的三个入口，每次选择立即生效。媒体文件由服务器提供，观看状态由当前服务器保存。

## Sub-features

- 分别连接三种服务，切换 Tab 后保留各自的导航位置。
- 在设置的通用分类选择三个入口的八种合法组合，包括全部隐藏。每行左侧为来源品牌图标，右侧为 MenuCheckmark；点击立即更新入口显示偏好与 Tab。隐藏入口保留登录凭证。
- 浏览电影、系列、季、剧集和合集，查看详情与图片。
- 搜索、选择媒体版本、从头播放与续播。
- 播放时选择音轨和字幕，退出后刷新服务器观看进度。
- 季内连播使用当前播放所属服务的队列。

## How to get to it (user POV)

从已显示的 Emby、Plex 或 Jellyfin Tab 进入。入口显示设置位于 Settings Tab 的 General 分类；初始偏好显示全部三个入口。Emby 与 Jellyfin 输入服务器地址、用户名和密码。Plex 使用浏览器账号授权，然后选择服务器。登录后的浏览和播放入口见 [Emby 媒体库](emby-library.md) 的共用控件路径。

## Driving it with the controller

Preconditions: 按索引建立当前构建的会话；目标服务健康；媒体样本已完成扫描；需要续播的样本满足该服务器的续播门槛。

```sh
C tap --identifier Emby-Navigation-Tab
C tap --identifier Plex-Navigation-Tab
C tap --identifier Jellyfin-Navigation-Tab
```

入口显示设置使用真实控件：

```sh
C tap --identifier Navigation-Ornament-tab-settings
C tap --identifier Settings-category-general
C snapshot --identifier Settings-mediaLibraryTabs-group
C tap --identifier Settings-mediaLibraryTabs-choice-emby
C tap --identifier Settings-mediaLibraryTabs-choice-plex
C tap --identifier Settings-mediaLibraryTabs-choice-jellyfin
```

选择行的 AX value 为当前语言的 Selected 或 Not selected，selected trait 同步表达当前选择。先读取当前值，只点击与目标组合不同的行。每次点击后，立即核对该行的两个 AX 信号与三个来源的 `*-Navigation-Tab` 集合，同时核对 Files、Settings 和 Environments 仍存在。本次点击的 `action.media-library-tabs-change` 探针须在点击后、下一次操作前出现。切换来源前记录账号身份，隐藏和重新显示期间不执行退出或 `resetState`。

八种选择组合必须各有选择后的 AX 层级证据，并在重启后核对同一集合：

| Emby | Plex | Jellyfin | 选择后显示的来源 |
|---|---|---|---|
| 未选择 | 未选择 | 未选择 | 无 |
| 未选择 | 未选择 | 选择 | Jellyfin |
| 未选择 | 选择 | 未选择 | Plex |
| 未选择 | 选择 | 选择 | Plex、Jellyfin |
| 选择 | 未选择 | 未选择 | Emby |
| 选择 | 未选择 | 选择 | Emby、Jellyfin |
| 选择 | 选择 | 未选择 | Emby、Plex |
| 选择 | 选择 | 选择 | Emby、Plex、Jellyfin |

多窗口验证中，一窗口的选择须立即更新其他窗口的选择状态与 Tab 集合。隐藏当前选中来源或外部路由指向隐藏来源时，内容目的地须回到 Files。场景结束时，通过真实选择行恢复初始组合，并核对选择状态与 Tab 集合一致。恢复失败时，该场景不能通过。

三个 Tab 内的共用浏览控件使用 `Emby-` 前缀标识。取 `Emby-Evidence` 后，先检查 `account.provider`，再检查 `serverID`、`userID` 和媒体 ID。三种服务的媒体 ID 各自独立。

Emby 与 Jellyfin 的连接控件为 `Emby-Connection-Address`、`Emby-Connection-Username`、`Emby-Connection-Password` 和 `Emby-Connection-Connect`。Plex 入口为 `Plex-Connection-SignIn`。等待授权时读取 `Plex-Connection-AuthorizationLink` 的 value，在已登录的浏览器中打开这条当前链接；`Plex-Connection-Cancel` 取消该次等待。浏览器确认后，原生页面须出现 `Plex-Connection-Server-<clientIdentifier>`，选择服务器后再读取账号证据。取消或过期的链接不能用于后续连接的验收。

DEBUG 启动前置可以使用 `ENCHRON_MEDIA_SERVER_KIND`（`emby`、`plex` 或 `jellyfin`），以及同前缀的 `ADDRESS`、`USERNAME`、`PASSWORD`、`TOKEN`、`LIBRARY`、`ITEM`。Plex 的 `USERNAME` 是账号 ID，`TOKEN` 是所选服务器的访问令牌。此方式属于 `injected`，不能证明真实登录操作。凭证只通过本地私有文件提供，不写入命令记录或截图。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 三种服务的凭证互不覆盖，退出一种不删除另外两种 | `EmbyServerStoreTests` |
| 结构 | 八种入口组合往返存取；缺失或错误类型字段默认显示；切换入口保留其他偏好；隐藏来源及环境动作回退 Files | `PreferencesPersistenceTests` |
| 物理 | 三个选择行可真实点击；每次选择立即更新偏好、当前及其他窗口的 Tab；八种组合重启后保留；场景恢复初始组合 | 主窗口浏览的 AX 层级、change 探针与 Operation 证据 |
| 物理 | 隐藏后重新显示同一服务，provider、serverID、userID 保持一致且无需登录便可浏览；正在播放的会话继续 | 隐藏前后的 `Emby-Evidence`、浏览结果及播放画面 |
| 结构 | Jellyfin 服务器轨道与文件轨道正确对应，外挂字幕使用服务器编号 | `EmbyClientTests`、播放桥测试 |
| 结构 | Plex 进度回报包含总时长，媒体时间单位转换正确 | `EmbyClientTests` |
| 结构 | Plex PIN 首次轮询返回 404 后仍可授权；选择服务器前不保存会话 | `EmbyClientTests.plexSignInWaitsForPINAuthorization` |
| 结构 | 电影和剧集的续播决策使用当前服务器进度；详情页缓存不决定续播位置 | `EmbyViewModelTests.freshResumeDecision` |
| 物理 | 三个生产客户端读取同一影片，媒体字节相同，详情和海报可读取 | `MediaServerLiveIntegrationTests` |
| 物理 | 真实操作到达正确服务的详情、播放与续播终态 | Simulator／device 的 Operation 证据 |
| 感知 | 不进入自动裁决 | |

## 证明的终态

入口显示验收须绑定选择前、每次选择后与重启后的 AX 层级。点击返回值和 reachability 探针只证明动作送达，选择行的 Selected/Not selected value、selected trait 与入口集合共同证明即时更新终态。每次变化的探针须绑定独立时间边界，恢复事件只能证明恢复操作。凭证保留以重新显示后的账号身份及真实浏览结果证明，截图中不记录令牌或密码。

共同旅程必须分别绑定服务、服务器、账号和媒体身份。播放需有实际画面证据。进度保存需通过服务器重新读取确认。切换服务后，退出、续播与连播不得影响另一服务。

基础真机路径为真实登录、搜索同一底层文件、详情播放、暂停、前进、退出、服务器进度读回、再次播放并接受续播、切换 Tab、重启后恢复账号。再次播放应从刚退出的详情页发起，才能发现详情缓存导致的过期续播决策。分别保存三个服务的账号证据与播放画面，结束后恢复样本的原始观看状态。

自动隐藏的播放控件可通过 `app-command toggleControls` 建立操作前置，再点击真实暂停、前进和返回按钮。此路径的控件展开属于 `injected`，不覆盖真实唤出手势；按钮操作及其终态分别取证。

完整验收还需覆盖各服务的真实登录、断线、凭证失效、多版本选择和季内连播。正式场景及成功条件以 `Regression/` 为准。现有 Emby 场景的收据仅覆盖 Emby。

正式 Emby 场景声明 `mediaServerProvider=emby`。其证据必须包含版本为 `enchron.regression.emby-source-preflight@2` 的服务器报告，并与应用的 provider、服务器 ID 和账号 ID 一致。缺少来源身份或使用另一来源的证据会被拒绝。

## 待纳入正式回归的验收矩阵

下表定义三来源扩展所需的覆盖范围。正式 Operation、场景绑定和收据合同尚需在 `Regression/` 中实现；本表不授予现有 Emby 收据跨来源覆盖。

| 范围 | 执行范围 | 必须观察的结果 |
|---|---|---|
| 媒体同步 | 每个原始库 | 映射 Emby 的全部源目录；扫描结束后按底层文件核对覆盖，包括多版本、多个 Part 和附加视频；额外样本库不抵消原始库遗漏。云盘不可达时保留已有索引。 |
| 连接与退出 | 每个服务 | 从未连接状态完成真实登录，重启后恢复，退出只清除当前服务。Plex 还需覆盖浏览器授权、取消和服务器选择。 |
| 浏览与搜索 | 每个服务 | 电影、系列、季、剧集、合集能从列表和搜索到达；分页无重复和遗漏；缺失海报、简介时仍能操作。 |
| 播放入口 | 每个服务 | 从头播放、续播和多版本选择打开预期文件；服务、服务器、账号、媒体和版本身份正确；有实际画面。 |
| 音轨与字幕 | 每个服务 | 切换内嵌音轨、内嵌字幕、外挂字幕及关闭字幕后，播放器选择正确；回报使用服务器轨道编号。 |
| 进度与连播 | 每个服务 | 暂停、跳转、退出后重新读取服务器状态；续播位置正确；结束当前集后进入下一集，季末结束；恢复测试前的观看状态。 |
| 服务隔离 | 每对服务 | 切换 Tab 保留导航；当前播放的进度、轨道和下一集始终属于启动该播放的服务；退出另一服务不影响当前播放。 |
| 失败与恢复 | 每个服务 | 错误凭证、令牌失效、不可达服务器和播放中断有明确错误；重试可恢复；失败不会写入成功会话或错误观看进度。 |
| 播放器公共行为 | 公共引擎矩阵 | 暂停、跳转、呈现模式和解码行为沿用公共矩阵；每个服务补一条流读取与回报闭环，避免重复整个硬件矩阵。 |

样本至少包含同一电影、两部电影组成的合集、连续三集、多版本、多个音轨、内嵌及外挂字幕、缺失图片、16 分钟续播片。跨服务以底层文件及媒体版本对应，分别保存服务侧 ID。续播判据采用服务器实际门槛，测试前保存观看状态，测试后恢复。

驱动把输入动作、应用终态与服务器终态分别绑定。点击成功只证明输入送达。凭证注入、直接调用播放或跳转命令只能承担前置，不能替代相应的真实 UI 验收。

## Gotchas

- Plex 授权网页的错误与跳转判据见[浏览与来源的外部约束](../../../../docs/BROWSING_AND_SOURCES_CONSTRAINTS.md#plex-账号授权)。
- 真机首次访问服务器可能出现局域网权限卡。窗口输入无法获得焦点时先看截图；App 层级可能没有这张卡，外侧 Tab 仍可点击。系统 Scene 的处理边界见[真机 lane](../references/device.md#已证伪路径)。
- 同一文件会被各服务赋予不同 ID，刮削内容也可能不同。跨服务样本以底层文件对应。
- Plex 的 On Deck 包含未开始的下一集；Continue Watching 使用独立接口。
- Jellyfin 可以把合集放在独立的合集库。浏览入口使用服务器返回的库结构。
- Plex 接受缺少总时长的 timeline 请求，但续播位置可能不保存。
- Jellyfin 外挂字幕可能改变服务器轨道编号。服务器编号不能直接作为文件轨道编号。
- 测试服务的短片续播门槛不同。续播验证使用 16 分钟样本，分别设置并恢复状态。
- Plex 与 Jellyfin 的部署脚本分别为 `Scripts/services/plex_test_service.py` 和 `Scripts/services/jellyfin_test_service.py`。两者映射 Emby 的全部原始媒体目录，并配置每小时刷新。代表性样本库用于固定测试入口。
- 同步覆盖按每个原始库的实际文件路径计算，同时保留 Emby 已索引清单与源目录文件清单。影片条目数不能代替文件数；多个版本可能合并到一个条目，附加视频也可能不出现在普通列表。
- 后台刷新需在实际 launchd 环境验证媒体目录访问。终端执行成功不能证明后台权限就绪。Jellyfin 的目录检查与 Plex 中文集数链接更新分别由 `Scripts/services/jellyfin_refresh.py` 和 `Scripts/services/plex_normalized_media.py` 承担，部署副本位于各自服务目录，不依赖当前 Git 分支。
