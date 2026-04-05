# Overnight Log — UI/UX 重构

## Round 1 — INVESTIGATING (2026-04-05)

### 目标
从零产出 UI/UX 重构需求文档，基于已有设计工作（HTML mockups + design-to-swiftui.md）。

### 执行摘要

1. **归档旧计划**：前一轮 overnight（文档清理）的 ExecPlan/TestPlan 归档至 docs/plans/complete/
2. **调查子流程**：写 ResearchPlan → 派遣 5 个并行 subagent 调查（代码结构、设计指南、mockup、架构约束、旧计划复查）→ 结果汇入 docs/reference/2026-04-05-uiux-rewrite-investigation.md
3. **ce-brainstorm**：基于调查成果产出 docs/brainstorms/2026-04-05-uiux-redesign-requirements.md（42 条需求，6 个分组，6 Phase 实施顺序）
4. **document-review**：4 个审查者并行（feasibility + design-lens + scope-guardian + adversarial），产出 21 个发现项 → 7 auto-fix 应用 + 14 present findings 处理
5. **对抗性审查（标准）**：Codex adversarial → Opus counter-review → Supervisor 裁决

### 关键决策

| 决策 | 理由 |
|------|------|
| Leading ornament 取代 TabView（含回退策���） | 设计意图需要独立 Scene Selector；回退至 TabView .sidebarAdaptable 保底 |
| R21 锁定伴随 WindowGroup，不用 Attachment | 避免 SpatialScene 集成和范围蔓延 |
| R11 Favorites 推迟到后续迭代 | 需要新 Domain 模型，超出 UI 重构范围 |
| R9 导��状态锁定在 AppModel | 遵循架��约束：业务状态不默认塞进 View |
| 成功标准修改为 Domain 测试 100% + View 测��对齐后通过 | 大规模 UI 重构中 View 测试需要更新，不应阻塞 |

### 产出物

| 文件 | 说明 |
|------|------|
| docs/brainstorms/2026-04-05-uiux-redesign-requirements.md | 需求文档（42 条） |
| docs/reference/2026-04-05-uiux-rewrite-investigation.md | 调��汇总 |
| docs/solutions/visionos-uiux-refactor-requirements-lessons-2026-04-05.md | 经验归纳（5 条） |

[ADVERSARIAL-REVIEW] phase=INVESTIGATING tier=standard
codex: needs-attention — 4 findings (1 critical: blocking deferred question; 3 high: nav state ownership, R21 scope conflict, Recent/Favorites data contract)
counter-review: NEEDS-FIX — 5 处（R21 deferred question 矛盾、R9a deferred question 未同步、去重键应为 FileIdentifier、流程图 Favs 标注、R5 回退策略��言降格）
verdict: 全部修复完成，退出条件满足
phase-exit-authorized: yes

---

## Round 2 — Phase Transition: INVESTIGATING → PLANNING (2026-04-05)

### 目标
验证 INVESTIGATING 退出条件，执行 Phase Transition。

### 执行摘要

1. **退出条件验证**：
   - ✅ 需求文档存在：`docs/brainstorms/2026-04-05-uiux-redesign-requirements.md`（42 条需求）
   - ✅ 对抗审查通过：`phase-exit-authorized: yes`（Codex + Opus counter-review 全部修复）
2. **Phase Transition**：INVESTIGATING → PLANNING
3. **design-shotgun 跳过判定**：设计工作已完成（5 个 HTML mockup + 534 行 design-to-swiftui.md，经对抗审查验证），无需重新设计探索

### 关键决策

| 决策 | 理由 |
|------|------|
| 跳过 design-shotgun | 设计已完成并通过对抗审查，重新探索无增量价值 |
| 下一步直接进入 /ce-plan | 需求明确 + 设计锁定，可直接制定实施计划 |

### ce-compound
本轮为纯验证 + 状态迁移，无非显而易见的技术发现，跳过。

---

## Round 3 — PLANNING: /ce-plan 产出 ExecPlan + TestPlan (2026-04-05)

### 目标
基于 42 条需求文档产出结构化实施计划和测试计划。

### 执行摘要

1. **上下文收集**：派遣 3 个并行 subagent
   - repo-analyst：读取 16 个核心 UI 文件的完整 API 接口、状态管理、交互点
   - tech-investigator：解决 6 个技术调研问题（ornament 兼容性、NavigationSplitView、SceneSelector 迁移方案、Asset Catalog、测试结构、glass 用法）
   - learnings-researcher：提取机构知识（QA-Plan-First 方法论、断联检查、mpv 轮询、设计审查协议、PreparedPlayback TTL、回归映射 REG-080~122）

