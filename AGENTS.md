# Enchron

Enchron 是最低运行于 visionOS 27 的唯一产品与代码仓库。`Packages/PlaybackCore` 是仓库内独立 Swift Package；它拥有媒体会话、sample、播放生命周期、控制语义、时间线和 renderer graph。Entry App 拥有来源、产品策略、SwiftUI、RealityKit 和空间呈现，不实现第二套播放核心。

开始工作先读 `ARCHITECTURE.md`、`CONTEXT.md`、`docs/core-spec.md`、`docs/product-requirements.md` 和 `docs/acceptance/verification-system.md`。修改 UI Surface、页面结构或交互结果补读 `docs/ui/README.md`。历史 ADR 只作决策收据，不是当前规格。

前端页面只组装 `XrPlayer/Shared/Components` 的生产组件并绑定产品状态。共享视觉变化修改组件或 `DesignTokens`；页面特有布局修改生产页面。DesignPreview 只陈列生产组件，不维护平行页面或产品状态。

产品运行只通过 `PlaybackRuntime` 接入 `Packages/PlaybackCore`。`PlaybackRuntime` 只负责来源交接、产品策略和核心状态投影，不复制 Media Session、seek 调度、timeline、renderer queue 或 Playback Lifecycle。Apple compressed 等对照路线只存在于验证入口，不进入产品 UI 或失败 fallback。

修改 PlaybackCore 后在 `Packages/PlaybackCore` 运行 `swift test`；修改纯 App 逻辑在仓库根运行 `swift test`；App、SwiftUI 或 RealityKit 变更构建对应 Xcode scheme。验证严格按 L1 → macOS L2 Core → macOS L2 App Adapter → visionOS Simulator → Vision Pro L3 升级。

跨线程的本地 Apple 重型验证：主控使用 `$enchron-validation-controller`，验证线程使用 `$enchron-validation-runner`，缺陷处理线程只提交验证需求；未明确角色的线程不得启动重型命令。Review Deadline 只升级给主控，不得自动中断进程或释放槽位。
