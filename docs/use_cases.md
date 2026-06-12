# 用例表（Use Case Ledger）

App 用户可观察行为的唯一规范清单。时态：**活法律**——随行为变更同 commit 更新。立档决策与被否方案见 `docs/adr/0003`。

## 宪章

**裁决次序**：
1. 对代码：本表为准。`已验证`/`未验证` 条目与实际行为冲突 → 默认改代码，不改表。
2. 对 `ARCHITECTURE.md`：互不裁决。架构约束导致某用例不可实现时，上报人类，不自动取舍。
3. 对 `docs/product_philosophy.md`：哲学是上游。新增用例违背产品哲学的，哲学赢。

**报警规则**：发现本表与实际行为有出入且不在本轮任务验收范围内时——开 issue，标题带用例 ID，写清「表说 X、实测 Y」，**本轮不动代码也不动表**。证据丰富度随问题大小升级：小出入贴文字描述即可，行为性偏差贴截图，交互/时序类偏差录屏。冲突恰在本轮验收范围内的，按正常工作处理，不算报警。

**蓝图模式**：本表记「应然」行为，含未实现条目。一条用例 ⟷ 一个可观察断言 ⟷（未来）一个 UI 测试。一行表格写不下的条目，说明粒度太粗，拆。

**视角规则**：主语是用户。触发可以是用户操作或系统事件（断网、播放结束），但**结果必须用户可观察**；内部机制不进表。负路径（出错场景）与正路径平等入表。visionOS 系统默认行为（如捏合关窗）不是 app 的承诺，不记；只记 app 自己实现的行为。

**锚点规则**：可观察结果以 `accessibilityIdentifier` 为锚，用户可见文案作辅助描述——文案会随本地化变，identifier 不变。

**排序规则**：初次填充时章内按典型操作动线排；此后新增一律追加章末取下一序号，**永不重排已有行**。ID 序号 = 追加顺序，不承载语义。

**字段说明**：
- **ID**：`UC-<前缀>-<序号>`，永不复用。前缀封闭名单见下，新增前缀需人类批准。
- **简名**：3~8 字动宾短语，该用例的正式名字（如函数名）。管线节、issue 标题引用时必须逐字使用；简名可改，改时全文 grep 同步替换。
- **触发·前置**：用户在哪、做了什么；必要前置条件。
- **预期可观察结果**：机器可核对真假的断言，不写意图（「用户感觉流畅」不合格）。
- **验证状态**：`已验证`（有链接证据）/ `未验证`（凭记忆，待核）/ `未实现`。描述证据等级，与代码是否存在无关。
- **关联测试**：测试名 / `未覆盖` / `BLOCKED-原因`。
- **模式适用**：取值 = `PlaybackMode`（`窗口`/`沉浸`/`全景`），可多选；**缺省（`—`）= 与呈现模式无关**。同一行为在不同模式下结果不同的，拆成多条。

**归属规则**：跨 surface 的用例归触发动作所在的 surface（用户在哪里按下的，归哪章）。

**前缀名单（封闭）**：

| 章节 | 前缀 | 范围 |
|---|---|---|
| Launch | `LNCH` | App 启动与窗口生命周期 |
| Files | `FILE` | 文件浏览与数据源（本地/相册/SMB/WebDAV） |
| Settings | `SET` | 设置 |
| Playback | `PLAY` | 播放控制 |
| Scene | `SCEN` | 空间场景与呈现切换 |

复杂条目的补充说明不进表格，在该章末尾用 `> UC-XXX-NN 备注：…` 引用块承载。

---

## 典型操作管线（ID 链 + 逐字简名，只引用不复制内容）

供 agent 理解功能因果顺序；未来测试阶段的 E2E 剧本。只收典型管线，3~6 条封顶。

- **冷启动看片**：UC-LNCH-01 启动进浏览页 → UC-FILE-01 点视频弹详情 → UC-PLAY-01 点按钮开始播放 → UC-PLAY-19 退出播放回浏览
- **添加远程源**：UC-FILE-02 展开添加源菜单 → UC-FILE-09 连接 WebDAV 服务器（或 UC-FILE-11 SMB 列出共享 → UC-FILE-12 选共享接入）→ UC-FILE-18 进文件夹扩面包屑
- **沉浸观影**：UC-FILE-01 点视频弹详情 → UC-SCEN-01 详情页选呈现模式 → UC-SCEN-03 进沉浸开虚拟屏 → UC-SCEN-08 调节屏幕位置 → UC-SCEN-12 关沉浸回窗口
- **续看**：UC-LNCH-01 启动进浏览页 → UC-FILE-29 最近播放列表 → UC-FILE-31 点最近条目开详情 → UC-PLAY-02 询问续播双按钮

