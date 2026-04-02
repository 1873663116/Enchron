# ExecPlan 039 — UX-03 Glass cornerRadius + UX-04 SliderGridRow + UX-05 ImmersionStyle 动态绑定

> Round 20 | Phase 2 T2.2 | 2026-04-02

## Goal
三个 P1 视觉/交互改进，均为"small"级别，合并为一轮执行：
1. **UX-03** — Glass Background Effect 添加自定义 cornerRadius，提升视觉层次
2. **UX-04** — 新建 SliderGridRow 可复用组件，重构 ScreenPositionControlView 布局
3. **UX-05** — ImmersionStyle 从 `.constant(.full)` 改为动态绑定，支持 .mixed / .full 切换

## Reference: HelloWorld Patterns
- GlobeControls.swift: `.glassBackgroundEffect(in: .rect(cornerRadius: 50))` 主控件
- SliderGridRow.swift: Grid 三列布局（标签 | 滑条 | 数值）
- WorldApp.swift: `.immersionStyle(selection: $orbitImmersionStyle, in: .mixed)` 动态绑定

## Changes

### UX-03: Glass cornerRadius (3 line changes)
1. `PlayerControlsView.swift` → `.glassBackgroundEffect(in: .rect(cornerRadius: 32))`
2. `PlaybackMenuView.swift` → `.glassBackgroundEffect(in: .rect(cornerRadius: 24))`
3. `ScreenPositionControlView.swift` → `.glassBackgroundEffect(in: .rect(cornerRadius: 24))`

### UX-04: SliderGridRow 组件
4. NEW: `XrPlayer/PlayerUI/Components/SliderGridRow.swift`
   - Grid 三列布局: 标签 | Slider | 数值(monospacedDigit + bold + trailing)
   - 参数: label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String
5. EDIT: `ScreenPositionControlView.swift` — 重构用 Grid { SliderGridRow } 替换现有 VStack 布局

### UX-05: ImmersionStyle 动态绑定
6. EDIT: `XrPlayer/App/AppModel.swift` — 添加 `@Published var immersiveImmersionStyle: ImmersionStyle = .full`
7. EDIT: `XrPlayer/App/XrPlayerApp.swift` — 改为 `.immersionStyle(selection: $appModel.immersiveImmersionStyle, in: [.mixed, .full])`
8. EDIT: `XrPlayer/PlayerUI/Views/SettingsView.swift` — 在 Appearance 或新的 Playback 区域添加沉浸风格 Picker

## Constraints
- `swift build` 零 error
- `swift test` 248 passed, 0 failures (no regressions)
- 不改变现有 ImmersiveSpace 状态机逻辑（3 态状态机保持不变）
- ScreenPositionControlView 功能不变，只是布局优化
- SliderGridRow 新建文件，不修改任何现有 UseCase 层

## QA Impact
- UX-03: 视觉改进，无 QA 路径直接对应
- UX-04: ScreenPositionControlView 布局改进，QA-D02/D03 受益
- UX-05: ImmersiveSpace 可切换风格，QA-D01 受益
