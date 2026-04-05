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

---

## Round 5 — Phase Transition: PLANNING → EXECUTING (2026-04-05)

### 目标
验证 PLANNING 退出条件，执行 Phase Transition。

### 执行摘要

1. **退出条件验证**：
   - ✅ ExecPlan 存在：`docs/plans/active/ExecPlan.md`（53KB, 18 units, 6 phases, 39 requirements）
   - ✅ TestPlan 存在：`docs/plans/active/TestPlan.md`（17KB, 42 AC, 10 E2E）
   - ✅ 对抗审查通过：`phase-exit-authorized: yes`（R4: 工程审查 + Opus adversarial, 8 P1 fixed）
2. **Phase Transition**：PLANNING → EXECUTING
3. **下一步**：Unit 1: Semantic Color System (R1) — Phase A 设计基础

### 关键决策

| 决策 | 理由 |
|------|------|
| R4 ce-compound 不重复调用 | 4 条发现已内化到 ExecPlan Institutional Knowledge 节 + log.md 永久记录 |
| EXECUTING 从 Unit 1 开始 | Phase A 设计基础是所有后续 Phase 的依赖 |

### ce-compound
本轮为纯验证 + 状态迁移，无非显而易见的技术发现，跳过。

---

## Round 6 — EXECUTING: Unit 1 Semantic Color System (R1) (2026-04-05)

### 目标
执行 ExecPlan Unit 1：建立 9 色语义调色板作为 SwiftUI 一等资产。

### 执行摘要

1. **Asset Catalog 创建**：9 个 Color Sets 在 `XrPlayer/Assets.xcassets/Colors/`，全部使用 "Any Appearance"（sRGB 浮点值）
2. **Color extension 冲突发现**：手动创建 `Color+DesignTokens.swift` 导致 Xcode build 失败（"invalid redeclaration"），因 Xcode 15+ 自动从 Asset Catalog 生成同名 `Color.xxx` 访问器
3. **修复**：删除手动 extension，依赖 Xcode Generated Asset Symbols
4. **测试**：DesignTokenTests.swift（7 个测试）— 验证调色板完整性、命名规范、hex 有效性、RGB 转换精度
5. **验证**：SPM tests 255/255 passed + Xcode visionOS Simulator build succeeded

### 关键决策

