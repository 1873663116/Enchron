# 用例表（Use Case Ledger）

App 用户可观察行为的唯一规范清单。时态：**活法律**——随行为变更同 commit 更新。立档决策与被否方案见 `docs/adr/0003`；功能簇结构与 Scene→Environment 改名见 `docs/adr/0005`；前缀 `ENV`、双上下文、冲突治理见 `docs/adr/0006`。

## 索引

- **Launch**（`LNCH`）— 启动与主导航
- **Files**（`FILE`）— 数据源管理 · 本地文件管理 · 浏览与导航 · 文件项与卡片 · 状态与边界
- **Settings**（`SET`）— Playback · Spatial Content · Storage & Privacy · Diagnostics & Tools · About · 框架（导航与持久化）
- **Playback**（`PLAY`）— 传输与进度 · 精度时间轴 · ⋯ 轨道菜单 · 播放设置面板（≡）· 控件显隐与窗口 · 续播与加载生命周期
- **Environment**（`ENV`）— 环境选择（本轮在场）· 沉浸呈现（延期）· 沉浸内调整（延期）
- **附录** — Picture 画面参数（libplacebo）

## 宪章

**裁决次序**：
1. 对生产代码（`XrPlayer` target）：本表为准（蓝图）。`已验证`/`未验证` 条目与实际行为冲突 → 默认改代码，不改表。
2. 对 DesignComps 设计稿：**无默认权威**。本表 agent 写成、人类只粗审，设计稿亦是人类意志；二者冲突时 surface 出来——明确的笔误/占位即定（写明理由、留否决），真·意图分歧路由人类裁决（见 `docs/adr/0006`）。
3. 对 `ARCHITECTURE.md`：互不裁决。架构约束导致某用例不可实现时，上报人类，不自动取舍。
4. 对 `docs/product_philosophy.md`：哲学是上游。新增用例违背产品哲学的，哲学赢。

**报警规则**：发现本表与实际行为有出入且不在本轮任务验收范围内时——开 issue，标题带用例 ID，写清「表说 X、实测 Y」，**本轮不动代码也不动表**。证据丰富度随问题大小升级：小出入贴文字描述即可，行为性偏差贴截图，交互/时序类偏差录屏。冲突恰在本轮验收范围内的，按正常工作处理，不算报警。

**蓝图模式**：本表记「应然」行为，含未实现条目。一条用例 ⟷ 一个可观察断言 ⟷ 一个 E2E 测试。一行表格写不下的条目，说明粒度太粗，拆。

**粒度决策程序**（判一条够不够「一条」）：
- 偏粗要拆：「预期结果」里出现「并且 / 然后」连接两个能独立观察的效果，或要写 ≥2 个 UI 测试 → 拆。
- 偏细要并：两条共用同一用户动作 + 同一断言，或一条离开另一条无法独立观察 → 并。
- 天然独立：负路径（出错）、同一行为的不同模式（窗口/沉浸/全景），各占一条。
- 锚点 = `accessibilityIdentifier` + 那个断言；一次可观察的状态跃迁 = 一条。

**视角规则**：主语是用户。触发可以是用户操作或系统事件（断网、播放结束），但**结果必须用户可观察**；内部机制不进表。负路径（出错场景）与正路径平等入表。visionOS 系统默认行为（如捏合关窗、关闭窗口 bar）不是 app 的承诺，不记；只记 app 自己实现的行为。

**锚点规则**：可观察结果以 `accessibilityIdentifier` 为锚，用户可见文案作辅助描述——文案会随本地化变，identifier 不变。

**命名对齐规则**：UI 区域与组件称呼以 `DesignPreview/DesignComps` 与代码真名为准——系统 TabView（顶层导航：Files / Settings / Environments，是 tab 不是 sidebar）、Source Sidebar（Files 页数据源列表，行 `SourceSidebarRow`）、CategorySidebar（Settings 页分类列表）、PlayerControlDeck（播放控制台）、GridCard / FileListGroup（文件卡 `.video`/`.folder` 变体）、EnvironmentCard / EnvironmentCardCarousel（环境卡/轮播）；播放设置面板分类 = Environment Setting / Play Mode / Picture。应然 UX 冲突时按裁决次序处理。组件真名以代码为准、设计层词汇见 `DesignPreview/CONTEXT.md`。

**排序规则**：章内按功能簇（`###` 子标题）分组；簇内按典型操作动线排。新增追加到所属簇末、取该章下一序号；**ID 永不复用、不承载语义**（序号在簇内不连续、不代表归属，均属正常）。退役条目从正文删行、记入退役名单。

**字段说明**：
- **ID**：`UC-<前缀>-<序号>`，永不复用。前缀封闭名单见下，新增前缀需人类批准。
- **简名**：3~8 字动宾短语，该用例的正式名字（如函数名）。管线节、issue 标题引用时必须逐字使用；简名可改，改时全文 grep 同步替换。
- **触发·前置**：用户在哪、做了什么；必要前置条件。
- **预期可观察结果**：机器可核对真假的断言，不写意图（「用户感觉流畅」不合格）。
- **验证状态**：`已验证`（有链接证据）/ `未验证`（凭记忆或仅 Canvas 视觉，待核）/ `未实现`。描述证据等级，与代码是否存在无关。
- **关联测试**：测试名 / `未覆盖` / `BLOCKED-原因`。
- **模式适用**：取值 = `PlaybackMode`（`窗口`/`沉浸`/`全景`），可多选；**缺省（`—`）= 与呈现模式无关**。同一行为在不同模式下结果不同的，拆成多条。

