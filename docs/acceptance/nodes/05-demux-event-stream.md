# 节点 5：Demux Envelope Stream

节点 5 使用当前 Media Session 的 Track Model Record 启动 FFmpeg packet 读取，并把 provider facts 转换成 PlaybackCore 稳定拥有的 Demux Envelope Stream。

每个 video packet envelope 至少包含 `mediaSessionID`、`trackModelID`、FFmpeg stream mapping、packet bytes、byte format、codec config、PTS、DTS、duration、timebase、keyframe、`streamEpoch` 和 `formatRevision`。packet 明确引用对应的 Track Format Snapshot。

离开 FFmpeg callback 后仍会使用的 bytes 和 metadata 必须被复制或转移所有权。节点 5 不把 FFmpeg 对象交给节点 6，也不提前建立 `CMBlockBuffer`、`CMVideoFormatDescription` 或 `CMSampleBuffer`。

当前 slice 的成功边界是同一个 fixture 的选中 H.264 video track 能产生连续、可追溯且生命周期稳定的 packet envelope。失败后节点 6 不启动。Apple Sample Reference Path 不经过节点 5。
