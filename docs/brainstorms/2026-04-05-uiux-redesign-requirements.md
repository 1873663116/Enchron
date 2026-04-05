---
date: 2026-04-05
topic: uiux-redesign
---

# Enchron UI/UX 重构需求

## 问题框架

Enchron 的当前 UI 基于 visionOS 1.x 标准控件的朴素组合（TabView + NavigationStack + 手写玻璃面板），缺乏统一视觉语言和空间交互深度。设计团队已完成完整的视觉探索——5 个 HTML mockup 变体 + 经对抗性审查验证的 534 行翻译指南——锁定了 Liquid Glass 暗色调美学方向。

本次重构将这些已验证的设计决策落地为 SwiftUI 原生实现，在不破坏 Clean Architecture 模块边界和 248 个现有测试的前提下，将 Enchron 提升至 Apple 平台原生品质标准。

## 用户流程

```
┌──────────────────────────────────────────────────────────┐
│  EnchronApp 启动                                         │
│                                                          │
│  ┌─────────┐   ┌──────────────────────────────────────┐  │
│  │ Leading  │   │  主窗口 (.plain)                      │  │
│  │ Ornament │   │  ┌────────────────────────────────┐  │  │
│  │          │   │  │ NavigationSplitView             │  │  │
│  │ ○ Browse │──▶│  │ ┌────────┐ ┌─────────────────┐ │  │  │
│  │ ○ Recent │   │  │ │Sidebar │ │  Content Grid   │ │  │  │
│  │ ○ Settings│  │  │ │Sources │ │  LazyVGrid      │ │  │  │
│  │          │   │  │ │(Favs※) │ │  VideoCards     │ │  │  │
│  │ ─────── │   │  │ │Storage │ │  Filter pills   │ │  │  │
│  │ ◉ Scene  │   │  │ └────────┘ └────────┬────────┘ │  │  │
│  └─────────┘   │  └──────────────────────┼──────────┘  │  │
│                │                         │              │  │
│                │               点击卡片   ▼              │  │
│                │         ┌──────────────────────┐       │  │
│                │         │ .sheet 详情面板        │       │  │
│                │         │ 预览 + 环境选择 + 设置  │       │  │
│                │         │ [Start Playback] ─────┼──┐   │  │
│                │         └──────────────────────┘  │   │  │
│                └───────────────────────────────────┘   │  │
│                                                        │  │
│                          PlaybackLaunchCoordinator ◀───┘  │
│                                    │                      │
│                 ┌──────────────────┼──────────────────┐   │
│                 ▼                  ▼                  ▼   │
│          ┌──────────┐    ┌──────────────┐   ┌──────────┐ │
│          │ 窗口模式  │    │  沉浸模式     │   │ 全景模式  │ │
│          │ ornament │    │ 伴随窗口/     │   │ .full    │ │
│          │ bottom   │    │ Attachment    │   │ 360°     │ │
│          └──────────┘    └──────────────┘   └──────────┘ │
└──────────────────────────────────────────────────────────┘
```

## 需求

**设计基础（Design Foundation）**

- R1. 在 Xcode Asset Catalog 中建立 9 色语义色板（surface #131313, onSurface #E5E2E1, tertiary #ADC6FF, onTertiary #002E6A, primary #C6C6C7, onPrimary #2F3131, surfaceContainerLow #1C1B1B, surfaceContainerHighest #353535, onSurfaceVariant #C1C6D7），并通过 `Color` extension 提供类型安全访问
- R2. 定义设计 Token 常量：圆角体系（radiusCard: 20, radiusWindow: 40, radiusBadge: 10）；同心法则内圆角手动计算 `inner = outer - padding`
- R3. 字体映射使用 SwiftUI 语义 Text Style（title2/headline/caption/caption2），不硬编码 `.system(size:)`
- R4. 统一 `.glassBackgroundEffect()` 参数为设计指南规定的 4 个变体（glass-window → `.rect(cornerRadius: 40)`, glass-control → `.capsule`, glass-panel → `.regularMaterial`, glass-sidebar → 系统 List 自带）

**全局导航（3+1）**

