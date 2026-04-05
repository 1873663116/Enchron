# Enchron 设计参考 → SwiftUI 实现指南

本文档桥接 Web 设计 mockup 与 visionOS SwiftUI 原生实现。
核心原则：**能用系统组件就用系统组件**，不自造容器和动画。

参考项目：`~/Movies/HelloWorld`（Apple 官方 visionOS 示范）

---

## 1. 场景架构映射

### Web mockup 结构 → SwiftUI Scene

| Web mockup | SwiftUI Scene | 参考 |
|------------|---------------|------|
| 文件浏览器主窗口 (variant-AB-combined.html) | `WindowGroup { ... }.windowStyle(.plain)` | HelloWorld/WorldApp.swift |
| 播放前浮动面板 (overlay) | 同一 WindowGroup 内的 NavigationStack push，或 `.sheet()` | 不要用自定义 overlay 模拟弹窗 |
| 沉浸式播放器 (player.html) | `ImmersiveSpace(id:) { ... }.immersionStyle(selection: $style, in: .mixed)` | HelloWorld Orbit 模式 |
| 全景播放 | `ImmersiveSpace(id:).immersionStyle(selection: $style, in: .full)` | HelloWorld SolarSystem 模式 |

### 窗口与空间管理

```swift
// 参照 HelloWorld/WorldApp.swift
@main struct EnchronApp: App {
    @State private var immersionStyle: ImmersionStyle = .mixed
    
    var body: some Scene {
        WindowGroup("Enchron", id: "browser") {
            FileBrowserView().environment(viewModel)
        }
        .windowStyle(.plain)
        
        ImmersiveSpace(id: "player") {
            ImmersivePlayerView().environment(viewModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
    }
}
```

**不要自己管理窗口层叠。** 用系统 Environment：
```swift
@Environment(\.openWindow) private var openWindow
@Environment(\.dismissWindow) private var dismissWindow
@Environment(\.openImmersiveSpace) private var openImmersiveSpace
@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
```

**打开沉浸空间必须 `await` 并处理结果**（系统同时只允许一个 ImmersiveSpace）：
```swift
// 参照 HelloWorld/Orbit/OrbitToggle.swift
Button("进入沉浸模式") {
    Task {
        let result = await openImmersiveSpace(id: "player")
        switch result {
        case .opened: break              // 成功
        case .userCancelled: break       // 用户取消
        case .error: fallthrough         // 系统错误，回滚 UI 状态
        @unknown default: break
        }
    }
}
```

**切换沉浸风格**：直接修改绑定到 `.immersionStyle(selection:in:)` 的 `@State` 变量即可触发运行时切换：
```swift
// 从 .mixed 切到 .full（全景模式）
immersionStyle = .full
```

---

## 2. 导航 Ornament

### Web: 竖向导航 pill（窗口外）→ SwiftUI: `.ornament()`

```swift
// 概念参照 HelloWorld/Settings/SettingsButton.swift（原文件为底部齿轮 ornament）
.ornament(attachmentAnchor: .scene(.leading)) {
    VStack(spacing: 8) {
        NavButton(icon: "folder", isActive: true)
        NavButton(icon: "clock", isActive: false)
        NavButton(icon: "slider.horizontal.3", isActive: false)
        Divider().frame(width: 32)
        SceneSelectorButton()
    }
    .padding(12)
    .glassBackgroundEffect(in: .capsule)
}
```

**不要用 fixed position 模拟。** `.ornament()` 是 visionOS 原生的窗口外附着组件。

---

## 3. 毛玻璃材质

### Web: `backdrop-filter: blur()` + rgba → SwiftUI: `.glassBackgroundEffect()`

| Web CSS | SwiftUI | 何时用 |
|---------|---------|--------|
| `glass-window` (rgba + blur 50px) | `.glassBackgroundEffect(in: .rect(cornerRadius: 40))` | 主窗口面板 |
| `glass-control` (rgba + blur 40px) | `.glassBackgroundEffect(in: .capsule)` | 控件栏胶囊 |
| `glass-panel` (rgba + blur 50px) | `.regularMaterial` 或 `.glassBackgroundEffect()` | 弹出面板 |
| `glass-sidebar` (rgba 25%) | 无需额外材质，系统 List 自带层级色调 | 侧栏 |