**归属规则**：跨 surface 的用例归触发动作所在的 surface（用户在哪里按下的，归哪章）。

**前缀名单（封闭）**：

| 章节          | 前缀     | 范围                                                                                           |
| ----------- | ------ | -------------------------------------------------------------------------------------------- |
| Launch      | `LNCH` | App 启动与主导航                                                                                   |
| Files       | `FILE` | 文件浏览、数据源、本地文件管理                                                                              |
| Settings    | `SET`  | 设置                                                                                           |
| Playback    | `PLAY` | 播放控制与播放设置面板                                                                                  |
| Environment | `ENV`  | 空间环境与呈现切换（领域概念由 Scene 改名 Environment 以避开 SwiftUI `Scene`；前缀 `ENV`，2026-06-18 由 `SCEN` 改名，见 ADR 0006） |

复杂条目的补充说明不进表格，在该章末尾用 `> UC-XXX-NN 备注：…` 引用块承载。

---

## 典型操作管线（ID 链 + 逐字简名，只引用不复制内容）

供 agent 理解功能因果顺序；未来测试阶段的 E2E 剧本。只收典型管线，3~6 条封顶。

- **冷启动看片**：UC-LNCH-01 启动进浏览页 → UC-FILE-01 点视频开始播放 → UC-PLAY-19 退出播放回浏览
- **添加远程源**：UC-FILE-02 展开添加源菜单 → UC-FILE-09 连接 WebDAV 服务器（或 UC-FILE-11 SMB 列出共享 → UC-FILE-12 选共享接入）→ UC-FILE-18 进文件夹扩面包屑
- **续看**：UC-LNCH-01 启动进浏览页 → UC-FILE-01 点视频开始播放 → UC-PLAY-02 询问续播
- **进环境观影**：UC-LNCH-03 切到 Environments 标签 → UC-ENV-13 环境页开独立空间 → UC-ENV-18 展开进入环境 →（沉浸播放，控件见 UC-PLAY-25 设置面板）
- **播放中切模式**：UC-FILE-01 点视频开始播放 → UC-PLAY-27 切播放模式 → UC-PLAY-26 屏幕几何调整 → UC-ENV-12 关沉浸回窗口
- **本地视频导入**：UC-FILE-03 主区 Manage 入口 → UC-FILE-43 新建文件夹，整理本地片库

## Launch（LNCH）

### Launch · 启动与主导航

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-LNCH-01 | 启动进浏览页 | 启动 app | 显示主窗口，系统 TabView 含 Files / Settings / Environments 三个标签，Files 默认选中并展示文件浏览内容 | 已验证 | FilesPlaybackUITests.testFilesScreenShowsFakeCatalog（导航实为 NavigationOrnament 三标签胶囊，非系统 TabView——表述待复核） | — |
| UC-LNCH-03 | 切换主导航标签 | 点系统 TabView 的标签 | Files / Settings 切换主区域内容页、当前标签高亮；Environments 不切页而是关主窗口、开独立环境窗口（见 UC-ENV-13），标签不驻留高亮 | 未验证 | 未覆盖 | — |

## Files（FILE）

### Files · 数据源管理

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-02 | 展开添加源菜单 | Files 页 Source Sidebar 点 more 按钮 | 二级菜单展开，含 Add、Refresh、Delete | 未验证 | 未覆盖 | — |
| UC-FILE-09 | 连接 WebDAV 服务器 | 点击 Add 展开三级菜单，点击 WebDAV | 弹出待填写的表单 | 未验证 | 未覆盖 | — |
| UC-FILE-10 | 连接超时留表单 | WebDAV/SMB 连接超时（地址不可达） | sheet 不关闭，显示橙色「连接超时：无法访问该地址」态，可重试 | 未验证 | 未覆盖 | — |
| UC-FILE-44 | 认证失败留表单 | WebDAV/SMB 凭据被服务器拒绝 | sheet 不关闭，显示红色「连接失败：认证被拒绝」态，可重试 | 未验证 | 未覆盖 | — |
| UC-FILE-11 | SMB 列出共享 | Add SMB Server 表单填地址点 Connect，连接成功 | 表单切换为该服务器的共享文件夹列表（锚 `FileBrowsing-DataSourceConfig-button-share-*`） | 未验证 | 未覆盖 | — |
| UC-FILE-12 | 选共享接入 | 在 SMB 共享列表点一个共享 | sheet 关闭，侧栏新增该源（名称 "地址/share" 或自定义）并标活跃，主区域显示共享根目录 | 未验证 | 未覆盖 | — |
| UC-FILE-13 | SMB 无共享提示 | SMB 登录成功但服务器无可访问共享 | 列表显示 "No shares found on this server." | 未验证 | 未覆盖 | — |
| UC-FILE-45 | SMB 访客连接 | Add SMB Server 表单开「以访客身份连接」开关 | 账号/密码字段隐藏，以访客身份连接（无需凭据） | 未验证 | 未覆盖 | — |
| UC-FILE-46 | 连接中锁输入 | WebDAV/SMB 连接中或成功态 | 表单地址/凭据/开关与 Connect 按钮禁用（防中途修改），成功后短暂显示「连接成功」并自动关闭 | 未验证 | 未覆盖 | — |
| UC-FILE-14 | SMB 地址接受主机名 | SMB 地址框输入 | 接受 IP 或主机名（如 `192.168.1.10` 或 `mynas.local`），不强制只数字和点 | 未验证 | 未覆盖 | — |
| UC-FILE-15 | 凭据免重输 | 连接过的远程源，重启 app 后在侧栏点它 | 直接连上并显示内容，无需重新输入用户名密码（凭据存 Keychain） | 未验证 | 未覆盖 | — |
| UC-FILE-16 | 切换数据源 | 点侧栏另一个已保存数据源 | 活跃源指示点移到该源、其余源不显示指示点（走 token，非裸色），主区域刷新为该源内容 | 未验证 | 未覆盖 | — |
| UC-FILE-17 | 删远程源回本地 | Source Sidebar 滑动删除一个远程源 | 该源从列表移除、凭据删除；若它是活跃源，自动回到 Local Storage | 未验证 | 未覆盖 | — |
| UC-FILE-47 | 多选删除数据源 | Source Sidebar more 菜单选 Delete 进入多选模式 | 可删源行显勾选框 + 计数，红色删除按钮删除选中源 | 未验证 | 未覆盖 | — |
| UC-FILE-48 | 离线源置灰 | 某源未启用/不可达 | 该源行置灰（降透明度、次级色）显示为不可用 | 未验证 | 未覆盖 | — |
| UC-FILE-35 | 拖拽重排数据源 | Source Sidebar 长按拖拽一个来源条目 | 来源顺序随拖拽改变并保持 | 未验证 | 未覆盖 | — |
| UC-FILE-36 | 侧栏显示存储条 | 查看 Source Sidebar 底部 | 显示设备总存储与已用空间的容量条 | 未验证 | 未覆盖 | — |

