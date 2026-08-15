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

## 未实现

`PlaybackRuntime` 与 `SpatialPlatformEffectExecutor` 仍然对每一次呈现转换构造新的 `PlaybackCoreController` 并重新 `open`。改用渲染图替换需要三步。

第一步，`PlaybackRuntime` 增加一条与 `prepareTechnicalSessionForPresentationConversion` 平行的转换路径，它更新 `renderer`、`rendererEpoch`、`videoComponentRevision`、`presentationState` 与 `startsWhenAttached`，但不更换 controller、session、`activeTechnicalSessionID` 与轨道列表，也不建立 `ActivatedTechnicalSessionCutover`。

第二步，`SpatialPlatformEffectExecutor` 的 `enterImmersivePlayback` 与 `exitImmersivePlayback` 在格式未变时走该路径。判据是 `technicalSessionFormatReplacementIsPending == false`，即 portal 与 panorama 之间、window 与 docked 之间的往返。应用格式引起的 window 与 portal 互换先保留会话替换，因为它还要证明 RealityKit 不会沿用旧的投影分类。

第三步，在物理设备上重测同一组转换，与上面的分段耗时对照。判据是远程 portal 到 panorama 的 `technicalSessionReplacementStage` 不再出现 `openingReplacement`，且 `PlaybackDebugRecorder` 不再为该转换新建会话目录。

## 相关决策

[ADR 0016](../adr/0016-unified-realitykit-video-player-consumer.md) 记载呈现状态转换迁移的是同一个 Media Session 与 Renderer 绑定，并且每个 `RealityView` 拥有自己的 Video Entity。跨 RealityView 需要新 Entity 的约束记在 `PlaybackRuntime.ReleasedRendererConsumer` 的注释中，它约束 Entity 与渲染图，不约束媒体会话。
