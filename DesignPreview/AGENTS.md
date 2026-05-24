# DesignPreview — 设计规范

规则针对 **visionOS**，其他平台不适用。

---

## DesignPreview 路由

- `ContentView.swift` / `ComponentLibrary.swift` / `SharedComponents.swift` 是现有 Component Library / UI Kit 资产库。页面必须直接复用其中已确认的按钮、卡片、列表、菜单、时间轴、窗格、搜索栏等组件；不要在页面局部仿写一个“看起来相似”的版本。
- `DesignComps/` 放从 `docs/designs/` HTML 设计稿拆出的高保真可交互 Preview Canvas。这里做的是设计审查用的 screen mockups；跨 Preview 的产品流程、导航状态同步、返回链路和假业务生命周期属于未来 FakeApp 阶段。
- 当前正式维护 3 个可交互 Preview Canvas：主窗口 Preview、视频详情 / 播放准备 Preview、窗口播放 Preview。沉浸空间 Preview 和全景模式 Preview 是未来预留边界，等明确启动时再纳入当前范围。
- 主窗口 Preview 包含 Files / Scenes / Settings，并允许通过 visionOS 侧边 `Sidebar` 在内部切换。`Sidebar` 是窗口侧主导航，类似移动端底部 Tab Bar，不是 Files 页内部左列。
- 视频详情 / 播放准备 Preview 承载视频信息、播放前设置和播放模式选择。窗口播放 Preview 承载普通窗口播放中的控件、时间轴、菜单、隐藏 / 显示等交互。
- Preview 内部可以有局部 hover、press、展开、菜单、sheet、Sidebar 切换等小交互。Preview 之间保持并列审查关系；从文件进入详情、从详情进入播放、从窗口播放进入沉浸空间等跨 Preview 流程留到未来 FakeApp 阶段。
- 新建 DesignComp 前先读 `docs/designs/` 中对应 HTML，参考设计稿决定页面数量、名称、窗口尺寸和交互范围。
- 稳定组件必须直接调用现有 components，需要新的视觉形态且组件库没有对应组件时，上报需求要求人类裁决。
- Xcode Canvas / Design Preview 已在运行，视觉微调优先观察 Canvas 自动刷新；不要每次小改后都主动执行 build。只有遇到 Canvas 失败、资源未加载、编译错误不明确、或需要交付前自动化确认时，才单独运行 build。

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
