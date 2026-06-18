# FakeApp 组装作战地图 — 前端定稿组装

- Purpose: 本轮作战地图。把打磨好的前端组装成将来要发布的真 app(数据先用假管线),并接入美术导出的 3D 场景。每个目标配验证手段。
- Status: Active(计划已与用户拍板,未开工)。
- **执棒者:mac**(本轮触 visionOS 表面 + 模拟器,证据归 mac 侧)。

## 这是什么(一句话)

FakeApp = 将来要发布的那个 app 本身,只是文件列表、播放、设置、3D 场景背后暂时接的是假数据/假引擎;以后把假的换成真的,app 直接发布、不重写。

## 拍板的决定(2026-06-18,grill 访谈)

1. **本体**:FakeApp 就是真 app,屏幕背后全是假数据(假读 SMB、假解码);日后换真适配器即发布,不重做。
2. **前端**:打磨好的 DesignPreview 组件成为真 app 的屏幕;旧 XrPlayer 视图(ContentGridView / FileBrowserView / DataSourceConfigView / PlayerControlsView / NLETimelineView / VideoDetailView / SettingsView)退役;控件内部标识(accessibilityIdentifier)从旧视图迁到新组件。
3. **3D 场景**:美术导出的 `world` 场景**复制一份**进本仓,在沉浸空间里**真加载**,取代手搓的程序化球顶 `EnvironmentDomeEntity`;mpv 视频屏仍是单独实体、合成在场景前面。
4. **点视频**:点一个视频 → 开播放窗、关主窗;返回 → 关播放窗、主窗回到离开时的标签。必须复用生产单一启动路径 `PlaybackLaunchCoordinator`、单一沉浸开启路径 `MainView.openImmersiveSpaceUnified`,不另开口子。
5. **验证**:精简自动化——能自动测的只覆盖确定性流程;差异化感知(真 HDR 亮度、立体景深、久看舒适)真机+人看;`swift test` 守纯逻辑;用例表 `关联测试` 列就是追溯表(测试名 `UC_<前缀>_<序号>`,挂迁移后的新锚点);补 `.xctestplan` 把已有 swift 测试纳进 scheme,堵假绿。

## 验证手段的四种标记

- **单元** — 纯逻辑,`swift test`,不开界面。
- **模拟器·自动** — 在模拟器里跑自动化 UI 测试,断言结果。
- **模拟器·看** — 我把 app 启动起来,观察/截图确认(含用指针在模拟器里模拟注视/拖拽)。
- **真机·人** — 只有戴头显的人能判断的感知品质。

## 核对修正与进展(2026-06-18,branch `claude/fakeapp-assembly`)

开工前跑了只读核对 workflow,逐条对真代码。计划主体准,关键修正:

- **批0 启动断言反了**:冷启动本就进主界面(旧 browse/recent/settings + `FileBrowserView`),不是临时播放窗(自动播放只在 `XRPLAYER_SMOKE_TEST=1` 测试 harness)。真实工作=换新词表+新组件,不是"改掉临时播放窗"。
- **批2 误判(会白改成熟代码)**:`WindowVideoViewModel` 已完全 `playbackState` 驱动(成熟生产代码),init 布尔只在 DesignPreview 视觉稿。**别改 ViewModel**;批2真实工作=造假播放源接入 + DesignPreview 组件接到 app。
- **批1 协议层比计划成熟**:`FileProviding`/`DataSourceConnecting` 已是协议、`LocalDataSourceAdapter` 已 conform、远程 adapter 已多态;只差 VM 改依赖协议(本地源构造在 `XrPlayerApp.swift:93`)。`ConnectionFormPanel` 5 态无 SMB"列共享"态(FILE-11/13 要补)。accessibilityIdentifier 实为三轨(`DesignComps-`/`DesignPreview-`/`FileBrowsing-`)。FILE-33 搜索过滤、FILE-37 前进栈未实现。
- **批3 基本准**:5 个 `UserPreferences` 字段确缺;`CategorySidebar`+`SettingsDetailContentView` 已组装(值/动作死、分类切换活);SET-07 目标锚点 `Settings-SpatialContent-picker-environment` 代码 0 命中(现状旧 `Settings-ImmersiveSpace-picker-environment`)。
- **批4 修正**:四个 ARKit 用途串全缺(只有相册串)→ 必补;Info.plist 在 `Config/XrPlayer-Info.plist`(仓库级)。

进展(截至 2026-06-18,11 commit:df09326→7e6ab59;均 visionOS 模拟器构建零错误;`swift test` 22 绿、`test_sim` 4 UI 全绿;经独立验证 workflow `fakeapp-final-verify` 对抗式核对 5 批——**0 虚报**,25 verified / 1 partial / 4 诚实声明 deferred,RKS 硬边界 grep 确认未越界):

