---
status: superseded by ADR 0017
---

# 以共同 renderer seam 承载三条显式路线

PlaybackCore 同时实现 Apple Decoded、FFmpeg Compressed 和 FFmpeg Decoded。Apple Decoded 作为系统参考路线；FFmpeg Compressed 验证“自有解封装、系统解码与呈现”；FFmpeg Decoded 验证“自有解封装、VideoToolbox 硬件解码、系统呈现”。两条 FFmpeg 路线先直接使用 FFmpeg，不引入 mpv。

三条路线只在 `VideoSampleProvider` 与 renderer input kind 处分流。decoded input 共享 pixel transfer 和 uncompressed sample 重建；此后所有路线共享 Renderer Input Coordination、renderer、synchronizer、RealityKit binding 和控制状态。这样比较的是输入路线本身，而不是三套不同播放器的行为。

路线切换采用 cold switch。当前明确不实现能力探测、自动优先级和失败回退，避免隐藏实际使用路线，也不提前固化 Dolby Vision 等格式的产品策略。

## Consequences

Renderer Input Coordination 必须同时接受 compressed 与 uncompressed `CMSampleBuffer`。诊断记录必须包含 requested route、selected route、input kind 与实际 codec。macOS 承担三条路线的播放成功验证，Vision Pro 承担三条路线的可见播放和画面观感验收。

ADR 0001 建立的 Apple decoded transfer seam 继续保留，但“compressed renderer input 不属于活跃规格”的限制被本决策取代。
