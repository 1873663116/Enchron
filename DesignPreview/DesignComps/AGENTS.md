# DesignComps Agent 说明

`DesignComps` 存放从 `docs/designs/` 派生出的高保真可交互 Preview Canvas。
这些文件是视觉设计资产，用于审查主要体验状态。跨 Preview 的产品流程、导航状态同步、返回链路和假业务生命周期属于未来 FakeApp 阶段。

## 文档语言

- `DesignPreview` 内的 Agent 文档和 README 使用中文书写。
- Swift 类型名、文件名、Apple / visionOS 专有名词、组件名和代码标识保留原文。

## 术语

- `Preview Canvas`：Canvas 中用于审查一个主要体验状态的高保真预览。它可以包含局部交互。
- `Sidebar`：visionOS 窗口侧主导航，类似移动端底部 Tab Bar。它用于切换 Files / Scenes / Settings 等主目的地，不是 Files 页内部左列。
- `Main Window Preview`：主窗口 Preview，包含 Files / Scenes / Settings，并允许在该 Preview 内通过 `Sidebar` 切换。
- `Video Detail / Playback Preparation Preview`：视频详情 / 播放准备 Preview，承载视频信息、播放前设置和播放模式选择。
- `Window Playback Preview`：窗口播放 Preview，承载普通窗口播放中的控件、时间轴、菜单、隐藏 / 显示等交互。
- `Immersive Space Preview`：未来预留的沉浸空间 Preview，表现真正进入 `ImmersiveSpace` 后的空间体验。
- `Panorama Preview`：未来预留的全景模式 Preview，表现全景 / 180 / 360 视频观看状态。
- `Source Pane`：Files 目的地中的位置窗格，用于本地存储、SMB、WebDAV 和文件夹位置等来源。
- `Player Control Panel`：完整的播放控制浮层，包括底部传输控制、进度、顶部标题区域、返回控制和辅助控制。
- `Timeline`：用于精细拖动和逐帧审查的二级精度时间轴。
- `Empty Panel`：窗口模式 app 表面的系统 `WindowGroup` 外壳。它是 Scene 层级的窗口语义，不是 Page，也不是普通 View 资产。
- `Window Content`：放置在系统 `WindowGroup` 外壳内部的页面内容。
- `Preview Stage`：仅用于 Canvas 审查的包装层，可以把 `Window Content` 与窗口侧 `Sidebar` 或其他审查辅助层并列展示。
- `DesignCompsPreviewGallery`：Xcode Canvas 审查入口，用于分组展示具名 Preview Canvas。

## Preview Canvas 边界

当前正式维护 3 个 Preview Canvas：

- 主窗口 Preview：Files / Scenes / Settings 通过 `Sidebar` 在同一 Preview 内切换。Scenes 可以表现窗口内容消失、透明 volume / 体积中展示场景卡；这仍是主窗口 Preview 内部状态。
- 视频详情 / 播放准备 Preview：显示选中视频后的详情、字幕、音轨、续播、播放模式选择和播放入口。
- 窗口播放 Preview：显示普通窗口播放中的视频画面、播放控件、时间轴、菜单、控件隐藏 / 显示等状态。

未来预留 2 个 Preview Canvas：

- 沉浸空间 Preview：真正进入 `ImmersiveSpace` 后的空间体验。
- 全景模式 Preview：全景 / 180 / 360 视频观看体验。

当前阶段先维护正式 3 个 Preview Canvas。未来预留 Canvas 等明确启动时再创建或扩写。

## 文件组织

- 采用适度模块化：主要 Preview Canvas、主要 `Sidebar` 目的地、复杂区域可以拆成 Swift 文件。
- 小交互保留在所属页面文件内部，例如 hover、press、菜单展开、sheet、filter、设置项展开。
- 当页面细节过多、需要分步校准时，再把大区块拆到 `Sections/`。
- `Pages/` 放主要页面和可被 Preview Canvas 组合的页面状态。
- `Windows/` 放窗口外壳、Preview Stage、`EmptyPanelWindowContent` 等 scene/window 语义辅助层。
- `Overlays/` 放 sheet、popover、menu、share panel 和其他浮动表面。
- `Assets/` 放 SwiftUI asset comps、图标处理和非窗口纯视觉资产。
- `Fixtures/` 放只供 `DesignComps` 使用的假数据。

## 构建规则

- 除非用户明确要求修改，否则保持 `ContentView.swift`、`ComponentLibrary.swift` 和 `SharedComponents.swift` 作为已确认组件库 / UI kit 来源。
- 添加新的局部结构之前，先直接复用现有组件和 `DesignTokens`。不要把组件内部实现复制到页面里，只为近似同一种外观。
- 新 Preview Canvas 从系统 `WindowGroup` / `EmptyPanelWindowContent` / Preview Stage 语义出发，按需要呈现窗口、`Sidebar`、volume 或其他审查表面。
- `Sidebar` 可以作为主窗口 Preview 内部交互出现；跨 Preview 的真实流程跳转留到未来 FakeApp 阶段。
- Empty Panel 的系统窗口语义由 `WindowGroup` 和 Scene 配置拥有。Canvas 中的包装层只表达审查所需的窗口内容或舞台。
- 使用 `DesignCompsPreviewGallery.swift` 作为具名 Preview Canvas 的审查入口。页面局部 `#Preview` 用于隔离组件工作；根审查入口保持为 Preview Canvas 总览。
- 当骨架需要提高审查清晰度时，使用简短区域标签。这些标签是设计审查标签，不是产品文案。
- 组件库中已有的控件直接复用。创建局部占位之前，先直接调用 `PlayerProgressStrip`、`PlayerControlBar`、`VideoCardLarge`、`FolderCard`、`FileListRow`、`MenuItemRow`、`SceneCardMedium`、`ViewModeCapsuleControl`、`MockBreadcrumb`、`PathBreadcrumbMenu`、`SearchInputCapsule`、`FilterPillBar`、`SourcePaneRow` 及相关组件。
- 局部预览状态只服务视觉状态检查，真实业务逻辑留给产品实现层。
- 在播放器子菜单的顶层面板语义稳定之前，保留为局部状态或占位，不展开成跨 Preview 流程。
