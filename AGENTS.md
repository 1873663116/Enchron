# Enchron

Enchron 是 visionOS 产品 App 与系统组装入口。播放行为由外部 `PlaybackCore` 仓库拥有；本仓库负责 SwiftUI、文件来源、持久化、播放启动协调和 RealityKit 空间呈现，不实现第二套播放核心。

开始工作先读 `ARCHITECTURE.md` 和 `CONTEXT.md`；修改用户行为再读 `docs/use_cases.md`，修改难以回退的本仓决策再读 `docs/adr/`。历史 ADR 只作决策收据，不是当前规格。

`XrPlayer/PlaybackCore` 与 mpv 代码是待删除的旧实现，不能扩展；在外部 PlaybackCore 接入完成前，只允许维护现有 FakeApp 前端验证面。场景内容由相邻 `../Xrplay_scene` 导出，场景仓不拥有播放行为。

纯逻辑运行 `swift test`；App、SwiftUI 或 RealityKit 变更构建对应 Xcode scheme；HDR、空间呈现和真实交互必须按风险升级到 Simulator 或 Vision Pro。PlaybackCore 位于相邻 `../PlaybackCore`。
