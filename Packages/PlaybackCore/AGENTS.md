# 协作准则

PlaybackCore 是 macOS 27 与 visionOS 27 及以上系统共用的音视频 sample-buffer library，不包含产品 App、SwiftUI scene、RealityView 或验收 App。

开始工作先读 `CONTEXT.md`、`ARCHITECTURE.md` 与 `docs/core-spec.md`。当前规格只有 `docs/core-spec.md`；验证规则只有 `docs/acceptance/verification-system.md`。

产品路径只读取容器、解封装音视频并组装保留原始编码的 `CMSampleBuffer`。Apple AVFoundation 拥有解码、HDR / Dolby Vision 解释和渲染；不要重新引入 decoded pixel 路线、产品路线选择、隐藏 fallback 或画面参数模型。

核心向调用方交付播放状态、轨道、诊断事实和 active video renderer。来源授权、renderer consumer、窗口、沉浸空间和产品交互属于 Enchron。

修改后运行 `swift test`。真实媒体、renderer 和设备声明按 `docs/acceptance/verification-system.md` 升级证据；消费方 UI 和空间呈现不作为本仓库完成条件。
