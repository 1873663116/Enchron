---
date: 2026-04-05
topic: doc-cleanup-and-path-normalization
---

# UI/UX 重构前文档清理与路径规范化

## 问题框架

Enchron 项目在迁移 `workspace-agents/` 到 `docs/` 的过程中，7 个关键文件从磁盘删除但未恢复或迁移，导致 CLAUDE.md、ARCHITECTURE.md、README 等核心文档的 ~40 处引用断裂。Agent 工作流依赖这些文件（回归映射、验证协议、产品哲学），断裂引用使 Agent 无法正确执行标准动作序列。

在 UI/UX 重构开始前，文档体系必须完整、引用一致、路径规范，否则重构过程中的 Agent 协作将建立在错误的基础上。

## 需求

**关键文件恢复**

- R1. 从 HEAD 恢复 `REGRESSION.md`、`TESTING.md`、`QUALITY_SCORE.md` 到项目根目录
- R2. 从 HEAD 提取 `workspace-agents/product_philosophy.md` → `docs/product_philosophy.md`
- R3. 从 HEAD 提取 `workspace-agents/Requirements.md` → `docs/Requirements.md`
- R4. 从 HEAD 提取 `workspace-agents/quality_gates.md` → `docs/quality_gates.md`
- R5. 从 HEAD 提取 `workspace-agents/mpv-build-guide.md` → `docs/reference/mpv-build-guide.md`

**断裂引用修复**

- R6. 更新 CLAUDE.md 全文：11 处 `workspace-agents/` 引用（含文档路由表 8 处 + 表外 3 处）。**注意**：`workspace-agents/skills/` 应替换为 `~/.claude/skills/`（全局路径），而非 `docs/`；其余 10 处替换为 `docs/` 路径
- R7. 更新 ARCHITECTURE.md：7 处 `workspace-agents/` → `docs/` 路径
- R8. 更新 README.md 和 README.en.md：各 6 处断裂引用
- R9. 更新 `docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md`：4 处断裂引用
- R10. 更新 `.overnight/supervisor-prompt.md`：2 处断裂引用
- R11. 更新 `docs/design_docs/README.md`、`Tests/README.md` 和 `docs/solutions/best-practices/autonomous-overnight-*.md` 中的旧路径引用

**结构规范化**

- R12. `mv "docs/archive/issues archive" docs/archive/issues-archive && git add docs/archive/issues-archive/`（目录名去空格；目录为 untracked 状态，git mv 不可用）
- R13. 移动活跃计划文件到 `docs/plans/active/`：`docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md`（规划阶段确认是否包含 `2026-04-02-arch.md`）
- R14. `git rm` 清理 `workspace-agents/` 和 `docs/ExecPlan/` 下 92 个已从磁盘删除但仍被 git 追踪的文件
- R17. `git rm` 清理其余已删除但仍被 git 追踪的临时文件：`TODOS.md`、`logs/runner.log`、`morning-report.md`、`overnight-log.md`、`overnight-log-v1-archived.md`、`overnight-log-v2-archived.md`

**路径命名规范化**

- R15. 重命名 `docs/designs/file-browser-redesign-20260405/` → `file-browser-redesign-2026-04-05/`（日期加分隔符）
- R16. 重命名 `docs/designs/DESIGN-TO-SWIFTUI.md` → `design-to-swiftui.md`（全小写 kebab-case），并同步更新所有引用：`.overnight/supervisor-prompt.md`（3 处）、`docs/solutions/best-practices/visionos-design-mockup-to-swiftui-pipeline-2026-04-05.md`（4 处，其中 2 处绝对路径）。R16 必须在 R6-R11 全部完成后最后执行

## 成功标准

1. 项目中活跃文档不存在对 `workspace-agents/` 的引用（`.overnight/` 目录、`docs/archive/` 归档文件、`docs/reference/` 参考文件除外）
2. CLAUDE.md 文档路由表中每个路径指向磁盘上实际存在的文件
3. `git status` 无 ` D`（空格+D）状态的文件——所有删除要么恢复要么正式 `git rm`
4. `docs/` 下无目录名含空格
5. 活跃文档路径遵循 kebab-case + ISO 日期格式（`YYYY-MM-DD`）

## 范围边界

- 不修改任何 Swift 源代码
- 不重写文档内容（仅修复路径引用）
- 不重命名 `docs/archive/` 下的归档文件（保留历史格式）
- 不创建 DESIGN-TO-SWIFTUI.md 的模块归属矩阵或 mockup 交叉引用（属于内容创作，超出本轮范围）
- 不添加 `.gitignore` 条目（低优先级可选项，不在本轮）
- QA 报告大写后缀不改名（低优先级，不影响功能）

## 关键决策

- **恢复而非重建**：根目录三个关键文件（REGRESSION/TESTING/QUALITY_SCORE）原地恢复，因为 CLAUDE.md Agent 动作序列硬编码了根目录路径
- **迁移而非恢复**：workspace-agents/ 下的文件迁移到 docs/ 子目录，因为 workspace-agents/ 已被全面替代
- **归档不动**：docs/archive/ 下 46 个旧格式 ExecPlan 和 8 个 snake_case design_docs 保留原名，避免无价值的 git 历史噪音
- **R16 blast radius 已确认**：活跃文档 7 处引用（`visionos-design-mockup-to-swiftui-pipeline` 4 处 + `.overnight/supervisor-prompt.md` 3 处）。CLAUDE.md 和 HTML mockups 无直接引用。R16 须在 R6-R11 之后最后执行

## 依赖 / 假设

- 当前所有删除均为 unstaged（` D` 状态），HEAD 仍包含完整文件内容——若删除被 stage 或 commit，恢复命令需调整
- `docs/contracts/`、`docs/design_docs/`、`docs/ubiquitous_language.md` 已确认迁移完成且内容一致（审计 Section 4 已验证）

## 待解问题

### 推迟到规划阶段

- [影响 R6][技术性] CLAUDE.md `workspace-agents/known_issues.md` 引用：删除整行还是替换为新路径？（审计建议删除行，因 known_issues 已归档解决）
- [影响 R14][技术性] `git rm` 操作是否需要分批提交（按目录/按类型），还是一次性 `git rm -r workspace-agents/`

## 下一步

→ /ce:plan 进行结构化实施规划
