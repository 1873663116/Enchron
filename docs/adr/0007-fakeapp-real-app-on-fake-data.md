# ADR-0007：FakeApp —— 真 app 跑在假数据上，定稿组件取代旧视图

- 状态：已接受
- 日期：2026-06-18
- 决策者：项目负责人（grill 访谈拍板）

## 背景

前端打磨已收尾（`docs/designs/` HTML 稿退役，DesignComps 三正式 Preview Canvas 齐全）。
本轮要把打磨好的前端组装成「将来要发布的那个 app 本身」。历史上 app target（`XrPlayer`）
里有一套粗糙但真实接通的视图（ContentGridView / FileBrowserView / DataSourceConfigView /
VideoDetailView / PlayerControlsView / NLETimelineView / SettingsView 等），与 DesignPreview
里精致但孤立的组件并存。两套前端必须收敛成一套。

需求规格不是白纸——`docs/use_cases.md`（89 条用例台账）已是勾选清单。本轮范围是「组装」，
不是「凭空写规格」。

## 决策

**FakeApp = 真 app（`XrPlayer` target），屏幕背后暂时接假数据 / 假引擎；日后把假的换成真的，
app 直接发布、不重写。**

1. **本体**：组装在 `XrPlayer` target 内完成（不在 DesignPreview）。FakeApp 就是真 app。
2. **前端**：打磨好的共享组件（`XrPlayer/Shared/Components/`，两 target 共享）成为真 app 的屏幕；
   app 侧新建 screen 视图（`FilesScreen` / `SettingsScreen` …）组合这些组件并接生产 view-model；
   旧 XrPlayer 视图退役。DesignPreview 保留为并列的设计审查 Canvas。
3. **假后端**：文件源 `FakeFileDataSource`、播放源 `FakePlaybackSource`、设置存储
   （`UserDefaultsStore` 真持久 / `FakePreferencesStore` 供测试）实现既有 protocol 端口，
   在组合根 `XrPlayerApp.init` 单点注入。**换真适配器即发布的切换点全部集中在组合根。**
4. **导航词表**：`NavigationTab` 统一为 `files / settings / environment`（退役 `browse / recent`）。
5. **验证**：纯逻辑走 `swift test`（SPM 镜像模块 `XrPlayerCore`）；UI / 集成走 `xcodebuild test`
   + `XrPlayer.xctestplan`（堵假绿）；差异化感知（HDR 亮度、立体景深、久看舒适）留真机人评。

## 后果

- 旧视图退役是**删除**，不是并存：本轮已删 FileBrowserView / ContentGridView /
  DataSourceConfigView / VideoDetailView / RecentlyPlayedView / SettingsView。控件标识迁到新组件
  （`FileBrowsing-*` / `Settings-*` 前缀，per-row 锚点在组件模型下降为分区组级）。
- 「假 → 真」的边界是 protocol 端口 + 组合根单点注入；适配器层不动 view-model 与组件。
- 共享组件机制同 `DesignTokens`：文件置于 `XrPlayer/` 自动入 `XrPlayer` target，并经
  DesignPreview 白名单（`membershipExceptions`）供 DesignPreview 编译。
- 沉浸 3D 场景（美术 `world` 取代程序球顶）依赖新增 SwiftPM 依赖 RealityKitScripting，
  属宪法硬边界，**待人类裁决**——见 ADR-0008（提案态）。
- 本轮未竟的 per-UC 细粒度（远程连接表单、打磨播放 deck、设置诊断长尾、SenseZone volume 迁移、
  沉浸 world 加载）在交付报告与作战地图中如实登记，不谎报完成。

## 关联

- `docs/use_cases.md`（蓝图规格，本轮范围由其驱动）；ADR-0003（用例台账）。
- ADR-0004（美术仓库取代模板 RealityKitContent）：本 ADR 的沉浸场景消费方即其导出。
- ADR-0008（RCP 直接沉浸接入，提案态，承接本 ADR 第 3 条的沉浸硬边界）。
- 记忆 `fakeapp-round-definition`；作战地图 `docs/plans/active/2026-06-fakeapp-assembly.md`。
