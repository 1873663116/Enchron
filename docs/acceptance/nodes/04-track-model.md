# 节点 4：Track Model

节点 4 把 Container Open Snapshot 中的 FFmpeg video track facts 转换为 PlaybackCore 自己的 Track Model Record。当前 slice 只支持一条被选中的 H.264 video track。

Track Model Record 至少包含 `mediaSessionID`、稳定 `trackModelID`、FFmpeg stream mapping、media type、codec、coded dimensions、timebase、format hints、selected 和 consumer。

节点 4 不读取 packet、不组装 sample，也不建立 renderer。成功后节点 5 只能为这条被选中的 video track 建立 Demux Envelope Stream。Apple Sample Reference Path 不经过节点 4，也不伪造 Track Model。
