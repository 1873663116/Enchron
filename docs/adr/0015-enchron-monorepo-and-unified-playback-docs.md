---
status: accepted
date: 2026-07-16
---

# Enchron 成为产品单仓并统一播放文档

PlaybackCore 与 Enchron 实际共享同一产品周期，新 AVFoundation API、核心调度、Entry App 接入和节点验证需要原子演进；继续维持独立 GitHub 仓库和两套 Architecture/Context/验收目录，已经造成 Verify App 已证明的控制与接入在迁移中断裂。Enchron 因此以保留历史的方式把 PlaybackCore 导入 `Packages/PlaybackCore`，成为唯一产品与代码仓库；PlaybackCore 继续保持独立 Swift Package、核心行为合同和测试边界，但不再形成第二个产品或文档上下文。

Enchron 根 `ARCHITECTURE.md` 与 `CONTEXT.md` 是唯一系统边界和术语来源；`docs/core-spec.md` 定义核心行为，`docs/product-requirements.md` 定义产品能力，节点 01–09、验证规则和证据统一位于 `docs/acceptance/`。Window、Docked、Panorama 等 Playback Presentation 从 Core Spec 迁入产品层；节点作为完整系统链不按实现模块拆分。独立 PlaybackCore GitHub 仓库在历史进入 Enchron 且目标仓验证通过后归档，不删除历史。

本决策取代 workspace 中“PlaybackCore 必须是受保护兄弟仓库”、ADR 0010 中“外部 PlaybackCore”以及 ADR 0011 中“核心 Spec 位于兄弟仓库”的部分；Xrplay_scene 继续保持独立资产仓库。
