# Overnight TODOS

## 目标
将 Enchron 迭代至 MVP v1.0 可发布状态：修复最高优先级的 HDR 问题、实现全景自动检测、补齐测试覆盖，不改变现有架构。

## 待办

- [x] **KI-010: 修复 HDR CAEDRMetadata 缺失** — 在 MPVPlayerAdapter 的 applyHDRRuntimeConfiguration() 中追加 CAEDRMetadata 设置逻辑（HDR10→hdr10 metadata, HLG→hlg metadata, SDR→nil），并在 setHDREnabled() 中同步更新。补充对应单元测试（EDR metadata 选择逻辑、HDR 开关同步）。更新 REGRESSION.md 和 QUALITY_SCORE.md。
- [x] **KI-012: 实现全景视频投影类型自动检测** — 将 MPVPlayerAdapter 中硬编码的 .flat 替换为基于 libmpv metadata（stereo3d-in、GSpherical 标签）的启发式检测。补充投影类型检测的数据驱动单元测试。更新 REGRESSION.md。
- [x] **补齐测试覆盖** — 为以下模块补充单元测试：PlaybackMode 决策逻辑、SortCriteria 排序正确性、FileFilter 过滤规则边界情况、GestureDisambiguator 状态机转换。目标将测试覆盖评分从 2 提升到 3。
- [x] **EP-003 收尾** — 检查 EP-003 (时间标签格式化收敛) 的最终状态，若代码已合入则归档 ExecPlan，若未完成则完成剩余步骤。
- [x] **文档同步** — 确保 QUALITY_SCORE.md、REGRESSION.md、known_issues.md 与实际代码状态一致。已修复的 KI 标记为已关闭，评分反映最新状态。

## 约束

- 不改变现有架构和模块边界
- 不引入新的第三方依赖
- 每个 task 独立 commit
- 遵循 CLAUDE.md 中的 Agent 标准动作序列
- 遵循 TESTING.md 双轨验证体系

## 参考资料

- `ARCHITECTURE.md` — 模块职责与边界
- `REGRESSION.md` — 回归集与代码路径映射
- `TESTING.md` — 双轨验证与 HDR/全景测试设计
- `QUALITY_SCORE.md` — 当前质量评分
- `workspace-agents/known_issues.md` — 开放问题与根因分析
- `workspace-agents/Requirements.md` — MVP 功能范围
