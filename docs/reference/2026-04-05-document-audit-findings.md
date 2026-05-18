# Document Audit Findings — 2026-04-05

Goal: UI/UX 重构前的文档更新 + 文件命名/路径规范化

---

## 1. 关键缺失文件

### 1.1 从 workspace-agents/ 删除但未迁移（CLAUDE.md 仍引用）

| 文件 | 影响 | 建议 |
|------|------|------|
| `product_philosophy.md` | **CRITICAL** — 设计冲突仲裁权威，CLAUDE.md 2 处引用 | 从 git 恢复到 `docs/product_philosophy.md` |
| `Requirements.md` | **CRITICAL** — 功能范围/验收边界，CLAUDE.md 引用 | 从 git 恢复到 `docs/Requirements.md` |
| `quality_gates.md` | **HIGH** — 提交前自查标准 | 从 git 恢复到 `docs/quality_gates.md` |
| `mpv-build-guide.md` | **MEDIUM** — visionOS 交叉编译知识 | 恢复到 `docs/reference/mpv-build-guide.md` |

### 1.2 根目录删除的文档（CLAUDE.md Agent 动作序列依赖）

| 文件 | 行数 | 引用数 | 影响 | 建议 |
|------|------|--------|------|------|
| `REGRESSION.md` | 906 | 7 (CLAUDE+ARCH) | **CRITICAL** — Agent 回归映射核心 | 恢复 |
| `TESTING.md` | 253 | 4 (CLAUDE+ARCH) | **CRITICAL** — 双轨验证协议 | 恢复 |
| `QUALITY_SCORE.md` | 42 | 1 (CLAUDE) | **HIGH** — 质量基线 | 恢复 |
| `TODOS.md` | 183 | 0 | **LOW** — 历史记录，可重建 | 可不恢复 |

---

## 2. 断裂引用

### 2.1 CLAUDE.md — 11 处 workspace-agents/ 引用（路由表 6 处 + 表外 5 处）

路由表内（6 处）：

| 引用路径 | 状态 | 修复目标 |
|---------|------|---------|
| `workspace-agents/product_philosophy.md` | DELETED | → `docs/product_philosophy.md` |
| `workspace-agents/Requirements.md` | DELETED | → `docs/Requirements.md` |
| `workspace-agents/quality_gates.md` | DELETED | → `docs/quality_gates.md` |
| `workspace-agents/known_issues.md` | DELETED | → 删除行（已归档解决） |
| `workspace-agents/ubiquitous_language.md` | DELETED | → `docs/ubiquitous_language.md` |
| `workspace-agents/contracts/` | DELETED | → `docs/contracts/` |
| `workspace-agents/design_docs/` | DELETED | → `docs/design_docs/` |

表外引用（5 处）也需更新：Agent 标准动作序列、技术 Skill 表等区域。修复时需 grep 全文。

### 2.2 ARCHITECTURE.md — 7 处 workspace-agents/ 引用

Lines 10, 205, 214, 216, 218, 243, 246 全部引用 workspace-agents/，需更新为 docs/ 路径。

### 2.3 README.md + README.en.md — 各 6 处断裂引用

全部 workspace-agents/ 路径，需更新为 docs/。

### 2.4 其他文件中的断裂引用（对抗审查补充）

| 文件 | 引用数 | 说明 |
|------|--------|------|
| `docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md` | 4 | **活跃计划**，优先修复 |
| `docs/design_docs/README.md` | 1 | 交叉引用 |
| `docs/solutions/best-practices/autonomous-overnight-*.md` | 1 | 旧 skill 路径 |
| `.overnight/supervisor-prompt.md` | 2 | 每轮 overnight 读取 |

---

## 3. 目录结构问题

### 3.1 命名违规

| 类型 | 数量 | 示例 | 建议 |
|------|------|------|------|
| PascalCase + 编号 | 46 | `docs/archive/ExecPlan/ExecPlan001.md` | 归档不改名，但标注为遗留格式 |
| 目录名含空格 | 1 | `docs/archive/issues archive/` | → `docs/archive/issues-archive/` |
| SCREAMING_CAPS | 1 | `DESIGN-TO-SWIFTUI.md` | → `design-to-swiftui.md` |
| 日期缺分隔符 | 1 | `file-browser-redesign-20260405/` | → `file-browser-redesign-2026-04-05/` |
| snake_case（legacy） | 9 | `docs/design_docs/phase1_capacity_estimation.md` | 归档不改名，标注遗留 |
| QA 报告大写后缀 | 4 | `qa-report-v3-batch1-ABC.md` | → 小写 `abc` |

### 3.2 结构错位

| 问题 | 当前位置 | 正确位置 |
|------|---------|---------|
| 活跃计划在 plans/ 根 | `docs/plans/2026-04-02-*.md` (2 files) | `docs/plans/active/` |

