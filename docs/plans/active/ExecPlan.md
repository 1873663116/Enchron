---
title: "refactor: 文档清理与路径规范化"
type: refactor
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-doc-cleanup-and-path-normalization-requirements.md
---

# refactor: 文档清理与路径规范化

## 概述

恢复 7 个关键文件、修复 ~45 处断裂引用、规范化目录/文件命名、清理 93 个已删除但仍被 git 追踪的文件。为即将开始的 UI/UX 重构建立干净、一致的文档基础。

## 问题框架

workspace-agents/ → docs/ 迁移未完整收尾，7 个关键文件从磁盘删除但未恢复或迁移，导致 CLAUDE.md、ARCHITECTURE.md、README 等核心文档的 ~45 处引用断裂。Agent 工作流依赖这些文件（回归映射、验证协议、产品哲学），断裂引用使 Agent 标准动作序列无法正确执行。(see origin: docs/brainstorms/2026-04-05-doc-cleanup-and-path-normalization-requirements.md)

## 需求追踪

从来源文档承接：

- R1. 从 HEAD 恢复 REGRESSION.md、TESTING.md、QUALITY_SCORE.md 到项目根目录
- R2. 从 HEAD 提取 workspace-agents/product_philosophy.md → docs/product_philosophy.md
- R3. 从 HEAD 提取 workspace-agents/Requirements.md → docs/Requirements.md
- R4. 从 HEAD 提取 workspace-agents/quality_gates.md → docs/quality_gates.md
- R5. 从 HEAD 提取 workspace-agents/mpv-build-guide.md → docs/reference/mpv-build-guide.md
- R6. 更新 CLAUDE.md 全文 11 处引用（skills/ → ~/.claude/skills/，known_issues 行删除，其余 → docs/）
- R7. 更新 ARCHITECTURE.md 7 处引用
- R8. 更新 README.md 和 README.en.md 各 6 处引用
- R9. 更新 docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md 4 处引用
- R10. 更新 .overnight/supervisor-prompt.md 引用
- R11. 更新 docs/design_docs/README.md、Tests/README.md、docs/solutions/best-practices/ 中的引用
- R12. 目录名去空格：docs/archive/issues archive → docs/archive/issues-archive
- R13. 移动活跃计划文件到 docs/plans/active/（含 arch.md）
- R14. git rm 清理 workspace-agents/ 和 docs/ExecPlan/ 下已删除文件
- R15. 重命名 file-browser-redesign-20260405/ → file-browser-redesign-2026-04-05/
- R16. 重命名 DESIGN-TO-SWIFTUI.md → design-to-swiftui.md + 同步更新 7 处引用
- R17. git rm 清理根目录和 logs/ 下的临时文件

## 范围边界

- 不修改任何 Swift 源代码
- 不重写文档内容（仅修复路径引用）
- 不重命名 docs/archive/ 下的归档文件
- 不创建 DESIGN-TO-SWIFTUI.md 的模块归属矩阵或 mockup 交叉引用
- 不删除或修改 scripts/sync_workspace_agents.py（虽然已过时，但属脚本变更，超出范围）
- 不添加 .gitignore 条目

## 上下文与调研

### 相关代码和模式

**文件恢复方法：**
- 根目录 3 个文件（REGRESSION.md 等）：当前 ` D`（unstaged deletion），HEAD 完整 → `git checkout HEAD -- <file>`
- workspace-agents/ 4 个文件：磁盘已删，需提取到新路径 → `git show HEAD:<old-path> > <new-path>`

**引用精确映射（调研已验证）：**

| 文件 | workspace-agents/ 引用数 | 其他引用 |
|------|--------------------------|----------|
| CLAUDE.md | 11 | — |
| ARCHITECTURE.md | 7 | — |
| README.md | 6 | — |
| README.en.md | 6 | — |
| docs/plans/2026-04-02-001...plan.md | 4 | — |
| .overnight/supervisor-prompt.md | 2 | 3× DESIGN-TO-SWIFTUI.md |
| docs/design_docs/README.md | 1 | — |
| Tests/README.md | 1 | — |
| docs/solutions/.../autonomous-overnight-...patterns.md | 1 | — |
| docs/solutions/.../visionos-design-mockup-to-swiftui-pipeline-...md | — | 4× DESIGN-TO-SWIFTUI.md |

**Git 清理范围（97 个 ` D` 文件）：**
- workspace-agents/: 84 个（skills/ 63, archive/ 8, contracts/ 4, design_docs/ 11, 根级 8）
- docs/ExecPlan/: 4 个
- 根目录: 7 个（4 恢复 + 3 git rm）
- logs/: 1 个
- 扣除 3 个恢复文件 = 94 个待 git rm（注意：TODOS.md 按需求不恢复，也 git rm）