## Launch（LNCH）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-LNCH-01 | 启动进浏览页 | 启动 app | 显示主窗口，侧栏含 Browse / Recent / Settings 三个标签，Browse 默认选中并展示文件浏览内容 | 未验证 | 未覆盖 | — |
| UC-LNCH-02 | 重启不续位 | 退出后重新启动 app | 浏览页回到根层级，不恢复上次浏览位置或上次打开的文件 | 未验证 | 未覆盖 | — |
| UC-LNCH-03 | 切换主导航标签 | 点侧栏导航条的 Recent / Settings 标签（锚 `Navigation-Ornament-tab-*`） | 主区域切换为对应页面，当前标签高亮 | 未验证 | 未覆盖 | — |

## Files（FILE）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-01 | 点视频弹详情 | Browse 页已有可用数据源；点一个视频文件 | 弹出视频详情面板（sheet），含播放按钮（锚 `videoDetail.playButton`，首次观看文案 "Start Playback"） | 未验证 | 未覆盖 | — |
| UC-FILE-02 | 展开添加源菜单 | Browse 页点 "Add Source" 菜单 | 菜单展开，含 Local 分组（Choose Folder… / Import Video… / Photo Library… / Use App Documents）与 Remote 分组（Add WebDAV Server… / Add SMB Server…） | 未验证 | 未覆盖 | — |
| UC-FILE-03 | 选本地文件夹接入 | Add Source → "Choose Folder…"，在系统选择器选一个文件夹 | 主区域显示该文件夹内容，侧栏 Local Storage 标记活跃（绿点） | 未验证 | 未覆盖 | — |
| UC-FILE-04 | 用 App 文档目录 | Add Source → "Use App Documents" | 主区域显示 Documents 文件夹内容，Local Storage 标记活跃 | 未验证 | 未覆盖 | — |
| UC-FILE-05 | 导入视频成功 | Add Source → "Import Video…"，多选视频文件确认 | 文件复制进 Documents，显示 "Imported X file(s)." 消息，列表出现新文件 | 未验证 | 未覆盖 | — |
| UC-FILE-06 | 导入跳过重名 | Import Video 选中与 Documents 已有同名的文件 | 该文件被跳过，消息含 "Skipped duplicates: <文件名>" | 未验证 | 未覆盖 | — |
| UC-FILE-07 | 相册授权接入 | Add Source → "Photo Library…"，在系统权限弹窗允许 | 侧栏出现 Photo Library 数据源，主区域显示相册列表（无视频的相册不显示） | 未验证 | 未覆盖 | — |
| UC-FILE-08 | 相册授权被拒 | Photo Library 权限弹窗选拒绝 | 显示错误 "Photo Library access was denied. Please grant access in Settings."，不接入 | 未验证 | 未覆盖 | — |
| UC-FILE-09 | 连接 WebDAV 服务器 | Add WebDAV Server 表单填地址（锚 `FileBrowsing-DataSourceConfig-textField-serverAddress`）点 Connect | 按钮转 "Connecting…"，成功后 sheet 关闭，侧栏新增该源并标活跃，主区域显示其根目录 | 未验证 | 未覆盖 | — |
| UC-FILE-10 | 连接失败留表单 | WebDAV/SMB 连接超时、认证失败或地址无效 | sheet 不关闭，表单内显示对应错误文案（如 "Authentication failed…" / "Connection timed out…"），可改后重试 | 未验证 | 未覆盖 | — |
| UC-FILE-11 | SMB 列出共享 | Add SMB Server 表单填 IP 点 Connect，连接成功 | 表单切换为该服务器的共享文件夹列表（锚 `FileBrowsing-DataSourceConfig-button-share-*`） | 未验证 | 未覆盖 | — |
| UC-FILE-12 | 选共享接入 | 在 SMB 共享列表点一个共享 | sheet 关闭，侧栏新增该源（名称 "IP/share" 或自定义）并标活跃，主区域显示共享根目录 | 未验证 | 未覆盖 | — |
| UC-FILE-13 | SMB 无共享提示 | SMB 登录成功但服务器无可访问共享 | 列表显示 "No shares found on this server." | 未验证 | 未覆盖 | — |
| UC-FILE-14 | SMB 地址滤非法字符 | 在 SMB 地址框输入数字和点以外的字符 | 非法字符被自动过滤，输入框只留数字和点 | 未验证 | 未覆盖 | — |
| UC-FILE-15 | 凭据免重输 | 连接过的远程源，重启 app 后在侧栏点它 | 直接连上并显示内容，无需重新输入用户名密码（凭据存 Keychain） | 未验证 | 未覆盖 | — |
| UC-FILE-16 | 切换数据源 | 点侧栏另一个已保存数据源 | 绿点移到该源，其余源圆点变灰，主区域刷新为该源内容 | 未验证 | 未覆盖 | — |
| UC-FILE-17 | 删远程源回本地 | 侧栏左滑/长按删除一个远程源 | 该源从侧栏移除、凭据删除；若它是活跃源，自动回到 Local Storage | 未验证 | 未覆盖 | — |
| UC-FILE-18 | 进文件夹扩面包屑 | 点一个文件夹卡片（锚 `FileBrowsing-ContentGrid-button-folder-*`） | 主区域加载该文件夹内容，面包屑追加一段且末段加粗 | 未验证 | 未覆盖 | — |
| UC-FILE-19 | 面包屑回跳 | 点面包屑中非当前段（锚 `FileBrowsing-Breadcrumb-button-*`） | 返回该层级，其后所有段移除，内容区重载 | 未验证 | 未覆盖 | — |
| UC-FILE-20 | 排序即时生效 | 点排序按钮（锚 `FileBrowsing-Toolbar-button-sort`）选 Name / Date Modified / Size 或反转方向 | 文件列表立即按所选键与方向重排，菜单中当前项带勾与方向箭头 | 未验证 | 未覆盖 | — |
| UC-FILE-21 | 过滤胶囊排他切换 | 点过滤胶囊（锚 `FileBrowsing-Filter-button-*`）：All 与 4K/HDR/Spatial 互点 | 选具体过滤器时 All 取消，全部取消时回到 All；激活项高亮 | 未验证 | 未覆盖 | — |
| UC-FILE-22 | 过滤实际筛文件 | 激活 4K / HDR / Spatial 过滤胶囊 | 列表只显示符合该媒体属性的文件 | 未实现 | 未覆盖 | — |
| UC-FILE-23 | 空文件夹空态 | 进入无文件夹且无可播文件的目录 | 显示空态卡片："No folders or playable videos found." | 未验证 | 未覆盖 | — |
| UC-FILE-24 | 加载骨架屏 | 切源、刷新或导航触发加载 | 显示 6 张闪烁灰色骨架卡（锚 `FileBrowsing-ContentGrid-skeleton`），加载完替换为真实内容 | 未验证 | 未覆盖 | — |
| UC-FILE-25 | 视频卡片显元数据 | 浏览含视频的目录 | 卡片显示缩略图（异步渐显）、文件名、大写扩展名·修改日期、文件大小徽章，特殊格式带左上角徽章 | 未验证 | 未覆盖 | — |
| UC-FILE-26 | 已看卡片显进度 | 目录中存在播放过的文件 | 该卡片底部显示橙色进度条与 "Watched HH:MM:SS" | 未验证 | 未覆盖 | — |
| UC-FILE-27 | 删除本地文件 | Documents 目录中右键视频卡片选 "Delete"（红色） | 文件从磁盘删除、卡片移除；远程源不提供此项 | 未验证 | 未覆盖 | — |
| UC-FILE-28 | 断连保列表弹警 | 浏览远程源时网络断开/服务器离线 | 列表保留上次内容不清空，弹 "File Browser Error" 对话框含 Retry / OK，OK 回 Local Storage | 未验证 | 未覆盖 | — |
| UC-FILE-29 | 最近播放列表 | 进 Recent 标签页 | 最多 50 条按最后播放时间降序，每条含文件名、播放位置、最后播放时间（锚 `App-RecentlyPlayed-row-*`） | 未验证 | 未覆盖 | — |
| UC-FILE-30 | 最近播放空态 | 无播放历史时进 Recent 页 | 显示 "No Recent Playback" 空态 | 未验证 | 未覆盖 | — |
| UC-FILE-31 | 点最近条目开详情 | 点 Recent 列表一条（其来源仍存在） | 打开该文件的详情面板 | 未验证 | 未覆盖 | — |
| UC-FILE-32 | 下拉刷新 | 主内容区下拉 | 重新加载当前目录，期间显示加载态 | 未验证 | 未覆盖 | — |
| UC-FILE-33 | 文件名搜索 | 工具栏搜索框输入关键词 | 列表实时过滤为匹配文件 | 未实现 | 未覆盖 | — |
| UC-FILE-34 | 网格列表视图切换 | 工具栏视图模式控件切换 Grid / List | 内容区在网格卡片与列表行两种布局间切换 | 未实现 | 未覆盖 | — |

