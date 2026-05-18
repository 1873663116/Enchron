# HelloWorld 对照验证报告 (T1.2)

> 生成时间: 2026-04-02 (v3 Round 11)
> 数据源: T0.2 `helloworld-ux-audit-v3.md` (12 项) + T1.1 QA 结果 (59 路径)
> 方法: Sonnet Agent 逐项读取代码验证 + Supervisor 综合裁决

---

## 总结

| 状态 | 数量 | 项目 |
|------|------|------|
| 需改进 | 8 | UX-01~08 |
| 已符合 | 3 | UX-10, REJECT-01, REJECT-02 |
| 不适用 | 1 | UX-09 |

---

## 逐项验证

### UX-01: DragRotationModifier — 拖拽旋转 + 弹性动画 + 惯性
**状态**: 需改进
**证据**:
- `SpatialScene/Modifiers/DragRotationModifier.swift` 不存在
- `MainView.swift:136` — `.drag` case 是 `break`（空操作），QA-H04 FAIL
- `ImmersiveSpaceView.swift` 无任何 drag gesture / spring animation
- `DisambiguateGestureUseCase` 正确 emit `.drag`，但接收端不消费

**Phase 2 改进方案**:
1. 新建 `XrPlayer/SpatialScene/Modifiers/DragRotationModifier.swift`
2. 实现: `DragGesture.targetedToAnyEntity()` + `.interactiveSpring` + predictedEndLocation 惯性
3. 应用到 `ImmersiveSpaceView` 中的 PanoramaSphereEntity / VirtualScreenEntity
4. `MainView.swift:136` 的 `.drag` case 接入新 Modifier
**优先级**: P0（核心沉浸体验）

### UX-02: VideoDetailView 分栏响应式布局
**状态**: 需改进
**证据**:
- `PlayerUI/Views/VideoDetailView.swift:65-113` — `ScrollView > VStack(spacing: 24)` 纯纵向堆叠
- 无 `GeometryReader`，无 `HStack` 分栏，浪费 visionOS 宽屏横向空间

**Phase 2 改进方案**:
1. 外包 `GeometryReader`，宽度 > 阈值时 `HStack` 分栏
2. 左栏: 缩略图 + 标题 + 元数据
3. 右栏: 轨道选择 + 播放按钮 + 预览
**优先级**: P1

### UX-03: Glass Background Effect cornerRadius
**状态**: 需改进
**证据**:
- `PlayerControlsView.swift:81` — `.glassBackgroundEffect()` 无参数
- `PlaybackMenuView.swift:75` — `.glassBackgroundEffect()` 无参数
- `ScreenPositionControlView.swift:73` — `.glassBackgroundEffect()` 无参数
- 所有面板使用默认圆角，无视觉层次区分

**Phase 2 改进方案**:
1. `PlayerControlsView` → `.glassBackgroundEffect(in: .rect(cornerRadius: 32))`
2. `PlaybackMenuView` → `.glassBackgroundEffect(in: .rect(cornerRadius: 24))`
3. `ScreenPositionControlView` → `.glassBackgroundEffect(in: .rect(cornerRadius: 24))`
**优先级**: P1（小改动高收益）

### UX-04: SliderGridRow 可复用组件
**状态**: 需改进
**证据**:
- `PlayerUI/Components/SliderGridRow.swift` 不存在
- `ScreenPositionControlView.swift:35-66` — 三个独立 `VStack > Text + Slider` 块
- 无 `Grid` 容器，标签与数值无对齐

**Phase 2 改进方案**:
1. 新建 `XrPlayer/PlayerUI/Components/SliderGridRow.swift`
2. 三列 Grid: 标签 | Slider | 数值（monospacedDigit）
3. `ScreenPositionControlView` 改用 `Grid { SliderGridRow(...) }` 布局
**优先级**: P1

### UX-05: ImmersiveSpace 沉浸风格选择绑定
**状态**: 需改进
**证据**:
- `XrPlayerApp.swift:147` — `.immersionStyle(selection: .constant(.full), in: .full)` 硬编码
- `AppModel.swift` 无 `immersiveImmersionStyle` 属性
- QA-D05 PARTIAL — `screenShape` 不持久化（关联问题）

**Phase 2 改进方案**:
1. `AppModel` 添加 `var immersiveImmersionStyle: ImmersionStyle = .full`
2. `XrPlayerApp.swift` 改为 `.immersionStyle(selection: $appModel.immersiveImmersionStyle, in: .full, .mixed)`
3. 添加 UI 切换入口（设置或控件面板）
4. 同时修复 `screenShape` 持久化（通过 `PreferencesStoring`）
**优先级**: P1

