# ExecPlan002 — Phase 0: 文档结构现代化

**Pipeline State**: PLANNING
**目标**: T0.1 — 整理项目文档结构，对齐当前 Skills/Overnight 工作流
**关联**: TODOS.md Phase 0

---

## 诊断结论（Round 1 审计 + Round 2 确认）

| 问题 | 严重度 | 修复方式 |
|------|--------|---------|
| AGENTS.md 与 CLAUDE.md 内容重复 | P1 | 删除 AGENTS.md |
| CLAUDE.md 引用不存在的 PLANS.md | P1 | 更新路由表和动作序列 |
| SpatialScene 描述过时("大部分 v0.4 规划中") | P2 | 对齐实际实现状态 |
| ExecPlan 归档路径不统一 (旧 workspace-agents/ vs 新 docs/) | P2 | 统一为 docs/ 体系 |
| morning-report.md 是上一次 overnight 的遗留 | P3 | 加入 .gitignore |
| ubiquitous_language.md 含已弃用条目(~~存储连接~~) | P3 | 清理弃用标记 |

## 执行清单

1. 删除 AGENTS.md
2. 更新 CLAUDE.md:
   - 删除 PLANS.md 路由行
   - 将"规则见 PLANS.md"改为"规则见 docs/ExecPlan/ 目录"
   - SpatialScene 描述从"大部分 v0.4 规划中"改为实际状态
3. 更新 .gitignore:
   - 添加 morning-report.md, overnight-log.md, TODOS.md
   - 添加 .overnight-supervisor/
4. 清理 ubiquitous_language.md 弃用条目
5. git commit

## Decision Log

- [AUTO] AGENTS.md 处理 | 删除而非合并 | P3+P5 | CLAUDE.md 是 Claude Code 标准文件，AGENTS.md 完全冗余
- [AUTO] PLANS.md 引用 | 删除路由行 + 更新引用 | P5 | PLANS.md 不再存在，ExecPlan 现在在 docs/ExecPlan/
- [AUTO] 旧 EP 归档 | 保留不迁移 | P6 | workspace-agents/archive/exec-plans/ 是历史记录，无需迁移
