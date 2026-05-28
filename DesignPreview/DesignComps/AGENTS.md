# DesignComps Agent 说明

`DesignComps` 存放从 `docs/designs/` 派生出的高保真可交互 Preview Canvas。
这些文件是视觉设计资产，用于审查主要体验状态。跨 Preview 的产品流程、导航状态同步、返回链路和假业务生命周期属于未来 FakeApp 阶段。

## 文档语言

- `DesignPreview` 内的 Agent 文档和 README 使用中文书写。
- Swift 类型名、文件名、Apple / visionOS 专有名词、组件名和代码标识保留原文。

## 术语

- `Preview Canvas`：Canvas 中用于审查一个主要体验状态的高保真预览。它可以包含局部交互。
- `Main Window Preview`：主窗口 Preview，包含 Files / Settings，并通过系统 `TabView` 的 Scene 入口打开 SenseZone Volume。
- `SenseZone Volume Preview`：Scenes 目的地的 volumetric `WindowGroup`，直接显示 Scene Card 组件，不渲染主窗口玻璃面板，也不保留 `Tab Bar Ornament`。
- `Window Playback Preview`：窗口播放 Preview，承载独立 16:9 `WindowGroup` 中的播放画面、控件、时间轴、菜单、隐藏 / 显示等交互，不沿用主窗口的 `TabView`。
- `Immersive Space Preview`：未来预留的沉浸空间 Preview，表现真正进入 `ImmersiveSpace` 后的空间体验。
- `Panorama Preview`：未来预留的全景模式 Preview，表现全景 / 180 / 360 视频观看状态。
- `Source Sidebar`：Files 目的地中的 sidebar，用于本地存储、SMB、WebDAV 和文件夹位置等来源。
- `Player Control Panel`：完整的播放控制浮层，包括底部传输控制、进度、顶部标题区域、返回控制和辅助控制。
- `Timeline`：用于精细拖动和逐帧审查的二级精度时间轴。
- `Empty Panel`：窗口模式 app 表面的系统 `WindowGroup` 外壳。它是 Scene 层级的窗口语义，不是 Page，也不是普通 View 资产。
- `Window Content`：放置在系统 `WindowGroup` 外壳内部的页面内容。
- `Preview Stage`：仅用于 Canvas 审查的包装层，可以把 `Window Content`、volume 或其他审查辅助层并列展示。
- `DesignCompsPreviewGallery`：Xcode Canvas 审查入口，用于分组展示具名 Preview Canvas。

## Preview Canvas 边界

当前正式维护 3 个 Preview Canvas：

- 主窗口 Preview：Files / Settings 留在主窗口；Scene 入口打开 SenseZone Volume。SenseZone Volume 只显示 Scene Card 组件，左上返回按钮回到进入前的主窗口目的地。
- SenseZone Volume Preview：Scenes 目的地的 volumetric `WindowGroup`，直接显示 Scene Card 组件。
- 窗口播放 Preview：显示独立 16:9 播放窗口中的视频画面、播放控件、时间轴、菜单、控件隐藏 / 显示等状态。
- 窗口播放 Preview 的视频区域按真实播放窗口的 render surface 语义建模：使用跟随播放边界 resize 的播放 surface fixture；当前视觉阶段可以用静态图片作为视频帧内容，但不能把图片、`UIImageView`、手写像素尺寸或外层壳当作播放窗口 / 分辨率模型。
- 修改窗口播放 Preview 前，先读 `../../docs/solutions/best-practices/window-playback-preview-fixture.md`。该文档是 Apple demo 对照、Canvas / Simulator / 生产管线边界、resize 调查和 fixture 验收清单的接力入口；新的调查结论必须持续回写。

未来预留 2 个 Preview Canvas：

- 沉浸空间 Preview：真正进入 `ImmersiveSpace` 后的空间体验。
- 全景模式 Preview：全景 / 180 / 360 视频观看体验。

当前阶段先维护正式 3 个 Preview Canvas。未来预留 Canvas 等明确启动时再创建或扩写。

## 文件组织

- 采用适度模块化：主要 Preview Canvas、主要目的地、复杂区域可以拆成 Swift 文件。
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
- 新 Preview Canvas 从系统 `WindowGroup` / `EmptyPanelWindowContent` / Preview Stage 语义出发，按需要呈现窗口、volume 或其他审查表面。
- SenseZone Volume 不挂 `Tab Bar Ornament`；从主窗口进入时记录返回目的地，卡片左上返回按钮打开主窗口并关闭 volume。
- Xcode Canvas 中的主窗口 Preview 不作为跨 `WindowGroup` open / dismiss 的证明表面；Scene Card 审查使用具名 `SenseZone Volume` Preview。
- DesignComps 前端 / 视觉工作默认以 Xcode Canvas 为验证表面。Canvas 会自动刷新；普通布局、字号、padding、hover、列表和玻璃样式调整后，不主动运行 `xcodebuild`、`build_run_sim`、`Simulator`、`simctl screenshot` 或其他模拟器截图流程。
- 用户正在用 Canvas 审查时，只做静态检查、diff 和代码级确认；需要截图或视觉确认时，优先让 Canvas 承担，不用 Simulator 代替 Canvas。只有 Canvas 中断、资源未加载、编译错误不明确、需要证明跨 `WindowGroup` / volume / runtime lifecycle 行为，或用户明确要求时，才升级到 build / Simulator，并先说明升级原因。
- 如果误启动了普通 Simulator，任务结束前关闭该普通 Simulator 和对应 booted device；不要关闭 Xcode Canvas 自己的 Preview simulator / `PreviewShell` / `previewsd` 进程。
- Empty Panel 的系统窗口语义由 `WindowGroup` 和 Scene 配置拥有。Canvas 中的包装层只表达审查所需的窗口内容或舞台。
- 使用 `DesignCompsPreviewGallery.swift` 作为具名 Preview Canvas 的审查入口。页面局部 `#Preview` 用于隔离组件工作；根审查入口保持为 Preview Canvas 总览。
- 当骨架需要提高审查清晰度时，使用简短区域标签。这些标签是设计审查标签，不是产品文案。
- 组件库中已有的控件直接复用。创建局部占位之前，先直接调用 `PlayerProgressStrip`、`PlayerControlBar`、`VideoCardLarge`、`FolderCard`、`FileListRow`、`MenuItemRow`、`SceneCardMedium`、`ViewModeCapsuleControl`、`MockBreadcrumb`、`PathBreadcrumbMenu`、`SearchInputCapsule`、`FilterPillBar`、`SourceSidebarRow` 及相关组件。
- 局部预览状态只服务视觉状态检查，真实业务逻辑留给产品实现层。
- 在播放器子菜单的顶层面板语义稳定之前，保留为局部状态或占位，不展开成跨 Preview 流程。
- 当前不维护“点开播放卡片后的二级播放设置页面”。视频详情、播放前设置和跨 Preview 启动链路留到未来 FakeApp 或产品流程明确后再裁决。