### Files · 本地文件管理

> 文件来源管理（上）与本地文件管理（本簇）分属不同管理层级：前者管「接入哪些源」，后者管「Local Storage 内的内容」。本地文件管理入口 = Files 主区 Manage 按钮（见 ADR 0006）。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-03 | 打开本地管理菜单 | Files 主区点 Manage 按钮 | 显示本地管理菜单，含：添加 Photos / Use Documents / 新建文件夹 / 多选 | 未实现 | 未覆盖 | — |
| UC-FILE-04 | 用 App 文件目录 | Manage → "Use Documents" 或 "Photos" | 主区域显示 系统 Documents/Photos 内容 | 未实现 | 未覆盖 | — |
| UC-FILE-05 | 导入视频成功 | 选择相册或文件内视频文件，并点击导入 | 文件复制进 Documents | 未实现 | 未覆盖 | — |
| UC-FILE-06 | 导入跳过重名 | 导入选中与 Documents 已有同名的文件 | 该文件被跳过，消息含 "Skipped duplicates: <文件名>" | 未实现 | 未覆盖 | — |
| UC-FILE-07 | 授权接入 | Manage → "Photos" / "Use Documents" 时 | 在系统权限弹窗允许 | 未实现 | 未覆盖 | — |
| UC-FILE-08 | 授权被拒 | Photos 权限弹窗选拒绝 | 显示空界面（见 UC-FILE-23） | 未实现 | 未覆盖 | — |
| UC-FILE-41 | 多选删除本地文件 | Manage → 多选模式，勾选若干文件后删除 | 选中文件/文件夹从磁盘删除（Grid/List 两种排布均可） | 未实现 | 未覆盖 | — |
| UC-FILE-42 | 多选移动本地文件 | Manage → 多选模式，勾选若干文件后移动到目标文件夹 | 选中文件移入目标文件夹，原位置移除 | 未实现 | 未覆盖 | — |
| UC-FILE-43 | 新建文件夹 | Manage → 新建文件夹 | Local Storage 出现一个新文件夹 | 未实现 | 未覆盖 | — |

### Files · 浏览与导航

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-18 | 进文件夹扩面包屑 | 点一个文件夹卡片（锚 `FileBrowsing-ContentGrid-button-folder-*`） | 主区域加载该文件夹内容，面包屑正确显示 | 未验证 | 未覆盖 | — |
| UC-FILE-19 | 面包屑回跳 | 点面包屑（PathBreadcrumbMenu） | 显示二级菜单，内含直到根目录的所有目录，点击可跳转至目标目录 | 未验证 | 未覆盖 | — |
| UC-FILE-20 | 排序即时生效 | 点排序按钮（锚 `FileBrowsing-Toolbar-button-sort`）选 Name / Date Modified / Size 或反转方向 | 文件列表立即按所选键与方向重排，菜单中当前项带勾、方向另有箭头表达 | 未验证 | 未覆盖 | — |
| UC-FILE-32 | 下拉刷新 | 主内容区下拉 | 重新加载当前目录，期间显示加载态（见 UC-FILE-24） | 未验证 | 未覆盖 | — |
| UC-FILE-33 | 文件名搜索 | 工具栏搜索框（SearchInputCapsule）输入关键词 | 列表实时过滤为匹配文件 | 未验证 | FileBrowsingViewModel.displayedFiles/displayedFolders 实时过滤（已实现；E2E 未自动化） | — |
| UC-FILE-34 | 网格列表视图切换 | 工具栏视图切换胶囊（ViewModeCapsuleControl）切 Grid / List | 内容区在 GridCard 网格与 FileListGroup 列表两种布局间平滑切换 | 未验证 | 未覆盖 | — |
| UC-FILE-37 | 浏览历史前后退 | 点工具栏前进/后退胶囊（NavBackForwardCapsuleControl） | 在浏览历史中后退/前进，无历史方向的按钮禁用 | 未验证 | FileBrowsingViewModel.forwardPathStack/navigateForward/canNavigateForward（已实现；E2E 未自动化） | — |
| UC-FILE-38 | 显示条目计数 | 浏览任意目录 | 工具栏下方右侧显示 "{N} items" 计数，随内容变化更新 | 未验证 | 未覆盖 | — |