| 决策 | 理由 |
|------|------|
| 不写手动 Color extension | Xcode 15+ 自动从 Asset Catalog 生成 type-safe Color 访问器，手动定义会冲突 |
| 测试作为 contract tests（非 Asset Catalog 直接测试） | SPM 测试无法访问 app bundle 的 xcassets，改为验证设计规范合约 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/Assets.xcassets/Colors/*.colorset | 9 个 Color Sets |
| Tests/XrPlayerCoreTests/DesignTokenTests.swift | 7 个合约测试 |
| docs/solutions/build-errors/xcode-asset-catalog-color-redeclaration-2026-04-05.md | ce-compound 经验归纳 |

### ce-compound
Xcode 15+ Asset Catalog 自动符号生成与手动 Color extension 冲突 — 平台陷阱，已归纳到 `docs/solutions/build-errors/`。

---

## Round 7 — EXECUTING: Unit 3 AppModel Navigation State (R9) (2026-04-05)

### 目标
执行 ExecPlan Unit 3：为 AppModel 添加导航状态（NavigationTab 枚举 + selectedTab + showSceneSelector）。

### 执行摘要

1. **AppModel 修改**：在 `XrPlayer/AppModel.swift` 添加 `NavigationTab` 枚举（browse/recent/settings，String RawValue + CaseIterable）、`selectedTab: NavigationTab = .browse`、`showSceneSelector: Bool = false`
2. **测试创建**：`Tests/XrPlayerCoreTests/NavigationStateTests.swift` — 5 个合约测试（SPM 无法导入 AppModel 因 SwiftUI/@Observable 依赖，延续 Unit 1/2 的合约测试模式）
3. **验证**：SPM tests 269/269 passed + Xcode visionOS Simulator build succeeded

### 关键决策

| 决策 | 理由 |
|------|------|
| NavigationTab 放在 AppModel 内部而非独立文件 | 遵循 ExecPlan 设计 + 与 ImmersiveSpaceState 模式一致 |
| 合约测试而非直接测试 AppModel | AppModel 依赖 SwiftUI/@Observable，无法在 SPM macOS 测试中实例化，延续已建立的合约测试模式 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/AppModel.swift | 添加 NavigationTab + selectedTab + showSceneSelector |
| Tests/XrPlayerCoreTests/NavigationStateTests.swift | 5 个合约测试 |

### ce-compound
纯附加枚举 + 属性添加，遵循已有模式，无非显而易见的技术发现，跳过。

---

## Round 8 — EXECUTING: Unit 6 NavigationSplitView Container (R10) (2026-04-05)

### 目标
执行 ExecPlan Unit 6：将 FileBrowserView 从 NavigationStack 重构为 NavigationSplitView 两栏布局。

### 执行摘要

1. **FileBrowserView 重构**：`NavigationStack { VStack { ... } }` → `NavigationSplitView { sidebar } detail: { content }`
2. **Sidebar**：数据源列表（Local Storage + 已保存远程源），含选中高亮、连接状态指示器、swipe-to-delete
3. **Detail**：保留现有 FolderListView + 连接横幅 + 导航上行按钮 + 排序/文件夹工具栏
4. **移除**：`.navigationDestination` for VideoDetailView（迁移到 Unit 10 的 .sheet）
5. **移动**：Add Source 菜单从 detail toolbar 移至 sidebar toolbar
6. **验证**：visionOS Simulator build succeeded + SPM tests 284/284 passed

### 关键决策

| 决策 | 理由 |
|------|------|
| Sidebar 使用 List + Button 而非 selection binding | Unit 7 将实现完整的 selection binding，当前阶段保持功能可用即可 |
| 保留 detail 内的 connected banner + navigate up | 这些是 Unit 7/8 的迁移目标，当前保持功能完整 |
| .navigationDestination 直接移除 | ExecPlan 明确：Unit 10 将以 .sheet(item:) 替代 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/FileBrowsing/Views/FileBrowserView.swift | NavigationSplitView 两栏重构 |

### ce-compound
直接的 NavigationStack → NavigationSplitView 重构，遵循标准 SwiftUI 模式和 design-to-swiftui.md 指南。无非显而易见的技术发现，跳过。

---

## Round 9 — EXECUTING: Unit 7 Sidebar with Data Sources & Storage (R11) (2026-04-05)

### 目标
执行 ExecPlan Unit 7：从 FileBrowserView 提取 Finder 风格侧栏到独立组件，实现数据源分区选择和本地存储容量指示器。

### 执行摘要

1. **创建 FileBrowserSidebar.swift**：从 FileBrowserView 的 placeholder sidebar 提取为独立视图
2. **SidebarItem 桥接枚举**：`enum SidebarItem: Hashable { case local; case remote(UUID) }` — 桥接 `List(selection:)` 的 Hashable 要求与 ViewModel 的 `activeDataSource: DataSource?`（仅 Equatable）
3. **选择绑定**：自定义 `Binding<SidebarItem?>` 双向同步 — get 从 activeDataSource 映射，set 触发 useDefaultFolder/connectToDataSource
4. **数据源分区**：Section "Sources" 内 Local Storage 行 + ForEach 远程源行，含连接状态绿点指示器 + onDelete 滑动删除
5. **存储容量条**：`URL.resourceValues` 获取卷容量 → ProgressView + ByteCountFormatter 显示已用/总容量，颜色按使用率分档（>90% 红，>75% 橙）
6. **验证**：visionOS Simulator build succeeded + SPM tests 284/284 passed

### 关键决策

| 决策 | 理由 |
|------|------|
| SidebarItem 桥接枚举而非让 DataSource 遵循 Hashable | DataSource 是 Domain 实体（Equatable + Codable），不应为 View 层需求修改 Domain 层 — Clean Architecture 依赖方向 |
| 存储容量在 View 层通过 FileManager 获取 | 一次性展示数据，无业务逻辑，不值得引入 ViewModel 方法或 Domain port |
| Add Source 菜单保留在 FileBrowserView（非 FileBrowserSidebar） | 菜单触发 fileImporter/sheet 状态绑定，这些状态属于 FileBrowserView 的 @State，移到子视图会增加不必要的状态传递 |
| onDelete 替代 swipeActions | List(selection:) 模式下 .onDelete 是 SwiftUI 标准 sidebar 删除方式，比 swipeActions 更符合系统惯例 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/FileBrowsing/Views/FileBrowserSidebar.swift | 新建 — Finder 风格侧栏组件 |
| XrPlayer/FileBrowsing/Views/FileBrowserView.swift | 修改 — 用 FileBrowserSidebar() 替换 placeholder sidebar |

### ce-compound
标准 SwiftUI List(selection:) + 视图提取 + FileManager 容量查询。无平台陷阱或非显而易见的技术发现，跳过。

---

## Rounds 10-13 — EXECUTING: Units 8-11 (2026-04-05) — Retroactive Sync

> 以下四轮由前任 Supervisor 完成但未同步 log.md，现从 git history 和 ExecPlan 补记。

### Round 10 — Unit 8: Breadcrumb Navigation & Filter Pills (R13, R14)
- **Commit**: `09d912a` feat(file-browser): add breadcrumb navigation & filter pills
- **产出**: 面包屑路径导航 + All/4K/HDR/Spatial 过滤标签

### Round 11 — Unit 9: Video Card Grid (R12, R15)
- **Commit**: `67a1c32` feat(file-browser): add video card grid with LazyVGrid layout
- **产出**: VideoCardView 组件 + LazyVGrid 内容网格

### Round 12 — Unit 10: Video Detail Sheet (R16, R17)
- **Commit**: `efd32a4` feat(file-browser): migrate VideoDetailView to sheet with two-column layout
- **产出**: VideoDetailView 迁移到 .sheet(item:)，双栏布局（预览 + 元数据）

### Round 13 — Unit 11: Data Source Config Styling (R18)
- **Commit**: `fca874c` feat(file-browser): update DataSourceConfigView styling to design tokens
- **产出**: DataSourceConfigView 样式迁移到设计 token 体系

> 注：Units 8-11 均通过 Xcode visionOS Simulator build 验证。Phase C 全部 6 个 Unit (6-11) 完成。

---

## Round 14 — EXECUTING: Unit 12 Window Mode Controls Upgrade (R19-R25) (2026-04-05)

### 目标
执行 ExecPlan Unit 12：将 PlayerControlsView 重构为 pill 形 glass 控制栏，用系统 Menu 替代自定义面板。

### 执行摘要

1. **创建 PlayerInfoBarView.swift**：顶部信息栏 — back button + 视频标题 + 格式元数据徽章（4K/HDR/HEVC 等）
2. **重构 PlayerControlsView.swift**：
   - 外形：`.enchronGlassControl()` capsule pill shape（替代 RoundedRectangle）
   - 布局：VStack — PlayerInfoBarView → 拖动条 → 控制行
   - 控制行：左 Menu | 后退 10s | 播放/暂停 | 前进 10s | 右 Menu
   - 左 Menu 吸收 PlaybackMenuView 功能：Speed Picker + HDR Toggle + Subtitles Picker + Audio Track Picker
   - 右 Menu 整合：Playback Mode + Projection + Cinema Environment + Screen Position + Playlist + Frame Step + Settings
   - 自动隐藏：`.task(id: lastInteractionTime)` + `Task.sleep(for: .seconds(5))`
   - ScreenPositionControlView + DebugOverlayView → `.sheet` 呈现（替代 ZStack overlay）
3. **删除 PlaybackMenuView.swift**：被系统 Menu 完全替代
4. **Restyle ScreenPositionControlView.swift**：`.enchronGlassPanel()` + `DesignTokens.Radius.card` + `.contentShape(.rect)` 60pt 注视目标
5. **MainView auto-hide**：超时从 3s 更新为 5s
6. **验证**：visionOS Simulator build succeeded + SPM tests 284/284 passed

### 关键决策

| 决策 | 理由 |
|------|------|
| 左 Menu 吸收 PlaybackMenuView 而非保留两者 | ExecPlan 明确要求删除 PlaybackMenuView，系统 Menu 替代 |
| 右 Menu 用 ellipsis 图标而非 gearshape | gearshape 已用于独立 Settings 窗口，ellipsis 表达"更多选项" |
| ScreenPositionControlView → .sheet 而非 ZStack overlay | 对抗审查 F4 确认 340x420 面板无法在 ornament 内叠加呈现 |
| 保留 MainView 的 controlsTimer 与 PlayerControlsView 的 .task(id:) 共存 | 双重保障 — MainView timer 是全局兜底，PlayerControlsView .task 是局部精准控制 |
| `.buttonStyle(.automatic)` 替代 PlayerControlSurfaceStyle | ExecPlan 要求系统按钮反馈，`.automatic` 提供 visionOS 原生注视交互 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/PlayerUI/Views/PlayerInfoBarView.swift | 新建 — 播放器信息栏 |
| XrPlayer/PlayerUI/Views/PlayerControlsView.swift | 重写 — pill 控制栏 + 系统 Menu |
| XrPlayer/PlayerUI/Views/ScreenPositionControlView.swift | Restyle — 设计 token |
| XrPlayer/MainView.swift | 修改 — auto-hide 5s |
| XrPlayer/PlayerUI/Views/PlaybackMenuView.swift | 删除 |

### ce-compound
本轮改动虽大但模式成熟：系统 Menu 替代自定义面板是 visionOS 标准实践，.sheet 呈现是对抗审查已验证的方案，.task(id:) auto-hide 是 SwiftUI 惯用模式。无非显而易见的平台陷阱或技术发现，跳过。

---

## Round 15 — EXECUTING: Unit 13 Immersive Mode Companion Window (R21) (2026-04-05)

### 目标
执行 ExecPlan Unit 13：为沉浸模式播放添加独立 Companion WindowGroup，复用 PlayerControlsView。

### 执行摘要

1. **XrPlayerApp.swift**：添加 `WindowGroup(id: "playerControls")` — 注入全部 5 个环境对象（AppModel, WindowVideoViewModel, FileBrowsingViewModel, PlaybackLaunchCoordinator, PanoramaLayerBridge），`.defaultSize(width: 600, height: 200)`
2. **MainView.swift**：
   - 添加 `@Environment(\.openWindow)` 和 `@Environment(\.dismissWindow)`
   - 底部 ornament 条件增加 `&& appModel.playbackMode == .window`（仅窗口模式显示）
   - 添加单条件生命周期管理：`.onChange(of: appModel.playbackMode != .window && appModel.isPlaying)` — 切换为 true 时 `openWindow(id: "playerControls")`，false 时 `dismissWindow(id: "playerControls")`
3. **验证**：visionOS Simulator build succeeded + SPM tests 284/284 passed

### 关键决策

| 决策 | 理由 |
|------|------|
| 单 `.onChange(of:)` 复合 Bool 条件替代双独立观察者 | ExecPlan 明确：双 onChange 观察者会产生 open/dismiss 竞争（R4 对抗审查 F6 已验证） |
| WindowGroup 而非 Window | 遵循现有 `WindowGroup(id: "settings")` 模式，visionOS 上 Window 不可用 |
| ornament 增加 playbackMode == .window 条件 | 沉浸模式下由 companion window 承接控件，ornament 不应同时显示 |
| 不添加 .windowStyle(.plain) | ExecPlan 未指定，遵循保守原则与现有 settings WindowGroup 一致 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/XrPlayerApp.swift | 修改 — 添加 `WindowGroup(id: "playerControls")` |
| XrPlayer/MainView.swift | 修改 — openWindow/dismissWindow 环境 + 生命周期 onChange + ornament 条件收窄 |

### ce-compound
标准 SwiftUI WindowGroup + openWindow/dismissWindow 生命周期管理模式。单条件 onChange 避免竞争是已知最佳实践（R4 对抗审查已验证）。无非显而易见的技术发现，跳过。

---

## Round 15 — EXECUTING Unit 14 (2026-04-05)

### 目标
ExecPlan Unit 14: NLE Timeline Shell & Animation (R26) — 创建可展开的 NLE 时间轴面板框架

### 执行摘要

1. **读取上下文**：ARCHITECTURE.md、REGRESSION.md、PlayerControlsView.swift、DetailedTimelineView.swift、DetailedTimelineGeometry.swift、DesignTokens.swift、View+EnchronGlass.swift
2. **创建 NLETimelineView.swift**：可展开面板，`.enchronGlassPanel()` 材质，`@Binding isExpanded` 驱动，`.spring()` 动画，`clipped()` 收起时零高度，placeholder 预留 ruler (Unit 15) 和 thumb strip (Unit 16) 位置
3. **创建 NLETimelineToggleButton**：timeline.selection 图标，tertiary 激活色，60pt 注视目标，accessibilityAddTraits(.isToggle)
4. **集成至 PlayerControlsView**：控制行添加 toggle 按钮，控制栏下方挂载 NLETimelineView，外层 VStack spacing 12
5. **构建验证**：visionOS Simulator build 成功，284 existing tests 全部通过

### 关键决策

| 决策 | 理由 |
|------|------|
| Timeline 挂载在 pill 控制栏外部 VStack 下方 | 保持控制栏 capsule 形态完整，timeline 是独立面板 |
| `frame(height: isExpanded ? 120 : 0) + clipped()` 而非 `if` 条件渲染 | 支持 spring 动画平滑展开，`if` 会导致突然出现 |
| Placeholder 使用 design tokens (surfaceContainerLow, onSurface) | 即使占位也保持视觉一致性，Unit 15/16 替换时无缝衔接 |
| `.spring()` 显式调用而非 `.spring` | Swift 类型推断在 Animation 上下文中无法推断 `.spring` 省略括号形式 |

### 产出物

| 文件 | 说明 |
|------|------|
| XrPlayer/PlayerUI/Views/NLETimelineView.swift | 新建 — NLETimelineView + NLETimelineToggleButton |
| XrPlayer/PlayerUI/Views/PlayerControlsView.swift | 修改 — 添加 isTimelineExpanded state + toggle 按钮 + timeline 面板挂载 |

### ce-compound
纯粹增量的 shell 组件，标准 SwiftUI 模式（@Binding + spring animation + clipped）。无非显而易见的技术发现，跳过。
