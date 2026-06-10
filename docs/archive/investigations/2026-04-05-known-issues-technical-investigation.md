# Technical Investigation: Known Issues API Research

Date: 2026-04-05
Source: docs/plans/active/2026-04-05-known-issues-handoff.md

## 1. visionOS Hover Effect Shape Control

**问题**: 按钮是圆角矩形，hover 高亮为圆形

**API 事实**:
- `.hoverEffect(.highlight)` 在 visionOS 上强制圆形高亮，忽略自定义 `contentShape`
- `.hoverEffect(.lift)` 完全遵守 `contentShape` 定义，显示 3D 提升效果
- `.hoverEffect(.automatic)` 由系统自动选择

**代码现状**:
- `PlayerControlSurface.swift:46-47` — `.contentShape(RoundedRectangle)` + `.hoverEffect(.highlight)` 冲突
- `PlayerControlsView.swift` 多处 — `.contentShape(.circle)` + `.hoverEffect(.highlight)`

**修复策略**: 将 `.hoverEffect(.highlight)` 替换为 `.hoverEffect(.lift)`，使 hover 形状匹配 contentShape

---

## 2. visionOS Ornament Transition Behavior

**问题**: ornament 内控件出现时有位移动画，期望纯 opacity

**API 事实**:
- ornament 可能有内置 insertion/removal transition
- 当前代码（提交 f234be8）已实现 `.transition(.opacity)` + `.animation()` + `withAnimation` 包裹
- 多个 `showControls` 赋值点已用 `withAnimation` 包裹（MainView lines 154, 157, 172, 206, 211, 291）

**分析**:
- 代码逻辑已正确实现纯 opacity fade
- 如果问题仍存在，可能是 ornament 自身的默认 transition 覆盖了子视图设置
- 需要在模拟器/真机上验证当前行为

**修复策略**:
1. 先用模拟器验证当前是否还有位移动画
2. 若仍存在 → 在 ornament 层级禁用默认 transition：`.transition(.identity)`
3. 确保 animation context 统一

---

## 3. UIViewRepresentable Window Resize Response

**问题**: visionOS 窗口缩放时，Metal 渲染层尺寸不更新

**API 事实**:
- `updateUIView(_:context:)` 不会因窗口几何变化自动调用
- 仅当绑定的 @State/@Bindable 属性变化时才触发
- `autoresizingMask` 和 `setNeedsLayout()` 在此场景下效果有限

**代码现状**:
- `MPVNativeMetalLayerView.swift:11-19` — MoltenVK 1×1 workaround（不是根因）
- 根因：SwiftUI 未通知 UIViewRepresentable 发生几何变化

**修复策略**:
- **推荐方案**: 用 GeometryReader 包裹 WindowVideoView，将 geometry.size 传入，强制触发 updateUIView
- 备选：CADisplayLink 轮询 bounds 变化
- 同时检查 mpv 是否缓存了输出分辨率

---

## 已有调查（不重复）

- P1 播放模式层级约束：见 `docs/reference/2026-04-05-playback-mode-hierarchy-investigation.md`
