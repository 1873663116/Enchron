# DesignPreview — 设计规范

Enchron UI 参考。`ComponentLibrary.swift` 中的组件持续确认中，以人工标注为准。

规则针对 **visionOS**，其他平台不适用。

---

## DesignPreview 路由

- `ContentView.swift` / `ComponentLibrary.swift` / `SharedComponents.swift` 是现有 Component Library / UI Kit 资产库。页面必须直接复用其中已确认的按钮、卡片、列表、菜单、时间轴、窗格、搜索栏等组件；不要在页面局部仿写一个“看起来相似”的版本。
- `DesignComps/` 放从 `docs/designs/` HTML 设计稿拆出的高保真页面稿。这里做的是 design comps / screen mockups，不是最终 Fake UX。
- `DesignComps/Pages/` 目前只承载两个窗口化页面：文件页面与播放/窗口交互页面。页面内部可以呈现需要校准的窗口化交互状态；沉浸空间与全景模式不在当前 DesignPreview 页面范围内。`Sections/` 只在页面细节过多、需要分步校准时拆出大区域；`Overlays/` 放 sheet、popover、menu、share panel；`Assets/` 放图标等视觉资产；`Fixtures/` 放假数据。
- 新建 DesignComp 前先读 `docs/designs/` 中对应 HTML，按真实设计稿决定页面数量和名称，不凭空发明页面数、窗口尺寸或最终流程。
- DesignComp 可以有局部 hover、press、展开、菜单、sheet 等小交互；不要接真实业务逻辑，也不要把它提前串成 Fake UX。
- 稳定组件必须直接调用现有资产库。只有当 HTML 中出现新的视觉形态且组件库没有对应组件时，才在明确范围内新增组件或 token。
- Xcode Canvas / Design Preview 已在运行时，视觉微调优先观察 Canvas 自动刷新；不要每次小改后都主动执行完整 build。只有遇到 Canvas 失败、资源未加载、编译错误不明确、或需要交付前自动化确认时，才单独运行 build。

---

## Design Tokens 与动画裁决

- Confirmed / production component 的 UI 样式值和动效参数必须走 `DesignTokens`。包括颜色、描边、圆角、间距、尺寸、动画曲线、动画时长、press feedback、loading timing。
- Design exploration 可以在局部页面稿里使用临时值，但要用 `// EXPLORATORY:` 标记目的和移除条件；这类值不能进入 `ComponentLibrary.swift`、`SharedComponents.swift` 或稳定组件库。
- 从探索稿提升为稳定组件前，临时值要转成 token、共享组件参数，或记录明确例外。未确认的裸 `.easeOut(...)`、`.spring(...)`、`.animation(.default...)`、临时 `Task.sleep(.milliseconds(...))`、临时 `scaleEffect` 参数不能作为稳定实现留下。
- 如果 confirmed component 的目标效果无法由现有 token 表达，上报人类裁决：新增 token、调整组件语义、记录例外，或取消该动画。

---

## Hover

**Hover 范围不能超过视觉形状。**

视觉区不低于 44pt，命中区不低于 60pt。命中区大于视觉区时，通过 padding 静默扩展——扩展出的部分接收点击但不显示 Hover。视觉区与命中区相等时此规则不适用。

`.contentShape(.hoverEffect, 形状)` 必须在 `.hoverEffect()` 之前，形状必须与玻璃一致。

> 参考实现：`NavBackForwardCapsuleControl`

### visionOS Gaze Hover

visionOS 的 Hover 是 gaze / focus 语义，不等同于 iOS、iPadOS、macOS 的指针 hover。实现 hover 状态时，优先接入系统 hover effect 管线，并用明确的 hover shape 表达可注视区域。

普通 `onHover` 不能作为 visionOS gaze 的默认可靠来源；只有在实测确认符合目标设备行为时才使用。

**隐含假设**
- padding 四边均匀；非均匀扩展时命中区尺寸需单独计算。
- 形状为规则凸形（Circle / Capsule / RoundedRectangle）；异形组件另行处理。

---

## 玻璃形状一致性

`clipShape(X)` 和 `glassBackgroundEffect(in: X)` 必须使用同一个形状，不能错配。

> 参考实现：`DesignPreview` 中任意控件

**隐含假设**
- 不仅类型相同，参数也必须相同（如 cornerRadius 值）；同类型但参数不同也算错配。
- 两者同时存在时规则生效；只用其中一个时无需对齐。

---

## 多分区胶囊

Capsule 内有多个点击区时，不用嵌套 Button（命中区互相干扰）。用 `SpatialTapGesture` + `value.location.x` 判断落点分区。

> 参考实现：`NavBackForwardCapsuleControl` / `ViewModeCapsuleControl`
> Apple Doc：`SpatialTapGesture` — developer.apple.com/documentation/swiftui/spatialtapgesture

**隐含假设**
- 默认两区均分（`x < width/2`）；三区或非均分需改写阈值逻辑。
- 默认水平布局；垂直分区改用 `y` 轴。

### 点击反馈

`SpatialTapGesture` 无内置 press 动效，需手动实现。规则（经设备与系统 Button 对比确认）：

- 只用 `scaleEffect`，不加 opacity
- 参数必须来自 `DesignTokens.PressFeedback`
- 普通组件优先使用 `.enchronPressFeedback(...)`
- 多分区胶囊保留 `SpatialTapGesture` 分区命中逻辑，但 press 参数仍必须读取 `DesignTokens.PressFeedback`

> 参考实现：`NavBackForwardCapsuleControl.pressedSide`

**隐含假设**
- scale 作用于子图标，而非整个胶囊；如需整体缩放，动画挂载点不同。
