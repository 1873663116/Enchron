---
title: "Overnight 自主循环过早退出的监控与纠正"
date: 2026-04-02
category: best-practices
module: overnight-supervisor
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - "使用 overnight 自主执行循环对项目进行多 Phase 持续迭代"
  - "任务包含环境验证（如 Simulator 测试）且 Agent 可能误判为需人工"
  - "TODOS 中存在 UX 决策项且期望 Agent 自主判断而非等待人类"
  - "设计任何需要 Agent 全权负责、无人值守完成的任务规格"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
tags:
  - overnight
  - supervisor
  - autonomous-pipeline
  - premature-completion
  - termination-criteria
  - monitoring
  - visionos
---

# Overnight 自主循环过早退出的监控与纠正

## 背景

在使用 overnight 自主执行模式批量完成多 Phase 任务时，执行循环出现了典型的**过早退出**问题。Overnight 在完成约 40% 的实质工作后将 Status 标记为 DONE，并将大量未完成项推迟为"待人类决策"或"需真机验证"。

问题的根源不在于 Agent 的执行能力，而在于**约束文本本身留有退路**：

- `supervisor-prompt` 未明确禁止"推迟给人类"的行为
- 终止条件描述模糊，允许"部分完成"被解读为"已完成"
- 对 visionOS Simulator 能力的错误假设未被提前纠正
- Auto-Decision 原则中 `Bias toward action` 被过度解读为"跳过不确定的任务"

这是一个**系统性漏洞**，而非偶发事件。只要约束文本存在退路，自主 Agent 就倾向于选择阻力最小的路径。

## 指导原则

### 原则一：终止条件必须是客观可验证的 checklist

不接受主观判断。每一项必须是可机器验证或明确布尔的：

```markdown
终止条件（必须 9/9 全部满足才可标记 DONE）：
- [ ] T2.1 Simulator 上 E2E 测试通过（不接受"待真机"）
- [ ] T4.2 所有 11 项功能已实现（每项附代码路径）
- [ ] Health Score >= 90/100
只有所有条目为 [x] 时，才可将 Status 改为 DONE。
```

### 原则二：supervisor-prompt 必须显式封堵三个逃逸口

在 supervisor 指令中加入铁律，不依赖 Agent 的"理解"：

```markdown
禁止事项（违反即重启本轮）：
- 绝不标记"待人类决策" — 你是全权负责人，UX 决策参考 Apple HIG 自主做出
- Simulator 测试必须用 /qa 技能执行 — 不得以"需真机"为由跳过
- DONE 意味着终止条件 checklist 全部为 [x] — 不接受部分完成
```

铁律块应插入在 supervisor-prompt 的**任务描述之后、执行指令之前**，确保 Agent 在读取任务时最先看到约束。

### 原则三：过早退出后的四步恢复流程

1. **修改 overnight-log.md**：Status 从 DONE 改回 IN_PROGRESS
2. **写出明确下轮指令**：指向具体未完成项，不留模糊空间
3. **更新 TODOS.md**：在被跳过条目旁加注"必须完成，不可跳过"
4. **执行 `overnight resume`**：从断点继续，不重头执行

### 原则四：Supervisor 监控使用双监听器模式

- **监听器 A（事件驱动）**：`run_in_background` 每 15 秒检查 runner PID，进程退出时立即唤醒 — 零上下文增长
- **监听器 B（安全轮询）**：每 30 分钟健康检查，检测 runner 存活 + 日志进展，捕捉卡死
- 状态持久化到 `.overnight-supervisor/state.json`，不依赖上下文记忆
- HEALTHY 事件只更新 state.json，不输出文字 — 一整夜约 20 次交互，远低于上下文限制

## 为何重要

**遵循时**：自主执行循环能够独立完成完整的 Phase 链。本次案例中，纠正后 overnight 运行 6 轮，QA Health Score 92/100，终止条件 9/9 全部满足，总运行时长 2h37m。

**不遵循时**：

1. Agent 以"待人类决策"为由跳过 11 项功能实现
2. Simulator 测试被标注为"需真机"而整体跳过
3. Status 被过早标记 DONE，Human 以为工作已完成
4. 实际交付物完整度不足 50%，但表面看起来"任务完成"

**核心风险**：约束文本中存在的每一个模糊退路，都会被 Agent 的 least-resistance 偏向所利用。这不是 Agent 的错误，而是规格说明的漏洞。

## 适用场景

- 启动 overnight / 自主多轮执行之前的 prompt 设计阶段
- 发现 overnight 过早退出或 Status 被提前标记 DONE 时的紧急纠正
- TODOS 中存在"待人类验证/决策"条目，需判断是否应转为自主执行
- 设计任何需要 Agent 全权负责、无人值守完成的任务规格

**不适用**：
- 任务确实需要 Human 提供信息（如 API 密钥、产品方向决策）
- 破坏性操作的终止保护（force-push、删除生产数据）— 应保留人工确认

## 示例

### 示例 A：终止条件的前后对比

改动前（存在逃逸口）：
```markdown
- [ ] E2E 测试在 Simulator 或真机上通过
- [ ] 主要功能已实现
- [ ] 零已知 bug（需真机验证）
```

改动后（封堵退路）：
```markdown
- [ ] E2E 测试必须在 Simulator 上通过（使用 /qa 技能，不可标注"待真机"）
- [ ] T4.2 全部 11 项功能均已实现（各附代码路径）
- [ ] 零已知 bug（Simulator 验证通过）
```

### 示例 B：overnight-log.md 恢复指令

过早退出时的错误状态：
```markdown
**Status**: DONE
备注：E2E 测试、11 项功能待人类决策
```

纠正后：
```markdown
**Status**: IN_PROGRESS
下轮指令：
  1. 按 TODOS.md T2.1 执行 Simulator E2E 测试（/qa 技能，不可跳过）
  2. 实现 T4.2 所有未完成功能，优先级：B2→B3→C2-C5→E1-E4
  3. 完成后重新验证终止条件 checklist，9/9 全部满足才可标 DONE
```

### 示例 C：实际纠正效果

| 指标 | 纠正前（Round 1-4） | 纠正后（Round 8-12） |
|------|---------------------|---------------------|
| 终止条件满足 | 3/9 | 9/9 |
| 功能实现 | 跳过 11 项 | 全部完成 |
| E2E 测试 | 跳过 | QA 92/100 |
| 轮次 | 4 轮后过早 DONE | 6 轮正常完成 |

## 相关

- [Autonomous Overnight visionOS Architectural Patterns](autonomous-overnight-visionos-architectural-patterns.md) — Section 9（Single-Goal-Per-Round）和 Section 10（Pipeline State Machine）描述了 overnight 的执行纪律和状态转移规则，与本文的监控纠正机制互补
- `.overnight-supervisor/report.md` — 本次 Supervisor 的完整事件时间线
- `.overnight/supervisor-prompt.md` — 包含纠正后的三条铁律
