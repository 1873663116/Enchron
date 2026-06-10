---
title: Document Migration Verification Checklist
date: 2026-04-05
category: best-practices
module: docs
problem_type: best_practice
component: documentation
severity: medium
applies_when:
  - workspace-agents/ 或其他目录被迁移到 docs/ 时
  - 执行 git rm 批量清理被删除但仍追踪的文件时
  - 声称某个追踪文件"已全部归档解决"并准备删除时
tags: [migration, git-tracking, verification, workspace-agents, documentation-cleanup]
---

# 文档迁移验证清单

## 背景

workspace-agents/ → docs/ 迁移过程中，发现两类静默失败模式：
1. 文件在磁盘上存在（之前的迁移操作已复制），但从未执行 `git add`，导致 `git status` 中显示为 `??` untracked。本地工作正常，但 fresh clone 后文件缺失。
2. 删除追踪文件前，声称"所有条目已归档解决"但未逐项验证。KI-013（MoltenVK 线程安全）和 KI-014（饱和度增强 Compute Shader）两个开放项被静默丢弃。

## 指导原则

### 迁移后 git 追踪验证

每次将文件从旧路径迁移到新路径后，执行：

```bash
# 检查目标路径下是否有未追踪文件
git status --porcelain docs/ | grep "^??"
```

期望结果为 0 行。任何 `??` 条目意味着迁移未完成——文件存在但未进入 git 历史。

### 删除前逐项状态验证

删除含有状态条目的追踪文件（如 known_issues.md, TODO.md）前：

1. 逐条检查每个条目的 `状态` 字段（不信任文件头部的摘要声明）
2. 对每个声称"已关闭"的条目，验证关闭证据（归档文件存在、commit 记录、或 REGRESSION.md 对应项）
3. 对仍为"开放"的条目，确定迁移目标（REGRESSION.md、新的 known_issues.md、或其他追踪文档）

## 为何重要

- **git 追踪遗漏**：CLAUDE.md 路由表引用的路径本地通过 `test -f` 验证，但 fresh clone 后断裂。这使得 AC2 验收标准在本地 PASS 但在 CI 或其他开发者机器上 FAIL。
- **条目丢失**：被删除的开放 KI 从所有 agent 可见的追踪系统中消失，导致已知技术债在后续工作中无法被发现和规划。

## 适用场景

- 任何涉及文件路径迁移的文档清理工作
- 批量 `git rm` 操作前后
- 删除含有状态追踪条目的元文档时

## 示例

**迁移后验证（正确做法）**：
```bash
# 迁移 workspace-agents/contracts/ → docs/contracts/
cp -r workspace-agents/contracts/ docs/contracts/
git add docs/contracts/
git rm -r workspace-agents/contracts/
# 验证
git status --porcelain docs/contracts/ | grep "^??" && echo "FAIL: untracked files" || echo "PASS"
```

**删除前验证（正确做法）**：
```bash
# 检查 known_issues.md 中每个 KI 的状态
grep -E "^## KI-" workspace-agents/known_issues.md
# 对每个 KI 编号检查是否有关闭记录或迁移目标
grep "KI-013" REGRESSION.md docs/archive/ -r
```

## 相关

- [docs/known_issues.md](../../known_issues.md) — 本次迁移中恢复的 KI-013/KI-014
- [docs/plans/active/ExecPlan.md](../../plans/active/ExecPlan.md) — 本次迁移的实施计划
