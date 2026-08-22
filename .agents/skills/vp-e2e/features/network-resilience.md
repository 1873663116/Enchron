# 网络抖动下的播放

远程播放期间连接中断、恢复或变慢时的行为。目标：缓冲充足时用户毫无感知；缓冲耗尽时给出说明当前阶段的指示，而不是报错退出。

本特性的实现属于[总表](../../../../docs/plans/03-media-byte-stream/overview.md)第三阶段。播放引擎的 P1 至 P6 已实现；等待与失败界面 E1 至 E4 由后续阶段实现。

## Sub-features

- 解封装读线程填至水位线，无人等待时仍继续填包。
- 可恢复的读失败与真正的流结束区分开，失败后可恢复。
- 断线后有限次退避重连，不主动断连。
- 加载指示由播放饥饿触发，不由网络事件触发；缓冲充足时重连全程无提示。
- 播放中失败分四类：连接中断、文件不存在、拒绝访问、数据损坏，各自给出下一步且保住播放位置。
- 播放中证书变更单列：停止播放且不在此刻接受。

## How to get to it (user POV)

用户不主动触发。远程播放中网络抖动、服务器重启、Wi-Fi 切换都会走到这里。

## Driving it

抖动无法靠真机自然等待取证。PlaybackCore 的 `RecordingRangeServer`（`HTTPMediaSourceRangeTests.swift`）在本机打开真实 socket，记录请求，并可在响应途中断连、持续拒答或延迟分块响应。

真机侧可用的粗粒度手段是在播放中断开服务器进程或网络，观察诊断串与 PlaybackCore live debug 通道。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 无消费者阻塞时读线程仍填包至水位线 | `sharedDemuxPrefetchesWithoutABlockedConsumer` |
| 结构 | 一次读失败不被当作播完，重连后从断点继续 | `sharedDemuxReconnectsAfterOneReadFailureAndContinuesFromCheckpoint` |
| 结构 | 有限次重连耗尽后才报真实错误，且错误不是播放结束 | `sharedDemuxReportsErrorOnlyAfterFiniteReconnectAttemptsAreExhausted` |
| 结构 | 四类播放中失败各自可区分，位置不丢 | **待建** |
| 物理 | 缓冲充足时断开连接，播放不中断且无指示出现 | **待建**（总表 V4） |
| 物理 | 缓冲耗尽时指示显示当前阶段 | **待建** |
| 感知 | 不适用 | |

## 证明的终态

断线自愈：制造断线时诊断串 `lifecycle` 全程为 Playing、`position` 持续前进、加载指示从未出现。缓冲耗尽：指示出现且文案指明阶段，恢复后从原位置继续。

## Gotchas

- 重连判据必须看来源类型而不是地址前缀，否则回环地址会被误判为网络源。
- 水位线与 SMB 并发的取值由测量给出，不预设常量。
