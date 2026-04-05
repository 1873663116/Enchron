---
title: "文档清理与路径规范化 — 验收计划"
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-doc-cleanup-and-path-normalization-requirements.md
---

# 验收计划：文档清理与路径规范化

## 验收标准（来源于需求文档成功标准）

### AC1：无断裂 workspace-agents/ 引用

**条件：** 项目中活跃文档不存在对 `workspace-agents/` 的引用

**验证命令：**
```bash
grep -rn "workspace-agents" --include="*.md" . \
  | grep -v "docs/archive/" \
  | grep -v "docs/reference/" \
  | grep -v ".overnight/log.md" \
  | grep -v "docs/brainstorms/"
```

**期望结果：** 0 行输出

**排除说明：** docs/archive/（归档保留原文）、docs/reference/（审计报告）、.overnight/log.md（历史日志）、docs/brainstorms/（需求文档本身）不在修复范围内。

---

### AC2：CLAUDE.md 路由表可达

**条件：** CLAUDE.md 文档路由表中每个路径指向磁盘上实际存在的文件

**验证方法：** 对 CLAUDE.md 路由表中每个文档路径执行 `test -f` 或 `test -d`

**期望结果：** 所有路径均存在。特殊情况：`~/.claude/skills/` 是全局路径，验证 `test -d ~/.claude/skills/`

---

### AC3：无 unstaged deletion

**条件：** `git status` 无 ` D`（空格+D）状态的文件

**验证命令：**
```bash
git status --porcelain | grep "^ D"
```

**期望结果：** 0 行输出

---

### AC4：无含空格的 docs/ 子目录

**条件：** `docs/` 下无目录名含空格

**验证命令：**
```bash
find docs/ -type d -name "* *"
```

**期望结果：** 0 行输出

---

### AC5：kebab-case + ISO 日期

**条件：** 活跃文档路径遵循 kebab-case + ISO 日期格式（YYYY-MM-DD）

**验证方法：**
```bash
# 检查 SCREAMING_CAPS 文件名（排除 README/CLAUDE/ARCHITECTURE 等约定大写）
find docs/designs/ docs/plans/ -name "*[A-Z]*[A-Z]*" -not -name "README*" -not -name "CLAUDE*"

# 检查无分隔符的日期格式
find docs/ -name "*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" -not -path "*/archive/*"
```

**期望结果：** 两条命令均 0 行输出

---

## 单元级验证清单

| Unit | 关键验证 | 阻塞下一 Unit |
|------|----------|---------------|
| 1 | 7 个文件存在且内容正确 | 是（Unit 2, 3 依赖） |
| 2 | 活跃文档 0 处 workspace-agents/ 引用 | 是（Unit 4 依赖） |
| 3 | 0 个 ` D` 文件，0 个空格目录名 | 否 |
| 4 | 0 处 DESIGN-TO-SWIFTUI 旧引用 | 否（最终验收） |