## Settings（SET）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-01 | 设续播策略 | Settings → Resume Behavior（锚 `Settings-Playback-picker-resumePolicy`）选三值之一 | 下次打开已看过的视频时，详情页播放按钮按所选策略呈现（见 UC-PLAY-02/03/04） | 未验证 | 未覆盖 | — |
| UC-SET-02 | 设结束行为 | Settings → When Video Ends（锚 `Settings-Playback-picker-endBehavior`）选 Stop / Repeat / Play Next | 视频播完按所选行为执行（见 UC-PLAY-22） | 未验证 | 未覆盖 | — |
| UC-SET-03 | 设默认倍速 | Settings → Default Speed（锚 `Settings-Playback-picker-defaultSpeed`）选 0.25×~5.0× | 之后新开播放以该倍速起播 | 未验证 | 未覆盖 | — |
| UC-SET-04 | 开关沉浸空间 | Settings → 沉浸空间开关按钮（锚 `Settings-ImmersiveSpace-button-toggle`） | 沉浸空间打开/关闭，按钮文案在 "Show/Hide Immersive Space" 间切换；过渡中按钮禁用 | 未验证 | 未覆盖 | — |
| UC-SET-05 | 切沉浸风格 | Settings → Immersion Style（锚 `Settings-ImmersiveSpace-picker-immersionStyle`）选 Full / Mixed | 沉浸空间内虚拟屏周围环境随之显示或隐藏 | 未验证 | 未覆盖 | 沉浸 |
| UC-SET-06 | 切屏幕形状 | Settings → Screen Shape（锚 `Settings-ImmersiveSpace-picker-screenShape`）选 Flat / Curved | 虚拟屏幕几何即时切换：平面矩形 ⟷ 内弯曲面 | 未验证 | 未覆盖 | 沉浸 |
| UC-SET-07 | 切默认环境 | Settings → Environment（锚 `Settings-ImmersiveSpace-picker-environment`）选环境 | 沉浸空间背景穹顶切换为所选环境（暗黑影院/星空夜景/自然日落） | 未验证 | 未覆盖 | 沉浸 |
| UC-SET-08 | 显示缓存大小 | 打开 Settings 页 | Storage 区显示当前缓存大小（人类可读格式，空时 "Empty"，锚 `Settings-Storage-label-cacheSize`） | 未验证 | 未覆盖 | — |
| UC-SET-09 | 清缓存带确认 | 点 Clear Cache（锚 `Settings-Storage-button-clearCache`）并在对话框确认 | 弹确认对话框（Clear/Cancel）；确认后缓存清空，按钮变绿色 "Cache Cleared"，缓存大小刷新 | 未验证 | 未覆盖 | — |
| UC-SET-10 | 缓存空禁清理 | 缓存大小为 0 时查看 Clear Cache 按钮 | 按钮处于禁用态 | 未验证 | 未覆盖 | — |
| UC-SET-11 | 显示版本构建号 | 打开 Settings 页 About 区 | 显示 Version 与 Build（取自 Info.plist） | 未验证 | 未覆盖 | — |
| UC-SET-12 | 偏好重启保留 | 修改续播策略/结束行为/默认倍速/屏幕形状/默认环境后重启 app | 五项设置保持修改后的值 | 未验证 | 未覆盖 | — |
| UC-SET-13 | 设控件隐藏时长 | Settings → Controls Auto-Hide 选 5/8/15 秒 | 播放控件按所选秒数无交互后自动隐藏 | 未实现 | 未覆盖 | — |
| UC-SET-14 | 设空间内容自动沉浸 | Settings → Enter Immersion for Spatial Content 选 Off / Ask / Auto | 打开空间内容时按所选策略进入沉浸 | 未实现 | 未覆盖 | — |
| UC-SET-15 | 清除播放历史 | Settings → Clear Recent Playback & Progress | 最近播放列表与续播进度被清空，Recent 页回到空态 | 未实现 | 未覆盖 | — |

