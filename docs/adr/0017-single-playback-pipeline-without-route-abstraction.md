# ADR 0017：单一播放管线不保留 Route 抽象

状态：Accepted

## 背景

PlaybackCore 曾并行维护 Apple 与 FFmpeg provider，用于比较不同的 sample 生产方式。随着产品播放收敛到 FFmpeg demux → compressed sample → AVFoundation renderer，Apple provider、Route 选择器、切换操作和按 Route 分叉的诊断只剩历史验证用途。继续保留单值 Route 会让 API、状态、测试与证据模型表达一个已经不存在的产品选择。

## 决策

PlaybackCore 只维护一条播放管线：FFmpeg 负责 container 与 compressed sample，AVFoundation 负责解码、同步和 renderer，RealityKit 负责消费当前 renderer。

- 删除 Apple compressed video/audio provider。
- 删除 `PlaybackRoute`、显式 Route open、Route switch 与 UI Route selector。
- Media Session、operation、sample、binding 和 debug records 不再携带 Route。
- Core scenario 与 App Adapter scenario 验证同一管线；二者的区别是是否经过生产 `PlaybackRuntime`，不是 provider 实现。
- provider provenance 继续记录实际实现，但不是可选择的产品状态。

## 结果

打开媒体时不再存在选路或 fallback。需要比较新的 provider 实验时，应放在隔离 probe 或研究分支中；只有决定进入产品管线后，才改变活跃架构与验收合同。

`playbackcore-0002` 至 `playbackcore-0005`、`playbackcore-0008` 中关于多 Route 或 Apple reference 的部分由本决策取代；其中的历史运行结果仍作为当时证据保留。
