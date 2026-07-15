# Enchron

Enchron 是最低运行于 visionOS 27 的产品 App 与系统组装入口。播放行为由外部 `PlaybackCore` 仓库拥有；本仓库负责 SwiftUI、文件来源、持久化、播放启动协调和 RealityKit 空间呈现，不实现第二套播放核心。

开始工作先读 `ARCHITECTURE.md` 和 `CONTEXT.md`；修改产品能力补读 `docs/product-requirements.md`，修改 UI Surface、页面结构或交互结果补读 `docs/ui/README.md`。历史 ADR 只作决策收据，不是当前规格。

前端页面只组装 `XrPlayer/Shared/Components` 的生产组件并绑定产品状态。修改前先搜索现有组件；共享视觉变化修改组件或 `DesignTokens`，页面特有布局修改生产页面。新组件使用 `DesignTokens`，进入共享组件目录并由 DesignPreview 展示；DesignPreview 只陈列生产组件，不维护平行产品页面。

产品运行只通过 `PlaybackRuntime` 接入相邻 `../PlaybackCore`；不引入备用 route 或第二媒体状态机。fixture adapter 只服务 Preview 和测试。场景内容由相邻 `../Xrplay_scene` 导出，场景仓不拥有播放行为。

纯逻辑运行 `swift test`；App、SwiftUI 或 RealityKit 变更构建对应 Xcode scheme；HDR、空间呈现和真实交互必须按风险升级到 Simulator 或 Vision Pro。PlaybackCore 位于相邻 `../PlaybackCore`。
