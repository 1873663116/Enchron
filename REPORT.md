# 播放预读与断线恢复实现报告

## 交付范围

本阶段完成总表 P1 至 P6 与 M10。产品层的等待和失败界面 E1 至 E4 未改动。

| 编号 | 当前实现 |
|---|---|
| P1 | 共享解封装线程在视频、音频或字幕读取器订阅后立即启动。它以各已订阅包队列的媒体时长为反馈，持续读取至 6 秒水位线；消费者移走包时会唤醒线程继续补充。包时长缺失时使用 DTS/PTS 跨度补足水位计算。 |
| P2 | 只有已取得来源总长度、`av_read_frame` 返回 `AVERROR_EOF`，且 AVIO 没有记录传输错误时，才发布正常结束。已知长度响应的提前断开会留下 AVIO 错误，因此进入恢复路径；其他负值也都不是播放结束。容器可以在尾部非媒体字节之前报告逻辑 EOF，所以不能把 `avio_tell` 等于文件长度作为必要条件。 |
| P3 | 远程来源在负读取结果后最多重连 3 次，退避为 250、500、1000 毫秒，总退避 1.75 秒。短暂停顿先快速恢复，随后指数放慢以免持续冲击故障端点，同时用固定次数保证终态可达。只有读到断点之后的新包才重置连续失败计数。重连在读线程中进行，排队包不清空，消费者仍可取走已有包；桥接层不会因网络事件主动关闭一条健康连接。 |
| P4 | 没有新增网络事件、等待状态或产品 UI 信号。缓冲覆盖恢复窗口时，消费者只继续取得样本；重连耗尽后才取得原有读取错误通道中的真实错误。 |
| P5 | `PlaybackRuntime` 取 `PlaybackAddress.isRemote`，经 `PlaybackCoreController.open`、`SampleBufferPlaybackSession.prepare`、`FFmpegDemuxSession` 传至 `PBFFmpegDemuxSourceCreate`。C 层不检查 URL scheme。测试还证明 HTTP URL 在 `isRemote == false` 时不会重连。重新打开播放会保留同一来源属性。 |
| P6 | 水位线由下面的确定性吞吐与故障注入测量导出，为 6 秒媒体时长。 |
| M10 | `open_media_source` 的 HTTP scheme 判断、`seekable`、`multiple_requests`、`avio_open2` 前置探测、`end_offset` 和自定义 IO 所有权分支均已删除。本地与 HTTP 现在都由一次 `avformat_open_input` 打开；光盘镜像所需的格式与重同步选项仍由媒体事实决定。 |

## P6 测量与水位线

测量使用 `PlaybackSourceReadThroughputTests` 已验证的字节计数器和速率采样规则，并在 `RecordingRangeServer` 的真实本机 socket 上固定每 2 毫秒发送 4096 字节。测试语料 `av1-flac-avsync-10s.mkv` 长 10.000 秒、1,096,155 字节，平均码率 876,924 bit/s，即约 109,616 byte/s；服务端设定的发送上限为 2,048,000 byte/s，约为语料平均消耗率的 18.7 倍。

| 测量 | 结果 |
|---|---:|
| 无消费者等待时填满 6 秒水位线 | 0.418 秒 |
| 中途短响应断开一次，重连一次并从断点读至 9 秒以后 | 1.225 秒 |
| 服务端持续拒答，3 次重连耗尽并确认 0.5 秒内不再重连 | 2.276 秒 |

三次退避总计 1.75 秒。水位线取 `ceil(3 × 1.75)`，即 6 秒，给完整退避之外的重新打开、定位和补包各留出同量级余量；它也是本次单次恢复实测时间的约 4.9 倍。按测量语料的平均码率，6 秒约对应 657,693 字节。水位线按媒体时长计算，不把某一部片的字节码率写成全局常量。

## M10 行为差异

删除特殊分支后，FFmpeg 保留其默认的开放结束区间请求，例如 `bytes=<offset>-`；桥接层不再把首个响应长度写成后续请求的固定 `end_offset`。`openedHTTPContextUsesFFmpegDefaultOpenEndedRanges` 固定了新的请求形状，`httpPlaybackReadsTheWholeSourceWithoutStalling` 证明所有轨道可以读到真实末尾。

改前的基座探针在一个 Dolby Vision Profile 8.1 语料和三个 APMP HTTP 语料上会停在读取阶段直至 900 秒超时。改后的同一矩阵可完成这些语料，并保持本地与 HTTP 的解码可见字段一致。这是 M10 删除后观察到的打开路径行为改善。

## 新增结构证据

- `sharedDemuxPrefetchesWithoutABlockedConsumer`
- `sharedDemuxReconnectsAfterOneReadFailureAndContinuesFromCheckpoint`
- `sharedDemuxReportsErrorOnlyAfterFiniteReconnectAttemptsAreExhausted`

补充的 P5 证据为 `sharedDemuxDoesNotReconnectHTTPWhenTheSourceIsNotRemote`。`RecordingRangeServer` 现在可以分块延迟发送、在指定累计字节处断开一次、持续拒答并关闭现有连接，同时记录连接、发送、断开、拒答和 Range 请求。

测试优先执行的红灯结果如下：预读测试在 3 秒内没有新增读取；单次断线被发布为错误；重连耗尽测试没有观察到任何重连或错误文本。生产实现完成后，四条网络韧性测试并行复跑全部通过，耗时分别为 0.418、1.225、2.276 和 0.006 秒。

`.agents/skills/visionpro-xcuitest/features/network-resilience.md` 的三格“谁守”已经改为上述三条实际测试。产品失败分类和真机 UI 证据仍明确标为待建。

## 验证结果

- `swift test`（`Packages/PlaybackCore`）：共 207 条测试、3 个预期失败和 4 个 issue；失败仍为 `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`、`appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`、`controllerRejectsSecondOpenAndRecordsTheRejection`。`acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` 在最终全量运行和单独干净重跑中均通过。
- `swift test --filter 'sourceReadRate|sourceReadMonitor'`：4 条通过。
- `swift test --filter 'openedHTTP|httpPlayback|sharedDemux'`：7 条通过。
- `python3 Scripts/verification/verify_format_description_ownership.py`：通过。
- 基座 `b2d838c5` 的 `python3 Scripts/verification/verify_source_parity_matrix.py --mode parity`：107 个语料，3 个与传输无关的不可解码状态，另有 4 个本地/HTTP 差异；4 个 HTTP 探针均在 900 秒超时，分别为 Dolby Vision Profile 8.1 `P81_GlassBlowing2`、`APMP-360-example`、`APMP-wide-FOV-example` 和 `APMP-180-example`。每项的本地探针均为 `ok`。
- 改后 `python3 Scripts/verification/verify_source_parity_matrix.py --mode parity`：107 个语料，所有本地/HTTP 比较字段为 0 差异。脚本因 3 个与传输无关的语料状态返回 1：Profile 20 HLS 为 `no_frames`，LG HLG TS 为 `partial`，设备不支持的 ProRes RAW 为 `probe_failed`。
- `xcodebuild -project Enchron.xcodeproj -scheme Enchron -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build`：`BUILD SUCCEEDED`。

未执行物理 Vision Pro 验证，因为本单不改变佩戴者界面、物理音频或性能结论；对应产品体验证据属于后续 E1 至 E4。