### Files · 文件项与卡片

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-01 | 点视频开始播放 | Files 页已有可用数据源；点一个视频文件 | 直接进入播放（呈现模式按内容自动路由） | 已验证 | FilesPlaybackUITests.testTappingFilmCardOpensPlayer | — |
| UC-FILE-26 | 已看卡片显进度 | gaze 播放过的文件 | 该卡片底部显示已观看进度描边（走进度 token，非裸色） | 未验证 | 未覆盖 | — |
| UC-FILE-39 | 悬停浮现卡片徽章 | 视线/指针悬停一张 GridCard | hover：卡片浮起，浮现角标（HDR / MV-HEVC 等）、文件大小与时长；文件夹卡浮现 "N items" | 未验证 | 未覆盖 | — |

### Files · 状态与边界

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-FILE-23 | 空文件夹空态 | 进入无文件夹且无可播文件的目录；或权限被拒、Local Storage 为空 | 显示空白页：只显示按钮、无内容，此时禁用刷新与多选 | 未验证 | FakeFileDataSourceTests.emptyFolderIsEmpty（空目录数据层单元；UI 空态未自动化） | — |
| UC-FILE-24 | 加载转圈 | 切源、刷新或导航触发加载 | 显示加载转圈组件（LoadingSpinner）动画，加载完显示真实内容 | 未验证 | 未覆盖 | — |
| UC-FILE-28 | 断连保列表弹警 | 浏览远程源时网络断开/服务器离线 | 列表保留上次内容不清空，弹 "File Browser Error" 对话框含 Retry / OK，OK 回 Local Storage；再点该源成员触发加载重试 | 未验证 | FakeFileDataSourceTests.failureModeThrows（失败态数据层单元；UI 弹框未自动化） | — |

## Settings（SET）

### Settings · Playback

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-01 | 设续播策略 | Settings → Resume Behavior（锚 `Settings-Playback-picker-resumePolicy`）选 Ask Every Time / Always Resume / Always Start Over 之一 | 下次播放已看过的视频时按所选策略处理（见 UC-PLAY-02/03/04） | 未验证 | 未覆盖 | — |
| UC-SET-02 | 设结束行为 | Settings → When Video Ends（锚 `Settings-Playback-picker-endBehavior`）选 Stop / Loop Single Episode / Play Next | 视频播完按所选行为执行（见 UC-PLAY-22） | 未验证 | 未覆盖 | — |
| UC-SET-13 | 设控件隐藏时长 | Settings → Controls Auto-Hide 选 5 / 8 / 15 秒 / Never | 播放控件按所选秒数无交互后自动隐藏；选 Never 则不隐藏 | 未验证 | 未覆盖 | — |

### Settings · Spatial Content

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-07 | 默认环境首选项 | Settings → Default Environment（锚 `Settings-SpatialContent-picker-environment`）选环境（命名待定，MVP 2–3 个） | 默认进入的环境切换为所选项，也体现在环境卡中 | 未验证 | 未覆盖 | 沉浸 |
| UC-SET-14 | 设自动进入沉浸 | Settings → Enter Immersion for Spatial Content 选 Off / On | 打开对应内容时按元数据路由对应播放策略 | 未验证 | 未覆盖 | — |

### Settings · Storage & Privacy

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-08 | 显示缓存大小 | 打开 Settings 页 | Storage 区显示当前缓存大小（人类可读格式，空时 "Empty"，锚 `Settings-Storage-label-cacheSize`） | 未验证 | 未覆盖 | — |
| UC-SET-09 | 清缓存带确认 | 点 Clear Cache（锚 `Settings-Storage-button-clearCache`）并在对话框确认 | 弹确认对话框（Clear/Cancel）；确认后缓存清空，按钮显示瞬时反馈（"Cleared" + 勾，自动回弹），缓存大小刷新 | 未验证 | 未覆盖 | — |
| UC-SET-29 | 清最近播放进度 | Storage & Privacy → Clear Recent Playback & Progress 选范围（全部 / 30 天前 / 90 天前）并确认 | 弹确认对话框，确认后清除本地最近播放记录与续播进度（不删媒体与远程源） | 未验证 | 未覆盖 | — |
| UC-SET-17 | 显示隐私声明 | Settings → Storage & Privacy 的 Privacy Notice（disclosure） | 展开显示隐私声明键值（Local Files / Photos / Remote Credentials / Diagnostics） | 未验证 | 未覆盖 | — |

### Settings · Diagnostics & Tools