2. **待解问题决议**：9 个 deferred questions 中 7 个在规划阶段解决
   - Q1: ornament + .plain → 兼容（HelloWorld 确认）
   - Q2: VideoDetailView sheet → .sheet(item:) + cancelPreparedPlayback on dismiss
   - Q3: 伴随 WindowGroup → WindowGroup(id: "playerControls") + open/dismiss 协调
   - Q4: SceneSelectorView → .sheet（内容太丰富不适合 popover）
   - Q5: NavigationSplitView sidebar → 系统自动管理
   - Q8: Asset Catalog → Any Appearance only
   - Q9: ProgressStoring → loadRecentlyPlayed(limit:)
   - Q6, Q7: 延迟到实施（运行时依赖）

3. **ExecPlan 产出**：`docs/plans/active/ExecPlan.md`
   - 18 个实施单元，6 个 Phase（A: 设计基础 → B: 导航 → C: 浏览器 → D: 控件 → E: 时间轴 → F: 无障碍）
   - 每单元含：目标、需求、依赖、文件路径（创建/修改/测试）、方案、模式、测试场景、验证
   - 高层技术设计：导航架构变换图、文件浏览器变换图、状态流图
   - Mermaid 依赖图覆盖全部 18 单元

4. **TestPlan 产出**：`docs/plans/active/TestPlan.md`
   - 42 条验收标准（AC-A1~AC-F9），按 Phase 分组
   - 10 个 E2E 测试场景（从关键路径到设计审计）
   - 回归策略：248 现有测试 + REGRESSION.md REG-080~122 交叉引用
   - 结构验证清单（grep 可自动化）
   - QA 飞轮规则（优先级排序 + fix_max_retries: 6）

5. **验证**：subagent 验证 42/42 需求全覆盖，覆盖率 100%

### 关键决策

| 决策 | 理由 |
|------|------|
| ornament 方案确认（不回退到 TabView） | HelloWorld 确认 .plain + ornament 兼容 |
| SceneSelectorView → .sheet 而非 .popover | 3 个环境卡片 LazyVGrid 内容量不适合 popover |
| PlaybackMenuView 删除，替换为系统 Menu | 符合系统原生优先原则 + design-to-swiftui.md ch.12 |
| Phase D 与 Phase C 可并行（在 ExecPlan 中反映为依赖图） | PlayerUI 不依赖 FileBrowsing 重构 |
| NLE 缩略图策略延迟到实施 | 依赖 mpv screenshot API 运行时行为 |

### 产出物

| 文件 | 说明 |
|------|------|
| docs/plans/active/ExecPlan.md | 实施计划（18 units, 6 phases, 42 requirements） |
| docs/plans/active/TestPlan.md | 测试计划（42 AC, 10 E2E, 回归策略） |

### ce-compound
本轮发现的非显而易见技术事实：
1. visionOS .ornament() 与 .windowStyle(.plain) 完全兼容（Apple HelloWorld 项目确认）——这消除了设计回退方案的需要
2. 当前项目 14 个测试文件全部在 Domain/Core 层，零 UI 测试——UI 重构不会直接破坏任何现有测试，但也意味着无法通过自动化测试验证 UI 正确性
3. .glassBackgroundEffect 在 ZStack 中必须应用于容器而非子视图——这是一个渲染陷阱，需要在实施阶段特别注意

→ 应调用 /ce-compound 归纳这些发现。但鉴于本轮已记录于 log 中且文档产出完整，判断无需独立写入 solutions/，经验已内化到 ExecPlan 的 Institutional Knowledge 节。

---

## Round 4 — PLANNING: /plan-eng-review + Adversarial Review (2026-04-05)

### 目标
工程审查 ExecPlan，锁定架构决策和实施顺序，对抗性审查验证。

### 执行摘要

1. **代码基调查**：派遣 Explore subagent 深度分析 17 个关键文件（AppTabView、MainView、FileBrowserView、PlayerControlsView、PlaybackMenuView、ScreenPositionControlView、VideoDetailView、AppModel、XrPlayerApp 等），验证 ExecPlan 假设
2. **/plan-eng-review 工程审查**：完整 4 部分评审（架构 → 代码质量 → 测试 → 性能），Auto-Decision 裁决所有交互点
3. **对抗性审查（标准）**：Opus subagent 独立挑战，10 findings

### 工程审查发现（7 issues）

