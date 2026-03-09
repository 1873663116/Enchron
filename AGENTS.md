# Enchron — Agent 指令

面向 visionOS 的高质感视频播放器。本地与远程统一浏览播放，空间场景下的沉浸式交互。

---

## 项目身份

Enchron 不是一个"功能多但粗糙"的工具型播放器。它的目标是让用户觉得这是一款**Apple 平台原生产品**——高质感、低学习成本、强沉浸感。

技术栈：Swift 6 / SwiftUI / visionOS SDK / RealityKit / ARKit / Metal / SMB / WebDAV。

### 三种播放模式

产品围绕三种播放模式构建，它们共享同一套播放内核和控件体系，但渲染路径各自独立：

- **窗口模式** — SwiftUI 窗口内播放，类 iPad 体验。它是mpv在visionOS上跑通的地基，当前已可用
- **沉浸场景模式** — 进入 3D 虚拟场景，视频显示在虚拟屏幕上，Metal 纹理桥接渲染。v0.4 实现
- **全景模式** — 360°/180°/鱼眼全景视频投射到球体内壁，不加载虚拟场景。v0.5 实现

> 沉浸场景是产品的终极形态，也是核心差异化能力。虽然排在 v0.4，但当前所有交互设计、接口定义和模块边界都必须为它预留空间。不要为了解决窗口模式的临时问题而引入与沉浸场景不兼容的架构决策。

---

## 设计哲学

详见 `product_philosophy.md`。以下四条是精要：

- **播放体验是产品本体** — UI/UX、沉浸场景不是"功能的附属"，而是产品价值本身
- **性能是感知，不是指标** — 不追求 benchmark 数字，追求的是"用户不感到卡"，功耗不太高，菜单呼出不能发木，时间轴拖动必须跟手，模式切换不能掉帧。任何明显看得见、感觉得到的卡顿都是产品缺陷
- **HDR 可信度是底线** — 用户未必能说出 HDR10、HLG、Dolby Vision，但会直接感受到颜色对不对、高光是否被压坏。HDR 标签一旦显示，就必须可信
- **系统原生优先，少造轮子** — 能用系统容器就不造容器，能用系统材质就不自定义材质，能用系统动效就不写自定义动画。只有在"系统方案无法满足核心体验"时才自定义——而且每次自定义都要回答：**它是否真的让核心体验更好了？**

---

## 当前用户关注的核心目标

按优先级排列：

1. **二级进度条** — 产品最核心的交互资产。可快速进入、可精确定位、视觉焦点明确、不让用户迷路
2. **性能优化与卡顿** — 首播黑屏等待的相关冷启动问题
3. **播放控件反馈** — 每个控件必须看得见、选得准、有反馈。注视交互下不能出现"功能在但看不见"的情况
4. **HDR 正确性** — 识别准确、标签可信、映射正确
5. **远程浏览** — SMB / WebDAV 连接的稳定性和错误反馈清晰度
6. **未来沉浸场景接入** - 预留好接口，不要为了临时修复牺牲整体正确性

---

## Agent 行为边界

| 倾向 | 说明 |
|------|------|
| **先读文档再动手** | `workspace-agents/` 包含需求、架构、接口契约和已知问题，是动手前的必经之路 |
| **先找系统方案** | 任何 UI 改动，先确认 Apple 是否已有原生实现。系统容器、材质、过渡动效应是第一选择 |
| **改完要能验证** | 每次修复至少补充其中之一：自动化测试、阶段日志、smoke 检查步骤 |
| **按需查阅 skill** | 遇到领域问题时查阅 `workspace-agents/skills/` 中的对应 skill，而非凭记忆推断 |
| **聚焦单一目标** | 每次改动围绕一个明确目标，宁可多几轮迭代，不要一次推翻大量代码 |
| **标注临时方案** | workaround 必须标注 `// WORKAROUND:` 并注明移除条件，不要让它悄悄变成永久方案 |

### 值得警惕的倾向

- 为了"看起来特别"而引入装饰性动画或非标准组件——除非它直接改善了核心体验
- 实现与现有决策悄悄偏离——应先更新文档或说明例外，再写代码
- 把核心体验问题标记为"以后再说"——控件反馈、首播黑屏、HDR 可信度不适合长期搁置
- 为了解决眼前问题而牺牲整体正确性——尤其是可能与未来沉浸场景冲突的捷径

