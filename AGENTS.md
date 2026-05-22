# Enchron — Agent 指令

面向 visionOS 的高质感视频播放器
技术栈：Swift 6 / SwiftUI / RealityKit / ARKit / Metal / mpv / SMB / WebDAV

Enchron 的目标是 Apple 平台原生品质——高质量的窗口播放、低学习成本、强沉浸感的full space
详见 `docs/product_philosophy.md`

---

## 审视产出

编译通过不是完成。一个好的设计师看一眼就知道哪里不舒服——这种感受比任何检查清单都早到达。

写完代码之后，你应该能在脑中看到它在屏幕上的样子。如果看不到，那不是该交付的时刻，而是该去理解的时刻——读上下文、读设计稿、读平台约束，直到你能感受到产出在完整系统中的位置。

感受不到就不要动手。动完手感受不到对不对就不要交付。

---

## 架构速览

Clean Architecture + DDD，5 个限界上下文，依赖方向向内（Adapters → UseCases → Domain）。模块间通过 Swift protocol 通信。

```
XrPlayer/
  PlaybackCore/   — 视频加载、解码、播放控制（mpv 封装）
  PlayerUI/       — 播放界面与播放模式决策
  FileBrowsing/   — 多数据源文件浏览（本地/SMB/WebDAV）
  SpatialScene/   — 空间场景管理与帧渲染
  Persistence/    — 持久化服务（SwiftData/UserDefaults/Keychain）
  App/            — 启动入口 + 依赖注入组装
```

完整架构说明、Architecture Invariants、数据流图：**ARCHITECTURE.md**

---

## Agent 标准动作序列

### 改动代码前
1. 读 ARCHITECTURE.md 确认涉及的模块和 Architecture Invariants
2. Swift 改动触及平台表面、UI、播放、文件/网络/持久化、生命周期相关并发、性能，或任何 iOS/macOS 平台假设时，先读 `.agents/skills/visionos-platform/SKILL.md`，按其中路由打开对应 Apple 官方文档；纯 Domain / UseCase / 单元测试改动不强制读取。iOS / macOS 技能只能作为语法或通用 Swift 辅助，不能替代 visionOS 裁决
3. UI / Design Preview 改动先读存在的 UI 规范文件；当前 DesignPreview 规范入口是 `DesignPreview/AGENTS.md`
4. 产品体验判断先读 `docs/product_philosophy.md`，需求边界按需查 `docs/brainstorms/*-requirements.md`
5. 任务 >3 文件或跨模块 → 写 Exec Plan（存放于 docs/plans/active/，完成后归档至 docs/archive/ExecPlan/）

### 改动代码后
1. 执行与改动范围匹配的自动验证；优先使用项目 Bun 脚本，缺失时退回 Xcode CLI
2. UI / Design Preview 改动必须给出人类真机或 Simulator 验证清单
3. 修复 bug 时，在对应 QA 报告、计划或专项文档中记录复现路径和回归验证方式
4. 交付时说明：自动验证结果、需要人类确认的体验点、未覆盖风险

### 改动模块接口时
1. 先更新 `docs/contracts/`
2. 先更新 ARCHITECTURE.md 的对应 Architecture Invariants
3. 再改代码
4. 对照是否一致

### CLI / MCP 选择规则

默认优先级：

1. 项目 Bun 脚本
2. 原生 Xcode CLI
3. 项目级 XcodeBuildMCP

具体约定：

- 高概率重复、参数稳定的动作优先走 Bun 脚本：`bun run build:visionos`、`bun run test:smoke`、`bun run verify:agent`
- Bun 脚本缺失或不覆盖当前需求时，直接退回原生 CLI：`xcodebuild`、`xcrun simctl`、`xcrun xcresulttool`、`swift`、`swiftlint`
- 涉及 simulator UI 交互、截图、手势、按 accessibility 元素定位、结构化调试时，优先使用项目级 XcodeBuildMCP
- 项目级 MCP 配置位于仓库根目录 `.mcp.json`；它是 CLI 的补充层，不替代 CLI

---

## 行为准则

| 准则 | 说明 |
|------|------|
| 先读文档再动手 | 本文件 → ARCHITECTURE.md → `.agents/skills/visionos-platform/SKILL.md` → 就近 `AGENTS.md` / 相关专项文档 |
| 系统原生优先 | 系统容器、材质、动效是第一选择，自定义须证明改善了核心体验 |
| 聚焦单一目标 | 每次改动围绕一个明确目标，不顺手重构 |
| 临时方案标注 | `// WORKAROUND:` + 移除条件，不让它悄悄变永久 |
| 改完可验证 | 至少补一项：自动化测试、结构守卫、smoke 检查步骤 |
| 沉浸场景兼容 | 不为窗口模式的临时问题引入与沉浸场景冲突的架构决策 |

---

## UI 编码约束

- 所有 UI 样式值（圆角、间距、动画、颜色、材质）必须通过 Design Token 引用，禁止硬编码
- 所有可交互组件必须有 `accessibilityIdentifier` + `accessibilityLabel`
- Token 未覆盖时：有人值守上报询问；overnight 标记 BLOCKED
- 涉及 UI 改动时，先读：**`.agents/skills/visionos-platform/SKILL.md`** 和就近 `AGENTS.md`

---

## 文档路由表

### 核心文档（改动代码必读）

| 文档 | 是什么 | 何时查阅 |
|------|--------|----------|
| **ARCHITECTURE.md** | 模块职责、数据流、Architecture Invariants、跨模块通信 | 任何代码改动前 |

### 产品与规范

| 文档 | 是什么 | 何时查阅 |
|------|--------|----------|
| `docs/product_philosophy.md` | 产品灵魂、三种播放模式的体验愿景 | 做设计决策时 |
| `docs/quality_gates.md` | 一个改动怎样才算"可接受" | 提交代码前自查 |
| `docs/ubiquitous_language.md` | 项目统一术语表 | 命名类、方法、变量时 |

### docs/ 子目录

| 目录 | 是什么 | 何时查阅 |
|------|--------|----------|
| `docs/designs/` | HTML 设计稿与视觉原型 | 实现 UI 时对照设计 |
| `docs/reference/` | 技术调查报告（investigation）、构建指南 | 需要某领域的调查结论时 |
| `docs/solutions/best-practices/` | 经验沉淀：踩坑记录、架构模式、流程最佳实践 | 遇到类似问题时避免重蹈覆辙 |
| `docs/solutions/build-errors/` | 构建错误的诊断与修复方案 | 遇到构建报错时 |
| `docs/archive/` | 归档区：已完成的 ExecPlan、已解决的 issues、DDD 建模历史 | 需要历史上下文时 |

文档优先级（冲突时）：Apple 官方文档裁决 API 行为、隐私/安全、App Store 约束和平台可用性；本地文档在这些平台约束内裁决产品、架构和实现取舍。产品体验冲突按 product_philosophy > brainstorms/*-requirements > quality_gates > ARCHITECTURE > 其余。

---