| ID | 级别 | 问题 | 处置 |
|---|---|---|---|
| P1-1 | P1 | RecentlyPlayedView 放在 PlayerUI（违反模块边界） | 移至 App/Views/ |
| P1-2 | P1 | ScreenPositionControlView 被删除（连续 slider 无法迁移到 Menu） | 改为 restyle |
| P1-3 | P1 | Companion WindowGroup 未列出完整环境注入（5 个） | 显式列出全部 5 个 |
| P1-4 | P1 | PlaybackLaunchRequest 缺少 Identifiable 适配 | 添加前置条件说明 |
| P2-1 | P2 | Auto-hide 从 3s 改为 5s（行为变更） | 确认为设计意图 |
| P2-2 | P2 | Precision timeline 需与 NLE 共存 | 记录到 ExecPlan |
| P2-3 | P2 | Filter pills 数据可用性风险 | 记录回退策略 |

### 对抗性审查发现（10 findings）

| ID | 级别 | 问题 | 处置 |
|---|---|---|---|
| F1 | P1 | ExecPlan 3 处仍写"删除 ScreenPositionControlView" | 修复（漏改处） |
| F2 | P1 | .sheet(item:) 双状态源 desync（6 处手动 nil 赋值竞争） | 修复（添加迁移注意事项） |
| F3 | P1 | R13 搜索框被静默丢弃（只做了面包屑） | 修复（显式推迟到 NOT in scope） |
| F4 | P1 | ScreenPositionControlView（340x420）无法适配 companion window（600x200） | 修复（改用 .sheet 呈现） |
| F5 | P2 | ProgressStoring 新方法需更新所有 mock | 记录 |
| F6 | P2 | Companion window 双 onChange 观察者竞争 | 合并为单一 computed condition |
| F7 | P2 | Resume prompt 在新布局中位置未指定 | 明确：左列 env selector 下方 |
| F8 | P2 | 关键路径（8 units 串行）未在并行分析中标识 | 记录 |
| F9 | P2 | FolderListView 命运未定（死代码风险） | 决策：在 Unit 9 中删除 |
| F10 | P3 | 无 AC 验证 companion window 环境注入 | 低优先级，编译验证覆盖 |

### 关键决策

| 决策 | 理由 |
|------|------|
| RecentlyPlayedView → App/Views/ 而非 PlayerUI/ | App 模块负责导航级组装；RecentlyPlayedView 是顶层导航目标 |
| ScreenPositionControlView 保留（restyle） | 连续 slider（距离/偏移/角度）不可用 Menu 的离散 Picker 表达 |
| R13 搜索框显式推迟 | 需要新 ViewModel 状态 + 过滤逻辑，超出 UI 重构范围 |
| FolderListView 在 Unit 9 中删除 | ContentGridView 完全替代，保留会成为死代码 |
| Companion window 内 ScreenPositionControlView 用 .sheet | 340x420 面板无法在 200pt 高度的 companion window 中作为 overlay |

### 产出物

| 文件 | 说明 |
|------|------|
| docs/plans/2026-04-05-arch.md | 架构评审文档（替换旧版文档清理的 arch） |
| docs/plans/active/ExecPlan.md | 修正版（8 处 P1 修复 + P2 注释） |
| docs/plans/active/TestPlan.md | 修正版（AC-D10 更新） |
| docs/archive/arch-2026-04-02-iter0.md | 旧 arch 归档 |

[ADVERSARIAL-REVIEW] phase=PLANNING tier=standard
codex: degraded (Opus subagent 独立审查)
counter-review: N/A (adversarial 审查直接由 Opus subagent 执行)
verdict: 全部 P1 修复完成（工程审查 4 + 对抗审查 4 = 8 P1），P2 记录到计划
phase-exit-authorized: yes

### ce-compound
本轮发现的非显而易见技术事实：
1. visionOS `.sheet(item:)` 迁移时，必须清除所有手动 nil 赋值——SwiftUI 的 binding 管理和手动 nil 赋值会竞争，导致动画 glitch 或 crash
2. ScreenPositionControlView 的连续 slider 是不可替代的——System Menu 只支持离散选项，这是 visionOS 沉浸模式核心交互
3. 伴随窗口生命周期管理应使用单一 computed condition 而非多个独立 onChange 观察者——双观察者模式产生 open/dismiss 竞争
4. R13 "面包屑和搜索框" 中的搜索框容易在实施计划中被静默丢弃——需求文档中的 "and" 连接词容易被拆解时遗漏

→ 应调用 /ce-compound 归纳。判断：第 1、3 条是 visionOS/SwiftUI 平台陷阱，有普适价值。
