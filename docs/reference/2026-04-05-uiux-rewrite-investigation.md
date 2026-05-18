# UI/UX 重构调研汇总

日期：2026-04-05
调查来源：5 个并行 subagent（代码扫描、设计指南、mockup 分析、架构约束、旧计划复查）

---

## T1: 现有 UI 代码结构

### 文件树（关键模块）

```
FileBrowsing/ (17 files)
├── Adapters/ — Local, PhotoLibrary, SMB, WebDAV
├── Domain/ — BrowsingMediaFile, DataSource, MediaFolder, Ports, ValueObjects
├── ViewModels/ — FileBrowsingViewModel
└── Views/ — DataSourceConfigView, FileBrowserView, FolderListView

PlayerUI/ (17 files)
├── Components/ — SliderGridRow
├── Domain/ — PlaybackMode, GestureType, Ports
├── UseCases/ — DecidePlaybackMode, DetailedTimelineGeometry, DisambiguateGesture, Formatters
└── Views/ — DebugOverlay, DetailedTimeline, PlaybackMenu, PlayerControlSurface,
              PlayerControls, Playlist, ScreenPositionControl, VideoDetail

Settings/ (1 file) — SettingsView

App/ (8 files)
├── Navigation/ — AppTabView
├── AppCoordinator, NetworkMonitor
├── PlaybackLaunchCoordinator, PlaybackLaunching, PlaybackLaunchRequest
└── PlaybackMediaMetadataService, PreparedPlayback

SpatialScene/ (13 files)
├── Domain/ — CinemaEnvironment, FisheyeRemap, HemisphereMesh, ScreenGeometry, VirtualScreen
├── Modifiers/ — DragRotationModifier
├── Renderers/ — EnvironmentDome, PanoramaLayerBridge, PanoramaSphere, VirtualScreen
├── Scenes/ — ImmersiveSpaceView
└── Views/ — SceneSelectorView
```

### 全局 API 用法

| API | 使用数 | 位置 |
|-----|--------|------|
| NavigationStack | 3 | FileBrowserView, DataSourceConfigView, XrPlayerApp(settings) |
| NavigationSplitView | 0 | **需引入** |
| TabView | 1 | AppTabView (.sidebarAdaptable) |
| .ornament | 1 | MainView:105 (bottom, PlayerControls) |
| .glassBackgroundEffect | 10 | SceneSelector, FileBrowser, FolderList, PlaybackMenu, PlayerControls, ScreenPositionControl, DetailedTimeline, MainView, DebugOverlay, Playlist |
| .hoverEffect | 2 | SceneSelector, PlayerControlSurface |
| RealityView | 1 | ImmersiveSpaceView |
| WindowGroup | 2 | main + settings |
| ImmersiveSpace | 1 | "ImmersiveSpace" |

### 导航结构

```
MainView (root ZStack)
├── AppTabView (TabView .sidebarAdaptable)
│   ├── FileBrowserView (NavigationStack)
│   │   ├── → VideoDetailView (navigationDestination)
│   │   └── → DataSourceConfigView (sheet)
│   ├── SceneSelectorView (VStack/LazyVGrid)
│   └── SettingsView (List)
├── ImmersiveSpaceView (RealityView, in ImmersiveSpace)
└── PlayerControlsView (.ornament bottom)
```

### 需要重构的关键 View

**高优先级**：MainView, PlayerControlsView, AppTabView, FileBrowserView
**中优先级**：SettingsView, PlaybackMenuView, ScreenPositionControlView, SceneSelectorView
**低优先级**：PlaylistView, FolderListView, DataSourceConfigView, VideoDetailView

---

## T2: design-to-swiftui.md 翻译规则

### 系统原生组件（16 项必须使用）

1. NavigationStack / NavigationSplitView
2. List in NavigationSplitView (sidebar)
3. Menu / .popover()
4. Picker (.segmented/.menu)
5. Toggle
6. Slider
7. .ornament() (仅 Window)
8. .sheet()
9. .hoverEffect() / .hoverEffect(.lift)
10. .glassBackgroundEffect() / .regularMaterial
11. WindowGroup / ImmersiveSpace
12. @Environment(\.openWindow) / dismissWindow
13. @Environment(\.openImmersiveSpace) / dismissImmersiveSpace
14. .immersionStyle(selection:in:)
15. LazyVGrid with .adaptive(minimum:)
16. .buttonStyle(.automatic)

### 可以自定义的组件（4 项）

1. **NLE 时间轴** — DragGesture + MagnifyGesture + .interactiveSpring
2. **视频卡片** — 缩略图 + badge + 元数据 + .hoverEffect()
3. **环境选择器轮播** — ScrollView + scrollTargetBehavior(.viewAligned)
4. **播放头指示器** — Canvas 或 SF Symbol

### 关键翻译映射

- backdrop-filter: blur → .glassBackgroundEffect()
- border-radius: 20px/40px/10px → radiusCard/radiusWindow/radiusBadge
- text-xl bold → .font(.title2); text-sm semibold → .font(.headline)
- :hover translateY → .hoverEffect()
- scale(0.95) → .buttonStyle(.automatic)
- position: fixed → .ornament()
- grid cols-3 → LazyVGrid(.adaptive(minimum: 240))

