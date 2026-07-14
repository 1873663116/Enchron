# 协作准则

PlaybackCore 是 macOS 与 visionOS 共用的音视频 sample-buffer library，不包含产品 App、SwiftUI scene、RealityView 或验收 App。

开始工作先读 CONTEXT.md、README.md 与 ARCHITECTURE.md；当前行为规格只在 docs/core-spec.md，验证规则只在 docs/acceptance/verification-system.md。

两条显式视频路线当前仍是 Apple Compressed 与 FFmpeg Compressed。它们只在内部 VideoSampleProvider seam 分流，共用音频、Renderer Input Coordination、renderer graph、时间线和控制；不实现自动选路或隐藏 fallback。

核心只向调用方交付播放状态、诊断事实和 active video renderer。来源授权、renderer consumer、窗口、沉浸空间和产品交互属于调用方。不要把任何客户端状态机或 UI 约束写回核心。

修改后运行 swift test。真实显示、空间呈现和产品交互由消费仓库自行验证，不能作为核心完成条件。