## Playback（PLAY）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-01 | 点按钮开始播放 | 详情面板点播放按钮（锚 `videoDetail.playButton`） | 进入所选呈现模式开始播放，控制条出现 | 未验证 | 未覆盖 | — |
| UC-PLAY-02 | 询问续播双按钮 | 续播策略为 Ask，打开有进度（>5s）的视频详情 | 显示 "Resume from HH:MM:SS" 主按钮与 "Play from Start" 次按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-03 | 总是续播单按钮 | 续播策略为 Always Resume，打开有进度的视频详情 | 仅显示 "Resume" 按钮，点击从断点继续 | 未验证 | 未覆盖 | — |
| UC-PLAY-04 | 总是重头播放 | 续播策略为 Always Start Over，打开有进度的视频详情 | 仅显示 "Play" 按钮，点击从头播放 | 未验证 | 未覆盖 | — |
| UC-PLAY-05 | 播放暂停切换 | 点中央播放/暂停按钮（锚 `play-pause-button`） | 播放 ⟷ 暂停切换，图标随状态变化（play.fill / pause.fill） | 未验证 | 未覆盖 | — |
| UC-PLAY-06 | 播完按钮变重播 | 视频播放至末尾（结束行为为 Stop） | 中央按钮变重播图标（文案 "Replay"），点击从头播放 | 未验证 | 未覆盖 | — |
| UC-PLAY-07 | 快进十秒 | 点快进按钮（锚 `forward-button`） | 播放位置 +10 秒，画面跳转 | 未验证 | 未覆盖 | — |
| UC-PLAY-08 | 快退十秒 | 点快退按钮（锚 `rewind-button`） | 播放位置 −10 秒（不低于 0），画面跳转 | 未验证 | 未覆盖 | — |
| UC-PLAY-09 | 拖动进度跳转 | 拖动进度条（锚 `PlayerUI-SeekBar-slider-position`）后放开 | 播放位置跳到目标点，左右两端显示当前/剩余时间码 | 未验证 | 未覆盖 | — |
| UC-PLAY-10 | 拖动显帧级时间 | 拖动进度条过程中 | 滑块下方显示橙色帧级精度时间戳，随拖动实时更新 | 未验证 | 未覆盖 | — |
| UC-PLAY-11 | 左菜单三选项 | 点左菜单按钮（锚 `left-menu-button`） | 弹出玻璃面板，含 Subtitles / Audio Track / Playback Speed 三行，可展开子菜单 | 未验证 | 未覆盖 | — |
| UC-PLAY-12 | 切音轨即时生效 | 左菜单 → Audio Track 选另一条音轨 | 音频立即切换，选中轨带勾标记，无需重新加载 | 未验证 | 未覆盖 | — |
| UC-PLAY-13 | 切字幕与关闭 | 左菜单 → Subtitles 选某字幕轨或 Off | 选轨则画面显示该字幕，Off 则隐藏全部字幕，选中项带勾 | 未验证 | 未覆盖 | — |
| UC-PLAY-14 | 切播放倍速 | 左菜单 → Playback Speed 选 0.25×~5.0× | 播放速度立即变化，选中档带勾 | 未验证 | 未覆盖 | — |
| UC-PLAY-15 | 控件八秒自隐 | 播放中 8 秒无任何交互 | 控制条淡出隐藏，子菜单关闭 | 未验证 | 未覆盖 | — |
| UC-PLAY-16 | 交互唤回控件 | 控件隐藏后任意交互（窗口捏合 / 空间点按） | 控制条淡入重现 | 未验证 | 未覆盖 | — |
| UC-PLAY-17 | 双击展开时间轴 | 双击进度条 | 底部滑出 NLE 精度时间轴面板（锚 `PlayerUI-NLETimeline-container`）：刻度尺、缩略图条、帧步进按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-18 | 逐帧步进 | NLE 时间轴点前帧/后帧按钮（需媒体帧率已知） | 播放位置精确移动一帧，画面逐帧变化 | 未验证 | 未覆盖 | — |
| UC-PLAY-19 | 退出播放回浏览 | 点信息条返回按钮（锚 `PlayerUI-InfoBar-button-back`） | 停止播放、记录进度、返回文件浏览 | 未验证 | 未覆盖 | — |
| UC-PLAY-20 | 信息条显元数据 | 播放中查看顶部信息条 | 显示视频标题与徽章：分辨率（4K/1080p…）、HDR 类型、编解码器、空间音频（如有） | 未验证 | 未覆盖 | — |
| UC-PLAY-21 | 加载中转圈提示 | 选片后媒体加载阶段 | 详情页显示 "Loading media information…" 进度指示 | 未验证 | 未覆盖 | — |
| UC-PLAY-22 | 按设置执行结束行为 | 视频播完，结束行为设为 Repeat 或 Play Next | Repeat 自动从头重播；Play Next 自动播下一个文件 | 未验证 | 未覆盖 | — |
| UC-PLAY-23 | 加载失败可重试 | 文件损坏/不支持/网络失败导致加载失败 | 显示 "Failed to Load" 错误面板含原因描述，提供 Retry 与 Close 按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-24 | 缓冲显示指示 | 网络源播放中缓冲不足 | 画面出现缓冲指示，恢复后自动消失 | 未实现 | 未覆盖 | — |