- R5. 替换当前 `AppTabView`（TabView .sidebarAdaptable）为 `.ornament(attachmentAnchor: .scene(.leading))` 竖向导航栏，包含 3 个导航项（Browse/Recent/Settings）+ 分隔符 + 1 个独立 Scene Selector 按钮
- R6. 导航栏使用 `VStack` + `.glassBackgroundEffect(in: .capsule)` 实现 pill 形容器
- R7. 导航项使用 SF Symbols 图标，active 状态使用 tertiary 色标记
- R8. Scene Selector 按钮为独立圆形，点击触发环境选择（不进入新 tab）
- R9. 导航切换驱动主窗口内容区变更（Browse → 文件浏览器, Recent → 最近播放列表, Settings → 设置面板），使用条件渲染。导航选择状态必须由 `AppModel`（@Observable 非 View 模型）持有，View 层仅投射状态，不持有跨流程业务状态
- R9a. Recent 视图显示最近播放记录列表，复用 VideoCard 组件，按最后播放时间倒序排列，空状态显示引导文案。数据契约：通过 `ProgressStoring` port 查询（需新增 `loadRecentlyPlayed(limit:) -> [PlaybackProgress]` 方法），去重键为 FileIdentifier（path + sizeInBytes + serverFingerprint 合成），保留最近 50 条记录。具体布局在规划阶段确定

**文件浏览器（File Browser）**

- R10. 将 `FileBrowserView` 从 `NavigationStack` + `VStack` 重构为 `NavigationSplitView { sidebar } detail: { content }`
- R11. Sidebar 使用系统 `List(selection:)` 显示数据源（Local Storage / SMB / WebDAV），按 Sources 分组。底部显示本地 Storage 使用量进度条（仅本地，远程数据源不显示存储量）。Favorites 功能推迟到后续迭代（需要新增 Domain 模型和 CRUD 操作，超出 UI 重构范围）
- R12. Content 区域使用 `LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))])` 显示视频卡片网格
- R13. Content 区域顶部包含面包屑路径导航和搜索框
- R14. 实现 Filter pills（All/4K/HDR/Spatial）用于内容过滤，active 状态使用 tertiary 背景色
- R15. 视频卡片为自定义组件：缩略图（aspect-video）+ 格式 badge（左上，`.offset(z: 4)`）+ 时长 badge（右下，`.offset(z: 8)`）+ 标题 + 元数据；卡片整体使用 `.hoverEffect(.lift)` 提供系统注视反馈，badge 不同 Z 轴深度产生多层视差弹跳效果
- R16. 点击视频卡片使用 `.sheet()` 呈现详情面板（取代当前 `navigationDestination` 推送）
- R17. 详情面板内含：左列（视频预览 + 环境选择器轮播 + "Start Playback" 按钮）+ 右列（元数据 + 播放设置 Picker/Toggle）
- R18. 数据源配置流程保持 `.sheet()` 模态，内部保持两阶段（凭证输入 → 共享选择）

**播放器控件（Player Controls）**

- R19. 窗口模式：`PlayerControlsView` 继续使用 `.ornament(attachmentAnchor: .scene(.bottom))` 挂载，样式升级为 Pill 形 glass-control 容器
- R20. 窗口模式控制栏布局：Menu | Rewind-10s | Play(中心大按钮) | Forward-10s | Settings，按钮使用 `.buttonStyle(.automatic)` 获得系统按压反馈
- R21. 沉浸模式：控件使用独立 `WindowGroup("PlayerControls")` 伴随窗口方案；.ornament 不可用于 ImmersiveSpace。本阶段锁定伴随 WindowGroup，不使用 RealityKit Attachment（避免 SpatialScene 集成和范围蔓延）
- R22. 播放器菜单系统使用系统 `Menu` + `Picker`，不自建菜单层级
  - Menu popup: HDR toggle + Subtitles picker + Audio Track picker + Playback Speed picker
  - Settings popup: Playback Mode picker + Environment selector
- R23. Seek bar 使用系统 `Slider`；hover 时显示时间预览
- R24. 控件自动隐藏使用 `@State lastInteractionTime` + `.task(id:)` + `Task.sleep(for: .seconds(5))` 模式，不用 Timer
- R25. 顶部信息栏：返回按钮 + 视频标题 + 格式元数据（如 "4K HDR · HEVC · Spatial Audio"）

**NLE 时间轴（唯一核心自定义组件）**

- R26. 时间轴为可展开面板，初始隐藏，点击触发展开（`.offset` + `.spring` 动画）
- R27. 时间标尺（Ruler）使用 Canvas 绘制刻度线和时间标签
- R28. 轨道区域显示缩略图条（thumb strip），支持水平拖拽滚动（`DragGesture`）
- R29. 播放头固定居中，使用 Canvas 或自定义 Shape 绘制
- R30. 支持双指捏合缩放（`MagnifyGesture`）改变时间线精度
- R31. 支持逐帧步进（Frame Previous / Frame Next）按钮

**无障碍（不可省略）**

