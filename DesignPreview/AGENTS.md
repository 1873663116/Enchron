# DesignPreview — 设计规范

规则针对 **visionOS**，其他平台不适用。

---

## DesignPreview 路由

- `ContentView.swift` / `ComponentLibrary.swift` / `SharedComponents.swift` 是现有 Component Library / UI Kit 资产库。页面必须直接复用其中已确认的按钮、卡片、列表、菜单、时间轴、窗格、搜索栏等组件；不要在页面局部仿写一个“看起来相似”的版本。
- `DesignComps/` 放从 `docs/designs/` HTML 设计稿拆出的高保真可交互 Preview Canvas。这里做的是设计审查用的 screen mockups；跨 Preview 的产品流程、导航状态同步、返回链路和假业务生命周期属于未来 FakeApp 阶段。
- 当前正式维护 3 个可交互 Preview Canvas：主窗口 Preview、SenseZone Volume Preview、窗口播放 Preview。沉浸空间 Preview 和全景模式 Preview 是未来预留边界，等明确启动时再纳入当前范围。
- 主窗口 Preview 包含 Files / Settings，并允许通过系统 `TabView` 的 Scene 入口打开 SenseZone Volume。SenseZone Volume 不保留 `Tab Bar Ornament`，只显示 Scene Card 组件与卡片内返回控件；返回时回到进入前的主窗口目的地。
- 当前不维护“点开播放卡片后的二级播放设置页面”。播放前配置、详情页和跨 Preview 启动链路留到未来 FakeApp 或产品流程明确后再裁决。
- 窗口播放 Preview 承载独立 16:9 `WindowGroup` 中的播放画面、控件、时间轴、菜单、隐藏 / 显示等交互；它不沿用主窗口的 `TabView`。
- 窗口播放 Preview 的视频区域应按真实播放窗口的 render surface 语义建模：使用跟随播放边界 resize 的播放 surface fixture；当前视觉阶段可以用静态图片作为视频帧内容，但不能把图片、`UIImageView`、手写像素尺寸或外层壳当作播放窗口 / 分辨率模型。
- 修改窗口播放 Preview 前，先读 `../docs/solutions/best-practices/window-playback-preview-fixture.md`；其中记录 Apple demo 对照、Canvas / Simulator / 生产管线边界、resize 调查和当前 fixture 验收清单。新的调查结论必须回写该文档。
- Preview 内部可以有局部 hover、press、展开、菜单、sheet、Scene volume 进入 / 返回等小交互。Preview 之间保持并列审查关系；从文件进入详情、从详情进入播放、从窗口播放进入沉浸空间等跨 Preview 流程留到未来 FakeApp 阶段。
- 新建 DesignComp 前先读 `docs/designs/` 中对应 HTML，参考设计稿决定页面数量、名称、窗口尺寸和交互范围。
- 稳定组件必须直接调用现有 components，需要新的视觉形态且组件库没有对应组件时，上报需求要求人类裁决。
- DesignPreview 前端 / 视觉工作默认以 Xcode Canvas 为验证表面。Canvas 会自动刷新；普通布局、字号、padding、hover、列表和玻璃样式调整后，不主动运行 `xcodebuild`、`build_run_sim`、`Simulator`、`simctl screenshot` 或其他模拟器截图流程。
- 用户正在用 Canvas 审查时，只做静态检查、diff 和代码级确认；需要截图或视觉确认时，优先让 Canvas 承担，不用 Simulator 代替 Canvas。只有 Canvas 中断、资源未加载、编译错误不明确、需要证明跨 `WindowGroup` / volume / runtime lifecycle 行为，或用户明确要求时，才升级到 build / Simulator，并先说明升级原因。
- 如果误启动了普通 Simulator，任务结束前关闭该普通 Simulator 和对应 booted device；不要关闭 Xcode Canvas 自己的 Preview simulator / `PreviewShell` / `previewsd` 进程。Canvas 中的主窗口 Preview 不证明跨 `WindowGroup` open / dismiss；Scene Card 视觉审查使用具名 SenseZone Volume Preview。

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
