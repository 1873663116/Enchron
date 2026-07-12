# 节点 3：Container Open Snapshot

节点 3 让 FFmpeg demux adapter 使用当前 Media Session 的 demux-openable locator 打开媒体容器，并记录此时可观察的容器与轨道事实。它不读取 packet，不选择 Track Model，也不建立 CoreMedia sample。

输入是当前 Media Session 和 Media Source Record。输出是 Container Open Snapshot，至少包含 `mediaSessionID`、provider、container format、duration 状态和原始 video track facts。

当前 slice 要求同一个 H.264 video-only fixture 能被真实 FFmpeg adapter 打开，snapshot 只记录一条可识别 video track，并能追溯到当前 Media Source Record。打开失败必须形成绑定同一 Media Session 的失败记录，节点 4 不启动。

Apple Sample Reference Path 不经过节点 3，也不产生 Container Open Snapshot。