**已完成并验证(done):**
- [x] **测试地基救活**:`swift test`(SPM 镜像模块 `XrPlayerCore`)+ 真 XCUITest + `XrPlayer.xctestplan`(scheme 指向、去 `shouldAutocreateTestPlan`)。纯逻辑走 `swift test`,UI/集成走 `xcodebuild test`+testplan。
- [x] 删两个孤儿画布 + **组件库共享化**(`SharedComponents`/`SourceSidebar` 搬入 `XrPlayer/Shared/Components/`,白名单两 target 共享)。
- [x] **批0**:`NavigationTab`→files/settings/environment(Environment 不驻留主窗);新 `FilesScreen`/`SettingsScreen` 由共享组件组装接 view-model;退役 5 旧视图(FileBrowserView/ContentGridView/DataSourceConfigView/VideoDetailView/RecentlyPlayedView)+ SettingsView,零引用 clean 删。
- [x] **批1 Files**:`FilesScreen` 接 `FileBrowsingViewModel`(`LocalFileSource` 协议 + `FakeFileDataSource` 9 影片/子目录/空目录);FILE-33 搜索(`displayedFiles`)、FILE-37 前进栈(`navigateForward`)、FILE-01 直接开播(丢 `onPrepareFile`)、`SourceSidebar` `onSelectSource`(FILE-16)。UI 测试:catalog 上屏 + 点片卡开播放控件。
- [x] **批2 Playback 脊梁**:`FakePlaybackSource`(确定性 tick 时间线,组合根注入)经 `WindowVideoViewModel` 200ms 轮询驱动控件;单测 5 条;Files→播放 UI 测试绿。
- [x] **批3 Settings**:`UserPreferences` +5 字段 + `LogLevel`/`VerboseAutoOff` 枚举;`UserDefaultsStore` 跨启动持久(SET-12);`SettingsViewModel` 双向写穿 + `SettingsScreen`(CategorySidebar+SettingListGroup)绑核心持久项(SET-01/02/13/07/14/23/25/11/19);SET-07 锚点迁 `Settings-SpatialContent-picker-environment`;退役 SettingsView。UI 测试 SET-16 分类切换 + 单测 SET-12 往返。
- [x] **批4 到硬边界**:四个 ARKit Info.plist 用途串;`EnvironmentSceneMapping` 卡→world 总映射 + 单测。
- [x] **留痕**:ADR-0007(FakeApp 架构)+ ADR-0008(RCP 直接沉浸,**提案态**);`use_cases.md` 追溯列填已验证 UC。

## 第二轮全量收口(2026-06-18,branch `claude/fakeapp-assembly`)

用户指令:把所有未完成的 UI/UX 用打磨好的组件收口完;场景(RKS)已批准;别造难丢弃之物。
按 A→B→C→D→E 五阶段执行,每阶段构建+提交绿色增量。最终:**22 SPM 单测 + 5 UI 测试 + build SUCCEEDED 全绿**。

**已完成并验证(round 2):**
- [x] **Phase A 死命令**:播放窗换打磨 `PlayerControlDeck`(加可选 live 绑定接 `WindowVideoViewModel`:play/pause/replay、进度+时间气泡、字幕/音轨/倍速实时菜单、帧步进、拖动 seek、精度时间轴);新 `WindowPlayerDeckView`(底部 ornament)+ `PlaybackSettingsPanel`(leading ornament,CategorySidebar+SettingListGroup 拼 Environment/Play Mode/Picture)+ `PlaybackOverlayCard`(PLAY-23 失败卡片)。**退役 `PlayerControlsView`/`SeekBarView`/`NLETimelineView`/`MenuPopoverContent`/`SettingsPopoverContent`**。`PlaybackDeckUITests` 证明 deck 是活播放面。覆盖 PLAY-05/07/08/11/12/13/14/16/17/18/19/23/25/26/27 等(deck 可见面)。
- [x] **Phase B**:`connectToDataSource` 改可注入 `makeRemoteAdapter` 工厂(默认 nil 走真 adapter,行为不变;FILE-10/44/46 可注入测试)。
- [x] **Phase C 设置长尾**:SET-20 诊断披露(Route Snapshot/Media Inspector keyValueDetail)、SET-24/21 确认式破坏动作(confirmationDialog)、SET-08 Storage(Empty)、SET-17 Privacy Notice、SET-18 Licenses。
- [x] **Phase D1 场景 volume**:`SenseZoneVolumeRoot`(volumetric WindowGroup)托管共享 `EnvironmentCardCarousel`(7 卡);NavigationOrnament `.environment` → openWindow(volume);carousel 加 `onExpand` 经唯一沉浸入口进沉浸(程序球顶);取代 SceneSelectorView。ENV-13/14/15/16/17。
- [x] **Phase E**:SwiftLint 两条守卫扩到 `Shared/Components/`(挡裸动画/硬编码色,组件库 token 干净零误杀)。

**Phase D2 — RKS 真 `world` 加载(ENV-18):决策已定,实验阶段不落地。** 负责人已批准接法(硬边界解除),并于 2026-06-18 确认「这个大文件就没必要提交了」——**实验阶段不提交 ~43MB `.reality`、不接 RealityKitScripting 远程依赖**。沉浸沿用程序球顶(可丢弃);配方留 ADR-0008,转正后再启用。

**诚实边界(round 2):** ① `ConnectionFormPanel`(EXPLORATORY 未确认组件、在 DesignPreview)未数据驱动接入 app——本轮落工厂解耦,表单 UI 留待;② visionOS ornament 内控件在 XCUITest 命中不可靠,PLAY-05/25 细粒度点击靠 FakePlaybackSource 单测 + deck live 绑定保证,不做假绿 UI 断言;③ 设置破坏动作在假后端确认后为 no-op+反馈;④ 窗口路径下假源是否自动推进到 .playing 属 batch2 既有 launcher/VM 行为(deck 如实反映状态)。