> 工程/诊断分类（原名 Advanced，2026-06-18 改名 Diagnostics & Tools 以与播放面板 Picture 区分）。按「用户可观察划线」：带确认/持久副作用/可见效果的动作各立用例；纯只读诊断披露并入 UC-SET-20 一条。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-20 | 只读诊断面存在 | Settings → Diagnostics & Tools 分类 | 显示只读诊断披露（Route Snapshot / Media Inspector / HDR-EDR 状态 / Safe mpv Preset 概览等）。**纯只读披露不逐项立用例**；本行只记录该面存在 | 未验证 | 未覆盖 | — |
| UC-SET-21 | 重置引擎覆盖 | Diagnostics & Tools → Reset All Engine Overrides 并确认 | 弹确认对话框，确认后引擎诊断覆盖回到干净会话态 | 未验证 | 未覆盖 | — |
| UC-SET-22 | 重置环境屏位 | Diagnostics & Tools → Reset Environment Screen Position 选范围（当前/全部）并确认 | 弹确认（文案声明仅重置已存屏幕摆位、不动文件与源），确认后所选环境的屏位重置 | 未验证 | 未覆盖 | 沉浸 |
| UC-SET-23 | 设日志级别 | Diagnostics & Tools → Log Level 选级别 | 日志详细度切换并持久 | 未验证 | 未覆盖 | — |
| UC-SET-24 | 清日志 | Diagnostics & Tools → Clear Logs 并确认 | 弹确认对话框，确认后本地日志清空（瞬时反馈） | 未验证 | 未覆盖 | — |
| UC-SET-25 | 性能 HUD 开关 | Diagnostics & Tools → Performance HUD 切换 | 屏上性能 HUD 叠层显示/隐藏 | 未验证 | 未覆盖 | — |
| UC-SET-26 | 远程源连接测试 | Diagnostics & Tools → Remote Source Connection Test | 对当前远程源跑连接测试，显示结果（瞬时 Queued 反馈） | 未验证 | 未覆盖 | — |
| UC-SET-27 | 重连当前源 | Diagnostics & Tools → Reconnect Current Source | 尝试重建当前源连接 | 未验证 | 未覆盖 | — |
| UC-SET-28 | 导出诊断包 | Diagnostics & Tools → Export Diagnostic Package | 发起诊断包导出（瞬时 Queued 反馈） | 未验证 | 未覆盖 | — |

### Settings · About

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-11 | 显示版本构建号 | 打开 Settings 页 About 区 | 显示 Version 与 Build（取自 Info.plist），可复制 | 未验证 | 未覆盖 | — |
| UC-SET-18 | 查看开源许可 | About → Open-source Licenses 点 "View" | 打开开源许可列表 | 未验证 | 未覆盖 | — |
| UC-SET-19 | 反馈 | About → Feedback | 展示反馈邮箱，提供 Copy 复制（瞬时 "Copied" 反馈） | 未验证 | 未覆盖 | — |

### Settings · 框架（导航与持久化）

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-SET-16 | 分类侧栏切内容 | Settings 页点左侧 CategorySidebar 的分类（Playback / Spatial Content / Storage & Privacy / Diagnostics & Tools / About） | 右侧内容淡入切换为该分类的设置组，选中分类高亮 | 已验证 | SettingsUITests.testNavigatingToSettingsAndSwitchingCategory（注：分类为 Playback/Spatial/Diagnostics/About 四类，Storage&Privacy 长尾未绑定） | — |
| UC-SET-12 | 偏好重启保留 | 修改续播策略 / 结束行为 / 默认环境 / 进沉浸开关 / 控件隐藏时长后重启 app | 各项设置保持修改后的值 | 已验证 | PreferencesPersistenceTests.testUserDefaultsStoreRoundTripsExtendedFields（UserDefaults 跨实例往返） | — |

## Playback（PLAY）

### Playback · 传输与进度

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-05 | 播放暂停切换 | 点中央播放/暂停按钮 | 播放 ⟷ 暂停切换，图标随状态变化（play.fill / pause.fill） | 未验证 | 未覆盖 | — |
| UC-PLAY-06 | 播完按钮变重播 | 视频播放至末尾（结束行为为 Stop） | 中央按钮变重播图标（文案 "Replay"），点击从头播放 | 未验证 | 未覆盖 | — |
| UC-PLAY-07 | 快进十秒 | 点快进按钮（goforward.10） | 播放位置 +10 秒，画面跳转 | 未验证 | 未覆盖 | — |
| UC-PLAY-08 | 快退十秒 | 点快退按钮（gobackward.10） | 播放位置 −10 秒（不低于 0），画面跳转 | 未验证 | 未覆盖 | — |
| UC-PLAY-09 | 拖动进度跳转 | 拖动进度条（锚 `PlayerUI-SeekBar-slider-position`）后放开 | 播放位置跳到目标点，跟随 thumb 的浮动气泡显示当前/剩余时间码 | 未验证 | 未覆盖 | — |

### Playback · 精度时间轴

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-17 | 双击展开时间轴 | 双击 scrubber thumb | 出现 NLE 精度时间轴面板（`PrecisionTimelineView`）：刻度尺、胶片条、帧步进按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-18 | 逐帧步进 | 精度时间轴点前帧/后帧按钮（需媒体帧率已知） | 播放位置精确移动一帧，画面逐帧变化 | 未验证 | 未覆盖 | — |
| UC-PLAY-31 | 时间轴缩放与拖播放头 | 精度时间轴拖 zoom 滑杆缩放，或拖动刻度尺/胶片条 | 时间轴按缩放重绘；拖动改变 currentTime，画面跟随 | 未验证 | 未覆盖 | — |

