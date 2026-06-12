# 0002 — 修宪：收窄宪法第 2 条 /visionos-platform 的触发面

- Status: 已采纳
- Date: 2026-06-12

## 背景

宪法第 2 条原文为「需判断以及编码时，执行 /visionos-platform」。这是 visionOS 项目，该措辞等于每次编码都无条件先跑一遍 skill，把判断指南变成了仪式。与之矛盾的是：

- SKILL.md 自身写明逃生口（小、可逆、有支撑的任务保持轻量）；
- CLAUDE.md「验证跟着风险走」一节的触发措辞是「触及任何 visionOS 表面……先用 skill 校验直觉」——按风险触发，而非无条件。

宪法层「总是」与 skill 层「按需」自相矛盾，路由层的强制覆盖了 skill 内的全部克制条款。

## 决策

宪法第 2 条改为：「触及 visionOS 表面或对平台行为不确定时，执行 /visionos-platform（触发面见『验证跟着风险走』）」。触发语义与「验证跟着风险走」一节统一，该节的表面清单（窗口、volume、`ImmersiveSpace`、RealityKit、Metal、AVKit、scene 生命周期、空间交互、隐私、性能）是触发面的唯一定义。

同轮配套（非修宪，记录在此供追溯）：SKILL.md 瘦身约 1/3——删 query seeds 名词清单（语义搜索下 agent 自组 query）、模块清单改指 `ARCHITECTURE.md`、证据阶梯改指 `docs/quality_gates.md` 仅保留 visionOS 增量条款。实证依据：官方 Xcode MCP `DocumentationSearch` 工具自带说明仅一句话，skill 的方法论骨架（平台过滤、availability 盲区、SDK probe）经实测确为工具盲区，保留；冗余部分为与其他活法律文档的重复副本。

## 考虑过的替代方案

- **保持「需判断以及编码时」不动，靠 skill 内逃生口自我调节**：路由层指令优先级高于 skill 内文，逃生口实际不生效。否决。
- **彻底取消宪法层触发，全靠 skill description 自动匹配**：description 匹配不可靠，平台陷阱（如 `CustomMaterial` 在 visionOS 不可用但文档搜索无标注）漏触发代价高。否决；保留按风险的显式触发。

## 后果

- 小、可逆、不触 visionOS 表面的编码工作不再强制过 skill；触发面收口到一处定义，消除两节措辞漂移的可能。
- SKILL.md 与 CLAUDE.md / ARCHITECTURE.md / quality_gates.md 之间不再有实质内容副本，只剩指针。