## 总账

约 **100 个目标 + 23 项先决代码工作**,分 5 批。验证分布:绝大多数 **模拟器·自动 / 模拟器·看**,少数 **单元**,**只有 1 个 真机·人**(批 5 沉浸场景的感知品质)。一句话:这个 app 几乎全都能在模拟器里验完,真机只剩"看起来爽不爽"那一项。

> 诚实边界:批 5 里几个标"模拟器·看"的沉浸项(场景加载、空间点按),若模拟器实测信息不够,可能要升到真机——开工实测后回写。

---

## 批 0|地基(启动与装配)

**这批要达成:** 把假数据接进生产 view-model、还原启动画面、删旧屏幕和孤儿、统一导航词表、修测试假绿、SwiftLint 扩面。**使能后面每一批。**

**先决代码工作:**
- 在 FileBrowsing 抽一个文件读取协议(listContents/listFolders/resolvePlayableURL),让 `FileBrowsingViewModel` 依赖协议而非具体 `LocalDataSourceAdapter`,并写一个返回固定假片单的假实现。验证:单元(注入假源,断言 files = 假列表,不碰真磁盘)。
- 把打磨好的 `MainWindowPage` 从 DesignPreview 迁进 app target,数据改读 `FileBrowsingViewModel.files`(不再自带写死数组)。验证:构建通过 + grep 确认无硬编码数组。
- 在 `XrPlayerApp.init` 统一装配:appModel + 接假源的 viewModel + 既有 `PlaybackLaunchCoordinator`,主窗渲染迁移后的 `MainWindowPage`。验证:构建通过 + grep 确认走 launcher.beginPlayback。

| UC | 目标 | 验证 | 怎么验 |
|---|---|---|---|
| — | 启动直接进真正主界面,不再进临时播放窗 | 模拟器·看 | 冷启动,首屏是 Files/Settings/Environments 三标签主窗,不是播放窗 |
| LNCH-01 | 启动显示主窗,三标签,Files 默认选中并展示假片单 | 模拟器·自动 | 断言 rootTabView 存在、三标签、Files 选中、主区至少一张 GridCard |
| LNCH-03 | 点 Files/Settings 切内容并高亮;点 Environments 关主窗开环境窗、标签不驻留 | 模拟器·看 | 依次点三标签,观察切换/高亮/开关窗,截图 |
| — | 导航词表统一到 files/settings/environment,退役 browse/recent/settings | 单元 | grep 断言主导航只引用新词表,旧 .recent 分支无引用 |
| — | 删退役旧视图,app 仍能启动 | 模拟器·看 | 删后构建通过、grep 无残留引用、模拟器启动正常(锚点须先迁,见下条) |
| — | 旧视图控件标识迁到新组件,UI 测试锚点延续 | 模拟器·自动 | 用迁移后锚点能定位新组件控件并交互 |
| — | 删两个孤儿画布(PlayerControlPanelPage、HomeV1Page) | 模拟器·看 | grep 已确认零引用;删后 DesignPreview 三正式 Canvas 仍渲染 |
| — | 修空的 UITests 脚手架 + 提交 .xctestplan,scheme 真跑测试不假绿 | 模拟器·自动 | 写一条真 UI 测试 + 把 core 测试纳入测试计划;故意造失败断言看 scheme 变红 |
| — | SwiftLint 架构守卫扩到新前端,挡裸动画/绕 token 的值 | 单元 | 在新组件目录放裸 .easeOut/硬编码色,断言 lint 报错;移除后通过 |

**最大风险/未知:** 已有 swift 测试走 SPM、根本不在 xcodeproj 里,scheme 只挂着空的 UITests 在假绿——要让一个 `.xctestplan` 同时跑 UI 测试和这些 SPM 测试,得先验证 Xcode 能否把 SPM 测试纳入,或要不要加桥接测试 target。这条路径**先打通再落地**。次要:锚点迁移要先于删旧视图,否则丢锚点。

---

## 批 1|Files(文件浏览)

**这批要达成:** 假文件源驱动整条浏览(列表/排序/搜索/导航/状态/连接表单),打磨组件替换旧三视图。

**先决代码工作:**
- `FileBrowsingViewModel` 本地源参数从具体类加宽成协议(注意 `ownerDataSourceID` 不在协议里,要提上去)。验证:构建通过(两处真实构造点 XrPlayerApp.swift:94、MainView.swift:488 仍编译)。
- `connectToDataSource` 里 WebDAV/SMB/Photo 三个 adapter 硬构造改成可注入工厂(默认仍构造真 adapter)。验证:构建 + 默认行为不变、传假工厂走假路径。
- 新建假文件源(实现协议,种子用现有 9 条演示影片 + 假文件夹层级)。验证:单元(listContents/listFolders/resolvePlayableURL/空目录)。
- 装配层两处构造点都接假源+假工厂。验证:grep 确认无遗留 `new LocalDataSourceAdapter`。
- 用打磨组件搭新 Files 屏接 viewModel,替换 `MainView.swift:80` 的 `FileBrowserView()`,退役旧三视图。验证:构建 + grep 无旧视图引用。
- 控件标识从旧视图迁新组件并统一 `FileBrowsing-*` 前缀(去掉 DesignComps- 前缀分裂)。验证:模拟器·自动(用新锚点命中)。

