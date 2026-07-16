---
status: partially superseded by ADR 0015
date: 2026-07-14
---

# Enchron 独占完整产品需求，兄弟仓库只维护各自契约

Enchron 是最终产品 App 与 composition root，因此完整 V1 功能需求只在 Enchron 中定义。作出本决策时，PlaybackCore 仍在兄弟仓库维护媒体 library spec，Xrplay_scene 只维护场景资产交付 contract。ADR 0015 后，PlaybackCore Spec 进入 Enchron 统一 `docs/`，但仍只定义核心行为；本 ADR 关于产品需求唯一所有者和 Xrplay_scene 资产边界的部分继续有效。