### 决策检查清单

每次设计或实现决策前：

1. 有没有系统原生方案？
2. 这个自定义是否真的服务核心体验？
3. 会不会引入额外卡顿、复杂度或视觉噪声？
4. 改完之后怎么验证？

四个问题中任何一个答不上来，值得暂停思考。

---

## 架构

Clean Architecture + DDD 分层：

```
XrPlayer/
  FileBrowsing/      # 本地/远程数据源接入与文件浏览
  PlaybackCore/      # 播放内核与播放器适配
  PlayerUI/          # 播放控制与交互
  Persistence/       # 持久化与 Keychain 凭证存储
```

验证：`swift test`

---

## 技术 Skill

`workspace-agents/skills/` 目录包含领域专属技术 skill。**按需查阅，不要一次性全部加载。**

| Skill | 用途 |
|-------|------|
| `swift-concurrency-6-2` | Swift 6.2 并发模型 |
| `swiftui-patterns` | SwiftUI 架构与状态管理 |
| `swift-protocol-di-testing` | 协议依赖注入与测试 |
| `metal-shader-expert` | Metal 着色器与 GPU 优化 |
| `metal-shaders` | Metal MSL 开发实践 |
| `metal-gpu` | Metal GPU 编程 |
| `metal-graphics` | Metal 图形渲染管线 |
| `shader-programming` | 跨平台着色器编程 |
| `arkit-visionos-developer` | ARKit + visionOS 开发 |
| `visionos-design-guidelines` | visionOS 设计规范 |
| `visionos-widgets` | visionOS Widget 模式 |
| `apple-hig` | Apple 人机界面指南 |
| `mobile-ios-design` | iOS 设计模式 |
| `liquid-glass-design` | iOS 26 Liquid Glass 设计 |
| `axiom-metal-migration-ref` | GLSL/HLSL → MSL 迁移 |
| `axiom-realitykit-diag` | RealityKit 问题诊断 |
| `axiom-scenekit` | SceneKit 与迁移 |

## 设计文档

`workspace-agents/` 目录包含详细设计文档。修改代码、文档或测试前，先对齐相关文档。

### 文档优先级

发生冲突时，按以下优先级判断：

1. `product_philosophy.md` — 定义产品方向和设计底线
2. `Requirements.md` — 定义功能范围和验收边界
3. `quality_gates.md` — 定义当前阶段的质量门禁
4. `known_issues.md` — 记录当前偏差与修复线索
5. `design_docs/phase2~phase4_*` — 作为架构设计背景与路线图参考

如果下层文档与上层文档冲突，应先更新冲突说明，不要让代码默默偏离。

### 各文档用途

| 文档 | 回答什么问题 | 何时查阅 |
|------|------------|---------|
| `product_philosophy.md` | 产品的灵魂是什么，三种模式的体验愿景 | 做设计决策、评审 UI 改动 |
| `Requirements.md` | 要做哪些功能，MVP 到哪里为止 | 接新需求、判断功能是否越界 |
| `quality_gates.md` | 一个改动怎样才算"可接受" | 提交代码前的自查清单 |
| `known_issues.md` | 目前最痛的偏差在哪里，证据是什么 | 修 bug 前了解上下文和历史 |
| `design_docs/phase2_bounded_contexts_and_context_map.md` | 五个限界上下文的职责和协作关系 | 涉及跨模块交互时 |
| `design_docs/phase2_tactical_domain_model.md` | 聚合根、实体和值对象的定义 | 修改 Domain 层代码时 |
| `design_docs/phase2_ubiquitous_language.md` | 项目统一术语表 | 命名类、方法、变量时 |
| `design_docs/phase3_clean_architecture_structure.md` | 每个模块的三层结构和依赖规则 | 新增文件、重构模块时 |
| `design_docs/phase3_interface_contracts.md` | 模块间 protocol 接口的完整定义 | 修改模块边界时 |
| `design_docs/phase4_implementation_roadmap.md` | 实施路线图和阶段目标 | 规划工作优先级时 |
