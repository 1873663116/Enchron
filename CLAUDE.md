# Enchron — Agent 指令

面向 visionOS 的高质感视频播放器
技术栈：Swift 6 / SwiftUI / RealityKit / ARKit / Metal / mpv / SMB / WebDAV

Enchron 的目标是 Apple 平台原生品质——高质量的窗口播放、低学习成本、强沉浸感的full space
详见 `docs/product_philosophy.md`

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
2. 读 REGRESSION.md 代码路径映射索引，预判改动触发哪些回归项
3. 任务 >3 文件或跨模块 → 写 Exec Plan（存放于 docs/plans/active/，完成后归档至 docs/archive/ExecPlan/）

### 改动代码后
1. 执行 agent 自检六件套（详见 TESTING.md）
2. `git diff --name-only` 匹配 REGRESSION.md 索引，生成人类真机验证清单
3. 修复 bug → 必须在 REGRESSION.md 新增对应回归项
4. 产出三件交付物：自检报告、人类验证清单、回归集更新

### 改动模块接口时
1. 先更新 `docs/contracts/`
2. 先更新 ARCHITECTURE.md 的对应 Architecture Invariants
3. 再改代码
4. 对照是否一致

---

## 行为准则

| 准则 | 说明 |
|------|------|
| 先读文档再动手 | 本文件 → ARCHITECTURE.md → REGRESSION.md → 相关专项文档 |
| 系统原生优先 | 系统容器、材质、动效是第一选择，自定义须证明改善了核心体验 |
| 聚焦单一目标 | 每次改动围绕一个明确目标，不顺手重构 |
| 临时方案标注 | `// WORKAROUND:` + 移除条件，不让它悄悄变永久 |
| 改完可验证 | 至少补一项：自动化测试、结构守卫、smoke 检查步骤 |
| 沉浸场景兼容 | 不为窗口模式的临时问题引入与沉浸场景冲突的架构决策 |

---

## 文档路由表

| 文档                                              | 是什么                                    | 何时查阅              |
| ----------------------------------------------- | -------------------------------------- | ----------------- |
| **ARCHITECTURE.md**                             | 模块职责、数据流、Architecture Invariants、跨模块通信 | 任何代码改动前           |
| **TESTING.md**                                  | 双轨验证体系、agent 自检命令、人类验证清单格式             | 改动代码后验证时          |
| **QUALITY_SCORE.md**                            | 各领域当前质量评分、差距                           | 评估改动优先级时          |
| **REGRESSION.md**                               | 代码路径 → 回归项映射、回归集维护规则                   | 改动代码前后（必读）        |
| `docs/product_philosophy.md`                    | 产品灵魂、三种播放模式的体验愿景                       | 做设计决策时            |
| `docs/Requirements.md`                          | 功能范围、验收边界、里程碑                          | 接新需求、判断功能是否越界     |
| `docs/quality_gates.md`                         | 一个改动怎样才算"可接受"                          | 提交代码前自查           |
| `docs/ubiquitous_language.md`                   | 项目统一术语表                                | 命名类、方法、变量时        |
| `docs/contracts/frontend-backend-contract.md`   | 前后端职责边界、协作规则                           | 涉及远程数据流时          |
| `docs/design_docs/`                             | DDD 建模细节、完整接口签名（参考归档）                  | 需要深入设计背景时         |
| `docs/contracts/`                               | 契约规范 + OpenAPI 参考 + Mock 数据                 | 改远程数据模型、接口或协作边界时 |

文档优先级（冲突时）：product_philosophy > Requirements > quality_gates > ARCHITECTURE > 其余。

---

## 技术 Skill

`~/.claude/skills/` 包含领域专用 skill。遇到领域问题时按需调用，不凭记忆推断。

| 领域 | Skill |
|------|-------|
| Swift 并发 | `swift-concurrency-6-2` |
| SwiftUI | `swiftui-patterns` |
| 协议/DI/测试 | `swift-protocol-di-testing` |
| Metal | `metal-shader-expert`, `metal-shaders`, `metal-gpu`, `metal-graphics` |
| 着色器 | `shader-programming`, `axiom-metal-migration-ref` |
| visionOS | `arkit-visionos-developer`, `visionos-design-guidelines`, `visionos-widgets` |
| Apple 设计 | `apple-hig`, `mobile-ios-design`, `liquid-glass-design` |
| RealityKit | `axiom-realitykit-diag`, `axiom-scenekit` |


## Review guidelines
*非review agent忽略*

- Don't log PII.
- Verify that authentication middleware wraps every route.
