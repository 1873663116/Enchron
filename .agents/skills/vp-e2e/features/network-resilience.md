# 网络抖动下的播放

本特性覆盖远程播放期间连接中断、恢复或变慢时的行为。目标是：缓冲充足时，用户对网络波动毫无感知；缓冲耗尽时，给出说明当前所处阶段的指示，而不是报错退出。

本特性的实现属于[总表](../../../../docs/archive/plans/03-media-byte-stream/overview.md)的第三阶段。播放引擎部分的 P1 至 P6 已经实现；等待与失败界面 E1 至 E4 将由后续阶段实现。

## Sub-features

- 解封装读线程把缓冲填至水位线，即使没有消费者在等待也继续填包。
- 可恢复的读失败与真正的流结束被区分开，读失败之后可以恢复。
- 断线后进行有限次的退避重连；播放引擎不主动断开连接。
- 加载指示由播放饥饿触发，而不由网络事件触发；缓冲充足时，整个重连过程不出现任何提示。
- 播放中的失败分为四类：连接中断、文件不存在、拒绝访问、数据损坏；每一类都给出对应的下一步指引，并保住播放位置。
- 播放中的证书变更单独归为一类：此时停止播放，且不在此刻接受该证书。

## How to get to it (user POV)

这一特性不由用户主动触发。远程播放过程中的网络抖动、服务器重启、Wi-Fi 切换都会走到这条路径。

## Driving it with RecordingRangeServer

Preconditions: 结构侧在本机运行 PlaybackCore 单测即可；设备侧需要一个正在播放远程来源的会话。

网络抖动无法靠真机自然等待来取证。PlaybackCore 的 `RecordingRangeServer`（位于 `HTTPMediaSourceRangeTests.swift`）在本机打开真实 socket 并记录请求，还可以在响应途中断开连接、持续拒绝应答或延迟发送分块响应。

真机侧可用的粗粒度手段是在播放中直接断开服务器进程或网络，然后观察诊断串与 PlaybackCore 的 live debug 通道。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 没有消费者阻塞等待时，读线程仍然填包至水位线 | `sharedDemuxPrefetchesWithoutABlockedConsumer` |
| 结构 | 单次读失败不会被当作播放结束，重连后从断点继续 | `sharedDemuxReconnectsAfterOneReadFailureAndContinuesFromCheckpoint` |
| 结构 | 只有在有限次重连全部耗尽后才报出真实错误，且该错误不是播放结束 | `sharedDemuxReportsErrorOnlyAfterFiniteReconnectAttemptsAreExhausted` |
| 结构 | 四类播放中失败各自可以区分，播放位置不丢失 | **待建** |
| 物理 | 缓冲充足时断开连接，播放不中断且没有任何指示出现 | **待建**（总表 V4） |
| 物理 | 缓冲耗尽时，指示显示当前所处的阶段 | **待建** |
| 感知 | 不适用 | |

## 证明的终态

断线自愈场景的终态是：制造断线期间，诊断串的 `lifecycle` 全程保持 Playing、`position` 持续前进、加载指示从未出现。缓冲耗尽场景的终态是：指示出现且文案指明当前阶段，恢复后播放从原位置继续。

## Gotchas

- 重连判据必须依据来源类型而不是地址前缀，否则回环地址会被误判为网络来源。
- 水位线与 SMB 并发的取值由实际测量给出，不预设为常量。