### Playback · ⋯ 轨道菜单

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-11 | 打开 ⋯ 菜单 | 点 `⋯` 更多菜单按钮 | 弹出菜单，含 Subtitles / Audio Track / Playback Speed / Episodes，可展开子菜单 | 未验证 | 未覆盖 | — |
| UC-PLAY-12 | 切音轨即时生效 | ⋯ 菜单 → Audio Track 选另一条音轨 | 音频立即切换，选中轨带勾标记，无需重新加载 | 未验证 | 未覆盖 | — |
| UC-PLAY-13 | 切字幕与关闭 | ⋯ 菜单 → Subtitles 选某字幕轨、Auto 或 Off | 选轨则显示该字幕，Auto 按音轨语言自动选，Off 隐藏全部字幕，选中项带勾 | 未验证 | 未覆盖 | — |
| UC-PLAY-14 | 切播放倍速 | ⋯ 菜单 → Playback Speed 选 0.25×~5.0×（0.25/0.5/0.75/1/1.25/1.5/2/3/5×） | 播放速度立即变化，选中档带勾 | 未验证 | 未覆盖 | — |
| UC-PLAY-29 | 切剧集 | ⋯ 菜单 → Episodes 选一集 | 跳转到所选剧集（同文件夹/季内的另一视频文件）播放 | 未验证 | 未覆盖 | — |

### Playback · 播放设置面板（≡）

> 由 Deck 左侧 `≡` 打开，作为独立窗口（SwiftUI `Window`）呈现；沉浸/全景模式下复用同一套窗口播放控件。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-25 | 打开播放设置面板 | 点 Deck 左侧 `≡` 按钮 | 打开播放设置面板，左侧分类（Environment Setting / Play Mode / Picture）+ 右侧详情 | 未验证 | 未覆盖 | — |
| UC-PLAY-26 | 屏幕几何调整 | 面板 → Environment Setting 调屏幕曲率 / 高度 / 距离 / 大小 / 位置，或恢复默认 | 虚拟屏幕实时按参数变化（沉浸效果见 UC-ENV-08，延期） | 未验证 | 未覆盖 | 沉浸 |
| UC-PLAY-27 | 切播放模式 | 面板 → Play Mode 切 3D / 180° 沉浸 / 360° 沉浸 三个开关 | 3D 反映源立体能力（源为 2D 时禁用）；180°/360° 互斥开关切换对应投影/沉浸呈现（沉浸效果见 UC-ENV-03/04，延期） | 未验证 | 未覆盖 | — |
| UC-PLAY-28 | 调 Picture 画面参数 | 面板 → Picture 调任一参数（按 list-group 分区） | 画面即时按该参数变化；参数全集见**附录·Picture 画面参数**；只读项以信息行展示不可交互 | 未验证 | 未覆盖 | — |

### Playback · 控件显隐与窗口

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-15 | 控件自动隐藏 | 播放中无交互达 Controls Auto-Hide 设定秒数（见 UC-SET-13） | 所有控件淡出隐藏 | 未验证 | 未覆盖 | — |
| UC-PLAY-16 | 交互唤回控件 | 控件隐藏后对画面空间点按 | 控件淡入重现 | 未验证 | 未覆盖 | — |
| UC-PLAY-19 | 退出播放回浏览 | 点顶栏返回按钮 | 停止播放、记录进度、返回文件浏览 | 未验证 | 未覆盖 | — |
| UC-PLAY-30 | 进入沉浸环境 | 点顶栏展开按钮 | 切换为虚拟环境，屏幕移动到虚拟屏幕 | 未实现 | 未覆盖 | — |
| UC-PLAY-32 | 窗口播放 resize | 拖窗口边角 | 播放 render surface 按 16:9 等比在 min 960×540 / ideal 1280×720 / max 1600×900 间缩放跟随（app 实现的 `requestGeometryUpdate`，非系统窗口 bar 行为；证据见 `DesignPreview/docs/window-playback-preview-fixture.md`） | 未验证 | 未覆盖 | 窗口 |

### Playback · 续播与加载生命周期

> 本簇运行时逻辑留待 FakeApp 接模拟管线阶段；resume 提示 / 加载 / Failed-to-Load 的视觉壳本轮新建（见 ADR 0006），缓冲等纯运行时项仍蓝图。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-PLAY-02 | 询问续播 | 续播策略为 Ask，开始播放有进度（>5s）的视频 | 播放前弹续播选择："Resume from HH:MM:SS" 主按钮与 "Play from Start" 次按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-03 | 记住续播选择 | 续播提示里勾「记住选项」 | 应用选项，以小字形式可勾选出现，后续不再提醒 | 未验证 | 未覆盖 | — |
| UC-PLAY-04 | 总是重头播放 | 续播策略为 Always Start Over，开始播放有进度的视频 | 不询问，直接从头播放 | 未验证 | 未覆盖 | — |
| UC-PLAY-21 | 加载中转圈提示 | 选片后媒体加载阶段 | 黑屏，加载进度指示，加载完成后隐藏 | 未验证 | 未覆盖 | — |
| UC-PLAY-22 | 按设置执行结束行为 | 视频播完，结束行为设为 Loop Single Episode 或 Play Next | Loop Single Episode 自动从头重播本集；Play Next 自动播下一个文件 | 未验证 | 未覆盖 | — |
| UC-PLAY-23 | 加载失败可重试 | 文件损坏/不支持/网络失败导致加载失败 | 显示 "Failed to Load" 错误面板含原因描述，提供 Retry 与 Close 按钮 | 未验证 | 未覆盖 | — |
| UC-PLAY-24 | 缓冲显示指示 | 网络源播放中缓冲不足 | 画面出现缓冲加载，恢复后自动消失 | 未实现 | 未覆盖 | — |

