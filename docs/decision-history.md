# Decision History

## 2026-07-13 — 收敛为双 compressed 路线并完成共享音频与控制

当前活跃路线是 Apple Compressed 对照层与 FFmpeg Compressed 产品主线。FFmpeg Decoded 的可行性比较已经完成并从活跃源码删除；旧三路线证据保留为历史事实。两条视频路线共享 FFmpeg 音频解码、Linear PCM sample、`AVSampleBufferAudioRenderer`、synchronizer、控制状态与 RealityKit presentation。对应决策见 [ADR 0005](adr/0005-two-compressed-routes-and-shared-audio.md)。

## 2026-07-13 — 融合 xr-fork 对象模型，移除 mpv 单路线前提

xr-fork 的 Media Session、Track Model、event epoch、format revision、renderer 与 runtime operation 模型进入 PlaybackCore，但 nodes 3–6 改为 route-neutral Provider records。当时的 App 验证模型现已归档，不再属于核心完成条件。对应历史决策见 [ADR 0004](adr/0004-route-neutral-provider-records-and-macos-l2.md)。

## 2026-07-12 — Apple 参考路线改为 compressed storage samples

Apple 参考路线由 decoded P010 改为 `AVAssetReaderTrackOutput(outputSettings: nil)` 输出的 storage-format compressed sample。它不再经过 pixel transfer，把系统支持格式的解码与 Dolby Vision 解释留给 `AVSampleBufferVideoRenderer`。三条活跃路线变为 Apple Compressed、FFmpeg Compressed 与 FFmpeg Decoded。对应决策见 [ADR 0003](adr/0003-apple-compressed-reference-route.md)。

## 2026-07-12 — 三条显式路线进入同一播放核心

Apple Decoded、FFmpeg Compressed 与 FFmpeg Decoded 同时成为活跃路线。三条路线在 `VideoSampleProvider` 处分流，共用 Renderer Input Coordination、`AVSampleBufferVideoRenderer`、synchronizer 和 RealityKit binding。切换采用 cold switch；能力探测、自动选路与失败回退暂不实现。对应决策见 [ADR 0002](adr/0002-three-explicit-playback-routes.md)。

两条自有路线先直接使用 FFmpeg。FFmpeg Compressed 只解封装，FFmpeg Decoded 通过 VideoToolbox 硬件解码；当前不引入 mpv。

## 2026-07-12 — 先证明 Apple decoded sample 主线

Apple 参考路线固定为 `AVAssetReader` 解码、`VTPixelTransferSession` 转移、uncompressed `CMSampleBuffer` 重建、`AVSampleBufferVideoRenderer` 与 RealityKit 呈现。这项决策建立了 decoded transfer seam，见 [ADR 0001](adr/0001-decoded-video-samples-first.md)；其中排除 compressed input 的限制已由 ADR 0002 取代。
