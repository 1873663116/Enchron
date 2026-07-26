---
status: partially superseded by ADR 0015
date: 2026-07-14
---

# Enchron 独占完整产品需求，兄弟仓库只维护各自契约

Enchron 是最终产品 App，也是所有产品依赖的组装入口，因此完整 V1 功能需求只在 Enchron 中定义。作出本决策时，PlaybackCore 仍在兄弟仓库维护媒体库规格，Xrplay_scene 只维护场景资产交付约定。ADR 0015 后，PlaybackCore 规格进入 Enchron 统一的 `docs/`，但仍只定义播放核心行为；本 ADR 关于产品需求唯一所有者和 Xrplay_scene 资产边界的部分继续有效。
