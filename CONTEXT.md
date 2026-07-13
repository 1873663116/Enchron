# Enchron 术语

**PlaybackCore**：相邻独立仓库提供的音视频 sample-buffer 播放模块。它拥有 Media Session、播放控制、轨道、时间线、renderer 和播放诊断；Enchron 不重新定义这些概念。

**Playback App Adapter**：Enchron 内连接 PlaybackCore 与产品界面的 adapter。它持有产品会话所需的来源授权，把核心状态投影给 SwiftUI，并把 video renderer 绑定到 RealityKit entity。

**PlaybackLaunchCoordinator**：本仓唯一播放启动协调入口。它把用户选择、恢复位置、窗口和持久化动作组织成一次产品播放启动，但不实现媒体播放。

**PlaybackMode**：产品选择的视频呈现方式，当前包括 Window、沉浸环境中的固定屏幕和 Panorama。它不是播放路线。

**Environment**：由 Xrplay_scene 创作并导出的沉浸观影环境。它属于空间内容，不拥有 video renderer 或播放控制。

**Presentation Surface**：承载 renderer-backed video entity 的产品位置，例如窗口、固定屏幕或全景呈现。

**Media Profile**：供产品决策使用的 projection、stereo layout、HDR type 和尺寸等媒体事实。检测事实来自 PlaybackCore；用户覆盖和有效呈现结果属于 Enchron。

**Browsing Media File**：文件浏览中的条目，包含名称、大小、修改时间和来源身份。

**Playback Launch Request**：FileBrowsing 交给 PlaybackLaunchCoordinator 的产品请求，包含来源 locator、显示名称、持久化身份和可选预取事实。

**Data Source**：本地文件系统、Photos、SMB、WebDAV 或未来来源。

**RealityKitContent**：Xrplay_scene 导出的版本化场景产物，由 Enchron 的 SpatialScene 消费。

**FakeApp**：使用假目录和假播放状态验证最终 SwiftUI 产品界面的临时开发形态。它不是第二个播放器，也不能作为真实播放证据。
