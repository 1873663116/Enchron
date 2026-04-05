# 增量总结 — 2026 年 3 月

更新时间：2026-03-14

补记：2026-03-15、2026-03-17


## 已解决问题（RES-001 ~ RES-007）

来源：`archive/issues archive/known_issues_2026-03-10_resolved.md`

| 编号 | 问题 | 修复要点 | 关联回归项 |
|------|------|---------|-----------|
| RES-001 | 播放启动路径分叉，失败时残留"正在播放"状态 | 所有启动路径统一经过 PlaybackLaunchCoordinator；失败回滚 | REG-040 |
| RES-002 | SMB 仍要求手填 share 名 | 改为 IP 输入 + 连接后枚举 share 选择 | REG-020 |
| RES-003 | Persistence adapter 是 fatalError("TODO") | UserDefaultsStore、SwiftDataStore 最小可用实现 | REG-030, REG-031 |
| RES-004 | MediaFolder.dataSourceID 不稳定 | Local/WebDAV/SMB 三条路径透传稳定数据源 ID | — |
| RES-005 | SMB 凭证 key 因 share 变化而漂移 | 改为 host 级稳定键 | REG-021 |
| RES-006 | MediaFolder.id 每次刷新都变 | 改为 dataSourceID + path 派生的稳定身份 | — |
| RES-007 | HDR 识别误报 + 输出模式文案不诚实 | 收紧识别逻辑；hdrOutputMode 仅在已验证 HDR surface 时报 passthroughHDR | — |


## 仍开放问题

| 编号 | 问题 | 状态 |
|------|------|------|
| KI-007 | 首次构建后首启首播的一次性冷卡顿 | 开放，已重新定界 |
| KI-010 | Window 模式 HDR 缺少 CAEDRMetadata | 当前最高优先级，根因已修正（2026-03-17） |


## 文档体系重构

2026-03-14 完成文档工程体系重构（docs-v2 分支），新增/增强以下文件：

- **AGENTS.md**：重写为 ~100 行路由表
- **ARCHITECTURE.md**：从 design_docs 提炼的架构速览 + Architecture Invariants
- **PLANS.md**：OpenAI Exec Plans cookbook 的严格本地化
- **TESTING.md**：双轨验证体系（agent 自检 + 人类真机验证）
- **QUALITY_SCORE.md**：13 个领域的 0-5 评分
- **REGRESSION.md**：15 条初始回归项 + 代码路径映射索引
- **known_issues.md**：KI-007/010/011 补充统一模板字段
- **design_docs/README.md**：降级为参考归档说明


## 本月关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 文档中心位置 | 沿用 workspace-agents/，不新建 docs/ | 减少迁移成本，现有引用不需要全量修改 |
| Exec Plan 模板 | 嵌入 PLANS.md 本身，不单独建模板文件 | 每个 agent 读 PLANS.md 后自行按骨架写 ExecPlan |
| design_docs 处置 | 降级为参考归档，新增 README.md 说明 | 保留历史价值，主要依据迁移到 ARCHITECTURE.md |
| 回归集设计 | 代码路径映射索引 + 双轨验证 | 解决"修一处坏一处"的核心痛点 |


## 2026-03-15 增量收口

- EP-001 `修复 KI-007 KI-010 KI-011` 已归档到 [EP-001-known-issues-remediation.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/exec-plans/EP-001-known-issues-remediation.md)。
- 本轮真机结果确认：KI-011 已关闭；KI-007 中的 `i` 面板容器问题已关闭；KI-010 仍开放，并上升为当前第一优先级。
- 新建 EP-002 `修复 HDR 真实输出并解释首启首播一次性冷卡顿`，作为后续执行入口。
- 对 KI-007 的理解已更新：问题不再笼统定义为”首播慢”，而是”首次构建后第一次真实进入 native GPU 播放路径时的一次性冷建链成本”。


## 2026-03-17 文档清理与根因修正

### EP-002 废止

EP-002 `修复 HDR 真实输出并解释首启首播一次性冷卡顿` 标记为 superseded 并归档。原因：该计划基于错误的根因分析——将 HDR 问题归因于 `verified_surface=false` 和 MoltenVK 线程违规，实际根因是缺少 `CAEDRMetadata`。

归档位置：`archive/exec-plans/EP-002-hdr-output-and-cold-start.md`

### KI-010 根因修正

KI-010 的描述从”HDR 识别准确但真实输出与切换仍失败”修正为”Window 模式 HDR 缺少 CAEDRMetadata，系统无法做精确 EDR tone mapping”。之前的根因 A~D（verified_surface、MoltenVK 线程、HDR surface 未建立）全部废止。

真正的根因：libmpv gpu-next 路径已正确渲染 HDR，Metal Layer 已配置 rgba16Float + wantsExtendedDynamicRangeContent，但从未设置 `CAEDRMetadata`，导致 Apple 显示系统无法做精确的 system-level EDR tone mapping。

### 文档批量更新

| 文档 | 变更内容 |
|------|---------|
| PLANS.md | EP-002 状态改为 superseded；新增 superseded 状态类型 |
| known_issues.md | KI-010 完全重写根因分析 |
| QUALITY_SCORE.md | HDR 可信度评分描述修正；SMB 评分从 2 提升至 3（KI-011 已修复）；冷启动描述修正 |
| TESTING.md | 新增 HDR 测试设计和全景测试设计章节；更新测试文件描述 |
| REGRESSION.md | 新增 REG-060~063（HDR EDR Metadata）和 REG-070~071（全景渲染）；更新代码路径映射索引 |
| Tests/README.md | 修复断链的文档引用；更新测试文件清单 |

### 测试清理

- CoreLogicTests.swift 中与 V02Tests.swift 重复的 PlaybackSpeed/Position 测试已移除
- V02/V03/V04 文件名保留（重命名风险大于收益），但 Tests/README.md 和 TESTING.md 中已补充清晰的主题描述
