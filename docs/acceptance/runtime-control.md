# Runtime control

运行控制只作用于当前 Media Session：play、pause、seek、setRate、setVolume、setMuted、selectAudioTrack、reopen、cold route switch 与 close。

无 active session、cleanup 未完成、目标 session 已过期或互斥操作进行中时，命令必须显式拒绝并记录原因。seek 可以取代更早的 seek；被取代操作不得提交最终状态。

close 是 barrier：Provider cancel、delivery stop、synchronizer rate reset、audio/video flush、binding invalidation 和 slot release 完成前，新 open 必须等待。close 后的旧 callback 只能作为 stale record。

本文件不定义 UI、command inbox、窗口或 presentation command；这些属于调用方。
