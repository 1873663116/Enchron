# PlaybackCore module

PlaybackCore 是 Enchron 仓库内可独立构建和测试的播放模块，不是独立产品或文档上下文。工作前读取仓库根 `ARCHITECTURE.md`、`CONTEXT.md`、`docs/core-spec.md` 与 `docs/acceptance/verification-system.md`。

模块只读取容器、建立 Media Session、组装 sample、协调 AVFoundation renderer graph，并发布播放事实。来源长期授权、产品策略、SwiftUI、RealityKit consumer、窗口和空间呈现属于 Enchron App。

产品只有一条 FFmpeg demux compressed-sample 路径。不要引入 decoded pixel 产品路线、隐藏 fallback、第二时间线或产品 presentation 状态。修改后运行 `swift test`；真实 renderer 与设备声明继续服从仓库统一验证门槛。