| UC | 目标 | 验证 | 怎么验 |
|---|---|---|---|
| FILE-01 | 点视频卡直接开播、关主窗(不经详情页) | 模拟器·自动 | 点 .video GridCard,断言经 PlaybackLaunchCoordinator 触发、播放窗出现、主窗关 |
| FILE-02 | 侧栏 more 菜单展开 Add/Refresh/Delete | 模拟器·看 | 点 more,观察三项(Add 再展开 WebDAV/SMB) |
| FILE-09 | Add→WebDAV 弹连接表单 | 模拟器·看 | 观察 ConnectionFormPanel 含地址/账号/密码 + Connect |
| FILE-10 | 连接超时:表单不关、橙色超时态、可重试 | 模拟器·自动 | 注入超时假工厂,断言 sheet 在、超时文案、Connect 恢复可点 |
| FILE-44 | 凭据被拒:红色认证失败态、可重试 | 模拟器·自动 | 注入 401 假工厂,断言失败文案、可重试(复用 friendlyErrorMessage) |
| FILE-46 | 连接中/成功:禁用字段+按钮,成功后短暂提示并自动关 | 模拟器·自动 | 注入延迟成功假工厂,断言 isEnabled=false、成功后自动 dismiss |
| FILE-45 | SMB 访客开关:隐藏账号/密码字段 | 模拟器·看 | 切访客开关,观察字段消失、Connect 仍可点 |
| FILE-11 | SMB 连接成功后表单切到共享文件夹列表 | 模拟器·自动 | 注入返回共享名的假 SMB 工厂,断言切共享列表 *(待核:5态mock是否含共享态)* |
| FILE-12 | 点共享:表单关、侧栏新增活跃源、主区显共享根 | 模拟器·自动 | 断言 sheet 关、侧栏多出活跃源、主区刷新 |
| FILE-13 | 无共享时显 "No shares found on this server." | 模拟器·自动 | 注入空共享假工厂,断言空文案 |
| FILE-16 | 点另一已保存源:活跃点移过去且唯一,主区刷新 | 模拟器·自动 | 断言 connectToDataSource 调用、isActiveSource 唯一、内容替换 |
| FILE-17 | 滑动删除远程源:移除+删凭据;活跃源则回 Local | 模拟器·自动 | 断言 removeDataSource/deleteCredential 调用、回 Local |
| FILE-47 | more→Delete 多选模式:勾选框+计数+红删 | 模拟器·自动 | 勾两行断言计数 2、删后 savedDataSources 移除这两个 |
| FILE-48 | 未启用/不可达源行置灰 | 模拟器·看 | 种子放 isEnabled=false 源,观察置灰 |
| FILE-35 | 长按拖拽重排来源条目并保持 | 模拟器·看 | 拖一行,观察跟手、松手新序保留 |
| FILE-36 | 侧栏底部显设备总/已用容量条 | 模拟器·看 | 观察 "Storage 1.2 TB / 4 TB" + 比例胶囊 |
| FILE-03 | 点 Manage 显本地管理菜单 | 模拟器·看 | 观察 Add Photos/Use Documents/New Folder/Select |
| FILE-43 | Manage→New Folder 后 Local 出现新文件夹 | 模拟器·自动 | 断言假源 listFolders 多一个、网格出现该文件夹卡 |
| FILE-18 | 点文件夹卡:主区加载其内容,面包屑正确 | 模拟器·自动 | 断言 navigateToFolder、内容替换、breadcrumb 末段为该文件夹 |
| FILE-19 | 点面包屑展开各级,点击跳转 | 模拟器·自动 | 进两层后点面包屑,断言列出各级、点中间级跳转 |
| FILE-20 | 排序选 Name/Date/Size 或反向,列表立即重排,菜单带勾+箭头 | 模拟器·自动 | 选 Size 降序,断言 files 顺序、菜单勾、箭头朝下 |
| FILE-32 | 下拉刷新当前目录,期间显加载态 | 模拟器·自动 | 下拉,断言 loadFiles 重调、isLoading 期间显 LoadingSpinner |
| FILE-33 | 搜索框输入实时过滤列表 | 模拟器·自动 | 输入 "Dune" 断言只剩匹配卡、清空恢复 *(未实现:需加过滤逻辑)* |
| FILE-34 | 视图切换 Grid/List | 模拟器·自动 | 点 List 段断言切列表布局,再切回 |
| FILE-37 | 前进/后退胶囊在历史里前后退,无历史方向禁用 | 模拟器·自动 | 进文件夹后退回上层,根处后退禁用 *(未实现:需加历史栈)* |
| FILE-38 | 显 "{N} items" 计数随内容更新 | 模拟器·自动 | 进 9 项目录断言 "9 items",换目录断言更新 |
| FILE-26 | 看过的卡底部显已观看进度描边(走 token) | 模拟器·自动 | 种子设 fileWatchedSeconds,断言对应卡有描边、未看无 |
| FILE-39 | 悬停卡片浮起+浮现徽章/大小/时长(文件夹显 N items) | 模拟器·看 | 指针模拟注视悬停,观察浮起与浮现层 |
| FILE-23 | 空目录显空白页,刷新与多选禁用 | 模拟器·自动 | 导航到空文件夹,断言空态视图、控件禁用 |
| FILE-24 | 切源/刷新触发加载显转圈,完成显内容 | 模拟器·自动 | 注入延迟假源,断言加载期 LoadingSpinner、完成显种子 |
| FILE-28 | 远程断连:列表不清空,弹错误对话框 Retry/OK,OK 回 Local | 模拟器·自动 | 让 loadFiles 抛错,断言 files 不空、弹框、OK 回 Local |
| — | 排序纯逻辑(Name/Date/Size×升降序) | 单元 | 构造乱序数组,六种组合断言顺序(含中文/大小写) |
| — | 断连保列表纯逻辑(失败不清空 files) | 单元 | 先成功后抛错,断言 files 仍非空、错误消息已设 |

