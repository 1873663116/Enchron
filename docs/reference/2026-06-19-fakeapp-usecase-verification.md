# FakeApp 用例端到端验证报告（2026-06-19）

- 时态：时间戳记录（当时为真，只追加）。本轮收口验证。
- 范围：`docs/use_cases.md` 全部 111 条用例，对照 XrPlayer FakeApp target（真 app + FakePlaybackSource + FakeFileDataSource）。
- 方法：三层证据叠加——① XCUITest 自动化（真实点击驱动）；② 多 agent workflow `fakeapp-usecase-verify`（14 簇并行代码追溯 + 对抗式证伪，28 agent）；③ RCP 真实场景运行时验证（日志 + 截图，见 ADR-0008）。
- **证据天花板（诚实声明）**：visionOS 模拟器无法合成任意坐标点击（`snapshot_ui`/`tap` 因 SimulatorKit 框架路径失效），但 **XCUITest（XCTest 进程内驱动）可用**。故核心流有自动化点击证据，其余靠代码追溯（trigger→handler→可观察结果，带 file:line）+ 对抗复核。纯视觉/HDR/真机感知项标注"需真机"。

## 总览

| 判定 | 数 | 含义 |
|---|---|---|
| confirmed | 60* | 全链路 trigger→handler→可观察结果在代码中接通且经对抗复核存活 |
| partial | 27 | 部分接通(UI 在但 handler 空转 / 单向绑定 / 数据没喂进去 / 存了不消费) |
| refuted | 5 | 代码追溯曾判 verified,被对抗复核推翻 |
| not-implemented | 48* | 无代码路径(多为远程源表单、导入、本地文件管理等蓝图未建) |
| **conflict** | **0** | **无任何代码与蓝图矛盾** |
| 需真机/运行时 | 7 | 代码接通,但视觉/持久化结果须真机或运行时确认 |

\* 因 workflow 簇有合并、部分 UC 跨簇重复计数,140 条含约 30 条重复;去重后 ≈111 唯一 UC。完整逐条 file:line 证据见 workflow 结果归档（session task `w021oq7xc` 输出）。

## XCUITest 自动化（5/5 全绿，真实点击）

| 测试 | 证明的用例 | 结果 |
|---|---|---|
| `FilesPlaybackUITests.testTappingFilmCardOpensPlayer` | UC-FILE-01 点片卡→打开播放器 | ✅ 9.1s |
| `PlaybackDeckUITests.testPolishedDeckIsLivePlaybackSurface` | 播放台是活播放面（非静态稿） | ✅ 11.1s |
| `FilesPlaybackUITests.testFilesScreenShowsFakeCatalog` | UC-LNCH-01 / 假目录渲染 | ✅ 10.0s |
| `SettingsUITests.testNavigatingToSettingsAndSwitchingCategory` | UC-LNCH-03 / UC-SET-16 设置导航+分类切换 | ✅ 12.5s |
| `SmokeLaunchUITests.testAppLaunchesToInteractiveMainWindow` | 启动到可交互主窗 | ✅ 7.7s |

> `testTappingFilmCardOpensPlayer` 通过 = 负责人报的 bug①"点视频没法播放"的播放路径**实际可用**(点卡→开播放器)。黑帧是 FakePlaybackSource 无解码的预期表现,已加占位帧。

## RCP 真实场景（ADR-0008 落地）

UC-ENV-18 展开进入环境:**已验证**。运行时日志 `world loaded name=world children=3`、零 RKS/sampler/NetworkAssetManager 报错、截图渲染美术世界(多云天空+水面)、主窗在 mixed 沉浸下与世界共存(volume 不关机制成立)。详见 ADR-0008「2026-06-19 复议」节。

## Confirmed 核心流（已接通）

启动/导航:启动进浏览(UC-LNCH-01)、设置分类侧栏切内容(UC-SET-16)、偏好重启保留(UC-SET-12,有 `PreferencesPersistenceTests` 单测往返证据)。
文件浏览:点片开播(UC-FILE-01)、进文件夹扩面包屑(UC-FILE-18)、面包屑回跳(UC-FILE-19)、排序即时(UC-FILE-20)、文件名搜索(UC-FILE-33)、网格/列表切换(UC-FILE-34)、加载/空态(UC-FILE-23/24)、断连保列表弹警(UC-FILE-28)、存储条(UC-FILE-36)、条目计数(UC-FILE-38)。
播放:播放暂停(UC-PLAY-05)、播完变重播(UC-PLAY-06)、快进/快退十秒(UC-PLAY-07/08)、双击展开时间轴(UC-PLAY-17)、逐帧步进(UC-PLAY-18)、时间轴缩放/拖播放头(UC-PLAY-31)、⋯菜单(UC-PLAY-11)、切音轨/字幕(UC-PLAY-12/13)、设置面板(UC-PLAY-25)、切播放模式(UC-PLAY-27)、交互唤回控件(UC-PLAY-16)、退出回浏览(UC-PLAY-19)、窗口 resize(UC-PLAY-32)、加载转圈(UC-PLAY-21)、按设置执行结束行为(UC-PLAY-22)、加载失败可重试(UC-PLAY-23)。
环境:屏位随环境记忆(UC-ENV-09)、空间点按切控件(UC-ENV-10)、关沉浸回窗口(UC-ENV-12)、展开进真实 world(UC-ENV-18)。

## Partial — 真实缺口（看着接好,实际差一截;按价值排序）

