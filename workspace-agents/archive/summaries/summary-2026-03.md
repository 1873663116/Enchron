# 增量总结 — 2026 年 3 月

更新时间：2026-03-14


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
| KI-007 | 首播黑屏 ~5 秒 + 首次打开"i"面板卡顿 | 开放 |
| KI-010 | HDR 识别准确但输出仍为 SDR Preview | 开放（依赖 v0.4 HDR 管线） |
| KI-011 | SMB 子文件夹无法展开 | 开放 |


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
