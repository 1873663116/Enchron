---
status: superseded by ADR 0002
---

# 先建立 decoded video sample 主线

PlaybackCore 先复现 Apple 完整示例所采用的 decoded-frame 形态：`AVAssetReader` 输出 decoded frame，经 `VTPixelTransferSession` 转移到满足 renderer 推荐属性的 IOSurface-backed pool，按原始 timing 重建 uncompressed `CMSampleBuffer`，再交给 `AVSampleBufferVideoRenderer` 与 RealityKit。直接把 reader 的 decoded buffer 送入 renderer 不作为参考实现，因为实际验证中 reader 可能给出 renderer 无法呈现的 packed pixel format；仅要求 P010 虽可呈现，仍不足以复现完整的 transfer seam。早期设计曾假定“FFmpeg 只 demux，Apple renderer 负责 decode”，因此把 compressed `CMSampleBuffer` 组装写成核心节点；该假设未经生产 provider 选型便被固化，现已撤回。未来可以选择 mpv、FFmpeg、VideoToolbox 或组合实现，但选择必须基于它能否稳定提供 pixel ownership、timing、color/HDR metadata 与硬件解码证据，不能由旧文档预先决定。

## Consequences

当前活跃规格不再包含 Demux Contract、Demux Envelope 或 compressed sample assembly。若未来重新选择 compressed renderer input，必须新增 ADR，说明它相对 decoded sample seam 的必要性及 metadata、平台呈现和验证代价。