- R32. 所有交互元素注视目标最小 60×60pt，小于此的元素使用 `.frame(minWidth: 60, minHeight: 60)` + `.contentShape(.rect)` 扩展
- R33. 视频卡片和播放控件添加 `.accessibilityLabel()` + `.accessibilityHint()` 描述
- R34. 时间轴添加 `.accessibilityAction(named:)` 支持 Play/Pause/Next Frame 等自定义动作
- R35. 检查 `@Environment(\.accessibilityReduceMotion)` 决定是否使用装饰性动画
- R35a. 关键场景切换（打开详情 sheet、切换导航项、进入沉浸模式）时使用 `@AccessibilityFocusState` 管理 VoiceOver 焦点落点
- R35b. VideoCard 网格和侧栏数据源行使用 `.accessibilitySortPriority()` 明确朗读顺序

**动画与交互**

- R36. hover 效果全部使用 `.hoverEffect()` 或 `.hoverEffect(.lift)`，不自造 translateY + shadow
- R37. 按压效果全部使用 `.buttonStyle(.automatic)`，不自造 scaleEffect
- R38. 面板弹出使用 `.sheet()` / `.popover()` 系统转场，不 withAnimation opacity 自造
- R39. 拖拽中使用 `.interactiveSpring`，拖拽结束使用 `.spring` 弹性归位

## 成功标准

1. **视觉一致性**：所有界面遵循统一色板、圆角体系、玻璃材质变体，无硬编码色值或字体大小
2. **系统原生率**：16 项系统原生组件全部使用系统 API，0 项自造替代；4 项自定义组件经过审查确认无系统替代
3. **架构完整性**：所有 22 条 Architecture Invariants 通过，Domain/UseCase 层测试 100% 通过，View 层测试与新实现对齐后通过，无新增跨模块直接依赖
4. **可用性**：所有交互元素注视目标 ≥60pt，Reduce Motion 路径完整，VoiceOver 可遍历所有功能
5. **导航流畅性**：用户从启动到播放的路径 ≤ 4 步（启动 → 选数据源 → 选视频 → 播放）

## 范围边界

- **不做**：PlaybackCore 或 mpv 层的任何改动
- **不做**：RealityKit 渲染管线（EnvironmentDome/PanoramaSphere/VirtualScreen）重构
- **不做**：新增数据源协议（如 FTP、Google Drive）
- **不做**：多媒体会话（同时播放多个视频）
- **不做**：跨设备同步或 iCloud 集成
- **不做**：自建窗口管理系统（依赖系统 @Environment open/dismissWindow）
- **包含**：XrPlayerApp.swift 的 WindowGroup 注册变更（限于沉浸模式控件伴随窗口 R21）
- **不保留**：现有自建播放器浮动面板组件（PlaybackMenuView/ScreenPositionControlView 的自建面板容器），全量替换为系统 Menu + Picker，原有面板容器代码删除
- **保留**：PlaybackLaunchCoordinator 的 preparePlayback/confirmPlayback 流程不变
- **保留**：FileBrowsing Domain 层（BrowsingMediaFile、DataSource、Ports）不变
- **保留**：SpatialScene 的 Renderers 和 Domain 层不变

## 关键决策

- **NavigationSplitView 取代 TabView**：文件浏览器从 flat tab 切换为 Finder 式侧栏，因为 visionOS 空间中侧栏比 tab 更符合信息层次。决策源于 mockup variant-AB-combined 的对抗性审查结论
- **Leading ornament 取代 sidebarAdaptable**：全局导航从 TabView 内置样式改为窗口左侧 ornament，因为设计需要独立的 Scene Selector 按钮和更紧凑的导航占位。决策源于 design-to-swiftui.md 第 2 章
- **详情面板用 .sheet() 而非 navigationDestination**：设计意图是模态浮层（overlay-panel）而非页面推送，保持浏览上下文不丢失。决策源于 design-to-swiftui.md 第 9 章
- **沉浸模式用伴随 WindowGroup**：.ornament 不可用于 ImmersiveSpace（系统限制），伴随窗口比 RealityKit Attachment 更灵活且可复用窗口模式的控件代码。决策源于 design-to-swiftui.md 第 10 章
- **系统 Menu/Picker 取代自建菜单层级**：mockup 的 3 级菜单系统在 SwiftUI 中应使用系统 Menu + Picker 组合实现，而非自建弹出面板。决策源于 design-to-swiftui.md 第 12 章

## 架构约束映射

