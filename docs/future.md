# 未来工作

这里保存不属于当前 video-only core 完成门的方向。

## Subtitle 与 chapters

xr-fork 已定义 subtitle renderable entity 和 chapter state 的目标模型，也留下旧实现可行性证据。PlaybackCore 当前已经实现 FFmpeg 音频解码、Linear PCM sample、共享 synchronizer 与音轨选择；subtitle 和 chapters 仍需重新设计 Provider seam，旧 mpv `sid` 和 subtitle callback 不直接迁移。

## PanoramaScannerLab

视觉 scanner 仍是独立实验工具。它可以使用 FFmpeg 做实验 FrameSampler，但 classifier 与生产 sampler 必须解耦。当前没有明确 metadata 时使用安全默认，不让 scanner 阻塞播放核心。

## Environment lighting 与 thumbnails

两者都需要 decoded pixel source。当前 compressed route 的 renderer 内部像素不可直接获取；未来需要明确旁路解码、成本、线程和与主播放 timeline 的关系，不能假装从 `AVPlayerItemVideoOutput` 取得本管线帧。

## 自动路线选择

能力探测、路线优先级和失败 fallback 只有在两条显式路线各自具备稳定能力矩阵、错误分类和 evidence 后才进入设计。任何自动策略都必须在 Debug Snapshot 中暴露 requested route、attempted routes、selected route 和 fallback reason。