**最大风险/未知:** 主体工作量在 app 侧把 `FileBrowsingViewModel` 两处构造的本地源加宽成协议、远程 adapter 改可注入——这步动生产依赖注入,要小心不破坏真机路径。最大未知:SMB 两阶段"列共享"态(FILE-11/13)是否已在 ConnectionFormPanel 的 5 态里,缺则要补或从旧 DataSourceConfigView 迁。

---

## 批 2|Playback(窗口播放)

**这批要达成:** 假播放源驱动控件/时间轴/菜单/续播/失败态;Files→播放窗口互换走单一启动路径。

**先决代码工作:**
- 造假播放源,实现 `PlaybackControlling`,内部计时器推进 position/state,play/pause/seek/skip/setSpeed/replay/frameStep 都真改值,经 `FrameOutput` 周期吐占位帧,注入 `WindowVideoViewModel`(不接真 mpv)。验证:单元(各时序语义)。
- 4 个保留态(续播提示/Failed-to-Load/加载中/控件显隐)从 init 布尔改接 `WindowVideoViewModel.playbackState` 驱动。验证:构建通过。
- Files 点视频→开播放窗关主窗(Back 反向)接 `PlaybackLaunchCoordinator.beginPlayback`/`stopPlayback` + 窗口互换 + 恢复 tab。验证:模拟器·自动(经 coordinator,断言 begin/stop 各一次)。

| UC | 目标 | 验证 | 怎么验 |
|---|---|---|---|
| PLAY-05 | 播放/暂停切换,图标随之变 | 模拟器·自动 | 点中央键,断言 state 翻转、图标 play.fill↔pause.fill |
| PLAY-07 | 快进 +10s | 模拟器·自动 | 断言新位置=旧+10 |
| PLAY-08 | 快退 −10s,不低于 0 | 模拟器·自动 | >10s 减10;<10s 落到 0 不为负 |
| PLAY-09 | 拖进度条跳转,拖动中显时间码气泡 | 模拟器·看 | 指针拖 40%→80%,观察气泡、松手位置与帧变化 |
| PLAY-06 | 停止行为下播到末尾→中央变重播,点它从头 | 模拟器·自动 | 推到 ended,断言重播图标+Replay 标签,点后归零重播 |
| PLAY-17 | 双击进度条展开 NLE 精度时间轴(刻度/胶片/帧步进) | 模拟器·自动 | 双击 thumb,断言 PrecisionTimeline 出现、帧步进键可见 |
| PLAY-18 | 精度时间轴前帧/后帧精确移一帧 | 模拟器·自动 | 点后帧断言 +1/帧率秒,前帧 −1 帧 |
| PLAY-31 | 时间轴缩放滑杆/拖刻度移播放头,按缩放重绘 | 模拟器·看 | 拖 zoom 观察刻度密度变,拖刻度观察时间码+帧跟随 |
| PLAY-11 | ⋯ 菜单含字幕/音轨/倍速/剧集四项可展开 | 模拟器·自动 | 点 more,断言四子菜单标题,倍速能展开档位 |
| PLAY-14 | 倍速选档(0.25×–5× 九档)即时生效,选中带勾 | 模拟器·自动 | 选 2×,断言带勾、单位时间推进翻倍 |
| PLAY-12 | 选另一音轨,带勾,不重新加载 | 模拟器·自动 | 选第二轨,断言带勾、selectAudioTrack 调用、保持 playing |
| PLAY-13 | 字幕选轨/Auto/Off,选中带勾 | 模拟器·自动 | 三选项各断言带勾、selectSubtitleTrack 收对应轨或 nil |
| PLAY-29 | 剧集选一集,跳到同目录另一文件 | 模拟器·自动 | 选第二集,断言 beginPlayback 以新 URL 调用、归零重播 |
| PLAY-25 | 点设置键打开播放设置面板(三分类+详情) | 模拟器·自动 | 断言 settingsPanel 出现,侧栏 Environment/Play Mode/Picture |
| PLAY-27 | 播放模式三开关(3D/180°/360°),2D 时 3D 禁用,180/360 互斥 | 模拟器·自动 | 开 180 断言 360 自动关;2D 假源断言 3D 禁用(沉浸效果延期) |
| PLAY-26 | 环境设置调屏幕曲率/高度/距离/大小/位置或恢复默认 | 模拟器·看 | 拖各几何滑块观察取值变、恢复默认重置(虚拟屏实时位移属批5) |
| PLAY-28 | 画面区调 libplacebo 参数,只读项不可交互 | 模拟器·看 | 拖 picture-saturation 观察取值变,只读信息行不可点(像素响应待真 mpv) |
| PLAY-15 | 无交互达设定秒数后控件淡出 | 模拟器·看 | 停交互等设定秒,观察控件淡出(阈值另可单元) |
| PLAY-16 | 控件隐藏后点画面淡入重现 | 模拟器·自动 | 隐藏后点中央,断言 isChromeVisible=true、控件重现 |
| PLAY-19 | 返回:停播+记进度+关播放窗+主窗回原标签 | 模拟器·自动 | 点 back,断言 stopPlayback、进度落库、窗口互换回原 tab |
| PLAY-02 | 询问策略+有进度:播前弹续播(Resume from 时间码 / Play from Start) | 模拟器·自动 | askEveryTime+假进度,断言续播面板、主次按钮文案,点各自验证 |
| PLAY-03 | 续播提示勾"记住选项",之后不再提醒 | 模拟器·自动 | 勾记住选续播,断言 resumePolicy 写入;再开同类不弹 |
| PLAY-04 | 总是重头策略:不询问直接从头 | 模拟器·自动 | alwaysStartOver+有进度,断言不弹、从 0、无 resumePosition |
| PLAY-21 | 加载阶段显黑屏加载指示,完成隐藏 | 模拟器·看 | 假源 play 前推 loading,观察黑屏指示→playing 消失 |
| PLAY-22 | 播完:循环本集则重播,播下一集则切下一文件 | 模拟器·自动 | 两分支:repeatOne 归零续播;playNext 以下一文件 beginPlayback |
| PLAY-23 | 加载失败显 "Failed to Load" 面板含原因+Retry/Close | 模拟器·自动 | 假源抛错进 failed,断言面板、Retry 走启动路径、Close 回主窗 |
| PLAY-32 | 拖窗边角:render surface 按 16:9 在 960×540–1600×900 间钳制缩放 | 模拟器·看 | 拖边角观察保持 16:9、钳制、不变形(参 window-playback-preview-fixture.md) |