## Environment（ENV）

### Environment · 环境选择

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-ENV-13 | 环境页开独立空间 | 点系统 TabView 的 Environments 标签 | 主窗口关闭，打开独立 volumetric 环境窗口，环境卡片轮播（EnvironmentCardCarousel）展示可选环境（占位 7 张，MVP 2–3 个，命名待定） | 未验证 | 未覆盖 | — |
| UC-ENV-14 | 环境页返回主窗 | 环境窗口点返回按钮 | 返回 TabView，主窗口恢复到进入前的标签（窗口 bar 关闭 = 退出该 volume，属系统行为） | 未验证 | 未覆盖 | — |
| UC-ENV-15 | 环境过渡守卫 | volume ↔ 主窗切换过渡中重复触发 | 过渡期防重复，过渡完成后恢复（`isEnvironmentTransitionInFlight`） | 未验证 | 未覆盖 | — |
| UC-ENV-16 | 卡片元数据展示 | 浏览环境卡片轮播 | 中心卡片显示背景图、标题、环境编号、引语、模式、氛围 | 未验证 | 未覆盖 | — |
| UC-ENV-17 | 轮播浏览磁吸 | 水平拖拽环境卡片轮播 | 卡片随拖拽 3D 深度叠放、磁吸对齐到最近卡 | 未验证 | 未覆盖 | — |
| UC-ENV-18 | 展开进入环境 | 中心卡片点展开按钮 | 接入 `xrplay_scene` 真实场景并成功进入（视频帧进 RCP3 场景，mpv 已验证）；进入后控件复用窗口播放控件（见 UC-PLAY-25） | 未实现 | 未覆盖 | 沉浸, 全景 |
| UC-ENV-19 | 空/单卡轮播态 | 环境卡片轮播为 0 或 1 个环境 | 布局降级（不报错；磁吸/深度叠放退化为单卡居中或空态） | 未实现 | 未覆盖 | — |

### Environment · 沉浸呈现

> 本簇行为有真实底座，留给「接管真实 Demo」阶段验证。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-ENV-02 | 立体内容 | 播放 SBS / TopBottom 立体视频 | 自动路由对应立体模式播放 | 未验证 | 未覆盖 | 沉浸 |
| UC-ENV-03 | 进沉浸开虚拟屏 | 以 Immersive 模式开始播放（或播放中切入） | 主窗口让位，沉浸空间打开，3D 空间中浮现虚拟屏幕与所选环境穹顶 | 未验证 | 未覆盖 | 沉浸 |
| UC-ENV-04 | 进全景开球面 | 全景内容以 Panorama 模式播放 | 全景球面包裹用户（360° 全球 / 180° 半球按内容投影），无虚拟屏幕 | 未验证 | 未覆盖 | 全景 |

### Environment · 沉浸内调整（延期·留给定稿前端接管真实 Demo）

> 控件复用窗口播放控件，作为独立窗口出现（见 UC-PLAY-25/26/27）；本簇记录沉浸效果侧的可观察结果。屏幕几何参数以播放面板那套（曲率/高度/距离/大小/位置）为权威，本簇真做时对齐。

| ID | 简名 | 触发·前置 | 预期可观察结果 | 验证状态 | 关联测试 | 模式适用 |
|---|---|---|---|---|---|---|
| UC-ENV-05 | 播放中切模式 | 播放中切到另一呈现模式（控件见 UC-PLAY-27） | 呈现切换到所选模式 | 未验证 | 未覆盖 | — |
| UC-ENV-06 | 过渡期禁操作 | 沉浸空间打开/关闭过渡中 | 过渡中软件禁用用户输入 | 未验证 | 未覆盖 | — |
| UC-ENV-07 | 播放中换环境 | 沉浸空间打开时换另一环境 | 切换过渡中软件禁用用户输入 | 未验证 | 未覆盖 | 沉浸 |
| UC-ENV-08 | 调节屏幕位置 | 调屏幕曲率/高度/距离/大小/位置或点预设（控件见 UC-PLAY-26） | 虚拟屏幕实时按参数移动/弯曲 | 未验证 | 未覆盖 | 沉浸 |
| UC-ENV-09 | 屏位随环境记忆 | 在环境 A 调过屏幕位置后切到环境 B 再切回 A | 环境 A 恢复其独立保存的屏幕位置（重置入口见 UC-SET-22） | 未验证 | 未覆盖 | 沉浸 |
| UC-ENV-10 | 空间点按切控件 | 沉浸/全景中对虚拟屏或球面做空间点按 | 播放控件显隐切换 | 未验证 | 未覆盖 | 沉浸, 全景 |
| UC-ENV-12 | 关沉浸回窗口 | 关闭沉浸空间 | 沉浸空间关闭，主窗口恢复，播放回 Window 模式继续 | 未验证 | 未覆盖 | — |

---

## 成功指标（占位·未定义）

