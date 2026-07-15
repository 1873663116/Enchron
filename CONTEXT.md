# Enchron 术语

**Enchron**：visionOS 产品 App 与 composition root。它拥有产品状态、界面、来源、持久化和 Apple 平台呈现，不拥有媒体核心。

**PlaybackCore**：相邻仓库中的唯一播放核心。它读取容器、解封装并组装保留原始编码的 `CMSampleBuffer`，把解码、HDR / Dolby Vision 解释与渲染交给 AVFoundation。

**PlaybackRuntime**：Enchron 中连接 SwiftUI、RealityKit 与 PlaybackCore 的薄 adapter。它不复制 PlaybackCore 状态机。

**Media Library**：Enchron 拥有的虚拟媒体目录，只保存用户分类、媒体引用和播放相关状态，不变更媒体源。
_Avoid_：App 文件目录、本地文件系统

**Library Folder**：Media Library 中由用户创建的分类容器，不对应系统文件夹，也不继承文件系统的路径与删除语义。
_Avoid_：本地文件夹、Documents 文件夹

**Media Reference**：Media Library 中指向原始媒体的持久引用；它可以解析为系统文件、Photos 资源或网络来源，删除引用不会删除原始媒体。
_Avoid_：导入文件、文件副本

**Add to Library**：在 Media Library 中创建 Media Reference，不复制、移动或修改原始媒体。
_Avoid_：导入

**Playback Presentation**：视频当前稳定的呈现位置，只包括 Window、Docked 和 Panorama。

**Environment Context**：当前没有观影场景，或某个观影场景已经打开。它独立于 Playback Presentation；打开场景不等于 Dock。

**Docked**：Enchron 把 PlaybackCore 的同一个 renderer 通过 `VideoPlayerComponent` 放入 RCP 场景中的产品呈现。它复用 Apple RealityKit 视频组件，但不是 `AVPlayerViewController` 的系统 Docking。

**Panorama**：`VideoPlayerComponent` 的 Apple immersive viewing behavior。projection 和 stereo layout 来自 PlaybackCore 媒体事实或用户显式覆盖。

**Presentation Transition**：从一个稳定呈现到另一个稳定呈现的暂态。目标 surface 与 renderer binding 成功后提交，失败则回滚。

**UI Assembly**：生产页面将产品状态和动作绑定到共享 SwiftUI 组件。组件与 Design Token 是 UI 视觉真相，页面不现场仿写已有组件。

**DesignPreview**：生产组件的代码化陈列入口，不是 Fake App，也不拥有产品导航或业务状态。

**Product Runtime Observability**：`Logger` / OSLog 与 signpost 产生可关联运行事实；Xcode、LLDB、Console、Instruments、XCTest 和 XCUIAutomation 负责实时观察、调试与验证。`.xcresult` 是运行后的测试证据，不是实时调试通道。