## Scene（SCEN）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SCEN-01 | 详情页选呈现模式 | 详情面板模式选择器（锚 `videoDetail.playbackModePicker`） | 三按钮 Window / Immersive / Panorama，选中带勾高亮；非全景内容 Panorama 灰显不可选 | 未验证 | 未覆盖 | — |
| UC-SCEN-02 | 立体内容强制沉浸 | 播放 SBS / TopBottom 立体视频 | 自动进入沉浸模式播放，Window 不可用 | 未验证 | 未覆盖 | 沉浸 |
| UC-SCEN-03 | 进沉浸开虚拟屏 | 以 Immersive 模式开始播放（或播放中切入） | 主窗口让位，沉浸空间打开，3D 空间中浮现虚拟屏幕与所选环境穹顶 | 未验证 | 未覆盖 | 沉浸 |
| UC-SCEN-04 | 进全景开球面 | 全景内容以 Panorama 模式播放 | 全景球面包裹用户（360° 全球 / 180° 半球按内容投影），无虚拟屏幕 | 未验证 | 未覆盖 | 全景 |
| UC-SCEN-05 | 播放中切模式 | 播放中右菜单（锚 `right-menu-button`）→ Playback Mode 选另一模式 | 呈现切换到所选模式，当前模式带勾，内容不允许的模式灰显 | 未验证 | 未覆盖 | — |
| UC-SCEN-06 | 过渡期禁操作 | 沉浸空间打开/关闭过渡中 | 模式与沉浸开关相关按钮禁用，过渡完成后恢复 | 未验证 | 未覆盖 | — |
| UC-SCEN-07 | 播放中换环境 | 沉浸空间打开时右菜单 → Environment 选另一环境 | 背景穹顶无缝切换；该子菜单仅在沉浸空间打开时出现 | 未验证 | 未覆盖 | 沉浸 |
| UC-SCEN-08 | 调节屏幕位置 | 沉浸中打开 Screen Position 面板，调 Distance(2–20m) / Vertical(±2m) / Angle(±45°) 或点预设 | 虚拟屏幕实时按参数移动/旋转 | 未验证 | 未覆盖 | 沉浸 |
| UC-SCEN-09 | 屏位随环境记忆 | 在环境 A 调过屏幕位置后切到环境 B 再切回 A | 环境 A 恢复其独立保存的屏幕位置 | 未验证 | 未覆盖 | 沉浸 |
| UC-SCEN-10 | 空间点按切控件 | 沉浸/全景中对虚拟屏或球面做空间点按 | 播放控件显隐切换 | 未验证 | 未覆盖 | 沉浸, 全景 |
| UC-SCEN-11 | 全景拖拽转视角 | 全景模式中拖拽球面 | 视角随拖拽旋转（俯仰限 ±30°） | 未验证 | 未覆盖 | 全景 |
| UC-SCEN-12 | 关沉浸回窗口 | Settings 或开关按钮关闭沉浸空间 | 沉浸空间关闭，主窗口恢复，播放回 Window 模式继续 | 未验证 | 未覆盖 | — |
| UC-SCEN-13 | 场景选择页开沉浸 | 点导航条场景按钮（锚 `Navigation-Ornament-button-sceneSelector`）选环境卡片 | 进入环境网格页，点卡片自动打开对应环境的沉浸空间 | 未验证 | 未覆盖 | — |

---

## 成功指标（占位·未定义）

本节空缺。成功指标 = 产品层「做好了」的可度量标准（性能、体验阈值），与单条用例的「预期可观察结果」不同层。
空缺原因：待管线技术验证与大规模测试设计阶段一并定义。填充责任：人类发起，agent 起草。
**在此之前，任何 agent 不得自行发明指标。**

## 退役名单（只追加）

（空。格式：`UC-XXX-NN — 退役 YYYY-MM-DD：一句话原因`。退役条目从正文删行，原文去 git history 查。）
