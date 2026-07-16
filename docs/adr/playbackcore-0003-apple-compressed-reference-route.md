---
status: superseded in route count by ADR 0005
---

# Apple 参考路线改为 storage-format compressed sample

Apple 参考路线使用 `AVAssetReaderTrackOutput(track: outputSettings: nil)` 读取 storage-format compressed `CMSampleBuffer`，直接进入共同的 Renderer Input Coordination。该路线不再提前解码，不经过 `VTPixelTransferSession`，把 codec decode、Dolby Vision metadata 解释与呈现交给 `AVSampleBufferVideoRenderer`。

三条活跃路线由此变为 Apple Compressed、FFmpeg Compressed 与 FFmpeg Decoded。它们仍只在 `VideoSampleProvider` 处分流，共用 renderer、synchronizer、RealityKit binding 和运行控制。Apple Decoded 不再是活跃路线；其历史验证结论保留在 ADR 0001 与决策历史中。

## Consequences

Apple Compressed 的 L1 证据必须记录 media subtype 与 sample-description atoms。Dolby Vision Profile 5 需要保留 `dvh1 + dvcC`；Profile 8.1 与 8.4 需要保留当前 fixture 的 `hvc1 + dvvC`。macOS probe 证明格式契约、renderer rendering 与 displayed pixel buffer；Vision Pro 继续承担最终 HDR 观感验收。