### 机构知识

- docs/solutions/ 下 5 个 best-practices 文档，其中 1 个含 workspace-agents 引用需修复
- 审计报告 Section 4 已验证所有有价值内容均已迁移到 docs/ 或 ~/.claude/skills/

## 关键技术决策

- **known_issues.md 行删除而非替换**：git HEAD 中 known_issues.md 所有条目已归档解决，无活跃 issues，无迁移目标。CLAUDE.md 和 README 中的引用行直接删除。(see origin: 审计报告 Section 2.1)
- **分 2 批 git 提交**：第 1 批恢复/迁移文件，第 2 批批量 git rm。避免恢复与删除混在同一提交中，git 历史更清晰。
- **R13 包含 arch.md**：`docs/plans/2026-04-02-arch.md` 与 plan 文件一起移入 `docs/plans/active/`，两者都是 UI/UX 重构的活跃文档。
- **README known_issues 行删除**：与 CLAUDE.md 一致，README.md:113 和 README.en.md:113 的 known_issues 引用行删除。
- **DESIGN-TO-SWIFTUI.md 重命名最后执行**：R16 修改文件名，所有引用必须在其他修复完成后统一更新，避免中间状态不一致。

## 未解决问题

### 规划期间解决

- **CLAUDE.md known_issues 行处理** → 删除整行（理由见关键技术决策）
- **git rm 批次策略** → 分 2 批提交（理由见关键技术决策）
- **R13 是否包含 arch.md** → 是（理由见关键技术决策）

### 推迟到实施

- **scripts/sync_workspace_agents.py 处置**：调研发现该脚本专为 workspace-agents 同步设计，现已过时。但删除脚本超出本轮"仅文档/路径/引用操作"范围。记录为后续清理项。
- **.overnight/supervisor-prompt.md 中的锚定文档引用**：supervisor-prompt.md 引用 `docs/designs/DESIGN-TO-SWIFTUI.md`，R16 重命名后需更新。但 supervisor-prompt.md 是每轮 overnight 动态生成的，实施时确认是否需要持久化此更新。

## 实施单元

依赖关系：

```
Unit 1 (恢复文件) ──→ Unit 2 (修复引用) ──→ Unit 4 (重命名规范化)
                  └──→ Unit 3 (结构清理)
```

