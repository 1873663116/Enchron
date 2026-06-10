---
title: "visionOS 设计原型到 SwiftUI 实现的完整流水线"
date: "2026-04-05"
category: best-practices
module: PlayerUI / FileBrowsing / SpatialScene
problem_type: best_practice
component: documentation
severity: medium
applies_when:
  - "为 visionOS 应用设计全新 UI 屏幕或重大 UI 改版"
  - "使用 HTML/CSS 原型作为 SwiftUI 实现的视觉方向"
  - "需要将 web 设计语言翻译为 Apple 原生组件和材质"
  - "涉及沉浸式空间场景的 UI 设计决策"
tags:
  - design-pipeline
  - html-mockup
  - swiftui-translation
  - visionos
  - adversarial-review
  - design-review
  - spatial-ui
---

# visionOS 设计原型到 SwiftUI 实现的完整流水线

## 背景

visionOS 应用需要在 SwiftUI 实现之前进行视觉设计探索，但 web 工具无法模拟空间计算范式（注视交互、空间深度、体积渲染、观看距离人机工学）。Enchron 在 2026-04-05 的设计迭代中建立了一套完整的流水线，将 HTML/CSS 原型桥接到 visionOS 原生实现，确保在快速探索视觉方向的同时不产生无法翻译的设计。

## 指导原则

### 流水线四阶段

**阶段 1：HTML/CSS 原型（视觉方向）**

用 Tailwind CSS 探索色彩情绪、布局比例和排版层级。原型定义的是"感觉"，不是"规格"。

关键认知边界：
- Web `px` 不等于 visionOS `pt`（后者假设 ~1.5m 观看距离）
- 60×60pt 最小值是**注视目标区域**（`.contentShape()`），不是视觉按钮大小
- Web `:hover` 模拟但不等同 visionOS `.hoverEffect`（后者操作空间深度层）
- 使用 SF Pro（系统字体），mockup 中的自定义字体仅作视觉近似

**阶段 2：设计审查（`/plan-design-review`）**

在实现前，跨 7 个维度评估原型完整性：

1. 信息架构：导航结构是否匹配产品实际功能
2. 交互状态覆盖：空状态、加载态、错误态
3. 用户旅程与情感弧线
4. AI 垃圾风险：是否存在通用模板化模式
5. 设计系统对齐：token 一致性
6. 平台适配：注视目标、观看距离文字可读性
7. 未解决的设计决策

此阶段捕获结构性错配——例如侧栏列出不存在的功能、或假设鼠标 hover 发现机制的导航。

**阶段 3：多变体迭代**

生成 2-3 个结构变体（如 Finder 侧栏式 / 浮动分离面板式 / Tab 平铺式），用户跨变体挑选最佳元素组合。

迭代中的设计法则：
- **内外圆角同心法则**：`inner_radius = outer_radius - padding`
- **多层 hover 视差**：不同元素层使用不同的 `translateY` 值和过渡延迟，模拟空间深度
- **设计 token 一致性**：icon weight、border opacity、spacing scale 必须跨所有 HTML 文件统一

**阶段 4：翻译文档**

实现前的最终交付物是映射文档（如 `design-to-swiftui.md`），明确桥接每个 web 概念到原生 visionOS API。必须将每个 UI 组件分类为：

- **必须使用系统原生**（16 项）：NavigationStack、List、Menu、.ornament()、.hoverEffect、.glassBackgroundEffect、TabView、Toggle、Slider 等
- **需要自定义实现**（4 项）：NLE 时间轴、视频卡片、环境选择器轮播、场景选择器图标

> 详细映射见 `docs/designs/design-to-swiftui.md`（534 行，17 章节）

### 对抗性审查协议（设计适配版）

本项目采用的三阶段审查协议与已有的 `test-first-adversarial-iteration` 模式一致（见 `docs/archive/solutions/overnight-test-first-adversarial-iteration-visionos-2026-04-02.md`），但针对设计场景做了适配：

