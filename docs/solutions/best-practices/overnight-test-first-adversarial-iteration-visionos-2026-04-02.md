---
title: "Test-First 对抗性迭代 — visionOS 三种播放路径完整实现"
date: 2026-04-02
category: best-practices
module: SpatialScene, PlayerUI, PlaybackCore, Persistence, App
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - 执行复杂多模块功能的无人值守自主开发循环
  - 需要 Test-First 对抗性迭代验证架构决策正确性时
  - 涉及 visionOS 空间计算、沉浸式场景、全景视频等高复杂度渲染路径实现
  - 使用 overnight 模式完成跨越 PLANNING → EXECUTING → VERIFYING → COMPLETING 全 pipeline 时
  - 平台限制导致真实 UI 测试不可行时（visionOS Simulator、headless CI）
tags:
  - test-first-adversarial-iteration
  - overnight-autonomous-loop
  - visionos
  - spatial-computing
  - immersive-cinema
  - panoramic-video
  - playback-routing
  - adversarial-review
---

# Test-First 对抗性迭代 — visionOS 三种播放路径完整实现

## 背景

Enchron 是一个 visionOS 原生视频播放器（Swift 6 / RealityKit / Metal / mpv）。进入本轮实现前，三种播放路径状态极度不均衡：

- **窗口模式**：已完整（10/10 功能点，v1 overnight 产出）
- **沉浸影院模式**：几乎全部缺失（17 项中仅 1 项完成）— 虚拟屏幕、环境系统、位置驱动全未做
- **全景视频模式**：只有 360° 可用（8 项中 2 项完成）— 180°/SBS/OU/鱼眼均未实现
- **播放模式路由**：决策矩阵存在但断联，UseCase 未接入主流程

约束条件：visionOS Simulator 无 CLI 交互 API、205 个既有测试不能破坏、任务跨 5 个模块（PlaybackCore / PlayerUI / SpatialScene / Persistence / App）、14 轮迭代需在单次 overnight 无人值守会话内完成。

这些约束促成了 **"测试陷阱先于实现"** 的方法论：在写任何功能代码之前，先用全红测试套件锁住需求边界，再让实现代码逐步让测试变绿。

## 指导原则

### 原则一：Phase 0 必须全红（Test-First 陷阱设计）

先写测试，但测试必须全部 FAIL，才算陷阱设置完毕。分四步：

**步骤 A — 全文档审计**：审计需求文档、设计文档、契约、回归集和现有代码，将每个功能点标注状态（已实现 / 部分 / 未实现 / 占位），输出带"FAIL 原因"列的功能清单。

**步骤 B — 三阶段对抗性审查（Pre-implementation）**：
- Stage 1（Codex Adversarial）：挑战测试设计的盲点、错误技术假设、范围蔓延
- Stage 2（Counter-Agent Rebuttal）：区分合理挑战（必须修复）与过度挑战（记录理由驳回）
- Stage 3（Opus Adjudication）：对照 Requirements.md 逐条核实做最终裁决

Pre-implementation 审查在代码写之前纠正设计级错误，成本接近零。

**步骤 C — Stub 而非 Skip**：为新类型创建"故意错误"的 stub 实现，确保旧测试继续 PASS、新测试全部 FAIL：

```swift
// HemisphereMeshConfiguration.swift — stub
public struct HemisphereMeshConfiguration: Sendable, Equatable {
    public let stacks: Int, slices: Int, radius: Float
    // stub: 零值，确保测试 FAIL
    public var uRange: ClosedRange<Float> { 0...0 }
    public var longitudeRange: ClosedRange<Float> { 0...0 }
}
```

**步骤 D — 确认全红**：`swift test` 必须输出旧测试 205 PASS + 新测试 43 FAIL。任何新测试意外 PASS 说明测试本身写错。

### 原则二：每个架构决策都要有约束理由

| 决策 | 选择 | 约束理由 |
|------|------|---------|
| 虚拟屏幕材质 | `UnlitMaterial` | mpv 非 AVPlayer，`VideoMaterial` 需要 AVPlayer 绑定 |
| 纹理来源 | 复用 `PanoramaLayerBridge.TextureResource` | 避免引入第二条 CVPixelBuffer → Metal 路径 |
| 曲面屏幕网格 | `generateCylinder + faceCulling=.front` | RealityKit 内置生成器，内表面剔除即可 |
| 环境切换 | Sky dome Entity 材质参数替换 | 重开 ImmersiveSpace 会中断播放 |
| SBS/OU 立体 | blit crop 左眼单目 | CompositorServices 是 v2 级工程，MVP 范围外 |
| 180° 网格 UV | `u=[0.25, 0.75]` | 等矩形纹理前半球对应中央 50% U 范围 |
| 鱼眼重映射 | Metal compute shader | CPU 路径会阻塞渲染线程 |