- [ ] **Unit 1：恢复关键文件并迁移到 docs/**

**目标：** 从 git HEAD 恢复 3 个根目录文件，提取 4 个 workspace-agents 文件到 docs/ 新路径，建立引用修复的前置条件。

**需求：** R1, R2, R3, R4, R5

**依赖：** 无

**文件：**
- 恢复：`REGRESSION.md`、`TESTING.md`、`QUALITY_SCORE.md`（从 HEAD checkout）
- 创建：`docs/product_philosophy.md`（从 HEAD:workspace-agents/product_philosophy.md 提取）
- 创建：`docs/Requirements.md`（从 HEAD:workspace-agents/Requirements.md 提取）
- 创建：`docs/quality_gates.md`（从 HEAD:workspace-agents/quality_gates.md 提取）
- 创建：`docs/reference/mpv-build-guide.md`（从 HEAD:workspace-agents/mpv-build-guide.md 提取）

**方案：**
- 根目录文件用 `git checkout HEAD -- <file>` 恢复（当前 unstaged deletion，HEAD 内容完整）
- workspace-agents 文件用 `git show HEAD:<old-path> > <new-path>` 提取到新位置
- 执行前先 `git status` 确认这些文件仍为 ` D` 状态（若已被 stage 则命令需调整）

**要遵循的模式：**
- docs/ubiquitous_language.md 已成功从 workspace-agents/ 迁移，遵循相同模式

**测试场景：**
- 正常路径：恢复后 `ls REGRESSION.md TESTING.md QUALITY_SCORE.md` 均存在且内容非空
- 正常路径：`diff <(git show HEAD:workspace-agents/product_philosophy.md) docs/product_philosophy.md` 内容一致
- 正常路径：docs/reference/mpv-build-guide.md 存在且内容与 HEAD 版本一致
- 边界情况：`git status` 中这 7 个文件不再显示为 ` D` 状态

**验证：**
- 7 个文件全部在磁盘上存在且内容正确
- git status 中这些文件的 ` D` 状态消失

---

- [ ] **Unit 2：修复全部 workspace-agents/ 断裂引用**

**目标：** 将 9 个活跃文档中 ~45 处 workspace-agents/ 引用替换为正确的 docs/ 或 ~/.claude/skills/ 路径。

**需求：** R6, R7, R8, R9, R10, R11

**依赖：** Unit 1（引用目标路径必须存在）

**文件：**
- 修改：`CLAUDE.md`（11 处：10 处 → docs/，1 处 → ~/.claude/skills/，1 行删除）
- 修改：`ARCHITECTURE.md`（7 处 → docs/）
- 修改：`README.md`（6 处：5 处 → docs/，1 行 known_issues 删除）
- 修改：`README.en.md`（6 处：5 处 → docs/，1 行 known_issues 删除）
- 修改：`docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md`（4 处：3 处 → docs/，1 处 known_issues → 删除或指向 docs/archive/）
- 修改：`.overnight/supervisor-prompt.md`（2 处 → docs/）
- 修改：`docs/design_docs/README.md`（1 处 → docs/）
- 修改：`Tests/README.md`（1 处 → docs/）
- 修改：`docs/solutions/best-practices/autonomous-overnight-visionos-architectural-patterns.md`（1 处 → ~/.claude/skills/）

**方案：**
- 逐文件处理，每处引用手动确认替换目标（调研已提供完整行号映射）
- CLAUDE.md 特殊处理：
  - 行 74（known_issues）→ 删除整行（含路由表行）
  - 行 86（skills/）→ ~/.claude/skills/（全局路径，非 docs/）
  - 其余 9 处 → docs/ 对应路径
- README 两个文件结构对称，引用位置相同，并行处理
- 替换完成后 grep 验证无遗漏

**要遵循的模式：**
- 精确匹配替换，保留 Markdown 链接语法和表格格式
- known_issues 行删除时注意表格行对齐

**测试场景：**
- 正常路径：`grep -rn "workspace-agents" CLAUDE.md` 返回 0 结果
- 正常路径：`grep -rn "workspace-agents" ARCHITECTURE.md` 返回 0 结果
- 正常路径：`grep -rn "workspace-agents" README.md README.en.md` 返回 0 结果
- 正常路径：CLAUDE.md 路由表每个路径指向磁盘上存在的文件（`test -f` 验证）
- 正常路径：`grep -rn "workspace-agents" docs/plans/ docs/design_docs/ Tests/ docs/solutions/ .overnight/supervisor-prompt.md | grep -v "docs/archive/" | grep -v "docs/reference/" | grep -v ".overnight/log.md" | grep -v "docs/brainstorms/"` 返回 0 结果
- 边界情况：CLAUDE.md 行 86 的 skills 引用替换为 `~/.claude/skills/` 而非 `docs/`
- 错误路径：Markdown 链接语法未被破坏（无悬挂括号或方括号）

**验证：**
- 项目活跃文档中不存在 workspace-agents/ 引用（排除 archive/reference/log/brainstorms）
- CLAUDE.md 路由表每条路径可达

---

- [ ] **Unit 3：结构规范化 — 目录重组与 git 清理**

**目标：** 修复目录命名问题、移动活跃计划文件、批量 git rm 所有已删除但仍被追踪的文件。

**需求：** R12, R13, R14, R17

**依赖：** Unit 1（恢复文件后才能安全 git rm 同目录的其他文件）

**文件：**
- 重命名：`docs/archive/issues archive/` → `docs/archive/issues-archive/`
- 移动：`docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md` → `docs/plans/active/`
- 移动：`docs/plans/2026-04-02-arch.md` → `docs/plans/active/`
- 删除（git rm）：workspace-agents/ 全部 84 个文件
- 删除（git rm）：docs/ExecPlan/ 4 个文件
- 删除（git rm）：TODOS.md、morning-report.md、overnight-log.md、overnight-log-v1-archived.md、overnight-log-v2-archived.md
- 删除（git rm）：logs/runner.log

**方案：**
- 目录重命名：`docs/archive/issues archive/` 是 untracked 状态（含空格），用 `mv` + `git add` 而非 `git mv`
- 计划文件移动：用 `git mv` 保留历史
- git rm 分一次操作：`git rm -r workspace-agents/ docs/ExecPlan/` + 逐个 `git rm` 根目录和 logs/ 文件
- 不恢复 TODOS.md（需求文档明确为"可不恢复"），直接 git rm

**要遵循的模式：**
- docs/plans/active/ 目录已存在（Unit 1 中创建），放置活跃计划
- docs/archive/ 下已有 issues-archive 内容（3 个归档文件），仅修目录名

**测试场景：**
- 正常路径：`docs/archive/issues-archive/` 存在且包含 3 个文件
- 正常路径：`docs/archive/issues archive/` 不存在
- 正常路径：`docs/plans/active/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md` 存在
- 正常路径：`docs/plans/active/2026-04-02-arch.md` 存在
- 正常路径：`git status --porcelain | grep "^ D"` 返回 0 行
- 正常路径：`find docs/ -type d -name "* *"` 返回 0 结果
- 边界情况：workspace-agents/ 目录在 git 索引中完全移除

**验证：**
- 无 ` D` 状态文件
- 无含空格的 docs/ 子目录
- 活跃计划文件在 docs/plans/active/

---

- [ ] **Unit 4：路径命名规范化 — 文件/目录重命名**

**目标：** 将不符合 kebab-case + ISO 日期规范的文件/目录重命名，同步更新所有引用。

**需求：** R15, R16

**依赖：** Unit 2（R16 必须在所有引用修复完成后最后执行，避免重命名期间的中间不一致状态）

**文件：**
- 重命名：`docs/designs/file-browser-redesign-20260405/` → `docs/designs/file-browser-redesign-2026-04-05/`
- 重命名：`docs/designs/DESIGN-TO-SWIFTUI.md` → `docs/designs/design-to-swiftui.md`
- 修改：`.overnight/supervisor-prompt.md`（3 处 DESIGN-TO-SWIFTUI → design-to-swiftui）
- 修改：`docs/solutions/best-practices/visionos-design-mockup-to-swiftui-pipeline-2026-04-05.md`（4 处）

**方案：**
- 目录重命名用 `git mv`（文件在 git 追踪中）
- DESIGN-TO-SWIFTUI.md 重命名用 `git mv`
- R16 引用更新精确位置（调研已验证）：
  - .overnight/supervisor-prompt.md: 行 26（完整路径）、行 44、行 54（文件名）
  - visionos-design-mockup-to-swiftui-pipeline-...md: 行 74（完整路径）、行 118（文件名）、行 130（完整路径）、另 1 处
- file-browser-redesign 目录内 5 个 HTML 文件无外部引用，重命名目录即可

**要遵循的模式：**
- docs/designs/ 下其他文件已遵循 kebab-case 命名

**测试场景：**
- 正常路径：`docs/designs/design-to-swiftui.md` 存在且内容与重命名前一致
- 正常路径：`docs/designs/DESIGN-TO-SWIFTUI.md` 不存在
- 正常路径：`docs/designs/file-browser-redesign-2026-04-05/` 存在且包含 5 个 HTML 文件
- 正常路径：`grep -rn "DESIGN-TO-SWIFTUI" .overnight/supervisor-prompt.md docs/solutions/` 返回 0 结果
- 正常路径：`grep -rn "20260405" docs/designs/` 返回 0 结果（目录名已改）
- 边界情况：重命名后 HTML mockup 文件内容完整（无截断或损坏）

**验证：**
- 活跃文档路径遵循 kebab-case + ISO 日期格式
- 所有 DESIGN-TO-SWIFTUI 引用已更新为 design-to-swiftui

## 系统范围影响

- **Agent 工作流恢复**：Unit 1+2 完成后，CLAUDE.md 中的 Agent 标准动作序列可正确引用 REGRESSION.md、TESTING.md 等文件，Agent 工作流恢复正常
- **Overnight pipeline**：.overnight/supervisor-prompt.md 的锚定文档引用需在 Unit 2 和 Unit 4 中更新，否则后续 overnight 启动时引用错误
- **UI/UX 重构计划**：Unit 3 将 plan 和 arch 文件移到 active/，不改变内容，但后续 /ce-work 引用路径需使用新位置
- **无代码影响**：所有变更仅涉及文档和 git 索引，不影响编译、运行或测试

## 风险与依赖

| 风险 | 缓解措施 |
|------|----------|
| git checkout HEAD 恢复失败（文件已被 stage） | 执行前 `git status` 确认 ` D` 状态，若已 stage 则用 `git show HEAD:` 替代 |
| 目录重命名在 macOS 大小写不敏感文件系统上行为异常 | `git mv` 处理大小写变更，macOS 默认 APFS 大小写不敏感但 git 追踪是敏感的，先 `git mv` 到临时名再到目标名 |
| 漏改引用导致后续 Agent 引用断裂 | 每个 Unit 完成后全局 grep 验证，Unit 2 有完整行号映射 |
| .overnight/supervisor-prompt.md 被下一轮 overnight 覆盖 | 此文件是模板生成的，更新后下一轮 setup 可能覆盖。但当前是 overnight 中，暂不重新生成 |

## 来源与参考

- **来源文档：** [docs/brainstorms/2026-04-05-doc-cleanup-and-path-normalization-requirements.md](docs/brainstorms/2026-04-05-doc-cleanup-and-path-normalization-requirements.md)
- **审计报告：** [docs/reference/2026-04-05-document-audit-findings.md](docs/reference/2026-04-05-document-audit-findings.md)
- **相关计划：** [docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md](docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md)（即将移入 active/）
