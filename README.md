# Enchron

Enchron 是最低运行于 visionOS 27 的媒体产品。仓库同时包含 Entry App、播放核心 Swift Package、RealityKit 内容、测试和统一文档。

```text
XrPlayer -> PlaybackRuntime -> Packages/PlaybackCore -> AVFoundation -> RealityKit
```

从 `ARCHITECTURE.md` 和 `CONTEXT.md` 开始。核心行为由 `docs/core-spec.md` 定义，产品能力由 `docs/product-requirements.md` 定义，完整节点和验证门槛位于 `docs/acceptance/`。

构建 `XrPlayer` scheme 运行 visionOS 产品；`EnchronMacOS` 是同一播放应用控制的 macOS L2 入口；`DesignPreview` 只展示生产组件。首次构建 PlaybackCore 前运行 `Packages/PlaybackCore/script/build_ffmpeg.sh` 生成本地 FFmpeg XCFramework。