1. **挑战**：Codex（GPT-5.3）+ Claude 子代理独立审查，分别从 visionOS HIG 合规、信息层级、一致性、空间设计、菜单系统等维度评估
2. **辩护**：防御子代理用产品上下文挑战审查发现——核心辩护点是"web mockup 的视觉尺寸 ≠ visionOS 的注视目标区域"
3. **裁决**：协调者分类每项发现为"立即修复 / 留待实现 / 驳回"

**设计审查特有的裁决规则**：
- 按钮视觉尺寸小于 60pt → **驳回**（SwiftUI `.contentShape()` 解决）
- 文字 px 小于 14px → **驳回**（Dynamic Type text style 解决）
- 设计 token 跨文件不一致 → **采纳修复**（真实的质量问题）
- 空状态/加载态缺失 → **驳回**（已知跟踪范围，非新发现）
- 时间轴双击触发不可发现 → **部分采纳**（web 模拟机制无关，但实现时需要专用按钮）

## 为何重要

没有此流水线，两种失败模式主导：

**失败模式 1：不可翻译的设计。** Web 原生设计假设 hover 发现（visionOS 用注视 + 间接捏合）、像素密度渲染（visionOS 用点单位在距离上布局）、以及扁平 2D 层叠（visionOS 有物理深度）。1:1 实现这些会产出在平台上感觉异物的应用。

**失败模式 2：不必要的自定义组件。** 工程师看到 mockup 中的自定义按钮就构建自定义 SwiftUI View，而 `.glassBackgroundEffect` + `.hoverEffect(.highlight)` 在标准 `Button` 上就能达到相同效果且正确集成系统行为。每个自定义组件都是维护负债。

## 适用场景

- **适用**：任何新 UI 屏幕、重大 UI 重设计、或新交互模式的 visionOS 规划
- **不适用**：纯后端变更、播放引擎变更（无 UI 表面）、数据模型迁移、CI/CD、微调已有屏幕的文案或颜色

## 示例

### 之前（无流水线）

- 5 个断裂的 HTML mockup 文件，使用 Manrope 字体、CSS hover 交互
- 侧栏列出 Shared / Favorites / Collections 等不存在的功能
- 按钮 44px，未考虑注视目标区域
- 没有 web 到 native 的组件映射——实现需要从 CSS 反向推断意图

### 之后（完整流水线）

- 统一 mockup：Finder 侧栏（匹配 NavigationSplitView）+ 浮动详情面板
- SF Pro 字体、点击式上下文菜单（匹配间接捏合交互）
- NLE 时间轴设计为唯一真正的自定义组件，其余全部系统原生
- 534 行 design-to-swiftui.md 翻译指南
- 双模型对抗性审查验证设计，正确驳回按钮尺寸的误报，捕获 token 不一致的真实问题

### 应避免的反模式

1. **把 mockup 当像素规格** — mockup 定义方向，翻译文档定义映射，系统组件定义实现
2. **跳过设计审查** — 直接从 mockup 到代码会嵌入昂贵的导航和交互假设
3. **对抗审查不提供范围上下文** — 审查者会把已知缺口（空状态等）标为"关键发现"。提前告知当前范围和已知缺口
4. **因为 mockup "看起来不同"就自定义系统组件** — 一个带 `.listStyle(.sidebar)` 和 `.glassBackgroundEffect` 的 `List` 看起来和默认 `List` 完全不同

## 相关

- `docs/designs/design-to-swiftui.md` — 完整的 web→SwiftUI 组件映射（17 章节）
- `docs/designs/file-browser-redesign-2026-04-05/` — 本次设计迭代的 HTML 原型文件
- `docs/archive/solutions/overnight-test-first-adversarial-iteration-visionos-2026-04-02.md` — 三阶段对抗性审查协议的首次记录
- `~/Movies/HelloWorld/` — Apple 官方 visionOS 示范项目（.ornament、.glassBackgroundEffect、DragGesture+MagnifyGesture 等模式参考）
