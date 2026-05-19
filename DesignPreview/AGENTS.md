# DesignPreview — 设计规范

Enchron UI 参考。`ComponentLibrary.swift` 中的组件持续确认中，以人工标注为准。

规则针对 **visionOS**，其他平台不适用。

---

## Design Tokens 与动画裁决

- 所有 UI 样式值和动效参数必须走 `DesignTokens`。包括颜色、描边、圆角、间距、尺寸、动画曲线、动画时长、press feedback、loading timing。
- 不允许在 DesignPreview 组件或页面中写临时动画，例如裸 `.easeOut(...)`、`.spring(...)`、`.animation(.default...)`、临时 `Task.sleep(.milliseconds(...))`、临时 `scaleEffect` 参数。
- 如果现有 token 无法表达目标效果，必须上报人类裁决：由人类决定新增 token、调整组件语义，或取消该动画。不得为了“先看效果”把临时动画留在组件里。

---

## Hover

**Hover 范围不能超过视觉形状。**

视觉区不低于 44pt，命中区不低于 60pt。命中区大于视觉区时，通过 padding 静默扩展——扩展出的部分接收点击但不显示 Hover。视觉区与命中区相等时此规则不适用。

`.contentShape(.hoverEffect, 形状)` 必须在 `.hoverEffect()` 之前，形状必须与玻璃一致。

> 参考实现：`NavBackForwardCapsuleControl`

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
