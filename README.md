# Enchron

Enchron 是 visionOS 产品 App。它负责文件来源、SwiftUI 前端、产品状态、持久化与空间呈现；相邻的 `../PlaybackCore` 是唯一播放核心，`../Xrplay_scene` 交付 Reality Composer Pro 场景资产。

当前产品规格在 `docs/product-requirements.md`，UI 结构在 `docs/ui/README.md`，模块边界在 `ARCHITECTURE.md`。页面和组件的精确内容以生产 Swift 代码为准。

构建 Xcode scheme `XrPlayer` 运行产品；`DesignPreview` 只展示生产组件，不维护第二套 App。仓库不再包含 mpv 播放路线、Metal 视频桥或内置备用播放核心。