```swift
// 参照 HelloWorld/Globe/GlobeControls.swift
HStack { ... }
    .padding()
    .glassBackgroundEffect(in: .rect(cornerRadius: 40))
```

**不要手动设置 `background(.ultraThinMaterial)`** 然后叠加 `opacity`。`glassBackgroundEffect` 一步到位。

**ZStack 约束**：在 `ZStack` 中使用时，将 `.glassBackgroundEffect()` 应用于 ZStack 本身，不要应用于 ZStack 内部的子视图，否则渲染效果不正确。

---

## 4. 圆角体系

### Web CSS 变量 → SwiftUI 常量

```swift
enum DesignToken {
    static let radiusCard: CGFloat = 20      // --radius-card: 1.25rem
    static let radiusWindow: CGFloat = 40    // --radius-window: 2.5rem
    static let radiusBadge: CGFloat = 10     // --radius-badge: 0.625rem
}
```

在 `glassBackgroundEffect` 中直接传入：
```swift
.glassBackgroundEffect(in: .rect(cornerRadius: DesignToken.radiusWindow))
```

**内外圆角同心法则**：
```
内圆角 = 外圆角 - 内边距
```
SwiftUI 的 `ContainerRelativeShape()` 会匹配最近容器的形状类型，但**不会自动减去 padding**。要实现真正的同心圆角，仍需手动计算 `innerRadius = outerRadius - padding`。

---

## 5. 色彩系统

### Web color tokens → SwiftUI Color Assets

在 Xcode Asset Catalog 中创建 Color Set：

| Token 名 | Hex | 用途 |
|----------|-----|------|
| surface | #131313 | 基底（通常不需要，系统处理） |
| onSurface | #E5E2E1 | 主文字 |
| onSurfaceVariant | #C1C6D7 | 次要文字 |
| tertiary | #ADC6FF | 强调色 |
| onTertiary | #002E6A | 强调色上的文字 |
| primary | #C6C6C7 | 主要按钮 |
| onPrimary | #2F3131 | 主要按钮文字 |

**不要硬编码 `Color(hex:)`。** 用 Asset Catalog，支持 Dark/Light 和 Accessibility 模式。

**类型安全的 Color 引用**（推荐模式，避免字符串字面量散落）：
```swift
extension Color {
    static let onSurface = Color("onSurface")
    static let onSurfaceVariant = Color("onSurfaceVariant")
    static let tertiary = Color("tertiary")         // 强调色 #ADC6FF
    static let enchronPrimary = Color("primary")    // 注意：不要用系统 Color.primary
}
```

