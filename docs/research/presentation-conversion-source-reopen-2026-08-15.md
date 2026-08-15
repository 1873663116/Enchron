# 呈现转换的来源重开代价

## 结论

呈现模式切换的等待时间几乎全部是重新打开来源的时间。本地与远程走同一条代码路径，PlaybackCore 中唯一按来源分叉的位置是 `PlaybackFFmpegBridge.c` 的 `open_media_source`，它只为 HTTP 路径多设一个 `end_offset` 并为此先做一次 `http_source_length` 探测。

## 设备实测

2026-08-15 在物理 Vision Pro 上测得，远程来源为 WebDAV `192.168.5.2` 上的 `Blade Runner 2049 (2017).mp4`，本地来源为媒体库中的 `180_3D.mp4`。证据在 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/mode-switch-source-latency-20260815/`，归约脚本为该目录的 `session_phase_timeline.py`。

远程 window 到 portal 的替换会话分段耗时：音轨与字幕轨枚举 15 秒，视频 reader 打开 14 秒，seek 回原播放位置 21 秒，时间线重锚 7 秒，合计 57 秒。远程 portal 到 panorama 的替换会话为 32 秒打开加 12 秒 seek。首次打开为 28 秒。本地同类替换会话的每个里程碑都在一秒内完成。

代价的倍数来自 `SampleBufferPlaybackSession.prepare` 在视频 reader 之前先枚举音轨与字幕轨，`PBFFmpegAudioTrackCount`、`PBFFmpegAudioTrackCopyInfo`（按音轨数）、`PBFFmpegSubtitleTrackCount` 与 `PBFFmpegReaderOpen` 各自独立打开一次容器，HTTP 路径上每次还先建立一条只读长度的连接。PlaybackCore、MediaSource 与 Emby 都不持有任何来源字节缓存，因此两个技术会话之间不共享已读数据，转换期间新旧 reader 同时向同一服务器拉流。

## 已实现

`SampleBufferPlaybackSession.replaceVideoRendererGraph()` 让一个媒体会话交出第二个渲染图。它向同一个 `AVSampleBufferRenderSynchronizer` 添加新的 `AVSampleBufferVideoRenderer`，替换其后的 sink，保持来源打开与 timebase 运行。

两条平台约束决定了它的形状。`AVSampleBufferVideoRenderer` 在添加 video target 之前拒绝入队，因此替换后视频样本投递保持挂起，由调用方绑定新渲染器后经既有的 `restartVideoSampleDelivery(at:)` 回填。离场渲染器保留在 synchronizer 上继续呈现最后一帧，直到 `retireDepartingVideoRendererGraph()`，使转换期间旧 Scene 始终有画面。

## 已接线并实测

`PlaybackRuntime` 的 prepare、activate、retire 三步在格式未变时改走渲染图替换，判据是 `technicalSessionFormatReplacementIsPending == false`，覆盖 portal 与 panorama 之间、window 与 docked 之间的往返。`SpatialPlatformEffectExecutor` 未改动，它原有的 prepare、activate、rebase、settle、retire 编排对两条路径同样成立。应用格式引起的 window 与 portal 互换仍走会话替换，因为它还要证明 RealityKit 不会沿用旧的投影分类。

2026-08-15 同设备同片源实测，证据在 `TestEvidence/mode-switch-graph-reuse-20260815/`。远程 portal 到 panorama 从点击返回到沉浸落地，基线 78 秒，改后两次分别为 17 秒与 12 秒。`technicalSessionReplacementStage` 全程只出现 `installingRenderer`，`openingReplacement` 一次未出现。两次运行的会话事件流中 `source.acquired`、`open.admitted`、`provider.opened` 各只有一条，都属于最初的打开，转换本身没有再打开来源；`rendererGraph.replaced` 与 `rendererGraph.departingRetired` 各一条，`graphRevision` 为 2。落定后 `displayedPixelBuffer` 为真、`rate` 与 `actualTimebaseRate` 均为 1、`actualViewingMode` 为 stereo。

## 一次远程打开的读取量

用 `TestEvidence/mode-switch-graph-reuse-20260815/open_read_volume.py` 轮询会话快照的 `sourceReadObservation` 测得，同一部片源从点击到出第一帧共读取约 37.4 MB，其中视频 reader 开始之前就读掉约 22 MB。字节计数只在 `avformat_open_input` 与 `avformat_find_stream_info` 返回时发布，因此读数呈阶梯，一级阶梯不对应一次探测。

读取量由容器索引主导，与探测无关。该片源 18416527997 字节，顶层只有 `ftyp`、`mdat` 与位于尾部的 `moov` 三个 box，`moov` 长 7360986 字节，不是分片 MP4，流表只有 HEVC 3840×2160 与 AC3 六声道两条，没有字幕轨。`mov_read_header` 在 `avformat_open_input` 内把整个 `moov` 读入，`probesize` 不管辖这段字节，它只管辖 `avformat_find_stream_info` 的读包循环。用产品自己 vendored 的 FFmpeg 8.0.1 照抄 `open_media_source` 的调用顺序与字节发布点对同一 URL 实测，`avformat_open_input` 返回时读取 7368761 字节，`avformat_find_stream_info` 的增量只有 7774 字节。因此 37.4 MB 是 7.36 MB 的 `moov` 被读了五次，22 MB 是它被读了三次。

因此打开慢由两件事叠加：媒体信息建立在播放时刻而不是入库时刻，因而完全不复用；同一个文件被独立打开四到五次，每次重读整个 `moov`。对照 Emby 的三到四秒，其服务端在扫描时就已经把轨道表落库，播放时只查库。

有效速率 1.1 到 2.2 MB/s 是这个打开序列自身的请求空转，不是链路上限。同一台服务器上单条连接顺序读实测 8.9 到 15.7 MB/s，设备进入 `playing` 之后自己记录的 `bytesPerSecond` 是 8342433。每个请求的连接建立加首字节耗时 330 到 520 毫秒，乘以每次打开四个请求、每次准备四到五次打开，正好摊成 1 到 2 MB/s。压请求数直接压打开时间，加带宽或调缓冲不会。

Emby 直连是另一条路径，它有一条真实的服务端上限。对 `~/Library/CloudStorage/EmbyMedia` 挂载尚未落地的区域，单条连接顺序读实测 0.42 MB/s，比 alist 慢 20 到 37 倍，与读取形态无关。来源选择对打开时间的影响大于任何 FFmpeg 选项。

测量方法与逐条数字见 `Scripts/verification/probe_remote_media_reads.py` 与 `remote_open_accounting_probe.c`。

## 剩余代价

转换耗时现在由回填的 seek 主导。从渲染图替换到第一个样本 13 秒，到 seek 完成 16 秒。原因是新渲染器同时承担解码，必须从一个可独立解码的关键帧开始，而当前实现向后 seek 回切换时刻，在 HTTP 来源上这是一次新的字节范围请求。可见的副作用是位置回退，实测从 16.686 秒回到 10.427 秒。

两条候选。一是改为向前推进到下一个关键帧，代价是播放位置小幅前跳而不是后退，这是产品取舍不是纯技术选择。二是让替换渲染器复用已缓冲的压缩样本，需要先确认 receiver 能否接受一段以非关键帧开头的输入并在下一个关键帧自愈。

## 相关决策

[ADR 0016](../adr/0016-unified-realitykit-video-player-consumer.md) 记载呈现状态转换迁移的是同一个 Media Session 与 Renderer 绑定，并且每个 `RealityView` 拥有自己的 Video Entity。跨 RealityView 需要新 Entity 的约束记在 `PlaybackRuntime.ReleasedRendererConsumer` 的注释中，它约束 Entity 与渲染图，不约束媒体会话。