### 色彩系统

| 语义 | 色值 | 用途 |
|------|------|------|
| surface | #131313 | 主表面 |
| onSurface | #E5E2E1 | 主文字 |
| tertiary | #ADC6FF | 强调色 |
| primary | #C6C6C7 | 品牌色 |
| surfaceContainerLow | #1C1B1B | 玻璃底色 |
| surfaceContainerHighest | #353535 | 高亮 |
| onSurfaceVariant | #C1C6D7 | 次文字 |

### 22 条禁区（摘要）

- 不自定义 window 堆叠 / 不硬编码颜色 / 不手动 ultraThinMaterial+opacity
- 不硬编码字体 size / 不 fixed position 模拟 ornament / 不在 ImmersiveSpace 用 ornament
- 不自造 hover/按压/面板转场动画 / 不自造菜单系统
- 不用 Timer 自动隐藏 / 不忘无障碍 / 不用 .fullScreenCover / 不跳过 Reduce Motion

---

## T3: HTML Mockup 设计决策

### 文件浏览器（variant-AB-combined.html）

**三层布局**：
1. 导航栏（72px 宽，glass-nav）→ 映射为 .ornament(.leading)
   - Browse / Recent / Settings（竖向 pill）
   - 独立圆形 Scene Selector 按钮
2. 主窗口（glass-window，border-radius: 2.5rem）
   - 侧栏（210px，glass-sidebar 0.25 opacity）→ NavigationSplitView sidebar
     - Sources（Local/NAS-01/WebDAV）+ Favorites + Storage bar
   - 内容区 → NavigationSplitView detail
     - 面包屑导航 + 搜索框
     - Filter pills（All/4K/HDR/Spatial）
     - 视频网格（3 列 adaptive）
3. 浮动详情面板（overlay-panel）→ .sheet() 或 navigationDestination
   - 左列：视频预览 + 环境选择器 + 播放按钮
   - 右列：元数据 + 播放设置

**交互特色**：
- 视频卡片多层 visionOS 悬停（卡片 -6px, badge -6px@50ms, badge -8px@100ms）
- Glow orb 大气背景（blur 100-140px）
- Filter pills active 状态用 tertiary 色

### 播放器（player.html）

**全屏沉浸式**：
- 顶部：返回按钮 + 标题元数据
- 底部：Seek bar + Control bar（Pill 形 glass-control）
  - Menu | Rewind-10s | Play(中心) | Forward-10s | Settings
- 可展开时间线面板（NLE 风格）
  - Ruler 时间标尺 + Track 缩略图条 + 固定 Playhead

**菜单系统（3 级）**：
- Level 1: Menu popup / Settings popup
- Level 2: Sub-menus（Subtitles, Audio, Speed, Playback Mode, Environment）
- Level 3: Items（可滚动列表）

---

## T4: 架构约束（重构不可违反）

### P0 约束（违反即架构崩溃）

1. **统一播放启动路径不可绕开** — 所有播放经 PlaybackLaunchCoordinator
2. **播放模式决策必须在 PlayerUI** — PlaybackCore/SpatialScene 不决策
3. **Protocol 边界强制** — 跨模块调用必须通过 protocol
4. **单媒体会话** — 切换媒体 = 结束旧 + 创建新

### P1 约束

5. PlaybackCore 不依赖 UI 框架
6. SpatialScene 是独立上下文（非 PlayerUI 子视图）
7. Persistence 无业务决策
8. FileBrowsing 统一协议适配

### P2 约束

9. App 只组装不承载业务规则
10. Shared 不收容跨模块业务逻辑
11. 时间轴为核心交互资产（可适度突破实现细节约束）
12. FileBrowsing 可播放性过滤

---

## T5: 旧计划可复用性评估

### 可直接复用

- 播放启动流程分析（PlaybackLaunchCoordinator generation stamp）
- 模块边界与依赖分析（5 大模块、8 单元粒度）
- 技术决策约束（系统原生优先、单通道不绕过、状态机不跳过）
- 风险缓解策略（120s TTL、直接调用路径保留）

### 需更新

- Liquid Glass API 版本确认
- HelloWorld 参考项目可用性验证
- toolbar 附着点设计（MainView 是 ZStack 非 NavigationStack）
- 网络中断 prepare→confirm 间隙的 UI 处理
- QA 计划需关联现有 59 条 E2E 路径

### 经验教训（来自 solutions/）

1. HTML→SwiftUI 存在不可翻译假设，必须经 design-to-swiftui.md 映射
2. 代码健康度 ≠ 用户健康度（97.75% vs 70.7%），需端到端验证
3. 对抗性审查发现的 4 类隐蔽 bug：路由断联、覆盖不触发更新、数学常数错误、nil 未重置
4. immersiveStyle 必须在 @main App 的 Scene 声明上
5. mpv→SwiftUI 200ms 轮询链路任何新增状态必须 4 步完整
