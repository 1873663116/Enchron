# Enchron

Enchron 是最低运行于 visionOS 27 的唯一产品与代码仓库。`Packages/PlaybackCore` 是仓库内独立 Swift Package；它拥有媒体会话、sample、播放生命周期、控制语义、时间线和 renderer graph。Enchron App 拥有来源、产品策略、SwiftUI、RealityKit 和空间呈现，不实现第二套播放核心。

开始工作先读 `ARCHITECTURE.md`、`CONTEXT.md`、`docs/core-spec.md`、`docs/product-requirements.md` 和 `docs/acceptance/verification-system.md`。修改 UI Surface、页面结构或交互结果补读 `docs/ui/README.md`。历史 ADR 只作决策收据，不是当前规格。

前端页面组装所属 feature 的生产组件和 `Modules/DesignSystem` 的通用视觉原语，并绑定产品状态。跨 feature 的视觉变化修改 DesignSystem；feature 行为与组件修改其所有者；页面特有布局修改生产页面。DesignPreview 只陈列这些生产实现，不维护平行页面或产品状态。

`Modules/MediaLibrary`、`Modules/PlaybackFeature`、`Modules/PlaybackPresentation` 与 `Modules/DesignSystem` 当前是源码所有权边界，尚未全部成为独立编译 target。编译器暂时允许的跨目录访问不自动构成架构许可；新增依赖前按 `ARCHITECTURE.md` 确认所有者，并保持依赖无环。不要用 target membership、复制源码或新增全局容器绕过所有权。

产品运行只通过 `PlaybackRuntime` 接入 `Packages/PlaybackCore`。`PlaybackRuntime` 只负责来源交接、产品策略和核心状态投影，不复制 Media Session、seek 调度、timeline、renderer queue 或 Playback Lifecycle。PlaybackCore 只有一条 FFmpeg demux → compressed sample → AVFoundation renderer 管线，失败不会切换到另一套媒体实现。

修改 PlaybackCore 后在 `Packages/PlaybackCore` 运行 `swift test`；App 模块、SwiftUI 或 RealityKit 变更通过 `Enchron.xcodeproj` 的对应 test target 与 scheme 验证。根目录不维护手工挑选源码的 SwiftPM 测试替身。验证严格按 L1 → macOS L2 Core → macOS L2 App Adapter → visionOS Simulator → Vision Pro L3 升级。

跨任务的本地 Apple 重型验证统一遵循 `docs/acceptance/validation-queue.md`。显式调用通用 Orchestrator 的任务拥有队列观察、Validation Task 唤醒与异常裁决权；被其明确委派的 Validation Task 每次只认领并执行一项验证；实现、缺陷处理和调查任务只有提交验证需求的权限。未获得 Validation Task 职责的任务不启动重型命令。Review Deadline 只触发 Orchestrator 复核，不中断进程或释放槽位。