本节空缺。成功指标 = 产品层「做好了」的可度量标准（性能、体验阈值），与单条用例的「预期可观察结果」不同层。
空缺原因：待管线技术验证与大规模测试设计阶段一并定义。填充责任：人类发起，agent 起草。
**在此之前，任何 agent 不得自行发明指标。**

## 附录·Picture 画面参数（libplacebo）

`UC-PLAY-28` 的规范来源。播放设置面板 → Picture 分区按 list-group 渲染下列参数，调任一项即时改变画面。参数源 = mpv（gpu-next / libplacebo）暴露的可调项（出处：`~/Applications/mpv/xr-fork/verify-visionos`）。**mpv 选项名为稳定键（锚点），「官方名」为面板显示名**；只读项以信息行展示、不可交互。

### 峰值检测（Peak Detection）

| 官方名 | mpv 选项（键） | 类型/范围·默认 |
|---|---|---|
| 动态峰值检测 | `hdr-compute-peak` | 枚举 auto/yes/no · auto |
| 峰值百分位 | `hdr-peak-percentile` | 90–100 · 99.9 |
| 峰值平滑率 | `hdr-peak-decay-rate` | 1–100 · 20 |
| 换场阈值·低 | `hdr-scene-threshold-low` | 0–20 · 1.0 |
| 换场阈值·高 | `hdr-scene-threshold-high` | 0–20 · 3.0 |

### 输出目标（Output Target）

| 官方名 | mpv 选项（键） | 类型/范围·默认 |
|---|---|---|
| 输出色域（只读） | `target-prim` | 只读信息 · display-p3 |
| 输出传递曲线（只读） | `target-trc` | 只读信息 · linear |
| 目标峰值亮度 (nits) | `target-peak` | 100–2000 · 406 |
| HDR 参考白 (nits) | `hdr-reference-white` | 50–1000 · 183 |
| 目标对比度 / 黑位 | `target-contrast` | 枚举 inf/auto/100000/10000/1000 · inf |

### 色调映射（Tone Mapping）

| 官方名 | mpv 选项（键） | 类型/范围·默认 |
|---|---|---|
| 色调映射曲线 | `tone-mapping` | 枚举（bt.2390/bt.2446a/spline/…）· bt.2390 |
| 曲线参数 | `tone-mapping-param` | 0–2 · 0 |
| 反向色调映射 | `inverse-tone-mapping` | 开关 · no |
| 最大提亮倍数 | `tone-mapping-max-boost` | 1–10 · 1 |
| 对比度恢复 | `hdr-contrast-recovery` | 0–2 · 0.15 |
| 对比度恢复平滑度 | `hdr-contrast-smoothness` | 1–100 · 100 |

### 色域与色彩（Gamut & Color）

| 官方名 | mpv 选项（键） | 类型/范围·默认 |
|---|---|---|
| 色域映射模式 | `gamut-mapping-mode` | 枚举（clip/perceptual/…）· clip |
| 饱和度 | `saturation` | -100–100 · 9 |
| 亮度 | `brightness` | -100–100 · 0 |
| 对比度 | `contrast` | -100–100 · 10 |
| 伽马 | `gamma` | -100–100 · 1 |
| 色相 | `hue` | -100–100 · 0 |

### 诊断（Diagnostics）

| 官方名 | mpv 选项（键） | 类型·默认 |
|---|---|---|
| 可视化色调曲线 | `tone-mapping-visualize` | 开关 · no |
| 色域越界标红 | `gamut-mapping-warn`（快捷切 warn↔clip） | 按钮 |

## 退役名单（只追加）

UC-LNCH-02 — 退役 2026-06-12：窗口关闭/重启的生命周期归 visionOS 管理，非 app 承诺（评审期删除）
UC-PLAY-01 — 退役 2026-06-12：详情面板取消，点视频直接播放，并入 UC-FILE-01（评审期删除）
UC-ENV-01 — 退役 2026-06-12：详情面板取消，呈现模式在播放中切换（UC-ENV-05）（评审期删除）
UC-FILE-21 — 退役 2026-06-17：过滤功能取消（用户手改划除）
UC-FILE-22 — 退役 2026-06-17：过滤功能取消（用户手改划除）
UC-FILE-25 — 退役 2026-06-17：卡片元数据 hover 展示并入 UC-FILE-39（用户手改划除）
UC-FILE-29 — 退役 2026-06-17：最近播放取消（用户手改划除）
UC-FILE-30 — 退役 2026-06-17：最近播放取消（用户手改划除）
UC-FILE-31 — 退役 2026-06-17：最近播放取消（用户手改划除）
UC-SET-03 — 退役 2026-06-17：全局默认倍速取消，倍速仅在播放器 ⋯ 菜单（UC-PLAY-14）
UC-SET-04 — 退役 2026-06-17：沉浸开关移至场景侧（Environment 章）
UC-SET-05 — 退役 2026-06-17：沉浸风格移至场景侧（Environment 章）
UC-SET-06 — 退役 2026-06-17：屏幕形状移至播放设置面板（UC-PLAY-26）
UC-SET-10 — 退役 2026-06-17：缓存空禁用并入 UC-SET-09 负路径
UC-PLAY-20 — 退役 2026-06-17：顶栏不显示元数据信息条

（格式：`UC-XXX-NN — 退役 YYYY-MM-DD：一句话原因`。退役条目从正文删行，原文去 git history 查。）