### 原则三：Phase 2 对抗性审查必须在实现完成后再次执行

第一次审查（Phase 0）保护设计，第二次（Phase 2）保护实现。本次 Phase 2 审查发现的 4 个真实 bug：

**C2 — auto-route 断联**：`updateDetectedProjection` 更新投影类型后未触发播放模式重算。

```swift
// 修复：追加 autoRoutePlaybackMode()
func updateDetectedProjection(_ projection: ProjectionType) {
    mediaProfile.projectionType = projection
    autoRoutePlaybackMode() // 触发决策矩阵重算
}
```

**C3 — projection override 不触发路由重算**：用户手动覆盖投影类型后播放模式未更新。修复同 C2，在 `setProjectionOverride` 末尾追加 `autoRoutePlaybackMode()`。

**C4 — 180° hemisphere UV 错误**：初版用 `u=[0,1]` 导致画面横向拉伸重影。修复为 `u=0.25 + 0.5 * normalized`。

**C5 — 环境位置记忆 nil 未重置**：首次进入环境时位置记忆返回 nil，屏幕出现在原点。修复：nil 时 fallback 到默认值 (8.0/0.0/0.0)。

### 原则四：结构化验证替代不可用的 UI 测试

| 检查类别 | 验证方法 |
|---------|---------|
| 协议 conformance | 构建成功 + grep conformance |
| 导航连线 | 静态 NavigationStack/Link 分析 |
| 依赖注入 | grep `.environment()` at app root |
| 回归覆盖 | 交叉引用 REGRESSION.md |
| 构建成功 | `xcodebuild build` |

无法通过结构检查验证的项目明确标注 "interactive validation deferred to human"。

## 为何重要

**遵循时**：43 个新测试在 Phase 0 全红，清晰界定"什么叫完成"。Phase 2 对抗性审查发现 4 个代码审查不会发现的 bug（路径断联、数学常数错误、隐蔽 nil 行为）。最终：248 tests 全绿，Health Score 97.75，14 轮迭代全部完成。

**不遵循时**：没有全红基线，"完成"边界模糊（C2/C3 正是路由逻辑存在但没接入主流程）。跳过 Phase 2 审查，C4 的 UV 错误会进入生产（功能"能运行"但画面变形）。

## 适用场景

- 任务跨越多个模块（超过 3 个文件或跨模块边界）
- 自主执行环境（overnight、CI、无人值守）
- 功能清单已知但实现未开始
- 平台限制导致真实 UI 测试不可行
- 技术路径有多个备选方案，需在实现前记录决策约束
- 存在现有测试套件需要保护

**不适用**：单文件小改动、探索性 spike、UI/视觉细节调整。

## 示例

### 从"功能存在但断联"到"有测试保证的路径连通"

```swift
// Phase 0 测试先写，全红
func testProjectionUpdateTriggersAutoRoute() {
    let model = AppModel()
    model.updateDetectedProjection(.panorama360)
    XCTAssertEqual(model.currentPlaybackMode, .panorama) // FAIL → Phase 1 实现后 PASS
}
```

### 三阶段对抗性审查的裁决

**Codex 挑战**："SBS/OU 应该用 CompositorServices 实现真立体。"
**Counter-Agent 反驳**："CompositorServices 是 v2 级工程。Requirements.md 原文是'左眼单目用于全景场景'，blit crop 符合定义。"
**Opus 裁决**：采纳 Counter-Agent 立场，MUST → SHOULD（v2），在 REGRESSION.md 记录技术债。

## 相关

- [Overnight v1 架构模式](autonomous-overnight-visionos-architectural-patterns.md) — 11 轮迭代的架构模式（Pipeline State Machine、Single-Goal-Per-Round），本文档在此基础上新增 test-first 和 adversarial review
- [Overnight 过早退出监控](overnight-premature-exit-monitoring-and-correction-2026-04-02.md) — supervisor 监控与纠正机制（互补参考）

## 统计

| 指标 | 值 |
|------|------|
| 迭代轮次 | 14 |
| Pipeline 阶段 | PLANNING → EXECUTING → VERIFYING → COMPLETING |
| 新增测试 | 43（总计 248） |
| 测试通过率 | 100%（0 FAIL, 1 pre-existing SKIP） |
| Health Score | 97.75 |
| 架构决策 | 9 项 |
| 对抗性审查发现 bug | 4 |
| 新增回归项 | 10（REG-100 ~ REG-109） |
| 终止条件 | 13/13 全部满足 |