### UX-06: 同时手势组合 (Drag + Magnify)
**状态**: 需改进
**证据**:
- `PlacementGesturesModifier.swift` 不存在
- `MagnifyGesture` 在整个代码库中不存在
- `.handActivationBehavior(.pinch)` 不存在
- 仅有 `DragGesture(minimumDistance: 0)` 用于消歧

**Phase 2 改进方案**:
1. 新建 `XrPlayer/SpatialScene/Modifiers/PlacementGesturesModifier.swift`
2. `.simultaneously(with:)` 组合 DragGesture + MagnifyGesture
3. 应用到沉浸空间 VirtualScreenEntity（拖拽移动 + 捏合缩放）
4. 添加 `.handActivationBehavior(.pinch)`
**优先级**: P1（与 UX-01 协同实施）

### UX-07: Window Management (openWindow/dismissWindow)
**状态**: 需改进
**证据**:
- `@Environment(\.openWindow)` 在代码库中不存在
- `XrPlayerApp.swift` 仅 1 个 `WindowGroup` + 1 个 `ImmersiveSpace`
- 无多窗口基础设施

**Phase 2 改进方案**:
1. `XrPlayerApp.swift` 注册第二个 `WindowGroup(id: "settings") { SettingsView() }`
2. 注入 `@Environment(\.openWindow)` / `@Environment(\.dismissWindow)`
3. 考虑将 ScreenPositionControl 或 PlaybackMenu 改为独立浮动窗口
**优先级**: P1（需评估架构影响）

### UX-08: FileCard/FolderCard 组件
**状态**: 需改进
**证据**:
- 无 `FileCard` / `FolderCard` 类型
- `FolderListView.swift:68-153` 使用 `Button { HStack }` 内联渲染
- 无提取的卡片组件，视觉一致性依赖内联代码

**Phase 2 改进方案**:
1. 新建 `XrPlayer/FileBrowsing/Components/FileCard.swift` + `FolderCard.swift`
2. 统一卡片样式: 圆角 + material background + thumbnail
3. `FolderListView` 改用提取的组件
**优先级**: P2

### UX-09: Settings Button ViewModifier
**状态**: 不适用
**证据**:
- 设置按钮在 `PlayerControlsView.swift:264-278` 定义为 `private var playbackSettingsButton`
- 仅单一使用点，提取 ViewModifier 无收益
**理由**: 单站点模式对播放器合理，无需过度抽象

### UX-10: Ornament 辅助锚定
**状态**: 已符合
**证据**:
- `MainView.swift:97` — `.ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center)`
- `.scene(.bottom)` 是媒体控制条的标准锚定，符合 visionOS HIG
**理由**: 底部居中是全宽控制条的正确位置，`.bottomTrailing` 适用于辅助按钮

### REJECT-01: 合并为单一 ViewModel
**状态**: 已符合（维持驳回）
**证据**:
- `WindowVideoViewModel.swift` 和 `FileBrowsingViewModel.swift` 独立存在
- `AppModel` 作为跨切面协调器
- 多 ViewModel 符合 DDD 5 限界上下文设计

### REJECT-02: 简化 ImmersiveSpace 状态机
**状态**: 已符合（维持驳回）
**证据**:
- `AppModel.swift:10-15` — 3 态 `.closed / .inTransition / .open`
- `.inTransition` 在 `PlayerControlsView.swift:398` 用于 `.disabled()` 防止过渡期操作
- 3 态比 2 态更健壮，防止 race condition

---

## Phase 2 修复优先级汇总

| 优先级 | UX 项 | 工作量 | 与 QA 缺陷关联 |
|--------|-------|--------|----------------|
| P0 | UX-01 DragRotationModifier | 中 | QA-H04 FAIL |
| P1 | UX-02 VideoDetailView 分栏 | 中 | — |
| P1 | UX-03 Glass cornerRadius | 小 | — |
| P1 | UX-04 SliderGridRow | 小 | — |
| P1 | UX-05 ImmersionStyle 绑定 | 小 | QA-D05 PARTIAL |
| P1 | UX-06 Drag+Magnify 手势 | 中 | QA-H04 关联 |
| P1 | UX-07 Window Management | 中 | — |
| P2 | UX-08 FileCard/FolderCard | 小 | — |

**合计**: 8 项需改进，预计 Phase 2 T2.2 实施
