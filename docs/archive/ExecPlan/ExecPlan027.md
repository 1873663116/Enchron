# ExecPlan027 — T0.6 验证所有功能是否真正实现

> Round 6 | 2026-04-02
> Pipeline: PLANNING (T0.6)

## 目标

对照 feature-inventory-v3.md 的 82 个功能点，逐项审查代码实现的真实状态：
1. 功能入口是否可达（UI 按钮/菜单存在且非 disabled）
2. 核心逻辑是否完整（无 stub/TODO/fatalError）
3. 数据流是否贯通（UI → UseCase → Domain → Persistence/Adapter 全链路）
4. 发现"名义上实现但断联"的功能 → 标记为 Phase 2 修复项

## 委派计划

按模块分 4 个并行 Sonnet subagent 审计：

| Agent | 审计范围 | 功能编号 |
|-------|---------|---------|
| audit-playback | PlaybackCore + PlayerUI | F1.5-F1.22, F3.1-F3.21, F4.1-F4.10, F5.1-F5.4 |
| audit-filebrowsing | FileBrowsing + App 导航 | F1.1-F1.4, F2.1-F2.9 |
| audit-spatial | SpatialScene + 沉浸环境 | F3.2-F3.3, F6.1-F6.7 |
| audit-settings | Settings + Persistence + 辅助功能 | F7.1-F7.6, F8.1-F8.5, F9.1-F9.5 |

## 产出

`docs/qa-plans/code-audit-v3.md` — 每个功能的实现完整性判定 + 断联功能列表