> **警告**：SwiftUI 的 `Color.primary` 是系统语义色（暗色模式下近白），与项目 Asset Catalog 中的自定义 `primary` (#C6C6C7) 不同。代码中需要项目品牌色时，使用 `Color("primary")` 或上述 extension。

**背景色**：visionOS 窗口自带玻璃背景，**不要设置 `background(Color.surface)`**。让系统处理。

---

## 6. 字体

### Web: SF Pro (system font) → SwiftUI: 系统 Text Style

| Web mockup | SwiftUI Text Style | 使用场景 |
|------------|-------------------|---------|
| text-xl font-bold (标题) | `.font(.title2)` | 视频标题、页面标题 |
| text-sm font-semibold (卡片标题) | `.font(.headline)` | 视频卡片标题 |
| text-[11px] (元数据) | `.font(.caption)` | 分辨率、文件大小、日期 |
| text-[10px] uppercase (section header) | `.font(.caption2)` | "SOURCES"、"VIDEO METADATA" |
| text-xs (badge) | `.font(.caption)` | MV-HEVC、HDR10+ 标签 |

**不要用 `.font(.system(size: 10))`。** 用语义化 Text Style，系统自动处理 Dynamic Type 和观看距离适配。

---

## 7. 交互目标区域

### 60×60pt 最小注视目标

Web mockup 中按钮视觉上可以是 48px，但 SwiftUI 中必须确保注视目标区域 >= 60pt：

```swift
Button(action: { }) {
    Image(systemName: "folder")
        .font(.system(size: 22))   // 视觉尺寸小
}
.frame(minWidth: 60, minHeight: 60) // 注视目标区域大
.contentShape(.rect)                // 确保整个区域可交互
```

**系统组件自动满足**：SwiftUI 的 `Button`、`Toggle`、`Picker` 在 visionOS 上自动有足够的注视目标区域。不需要手动调整。只有自定义组件才需要注意。

---

## 8. 文件浏览器

### Web: sidebar + grid → SwiftUI: NavigationSplitView

```swift
// 不要自己拼 HStack { sidebar; content }
NavigationSplitView {
    // Sidebar: 数据源列表
    List(selection: $selectedSource) {
        Section("Sources") {
            ForEach(dataSources) { source in
                SourceRow(source: source)
            }
        }
        Section("Favorites") {
            Label("Starred Videos", systemImage: "star")
        }
    }
} detail: {
    // Content: 视频网格
    VideoGridView(source: selectedSource)
}
```

**侧栏用系统 `List`**，自带 visionOS 的选中高亮、hover 效果、无障碍。不需要自己实现 source-item hover 状态。

> **注意**：若 WindowGroup 使用了 `.windowStyle(.plain)`，NavigationSplitView ���侧栏会失去系统默认的玻璃背景。此时需要手动为侧栏内容添加 `.glassBackgroundEffect()` 或改用 `.windowStyle(.automatic)`。

### 视频网格

```swift
ScrollView {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 20) {
        ForEach(videos) { video in
            VideoCard(video: video)
        }
    }
}
```

用 `.adaptive(minimum:)` 替代 `grid-cols-3`，自动适应窗口缩放。

### 视频卡片 hover 效果

```swift
// visionOS 的 hover 效果是系统级的
VideoCard(video: video)
    .hoverEffect()           // 系统标准注视反馈
    .contentShape(.rect)
```

**不要用 CSS 的 translateY + scale 模拟。** `.hoverEffect()` 提供 visionOS 原生的"抬起"视觉反馈，包括阴影和高光变化。

### 多层空间 hover（badge 弹跳）

Web mockup 中卡片的 format badge 和 duration badge 有不同层的弹跳延迟。在 SwiftUI 中：

```swift
// 使用 .hoverEffect(.lift) 在不同 Z 深度的子视图上
// 系统会自动产生视差效果
ZStack {
    thumbnail
    formatBadge
        .offset(z: 4)     // 空间 Z 轴偏移
    durationBadge
        .offset(z: 8)     // 更高的 Z 偏移 = 更强的视差
}
.hoverEffect(.lift)
```

---

## 9. 播放前面板（预播放）

### Web: overlay panel → SwiftUI: NavigationStack push 或 sheet

```swift
// 方案 A: NavigationStack push（推荐，有系统返回手势）
NavigationLink(value: video) {
    VideoCard(video: video)
}
.navigationDestination(for: Video.self) { video in
    PrePlaybackView(video: video)
}

// 方案 B: sheet（模态呈现）
.sheet(item: $selectedVideo) { video in
    PrePlaybackView(video: video)
}
```

**不要用自定义 overlay + 动画模拟弹出面板。** 系统的 NavigationStack 或 sheet 自带正确的转场动画、手势返回、无障碍支持。

---

## 10. 播放控件栏

### Web: 底部 glass capsule → SwiftUI: 伴随窗口（非 `.ornament()`）

> **重要**：`.ornament()` 只能附着在 **Window** 的场景边界上，不能用在 ImmersiveSpace 的内容上。沉浸空间中的播放控件必须使用伴随窗口或 RealityKit Attachment。

```swift
// 方案 A（推荐）：伴随窗口 — 在 App 中声明独立 WindowGroup
WindowGroup("PlayerControls", id: "player-controls") {
    PlayerControlBar()
        .glassBackgroundEffect(in: .capsule)
}
.windowStyle(.plain)
.defaultSize(width: 600, height: 80)

// 打开沉浸空间时同时打开控件窗口
Task {
    let result = await openImmersiveSpace(id: "player")
    if case .opened = result {
        openWindow(id: "player-controls")
    }
}
```

```swift
// 方案 B：RealityKit Attachment（控件跟随空间中的锚点）
// 适用于需要将控件固定在 3D 空间特定位置的场景
RealityView { content, attachments in
    if let controlBar = attachments.entity(for: "controls") {
        controlBar.position = [0, -0.5, -1.5]
        content.add(controlBar)
    }
} attachments: {
    Attachment(id: "controls") {
        PlayerControlBar()
            .glassBackgroundEffect(in: .capsule)
    }
}
```

### 播放/暂停按钮

```swift
Button(action: togglePlayback) {
    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.title)
}
.frame(width: 64, height: 64)
.background(
    LinearGradient(
        colors: [Color("primary"), Color("primaryContainer")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
)
.clipShape(.circle)
```

### 进度条

```swift
// 使用系统 Slider，不要自己画进度条
Slider(value: $currentTime, in: 0...totalDuration)
    .tint(Color("tertiary"))
```

---

## 11. NLE 时间轴（二级进度条）

这是 Enchron 的特色功能，没有系统组件可用，**需要自定义实现**。

### 核心交互
- 固定播放头（中央竖线），拖拽轨道左右滚动
- 双指捏合缩放时间精度（MagnifyGesture）
- 逐帧步进按钮

```swift
struct NLETimelineView: View {
    @State private var timeOffset: CGFloat = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0  // 手势开始前的缩放基准
    
    var body: some View {
        ZStack {
            // 可拖拽的轨道
            TimelineTrack(offset: $timeOffset, zoom: zoomScale)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // 参照 HelloWorld/DragRotationModifier.swift
                            withAnimation(.interactiveSpring) {
                                timeOffset += value.translation.width
                            }
                        }
                )
                .simultaneousGesture(
                    // 双指捏合缩放 — 参照 HelloWorld/PlacementGesturesModifier.swift
                    MagnifyGesture()
                        .onChanged { value in
                            zoomScale = value.magnification * baseScale
                        }
                        .onEnded { _ in
                            baseScale = zoomScale  // 捕获当前缩放作为下次基准
                        }
                )
            
            // 固定播放头
            PlayheadLine()
        }
        .glassBackgroundEffect(in: .rect(cornerRadius: 20))
    }
}
```

---

## 12. 弹出菜单

### Web: 自定义 popup → SwiftUI: `.popover()` 或 `Menu`

```swift
// 简单菜单用系统 Menu
Menu {
    Section {
        Toggle("HDR10+", isOn: $isHDREnabled)
    }
    Section {
        Picker("Subtitles", selection: $subtitleTrack) {
            ForEach(subtitleTracks) { track in
                Text(track.name).tag(track)
            }
        }
        Picker("Audio", selection: $audioTrack) {
            ForEach(audioTracks) { track in
                Text(track.name).tag(track)
            }
        }
    }
    Section {
        Picker("Speed", selection: $playbackSpeed) {
            ForEach(PlaybackSpeed.allCases) { speed in
                Text(speed.label).tag(speed)
            }
        }
    }
} label: {
    Image(systemName: "line.3.horizontal")
}
```

**不要自己实现弹出菜单 + 子菜单 + 点击展开逻辑。** 系统 `Menu` 和 `Picker` 自带正确的层级、动画、无障碍和注视目标。

### 环境选择器

```swift
// 用 ScrollView + LazyVStack，不要自己实现滚动
.popover(isPresented: $showEnvironments) {
    ScrollView {
        LazyVStack(spacing: 8) {
            ForEach(environments) { env in
                Button {
                    currentEnv = env
                } label: {
                    EnvironmentCard(env: env, isSelected: env == currentEnv)
                }
                .buttonStyle(.plain)
            }
        }
    }
    .frame(width: 240, height: 320)
}
```

---

## 13. 动画原则

### 系统动画优先

| Web mockup 效果 | SwiftUI 实现 | 不要这样做 |
|----------------|-------------|-----------|
| hover 上浮 + 阴影 | `.hoverEffect(.lift)` | 自己写 translateY + shadow |
| 卡片按压 scale(0.95) | `.buttonStyle(.automatic)` | 自己写 scaleEffect |
| 面板弹出 scale + opacity | `.sheet()` 或 `.popover()` 的系统转场 | 自己写 withAnimation { opacity = 1 } |
| 控件淡入淡出 | `.transition(.opacity)` | 自己写 timer + opacity toggle |
| 弹性回弹 | `.spring` 或 `.interactiveSpring` | 自己写 cubic-bezier |

```swift
// 参照 HelloWorld/Modifiers/DragRotationModifier.swift
// 拖拽中用 interactiveSpring（即时响应）
withAnimation(.interactiveSpring) { ... }

// 拖拽结束用 spring（弹性归位）
withAnimation(.spring) { ... }
```

### 动画速度

```swift
// 参照 HelloWorld/Globe/GlobeControls.swift
.animation(.default.speed(2), value: isVisible)     // 快速出现
.animation(.default.speed(0.25), value: isFading)   // 缓慢消失
```

### Reduce Motion

```swift
// 参照 HelloWorld/Solar System/SolarSystemControls.swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// 在 reduceMotion 开启时，跳过装饰性动画
if !reduceMotion {
    withAnimation(.spring) { ... }
} else {
    // 直接设值，无动画
}
```

---

## 14. 控件自动隐藏

### Web: setTimeout + mousemove → SwiftUI: 系统行为

visionOS 的系统播放器控件自动处理隐藏/显示。如果使用自定义控件：

```swift
@State private var controlsVisible = true
@State private var lastInteractionTime = Date()

var body: some View {
    ZStack { ... }
        .onTapGesture {
            withAnimation { controlsVisible = true }
            lastInteractionTime = Date()  // 重置计时器
        }
        .task(id: lastInteractionTime) {
            // 每次交互重置：task(id:) 在 id 变化时自动取消旧 Task 并启动新 Task
            do {
                try await Task.sleep(for: .seconds(5))
                withAnimation { controlsVisible = false }
            } catch {
                // Task 被取消（用户交互触发了新 task），不执行隐藏
            }
        }
}
```

**不要用 Timer + onAppear/onDisappear。** 用 Swift Concurrency 的 `Task.sleep`。

---

## 15. 无障碍（不可省略）

```swift
// 参照 HelloWorld 的无障碍实践

// 1. 注视焦点管理
@AccessibilityFocusState var focusedElement: ElementID?

// 2. 朗读排序
.accessibilitySortPriority(3)

// 3. 自定义动作
.accessibilityAction(named: "Play") { startPlayback() }
.accessibilityAction(named: "Next Frame") { stepForward() }

// 4. 标签
.accessibilityLabel("Interstellar, 4K HDR, 42.8 GB")
.accessibilityHint("Double tap to open video details")
```

---

## 16. 不应自定义的组件清单

以下组件**必须使用系统原生**，不得自造：

| 组件 | 系统 API | 理由 |
|------|---------|------|
| 导航 | `NavigationStack` / `NavigationSplitView` | 手势返回、无障碍、转场动画 |
| 侧栏 | `List` in NavigationSplitView | 选中高亮、hover 效果、VoiceOver |
| 弹出菜单 | `Menu` / `.popover()` | 层级、定位、注视目标自动满足 |
| 选择器 | `Picker` (.segmented / .menu) | 无障碍、语义 |
| 开关 | `Toggle` | 无障碍状态播报 |
| 进度条 | `Slider` | 拖拽手势、无障碍数值播报 |
| 窗口外面板 | `.ornament()`（仅限 Window，不可用于 ImmersiveSpace） | 空间定位、窗口生命周期 |
| 弹窗 | `.sheet()` | 转场、手势返回（注意：`.fullScreenCover()` 在 visionOS 不可用） |
| hover 反馈 | `.hoverEffect()` | 注视反馈、系统一致性 |
| 毛玻璃 | `.glassBackgroundEffect()` | 深度模糊、环境光 |

---

## 17. 可以自定义的组件

| 组件 | 理由 | 注意事项 |
|------|------|---------|
| NLE 时间轴 | 系统无对应组件 | 手势用 DragGesture + MagnifyGesture |
| 视频卡片 | 需要自定义布局（缩略图 + badge + 元数据） | 用 `.hoverEffect()` 而非自造 |
| 环境选择器轮播 | 特殊的横向滚动选择器 | 可考虑 ScrollView + scrollTargetBehavior(.viewAligned) |
| 播放头指示器 | NLE 时间轴特有 | 纯视觉元素 |
| 场景选择按钮（双三角图标）| 品牌特色图标 | 做成 SF Symbol 自定义符号 |