**A 类·UI 接好但数据/恢复没接(FakeApp 可见,修复廉价、价值高):**
- **UC-LNCH-03** 主导航返回不恢复标签:点 Environments 开 volume 时存了 `environmentReturnTab`,但返回时**从不读回**——主窗停在空白。`SenseZoneVolumeRoot.returnToMain` 缺 `selectedTab = environmentReturnTab`。
- **UC-FILE-26** 已看进度条:`fileWatchedSeconds` 已加载,但 `FilesScreen` 创建 `GridCard.video()` 时**没传 `watchedProgress`**→进度条永不显示。
- **UC-FILE-39** 悬停徽章:`FilesScreen` 给卡片传空 `badges`/空 `duration`→hover 无内容浮现(组件 hover 管线在,数据没喂)。
- **UC-PLAY-09** 拖动进度跳转:功能接通,但 accessibilityIdentifier 不符(规范 `PlayerUI-SeekBar-slider-position`,代码 `DesignPreview-PlayerControlDeck-thumb`)→E2E 测试定位不到。

**B 类·数据源 UI 只改不持久化(重启回滚):**
- **UC-FILE-17 / UC-FILE-47** 删/多选删数据源:只改本地 `items` 绑定,**没调 `viewModel.removeDataSource()`**→重启重现。
- **UC-FILE-35**(refuted) 拖拽重排数据源:同上,无回写 `viewModel.savedDataSources`,重启复原。

**C 类·设置存了但从不消费(dead storage;消费侧属真播放行为):**
- **UC-SET-01** 续播策略:`currentResumePolicy()` 全仓零调用。
- **UC-SET-07** 默认环境:`defaultEnvironmentID` 不被 `DecidePlaybackModeUseCase` 读取。
- **UC-SET-13 + UC-PLAY-15** 控件隐藏时长:`controlsAutoHideSeconds` 存了,但 `MainView.startControlsTimer` 硬编码 8 秒。
- **UC-SET-14** 自动进沉浸:`entersImmersionForSpatialContent` 不被路由决策读取。
- **UC-SET-25**(refuted) 性能 HUD 开关:持久化在,无渲染消费方。

**D 类·分类归属错 / 故意 no-op:**
- **UC-SET-08 / UC-SET-17** 缓存大小 / 隐私声明:放在 About 分类,**Category 枚举里根本没有 "Storage & Privacy" 分类**。
- **UC-SET-21 / UC-SET-24** 重置引擎 / 清日志:确认弹窗在,handler 是 FakeApp 故意 no-op。
- **UC-PLAY-29** 切剧集:`episodeItems` 恒为空→子菜单永不出现。

**E 类·过渡守卫不全:**
- **UC-ENV-06** 过渡期禁操作:`isTransitioningPlaybackMode` 挡窗口操作,但不挡 `SpatialTapGesture`。
- **UC-ENV-07** 播放中换环境:`switchEnvironment` 无重入守卫,并发可竞态。
- **UC-PLAY-24** 缓冲指示:仅网络重试时显示;FakePlaybackSource 不发 `.buffering`。
- **UC-PLAY-28** Picture 参数:只读(libplacebo 待真 mpv 后端,故意)。

## Refuted（代码追溯曾判 verified,对抗复核推翻）

UC-FILE-35(重排不持久化)、UC-FILE-37(navigateToBreadcrumb 不清 forwardPathStack + 前进按钮无 `canNavigateForward` 绑定恒可点)、UC-SET-25(HUD 无渲染方)、UC-PLAY-14(功能正常,仅追溯把"9 档"说错,实为 10 档含 1.75x——功能本身存活)。

## Not-implemented（48,多为蓝图未建;按主题）

- 远程源连接表单(WebDAV/SMB):UC-FILE-09/10/11/12/13/14/15/44/45/46/48——adapter 在,UI 表单未建。
- Photos/Documents 导入+授权:UC-FILE-05/06/07/08。
- 本地文件管理:多选删/移、新建文件夹、下拉刷新——UC-FILE-41/42/43/32/03(Add Photos/New Folder 空 stub)。
- 设置破坏/诊断动作:清缓存(SET-09)、重置环境屏位(SET-22)、连接测试(SET-26)、重连(SET-27)、导出诊断(SET-28)、清进度(SET-29)。
- 续播提示流:UC-PLAY-02/03/04(VideoDetailView 已退役,基建在但未用)。
- 播放器顶栏展开进沉浸:UC-PLAY-30(无按钮;注:环境卡展开 UC-ENV-18 已实现,是另一入口)。
- 立体内容自动路由:UC-ENV-02。

## 需真机/运行时确认（代码接通,视觉/持久化结果待证）

UC-SET-25(HUD 渲染)、UC-PLAY-29(剧集)、UC-PLAY-26(屏幕几何视觉)、UC-ENV-05(模式切换视觉)、UC-ENV-08(屏位视觉)、UC-ENV-09(屏位持久化)、UC-ENV-12(关沉浸视觉)。沉浸 HDR 亮度/立体景深/久看舒适始终是真机·人工项。

## 结论与建议

- **核心 happy path(浏览→点片→播放台→设置→环境→真实沉浸)端到端可用且有自动化点击证据。** 无任何代码与蓝图矛盾(conflict=0)。
- 优先级建议:A 类 4 项是"看着做完实则差一行"的廉价高价值修复(尤其 UC-LNCH-03 返回不恢复标签、UC-FILE-26/39 数据没喂),建议本轮或下轮先收;B 类数据源持久化次之;C/D/E 多属真播放后端或蓝图未建,按产品节奏推进。
- 逐条 file:line 证据:见本轮 workflow `fakeapp-usecase-verify` 输出(session task w021oq7xc)。