**最大风险/未知:** 假播放源要满足 `PlaybackControlling` 全部时序语义并持续供帧、且经 `WindowVideoViewModel` 注入不绕过——若它与真 mpv 行为偏差,换真源时控件链路可能返工。其次窗口互换必须严格走 `PlaybackLaunchCoordinator` 单一路径。

---

## 批 3|Settings(设置)

**这批要达成:** 假设置存储驱动所有设置项的读写与持久,打磨组件替换旧 SettingsView。

**先决代码工作:**
- 建假设置存储(实现既有 `PreferencesStoring`,内存或 UserDefaults)。验证:单元(save→load 读回一致)。
- 扩 `UserPreferences` 字段:控件自动隐藏秒数、进沉浸开关、日志级别、性能 HUD、verbose 自动关。验证:单元(新字段 save/load + 默认值)。
- 加设置视图模型,把每个设置项的 menu/toggle/value 双向绑到假存储。验证:模拟器·看(选项后右侧值即时更新、离开再回仍在)。
- 控件标识迁新组件,顺手修 SET-07 漂移(锚点定为 `Settings-SpatialContent-picker-environment`)。验证:模拟器·自动(新锚点存在、旧 ImmersiveSpace 锚点不存在)。
- 退役旧 SettingsView,设置屏改用 CategorySidebar+SettingsDetailContentView。验证:模拟器·看 + grep 无引用。

