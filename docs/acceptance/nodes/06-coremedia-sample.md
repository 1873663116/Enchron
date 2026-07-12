# 节点 6：CoreMedia Sample Assembly

节点 6 把 H.264 Demux Envelope 转换为 compressed video `CMSampleBuffer`。它不打开容器、不从 FFmpeg 读取 packet，也不把 sample enqueue 给 renderer。

输入必须能追溯到当前 Media Session、Track Model、源 Demux Envelope、`streamEpoch` 和 `formatRevision`，并提供完整 access unit、byte format、SPS/PPS 或等价 codec config、PTS、DTS、duration、timebase 和 keyframe 事实。

组装过程建立或复用 `CMVideoFormatDescription`，在需要时把 Annex B payload 转换为 length-prefixed payload，建立稳定拥有 packet bytes 的 `CMBlockBuffer`，创建 `CMSampleTimingInfo` 和 compressed `CMSampleBuffer`，并设置 sync 相关 attachment。

输出 sample provenance 保留 `trackModelID`、`sourceEnvelopeID`、`streamEpoch` 和 `formatRevision`。PTS 和 DTS 不能因为当前 fixture 简单而合并成一个时间字段。

当前 slice 的成功边界是同一个 fixture 的连续 H.264 packet 能形成 ready compressed sample stream，规范化 sample facts 可记录并满足节点 7 的输入契约。任何组装失败都必须绑定源 envelope，不能交给 renderer 猜测修复。

Apple Sample Reference Path 不经过节点 6；它提供的是参考 sample，不是节点 6 成功证据。
