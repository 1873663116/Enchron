# visionOS 误区清单

如果代码、注释、计划或拟议修复中出现这些假设，暂停并查阅相关 reference。

## 平台与 Scene 模型

- “visionOS SwiftUI 基本就是 iPadOS SwiftUI。”
- “摆放要用 macOS window-management 模式。”
- “视频应该走 full screen。”
- “app 想什么时候移动或调整窗口都可以。”
- “只要 id 不同，就能同时打开多个 immersive space。”
- “调用了 `openImmersiveSpace`，它就一定打开了。”
- “volume 只是更大的窗口。”
- “看起来像 3D 的 card 就是 volume。”
- “`WindowGroup` 只能打开通用窗口，所以视频/library 窗口需要全局 app state，而不是基于值的 scene routing。”
- “旧的固定 volume 指导就是完整的当前平台契约。”
- “UIKit scene bridging 意味着 UIKit 生命周期应该驱动 Enchron 架构。”

证据镜头：先对具名 scene/window 概念做 `DocumentationSearch`，再只把 `app-scenes.md` 用作 Enchron 边界说明。

## UI 与输入

- “Hover 就是 pointer hover。”
- “`onHover` 对 gaze 来说已经足够。”
- “44 pt target 没问题。”
- “`TapGesture` 等价于 `Button`。”
- “这是 productivity app，所以密集 desktop sidebar 没问题。”
- “自定义 glass/material 总是更原生。”
- “显式 accessibility label 总比正确语义 label 更好。”
- “RealityKit `ManipulationComponent` 是普通播放按钮的正确路径。”
- “Apple Pencil 或 spatial accessory 支持可以不查当前可用性和设备支持就接受或拒绝。”

证据镜头：SwiftUI/RealityKit API 事实用 `DocumentationSearch`，human interface 声明用 HIG，Enchron 边界说明用 `spatial-ui.md`。

## 播放与媒体

- “Enchron 用 MPV，所以 AVKit 文档无关。”
- “AVKit 文档证明 MPV 已经行为正确。”
- “AVKit 文档定义了 Enchron 当前 production playback route。”
- “Apple reference playback 是 production fallback。”
- “HDR label 可以跟随用户 toggle，而不是 media/display 证据。”
- “2D Metal layer 自动兼容 immersive rendering。”
- “iOS full-screen playback 是 Vision Pro 播放模型。”
- “visionOS media playback 原样继承 iOS Picture in Picture、background、routing 和 full-screen 行为。”
- “RealityKit video 只意味着 `VideoMaterial`。”
- “`CompositorLayer` 总是意味着 full immersion。”
- “360 video 默认就是把视频画在 sphere 内侧。”
- “inline 嵌入的 3D video 会 stereoscopic 显示。”
- “Spatial Video 就是 side-by-side 3D。”
- “Apple Immersive Video 就是普通高分辨率 180 或 360 video。”
- “`AVPlayerLayer` 或 MPV layer 能显示像素，所以 visionOS media experience 已完成。”
- “只要 frame 能解码，APMP 或 Apple Immersive Video metadata 可以忽略。”
- “High-motion immersive video 可以直接进入 full immersion。”

证据镜头：media、RealityKit、AVKit 和 Metal 事实用 `DocumentationSearch`；`immersive-media-profiles.md`、`playback-media.md` 和 `metal-compositor.md` 只用于匹配的 Enchron 边界。

## RealityKit、ARKit、传感器

- “普通控制需要 hand tracking。”
- “app 可以知道用户正在看哪里。”
- “iOS ARKit 显示代码可以直接移植。”
- “RealityKit entities 可以在 SwiftUI update 中随意重建。”
- “ARKit authorization 可以根据 provider 名称猜。”
- “所有 ARKit provider 都需要 Full Space。”
- “RealityKit `SpatialTrackingSession` 可以绕过 ARKit 隐私要求。”

证据镜头：先用 `DocumentationSearch` 搜索具名 RealityKit/ARKit API 和 availability，再用 `realitykit-spatialscene.md` 或 `arkit-privacy.md` 做 Enchron 边界说明。

## 文件、持久化、性能

- “Photo library 或 local file access 行为像 desktop file access。”
- “LAN 上的 SMB 或 WebDAV 不需要 local-network privacy。”
- “document selection 之后 raw file path 仍然有效。”
- “早期开发时 credentials 可以放在 defaults 里。”
- “UserDefaults 可以当通用数据库。”
- “Simulator verification 足以证明 spatial、video、HDR 或 performance。”
- “Simulator playback 能证明 audio、subtitles、comfort、power 和 immersive transitions。”
- “Debug build performance 已经是足够证据。”

证据镜头：先用 `DocumentationSearch` 搜索 platform API/privacy/performance 事实，再用 `files-network-persistence.md` 或 `performance-debugging.md` 处理匹配的 Enchron 边界。
