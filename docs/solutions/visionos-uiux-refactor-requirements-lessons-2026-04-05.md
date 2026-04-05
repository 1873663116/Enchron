# visionOS UI/UX 重构需求阶段经验

日期：2026-04-05
阶段：INVESTIGATING → 需求文档产出

## 经验 1: visionOS .sheet() 行为与 iOS 不同

在 visionOS 上，`.sheet()` 呈现为独立浮动窗口面板（非 iOS 的底部半屏滑出），位置和大小由系统控制。这���味着：
- `onDisappear` 在 sheet dismiss 和 swipe-to-dismiss 时均触发，语义与 NavigationStack 返回不同
- 从 `navigationDestination` 迁移到 `.sheet()` 时，所有依赖返回语义的逻辑（如 `cancelPreparedPlayback()`）必须显式重写
- sheet 可能覆盖整个主窗口，与 mockup 的局部 overlay-panel 设计不匹配

**应用场景**：任何从 NavigationStack push 迁移到 .sheet() 的改动

## 经验 2: ornament + windowStyle 兼容性需要原型验证

`.ornament(attachmentAnchor: .scene(.leading))` 在 `.windowStyle(.plain)` 上的行为未经验证。design-to-swiftui.md 第 8 章也注记 `.windowStyle(.plain)` 下 NavigationSplitView 侧栏可能失去玻璃背景。

**回退策���设计模式**：当一个系统 API 组合的兼容性未经验证时，在需求文档中声明回退方案（如"若 ornament 不���容则回��至 TabView .sidebarAdaptable"），确保两种方案共享相同的状态模型��仅容器实现不同。这使得 Phase B 不被阻塞，同时规划阶段可以通过原型验证��择最优方案。

## 经验 3: 伴随 WindowGroup vs RealityKit Attachment 的范围影响

R21（沉浸模式控件）面临两个方案：
- 伴随 WindowGroup：需要在 XrPlayerApp.swift 新增 Scene 声明 + 窗口生命周期管理，但不侵入 SpatialScene
- RealityKit Attachment：仅在 ImmersiveSpace 内可用（恰好匹配使用场景），但需要 SpatialScene 集成工作

**决策原则**：当两个方案技术上都可行时，选择范围影响更小的（不侵入不相关模块的）方案。伴随 WindowGroup 虽然有窗口管理复杂度，但其影响局限于 App 层；Attachment 的影响扩散到 SpatialScene，违反"SpatialScene 独立上下文"的架构约束。

## 经验 4: 需求文档中 deferred questions 必须非阻塞

Codex adversarial review 正确识别了 `[阻塞 Phase B]` 标记的 deferred question 违反了 INVESTIGATING 退出条件。

**规则**：deferred questions 中的每一项都必须有回退策略或明确的"可在规划阶段解决"证据。如果某项是真正的阻塞项，它应该在需求文档中直接解决（做出决策），而非标记为"推迟"。

## 经验 5: Favorites 等新 Domain 概念应延后

mockup 中的 Favorites 区域（侧栏）需要新增 Domain 模型（收藏夹 CRUD）和 Persistence 扩展。这超出了 UI 重构的范围边界——UI 重构应该用现有数据模���重新组织界面，而��创建新的业务功能。

**判断标准**：如果一个需求需要新增 Domain 层实体，它很可能��新功能而非重构，应该在范围边界中明确推迟。