### 3.3 空目录

| 目录 | 说明 |
|------|------|
| `docs/brainstorms/` | 本轮 INVESTIGATING 将产出到此 |
| `docs/reference/` | 本次审计已写入 |
| `docs/plans/complete/` | 保留，待归档用 |

---

## 4. 已迁移确认（无需动作）

| 来源 | 目标 | 文件数 | 状态 |
|------|------|--------|------|
| workspace-agents/contracts/ | docs/contracts/ | 4 | 内容一致 ✓ |
| workspace-agents/design_docs/ | docs/design_docs/ | 10 | 内容一致 ✓ |
| workspace-agents/ubiquitous_language.md | docs/ubiquitous_language.md | 1 | 内容一致 ✓ |
| workspace-agents/skills/ (18 domains) | ~/.claude/skills/ | 全部 | 已确认可用 ✓ |
| workspace-agents/archive/ | docs/archive/ | 全部 | 已迁移 ✓ |

---

## 5. 设计文档状态

### 5.1 DESIGN-TO-SWIFTUI.md — 功能完整，结构有缺

- 612 行，17 章，覆盖全 UI 组件
- HTML mockups 5 个文件全部有效
- **缺失**：模块归属矩阵（哪个 section 属于哪个 bounded context）
- **缺失**：HTML mockup ↔ section 交叉引用表
- **缺失**：与 ARCHITECTURE.md 的显式链接
- **潜在歧义**：immersionStyle 状态在 App 层，但决策逻辑在 PlayerUI

### 5.2 QA 文档 — 当前且完整

- 5 个 QA 计划（v3 methodology）
- 7 个 QA 报告 + 11 张截图
- 最新健康分 95.69%（3 天前）
- 无需更新

---

## 6. Git 清理

workspace-agents/ 和 docs/ExecPlan/ 的 88+ 个文件在磁盘已删除但仍被 git 追踪。需要 `git rm` 正式从索引移除。

> **安全确认**：Section 4 已验证所有有价值内容均已迁移到 docs/ 或 ~/.claude/skills/，`git rm` 不会导致数据丢失。

---

## 7. 动作优先级

### P0 — 恢复关键文件（阻塞 Agent 工作流）

> **安全注意**：当前删除为 unstaged（git status ` D`），HEAD 仍包含这些文件。
> 若删除被 stage 或 commit，以下命令将失败。执行前先 `git status` 确认。

1. `git checkout HEAD -- REGRESSION.md`
2. `git checkout HEAD -- TESTING.md`
3. `git checkout HEAD -- QUALITY_SCORE.md`
4. `git show HEAD:workspace-agents/product_philosophy.md > docs/product_philosophy.md`
5. `git show HEAD:workspace-agents/Requirements.md > docs/Requirements.md`
6. `git show HEAD:workspace-agents/quality_gates.md > docs/quality_gates.md`
7. `git show HEAD:workspace-agents/mpv-build-guide.md > docs/reference/mpv-build-guide.md`

### P1 — 修复断裂引用

8. 更新 CLAUDE.md 全文（11 处 workspace-agents/ → docs/，含路由表内外）
9. 更新 ARCHITECTURE.md（7 处 workspace-agents/ → docs/）
10. 更新 README.md + README.en.md（各 6 处）
11. 更新 docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md（4 处）
12. 更新 .overnight/supervisor-prompt.md（2 处）
13. 更新 docs/design_docs/README.md + docs/solutions/best-practices/autonomous-overnight-*.md

### P2 — 结构规范化

11. `git mv "docs/archive/issues archive" docs/archive/issues-archive`
12. 移动 `docs/plans/2026-04-02-*.md` → `docs/plans/active/`
13. `git rm` 清理已删除的 workspace-agents/ 和 docs/ExecPlan/ 追踪

### P3 — 路径规范化（命名）

14. 重命名 `file-browser-redesign-20260405/` → `file-browser-redesign-2026-04-05/`
15. 重命名 `DESIGN-TO-SWIFTUI.md` → `design-to-swiftui.md`（需同步更新所有引用）

### 超出范围（记录但不在本轮执行）

- DESIGN-TO-SWIFTUI.md 模块归属矩阵 + mockup 交叉引用 — 属于内容创作，非路径/引用修复
- `.gitignore` 添加 workspace-agents/ 防止意外重建 — 低优先级可选

### 不动作

- `docs/archive/ExecPlan/` 46 个旧格式文件 — 归档不改名
- `docs/design_docs/phase*_*.md` 9 个 snake_case 文件 — 遗留格式保留
- QA 报告大写后缀 — 低优先级，不影响功能
- `TODOS.md` — 可不恢复