| UC | 目标 | 验证 | 怎么验 |
|---|---|---|---|
| SET-16 | 点左侧分类,右侧切到该分类设置组并高亮 | 模拟器·自动 | 点四分类,断言右侧标题=所点、被点项选中 |
| SET-01 | Resume Playback 选三选项,行值更新并存盘 | 模拟器·自动 | 选 Always Resume,断言行值变、存储写入 |
| SET-02 | End of Playback 选 Stop/Loop/Play Next,值更新并存盘 | 模拟器·自动 | 选 Play Next,断言行值、重进仍在 |
| SET-13 | Controls Auto-Hide 选 5/8/15/Never,值更新并存盘 | 模拟器·自动 | 选 15s,断言行值、重进保留 |
| SET-07 | Default Environment 选环境,成默认并存盘(锚点修正为 SpatialContent) | 模拟器·看 | 选 Starry Night,断言行值+入存储,经统一沉浸入口进入是所选环境 |
| SET-14 | Enter Immersion 选 Off/On,值更新并存盘 | 模拟器·自动 | 选 On,断言行值、重进保留 |
| SET-08 | Storage 显当前缓存大小(空显 Empty) | 模拟器·看 | 进 Storage,断言可读字节串(0 时 Empty) |
| SET-09 | Clear Cache 弹确认,确认后清空+刷新+瞬时 Cleared | 模拟器·自动 | 点→确认对话框→confirm 断言缓存归零/刷新/Cleared;cancel 断言不变 |
| SET-29 | Clear Recent & Progress 选范围弹确认,确认后清最近+进度(不删媒体/源) | 模拟器·自动 | 选 Clear All→确认文案声明不删媒体→confirm 断言最近清、源不变 |
| SET-17 | Privacy Notice 展开显四条隐私键值 | 模拟器·看 | 点展开,观察 Local Files/Photos/Remote Credentials/Diagnostics |
| SET-20 | Diagnostics & Tools 分类存在,显只读诊断披露 | 模拟器·看 | 切该分类,观察 Route Snapshot/Media Inspector/HDR-EDR/Safe mpv 等可展开 |
| SET-21 | Reset All Engine Overrides 弹确认,确认后回干净态 | 模拟器·自动 | 点→确认→confirm 断言诊断覆盖清空;cancel 不变 |
| SET-22 | Reset Environment Screen Position 选范围弹确认,确认后重置屏位 | 模拟器·自动 | 先存非默认屏位→选当前→确认文案不动文件/源→断言该环境屏位回默认 |
| SET-23 | Log Level 选 Off/Error/Info/Verbose,切换并持久 | 模拟器·自动 | 选 Verbose,断言行值、重进保留 |
| SET-24 | Clear Logs 弹确认,确认后清空+瞬时反馈 | 模拟器·自动 | 点→确认→confirm 断言日志存储清空、Cleared 反馈 |
| SET-25 | Performance HUD 开关,状态更新并存盘 | 模拟器·自动 | 点开关断言翻转、重进保留 |
| SET-26 | Remote Source Connection Test 点后瞬时 Queued 反馈 | 模拟器·看 | 点,观察短暂 Queued 后回弹 |
| SET-27 | Reconnect Current Source 点后瞬时反馈 | 模拟器·看 | 点,观察短暂反馈后回弹 |
| SET-28 | Export Diagnostic Package 点后瞬时 Queued 反馈 | 模拟器·看 | 点,观察短暂 Queued 后回弹 |
| SET-11 | About 显 Version/Build(取自 Info.plist)可 Copy | 模拟器·看 | 断言版本号=Info.plist,点 Copy 观察 Copied |
| SET-18 | Open-source Licenses 点 View 打开许可列表 | 模拟器·看 | 点 View 观察打开许可表面 *(表面形态未定,缺则上报人类裁决)* |
| SET-19 | Support & Feedback 显只读反馈邮箱可 Copy | 模拟器·自动 | 断言显 feedback@enchron.app,点 Copy 断言 Copied |
| SET-12 | 改五项设置后重启 app 仍保留 | 模拟器·看 | 改五项→重启→逐项断言保留(假存储须落 UserDefaults,否则降级同进程重建) |

**最大风险/未知:** 打磨组件现在是纯静态数据(每个 accessory 空 action 或写死值),接到统一假存储做双向绑定是主体工作量。SET-07 锚点漂移须在迁锚那一刻一次性统一。`UserPreferences` 须补几个新字段才能"改了能存、重启能读回"。

---

## 批 4|Environment / RCP(环境与 3D 场景)

**这批要达成:** 环境卡片轮播落进真 volume,选环境进沉浸空间加载美术 `world` 取代程序球顶。**最重、放最后**(但只依赖批 0,你要提前可提)。

**现成参考(已跑通,照抄):** mpv fork `enchron` 分支的 `xr-fork/verify-visionos` 已经加载同一个美术 `world` 场景 + mpv 帧上屏。关键文件:`VerifyVisionOSApp.swift:21,37-40`(RKS.initialize + ImmersiveSpace)、`ImmersiveView.swift:14`(.scriptingSystem)、`VerifyModel.swift:93-132`(`Entity(named:"world")` + 复用已加载实体)、`project.yml:15-18,48-56`(RealityKitScripting 依赖 + Info.plist 键)。下面的先决工作就是把这套接法搬到生产 `ImmersiveSpaceView`。

**先决代码工作:**
- 复制场景文件:把 `Immersive_Space.reality`(~43MB,含 `world`)复制进本仓、加进 XrPlayer target 的 Copy Bundle Resources(放主 bundle,`Entity(named:"world")` 直接读主 bundle,不走 RealityKitContent 包)。验证:构建通过 + 确认进包。
- 接 RealityKitScripting(**已确认必需**,照 verify):加 SwiftPM 依赖 `github.com/apple/realitykitscripting`(branch main);`XrPlayerApp.init` 里 `try RKS.initialize()`;`ImmersiveSpaceView` 的 RealityView 挂 `.scriptingSystem()`。原因:`world` 含 RCP3 Script Graph,漏了会报 NetworkAssetManager / Invalid sampler binding、场景加载失败。验证:模拟器·看(沉浸场景正常加载、控制台无 RKS/sampler 报错)。
- 补 Info.plist 键(**硬门槛,缺则进不去沉浸**):`UIApplicationSupportsMultipleScenes=true` + 四个 ARKit 用途串(`NSWorldSensingUsageDescription` / `NSHandsTrackingUsageDescription` / `NSAccessoryTrackingUsageDescription` / `NSCameraUsageDescription`)——RCP 脚本图进沉浸会开 ARKit 世界感知+手部追踪,缺则进程被终止。验证:构建 + 模拟器能进沉浸不崩。
- 把 DesignPreview 的 SenseZone volume 进入/返回/过渡守卫迁到生产真实 WindowGroup/导航模型。验证:模拟器·看(点 Environments 关主窗开 volume,返回回原标签)。
- 接 FeaturedEnvironment 假数据(7 卡),写清"卡→场景"映射:当前选任意卡都加载同一个 `world`。验证:单元(映射恒返回 "world"、不返回 nil)。
- 换场景(照 verify 的 VerifyModel.installScene 结构):`ImmersiveSpaceView` .immersive 分支把 `EnvironmentDomeEntity.makeEntity` 换成 `try await Entity(named:"world")` + content.add + 复用已加载实体。**视频屏二选一**:① 保留现有 `VirtualScreenEntity`(程序面,帧管线原样不动,最省);② 照 verify 用 `world.findEntity(named:"screen")` 绑到美术场景里建好的屏面(位置/尺寸由美术定,需补 UV 摆正)。**本轮建议①**,②留作美术屏面就位后再换。验证:模拟器·看(看到美术世界、视频屏有帧)。
- 确认 `world` 在生产 `.mixed/.full` 沉浸样式下完整包裹(**verify 只验过 `.progressive`,别照抄 progressive**——`.mixed/.full` 是 Enchron 的产品决策)。验证:模拟器·看。

