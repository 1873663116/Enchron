---
status: accepted
date: 2026-07-14
---

# Enchron 独占完整产品需求，兄弟仓库只维护各自契约

Enchron 是最终产品 App 与 composition root，因此完整 V1 功能需求只在 Enchron 中定义。PlaybackCore 只维护媒体 library spec，Xrplay_scene 只维护场景资产交付 contract；Enchron 可以引用这些契约，但不得复制其内容。EnchronWorkspace 根目录只承担跨仓协作规则与共享工具治理，不拥有产品 spec。这个不对称所有权避免三个仓库各写一份 V1 spec，也避免根目录总 spec 与仓库 spec 形成重叠真相源。