| 约束 | 影响的需求 | 具体限制 |
|------|-----------|---------|
| P0: 播放启动单通道 | R16, R17 | 详情面板的 "Start Playback" 必须经 PlaybackLaunchCoordinator |
| P0: 播放模式决策在 PlayerUI | R21, R22 | 沉浸/窗口切换决策不能放在 App 或 SpatialScene |
| P0: Protocol 边界 | R10, R11 | FileBrowsing 的 sidebar 数据来自 DataSourceConnecting protocol |
| P1: SpatialScene 独立 | R8, R21 | Scene Selector 触发环境变更不等于启动播放；R21 锁定伴随 WindowGroup 方案以避免 SpatialScene 集成 |
| P1: FileBrowsing 统一适配 | R11, R18 | sidebar 数据源列表统一为 DataSource 模型 |
| P2: 时间轴核心资产 | R26-R31 | 可适度突破实现细节约束以保证高性能 |

## 依赖 / 假设

- **假设**：visionOS 2.x SDK 的 `.glassBackgroundEffect()` API 与当前项目使用一致（若 Liquid Glass API 变更需适配）
- **假设**：`~/Movies/HelloWorld/` 参考项目可用且匹配当前 visionOS SDK 版本
- **依赖**：R10（NavigationSplitView）必须在 R12-R17 之前完成，作为容器
- **依赖**：R1-R4（设计基础）应最早实施，所有 UI 组件依赖统一 token
- **依赖**：R5-R9（全局导航）必须在 R10 集成之前完成，因为 R10（FileBrowserView）是 Browse 导航项的内容视图，ornament 的选择状态变量必须先存在才能条件渲染内容视图
- **依赖**：R21（沉浸模式控件）需要新增 WindowGroup 声明，影响 XrPlayerApp.swift

## 待解问题

### 推迟到规划阶段

- [影响 R5][���术性] Leading ornament 在 `.windowStyle(.plain)` 窗口上的精确行为需在规划阶段的原型验证中确认。**回退策略已锁定**：若 ornament 与 `.plain` 不兼容，回退至 TabView `.sidebarAdaptable` + toolbar 中注入 Scene Selector 按钮（系统组件优先原则的自然回退路径）。两种方案可共享相同导航状态模型（待规划阶段定义 AppModel 导航枚举时验证），仅容器实现不同，不影响 R10-R18 的实施
- [影响 R16][技术性] VideoDetailView 从 navigationDestination 迁移到 .sheet() 时，现有 onDisappear 的 cancelPreparedPlayback() 和 detailNavigationRequest = nil 逻辑需显式重写。同时需验证 visionOS sheet 呈现效果是否匹配 mockup overlay-panel 的局部叠加设计
- [影响 R21][技术性] 伴随 WindowGroup 方案已锁定；待验证：窗口定位、跟随主窗口、大小约束、生命周期策略（用户手动关闭后恢复、沉浸退出后 dismiss 协调）
- [影响 R8][技术性] SceneSelectorView 从完整 Tab 迁移为 ornament 按钮触发的呈现形式（.popover / .sheet / 内联），需设计决策
- [影响 R11][技术性] NavigationSplitView 在 visionOS 上的 sidebar 自动折叠行为需验证（窗口缩小时）。Favorites 分组需要新的数据模型（FileBrowsingViewModel 当前无此概念）
- [影响 R26-R31][需要调研] NLE 时间轴的缩略图生成策略（mpv screenshot vs AVAssetImageGenerator vs 预生成缓存）——这是 R28 的阻塞依赖
- [影响 R15][技术性] 视频缩略图异步加载与缓存策略（影响卡片渲染性能）
- [影响 R1][技术性] 确认 Asset Catalog Color Set 在 visionOS 的 Dark/Light mode 适配方式（Enchron 暗色基底是否需要 Any Appearance 单一变体）
- [影响 R9a][技术性] ProgressStoring 接口扩展方案已锁定；待确认：loadRecentlyPlayed 的排序语义（由 port 实现保证还是调用方排序）

## 优先级与实施顺序

```
Phase A: 设计基础          R1-R4
    ↓
Phase B: 全局导航          R5-R9
    ↓
Phase C: 文件浏览器        R10-R18
    ↓
Phase D: 播放器控件        R19-R25
    ↓
Phase E: NLE 时间轴        R26-R31
    ↓
Phase F: 无障碍 + 动画      R32-R39 (横切关注点，贯穿 Phase B-E 同步实施，非串行末置)

注：Phase D 与 Phase C 可并行推进（PlayerUI 不依赖 FileBrowsing 重构结果）
```

## 下一步

→ /ce:plan 进行结构化实施规划