| UC | 目标 | 验证 | 怎么验 |
|---|---|---|---|
| ENV-13 | 点 Environments 关主窗,开 volume 环境窗,7 张轮播卡 | 模拟器·看 | 点标签观察主窗消失、volume 出现、横向轮播 7 卡、标签不驻留 |
| ENV-14 | 环境窗返回:关窗、回主窗、恢复进入前标签 | 模拟器·看 | 从 Files/Settings 分别进、返回,确认回原标签 |
| ENV-15 | 过渡中重复触发进入/返回不叠加错乱 | 模拟器·自动 | 过渡未完成时连点,断言只切一次、终态唯一、之后仍生效 |
| ENV-16 | 中心卡显背景图/标题/编号/引语/模式/氛围六项 | 模拟器·看 | 逐项核对与 fixtures 数据一致 |
| ENV-17 | 拖轮播卡按 3D 深度叠放,松手磁吸居中 | 模拟器·看 | 指针拖,观察深度叠放、松手收敛到最近卡居中 |
| ENV-18 | 点展开进沉浸空间加载真 `world`(取代球顶),视频屏合成在前,走唯一沉浸入口 | 模拟器·看 | 点展开,确认沉浸打开、画面是美术 world、视频屏浮在前;断点确认走 openImmersiveSpaceUnified |
| ENV-19 | 环境 0/1 个时轮播不报错(1 个单卡居中、0 个空态) | 模拟器·自动 | 分别注入 0/1 个,断言不崩、1 个居中不越界、0 个空视图 |
| — | 沉浸里看到的 `world` 是完整 3D 场景而非旧程序球顶 | 模拟器·看 | 进沉浸截图对照美术预览,控制台无加载失败/RKS 报错 |
| — | 接 RKS(已确认必需,照 verify):依赖 + RKS.initialize + .scriptingSystem + Info.plist 键 | 模拟器·看 | 接上后沉浸场景正常加载、控制台无 RKS/sampler 报错 |
| ENV-12 | 关沉浸空间后:关沉浸、主窗恢复、播放回窗口模式继续 | 模拟器·看 | 沉浸播放中触发关闭,确认沉浸消失、主窗回、切窗口模式继续 |
| ENV-03 | Immersive 模式起播:主窗让位,world 与虚拟屏同时出现 | 模拟器·看 | immersive 起播,观察主窗关、世界+虚拟屏并存、屏上有帧 |
| ENV-10 | 沉浸/全景里空间点按虚拟屏或世界,控件显隐切换 | 模拟器·看 | 指针模拟空间点按,观察控件每次切换 *(风险:world 须带命中组件)* |
| — | 沉浸场景感知品质:真 HDR 亮度、立体景深、久看舒适 | **真机·人** | Vision Pro 真机进沉浸,人工评估三项;模拟器只能证加载与几何 |

**最大风险/未知:** 已解(照 verify-visionos):RKS 必需、Info.plist 四串必加、场景走 `Entity(named:"world")`、帧管线不动。剩余未知两条:① `world` 在生产 `.mixed/.full` 下是否完整包裹(verify 只验过 `.progressive`,这是 Enchron 产品决策,要实测);② 旧球顶自带命中组件(InputTarget/Collision),换成 `world` 后空间点按(ENV-10)要确认 `world` 实体也有命中组件,否则点按落空。数量错配:美术只 1 个 `world`、卡 7 张,本轮选任意卡都进同一个 world。注:mpv→视频屏帧管线 Enchron 已有可用实现(`PanoramaLayerBridge`→`VirtualScreenEntity`),本轮不动;verify 的 IOSurface 零拷贝路线是另一个改 PlaybackCore 出口契约的高风险决策,不在本轮。

---

## 留痕(待办,用户拍板后)

- 写两份 ADR:① FakeApp 架构(真 app+假数据、定稿组件取代旧视图)② RCP 直接沉浸接入(超越 ADR-0004 机制推迟 + ADR-0005 沉浸推迟,走 supersede 标注,不改旧 ADR)。
- 更新 `docs/use_cases.md` 的 `关联测试` 列为追溯表;更新 `fakeapp-round-definition` 记忆。
