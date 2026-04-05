---
title: "visionOS SwiftUI Migration Pitfalls: Sheet Binding, WindowGroup Lifecycle, and Menu Constraints"
date: 2026-04-05
category: best-practices
module: PlayerUI, App
problem_type: best_practice
component: tooling
severity: high
applies_when:
  - Migrating SwiftUI views from navigationDestination to .sheet(item:)
  - Adding companion WindowGroup for immersive mode controls
  - Replacing custom panel views with system Menu components
  - Decomposing compound requirements into implementation units
tags:
  - visionos
  - swiftui
  - sheet-migration
  - windowgroup-lifecycle
  - menu-constraints
  - plan-review
---

# visionOS SwiftUI Migration Pitfalls

## 背景

Enchron UI/UX 重构的工程审查 + 对抗性审查中发现四类平台陷阱。这些问题在计划阶段被捕获，避免了实施阶段的 crash、功能丢失和竞争条件。

## 指导原则

### 1. `.sheet(item:)` 迁移：清除手动 nil 赋值

从 `.navigationDestination(isPresented:)` 迁移到 `.sheet(item:)` 时，SwiftUI 通过 binding nil 化自动管理 sheet 生命周期。如果旧代码中有手动 `viewModel.request = nil` 赋值（触发导航返回），这些赋值会与 SwiftUI 的 binding 管理竞争。

```swift
// BEFORE: navigationDestination 模式
// VideoDetailView 内部 6 处手动 nil 赋值：
func confirmPlayback() {
    coordinator.confirmPlayback(prepared)
    fileBrowsingViewModel.detailNavigationRequest = nil  // 手动触发返回
}

// AFTER: .sheet(item:) 模式
// SwiftUI 管理 dismiss，手动 nil 赋值必须删除：
func confirmPlayback() {
    coordinator.confirmPlayback(prepared)
    // detailNavigationRequest 由 SwiftUI binding 在 sheet dismiss 时自动 nil 化
    // 仅在 onDisappear 中处理 cancel 清理
}
```

**陷阱**：双重 dismiss（SwiftUI binding + 手动 nil）导致动画 glitch 或 crash。

### 2. 伴随 WindowGroup 生命周期：单一 computed condition

多个独立 `.onChange` 观察者监听不同状态变量（`playbackMode`、`isPlaying`）时，状态变化的触发顺序不确定。两个观察者可能同时尝试 `openWindow` 或 `dismissWindow`。

```swift
// BAD: 两个独立 onChange 观察者
.onChange(of: appModel.playbackMode) { ... openWindow/dismissWindow ... }
.onChange(of: appModel.isPlaying) { ... openWindow/dismissWindow ... }
// 停止播放时：isPlaying→false 和 playbackMode→.window 同时触发，竞争

// GOOD: 单一 computed condition
var shouldShowCompanion: Bool {
    appModel.playbackMode != .window && appModel.isPlaying
}
.onChange(of: shouldShowCompanion) { _, show in
    if show { openWindow(id: "playerControls") }
    else { dismissWindow(id: "playerControls") }
}
```

**陷阱**：`openWindow` 对已打开窗口可能创建第二个实例（取决于 WindowGroup 配置）。`dismissWindow` 对已关闭窗口是 silent no-op（安全）。

### 3. System Menu 只支持离散选项

visionOS 的 `Menu { Picker { } }` 组件只支持离散选择项（类似单选列表）。不支持连续值 `Slider`。当计划中写"替换为 system Menu"时，必须检查被替换的组件是否包含连续控件。

```
ScreenPositionControlView 包含：
  - Distance Slider: 2.0-20.0m（连续）
  - Vertical Offset Slider: -2.0-2.0m（连续）
  - View Angle Slider: -45°-45°（连续）

→ 不可迁移到 Menu。必须保留独立面板。
```

**陷阱**：静默丢失用户功能。沉浸模式屏幕位置调节是核心电影体验。

### 4. 需求文档 "A and B" 中的第二项容易被丢弃

当需求写为 "R13: 面包屑路径导航和搜索框" 时，实施计划容易只实现前半部分（面包屑）而遗漏后半部分（搜索框）。在 ExecPlan 的 Requirements Tracking 表中，R13 被标记为"已覆盖"但实际只覆盖了一半。

**检查方法**：对每条含 "和"/"及"/"+" 连接词的需求，验证每个子项在实施单元中都有对应代码产出。

## 为何重要

- 陷阱 1 导致运行时 crash 或动画 glitch（用户可见）
- 陷阱 2 导致伴随窗口重复创建或状态不一致
- 陷阱 3 导致沉浸模式核心功能静默丢失
- 陷阱 4 导致需求覆盖率报告虚高（"100% 覆盖"实际 < 100%）

四个陷阱都在计划审查阶段被捕获，成本远低于实施后修复。

## 适用场景

- 任何 SwiftUI 导航模式迁移（NavigationStack → sheet/fullScreenCover）
- 添加辅助 WindowGroup 管理多窗口生命周期
- 将自定义 UI 组件替换为系统组件时的功能审计
- 将自然语言需求分解为实施单元时的覆盖率验证

## 示例

本次工程审查共发现 8 个 P1 问题。其中 4 个（F1-F4）来自对抗性审查对工程审查结果的二次挑战。F1 发现工程审查修复了 Unit 12 的删除指令但遗漏了 Scope Boundaries 和 Key Decisions 中的 3 处相同文本，验证了"修复传播不完整"是常见模式。

## 相关

- `docs/solutions/visionos-uiux-refactor-requirements-lessons-2026-04-05.md` — 需求阶段经验（.sheet 行为差异、ornament 兼容性）
- `docs/solutions/best-practices/autonomous-overnight-visionos-architectural-patterns.md` — 架构模式（PreparedPlayback TTL、Clean Architecture 断联检查）
