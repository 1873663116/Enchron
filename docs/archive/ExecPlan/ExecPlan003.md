# ExecPlan 003 — Phase 4: 设计文档 Gap 分析与补齐

> 创建时间: 2026-04-02T07:00+08:00
> 分支: MinimaxTest
> 状态: DONE（安全项全部完成，待人类决策项已标记）

---

## T4.1 审计结果：设计文档 vs 实现差距

### 方法论
- 逐行对比 `workspace-agents/design_docs/phase1-4`、`Requirements.md`、`product_philosophy.md` 与当前源码
- 直接源码阅读 + codebase-auditor agent + design-docs-reader agent 并行调研

---

### Category A: 文档过时（Phase 3 变更后遗症）

| # | 文件 | 行号 | 问题 | 修复方式 |
|---|------|------|------|---------|
| A1 | ARCHITECTURE.md | 58-59 | 仍引用 `DetailedTimelineView`（已删除） | 移除引用，更新 PlayerUI 描述 |
| A2 | ARCHITECTURE.md | 166 | "二级进度条是核心交互资产" 不变量已失效 | 更新为统一时间轴不变量 |
| A3 | product_philosophy.md | 53 | "例如二级进度条" 引用 | 更新为统一时间轴 |
| A4 | product_philosophy.md | 65-72 | "二级进度条" 整节过时 | 重写为统一时间轴 + 精确时间标签 |
| A5 | QUALITY_SCORE.md | 22 | "二级进度条" 评分条目 | 更名为"统一时间轴" |
| A6 | REGRESSION.md | 26 | `PlayerUI/Domain/*` 映射到已退役 REG-010 | 移除 REG-010 引用 |

### Category B: Settings 页面断连

| # | 问题 | 严重程度 | 修复方式 |
|---|------|---------|---------|
| B1 | `autoResumeEnabled` 是 `@State`，未连接 `UserDefaultsStore`/`ResumePolicy` | 中 | 注入 PreferencesStoring，绑定 ResumePolicy |
| B2 | 缺少播放结束行为设置 | 低 | 待人类决策 UX |
| B3 | 缺少默认倍速设置 | 低 | 待人类决策 UX |

### Category C: UI 功能缺口（域层已实现，UI 未接入）

| # | 功能 | 域层状态 | UI 状态 | 修复方式 |
|---|------|---------|---------|---------|
| C1 | 文件排序选择器 | SortCriteria + 三个 adapter 全部实现 | FileBrowserView 无排序 UI | 添加 Menu/Picker |
| C2 | 播放进度恢复提示 | ProgressStoring + ResumePolicy 已实现 | 无恢复弹窗 | 需 UX 设计，标记待人类决策 |
| C3 | 文件列表进度指示 | ProgressStoring 可查 | FolderListView 无进度条 | 需 UX 设计，标记待人类决策 |
| C4 | 虚拟屏幕位置控件 | ScreenPositionControlView 存在 + SavedScreenPosition 域层完备 | 未接入播放器 UI，未连接持久化 | 沉浸场景功能(v0.4)，标记待人类决策 |
| C5 | X 轴旋转控件 | SavedScreenPosition.viewAngleDegrees 存在 | ScreenPositionControlView 无旋转 Slider | 沉浸场景功能(v0.4)，标记待人类决策 |

### Category D: 播放速度选项缺失

| # | 问题 | 修复方式 |
|---|------|---------|
| D1 | Requirements 列 10 档倍速（0.25~5.0），实现仅 6 档（0.5~2.0） | 添加 0.25, 1.75, 3.0, 5.0 到 PlaybackSpeed.allCases |

### Category E: 未实现功能（设计文档有，当前未实现）

| # | 功能 | 设计文档出处 | 当前状态 | 优先级 |
|---|------|------------|---------|--------|
| E1 | Photo Library 源 | Requirements 2.1 | SourceType.photoLibrary 枚举存在，无 PHPicker 实现 | 低（非 MVP 核心） |
| E2 | 播放结束后自动下一集 | Requirements 2.4 | onPlaybackEnded callback 存在，无 UI 行为 | 中 |
| E3 | 缓存清理策略（5天过期） | Requirements 2.4 | 未实现 | 低 |
| E4 | 网络中断重连机制 | Requirements 2.4 | 未实现 | 中 |

---

## T4.2 实施计划（本轮可安全执行的项目）

### Unit 1: Category A — 文档更新（A1-A6）
**风险**: 零（纯文档）
**文件**: ARCHITECTURE.md, product_philosophy.md, QUALITY_SCORE.md, REGRESSION.md

### Unit 2: Category D — 播放速度补全（D1）
**风险**: 极低（纯值添加）
**文件**: PlaybackCore/Domain/ValueObjects/PlaybackSpeed.swift

### Unit 3: Category B1 — Settings 接入持久化
**风险**: 低（接线，不改架构）
**文件**: Settings/Views/SettingsView.swift, App/XrPlayerApp.swift

### Unit 4: Category C1 — 文件排序 UI
**风险**: 低（UI 添加，域层已完备）
**文件**: FileBrowsing/Views/FileBrowserView.swift, FileBrowsing/ViewModels/FileBrowsingViewModel.swift

### 标记为"待人类决策"
- C2: 播放进度恢复提示 UX
- C3: 文件列表进度指示 UX
- C4/C5: 虚拟屏幕位置控件（v0.4 沉浸场景）
- E1-E4: 新功能开发

---

## 执行记录

### Unit 1: Category A — 文档更新 ✅
- ARCHITECTURE.md: 移除 DetailedTimelineView 引用，更新 PlayerUI 描述为 VideoDetailView + 统一时间轴
- ARCHITECTURE.md: 不变量从"二级进度条"更新为"统一时间轴（含精确时间标签和逐帧步进）"
- product_philosophy.md: "例如二级进度条"→"例如统一时间轴的精确时间标签、逐帧步进"
- product_philosophy.md: 重写"二级进度条"整节为"统一时间轴"
- QUALITY_SCORE.md: "二级进度条"→"统一时间轴"
- REGRESSION.md: 移除已退役 REG-010 引用

### Unit 2: Category D — 播放速度补全 ✅
- PlaybackSpeed.swift: 添加 0.25/0.75/1.25/1.75/3.0/5.0 四个预设，allCases 从 6 档扩展至 10 档
- `swift build` → Build complete ✅
- `swift test` → 205 tests, 0 failures ✅

### Unit 3: Category B1 — Settings 接入持久化 ✅
- SettingsView.swift: 完整重写，注入 PreferencesStoring，绑定 ResumePolicy 三态 Picker
- ResumePolicy.swift: 添加 Hashable 遵循（SwiftUI Picker 要求）
- `swift build` → Build complete ✅
- `swift test` → 205 tests, 0 failures ✅

### Unit 4: Category C1 — 文件排序 UI ✅
- FileBrowsingViewModel.swift: 添加 sortCriteria 属性 + applySortToFiles() 方法 + loadFiles 末尾调用
- FileBrowserView.swift: 工具栏添加排序 Menu（Name/Date Modified/Size，含方向指示）
- `swift build` → Build complete ✅
- `swift test` → 205 tests, 0 failures ✅

### 待人类决策项（未执行）
- C2: 播放进度恢复提示 UX
- C3: 文件列表进度指示 UX
- C4/C5: 虚拟屏幕位置控件（v0.4）
- E1-E4: Photo Library / 自动下一集 / 缓存清理 / 网络重连
