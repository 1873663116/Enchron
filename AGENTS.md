# Enchron

Enchron 是最低运行于 visionOS 27 的唯一产品与代码仓库。`Packages/PlaybackCore` 是仓库内独立 Swift Package；它拥有媒体会话、sample、播放生命周期、控制语义、时间线和 renderer graph。Enchron App 拥有来源、产品策略、SwiftUI、RealityKit 和空间呈现，不实现第二套播放核心。

开始工作先读 `ARCHITECTURE.md`、`CONTEXT.md`、`docs/core-spec.md`、`docs/product-requirements.md` 和 `docs/acceptance/verification-system.md`。修改 UI Surface、页面结构或交互结果补读 `docs/ui/README.md`。历史 ADR 只作决策收据，不是当前规格。

前端页面组装所属 feature 的生产组件和 `Modules/DesignSystem` 的通用视觉原语，并绑定产品状态。跨 feature 的视觉变化修改 DesignSystem；feature 行为与组件修改其所有者；页面特有布局修改生产页面。DesignPreview 只陈列这些生产实现，不维护平行页面或产品状态。

架构和产品文档必须使用完整、可直接理解的描述。不要用一个没有定义的形容词或简称代替完整约束；应该直接写清某个 Target 可以依赖哪些 Target，以及禁止哪些相互依赖。首次使用正式技术术语时说明它在 Enchron 中具体指什么；代码标识符可以保留英文，但正文必须说明其职责，不能用一串英文名词代替关系和因果。

根 `Package.swift` 将 `MediaSource`、`MediaLibrary`、`PlaybackFeature`、`PlaybackPresentation` 与 `DesignSystem` 分别编译为五个 Target。这些 Target 之间的依赖保持单向，不允许两个 Target 直接或间接地相互依赖。依赖方向写在 `Package.swift` 中，并由 Swift Package Manager 和编译器检查。需要 Apple 平台能力的 View、Scene 与 PlaybackCore 适配代码仍由 App Target 编译；具体范围见 `ARCHITECTURE.md`。不要通过修改 Xcode Target 的源文件归属、复制源码或新增全局容器绕过这些所有权边界。

产品运行只通过 `PlaybackRuntime` 接入 `Packages/PlaybackCore`。`PlaybackRuntime` 实现 `PlaybackFeature` 定义的窄控制合同，只负责 Core adapter 与核心状态投影；Resume、End、Format、Queue 等产品策略由 `PlaybackFeature` 编译。它不复制 Media Session、seek 调度、timeline、renderer queue 或 Playback Lifecycle。PlaybackCore 只有一条 FFmpeg demux → compressed sample → AVFoundation renderer 管线，失败不会切换到另一套媒体实现。

修改 PlaybackCore 后在 `Packages/PlaybackCore` 运行 `swift test`。不依赖 Apple 平台界面的产品核心先通过根 Package 构建、`EnchronDomainChecks` 与 `Scripts/verification/verify_package_membership.py`；App 模块、SwiftUI 或 RealityKit 变更再通过 `Enchron.xcodeproj` 中对应的测试 Target 和 Scheme 验证。`EnchronDomainChecks` 直接编译真实 Target 和生产规则，不得复制源码或维护测试替身；`verify_package_membership.py` 检查 Package 已拥有的源码不会再被 Enchron App Target 重复编译，并先运行 `verify_design_source_architecture.py` 阻止 DesignTokens、生产组件和 DesignPreview 的源码职责继续混合。Enchron 与 DesignPreview 的构建也会先运行同一项检查。验证按 PlaybackCore 单元验证、visionOS Simulator、Vision Pro 真机的顺序逐层进行，前一层结果不能由后一层代替。
