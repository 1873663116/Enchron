# PlaybackCore

PlaybackCore 是 macOS 与 visionOS 共用的音视频 sample-buffer library。它接受媒体来源，建立 Media Session，输出由同一个 AVSampleBufferRenderSynchronizer 管理的视频与音频 renderer，并提供播放控制、状态和结构化诊断。

```text
Media Source + Explicit Route
       ├─ Apple Compressed Video Provider
       ├─ FFmpeg Compressed Video Provider
       └─ Shared FFmpeg Audio Provider
                    │
                    ▼
          Renderer Input Coordination
                    │
                    ▼
 AVSampleBufferVideoRenderer + AVSampleBufferAudioRenderer
                    │
                    ▼
       AVSampleBufferRenderSynchronizer
                    │
                    ▼
            Consumer App Adapter
```

核心到 active video renderer 为止。消费方负责来源长期授权、renderer consumer、SwiftUI scene、窗口、沉浸空间和产品状态。

## 当前路线

Apple Compressed 使用 AVAssetReaderTrackOutput(outputSettings: nil) 交付 storage-format compressed sample，当前仅作为系统对照。FFmpeg Compressed 自行解封装并标准化 compressed CMSampleBuffer，是产品主线。两条路线共用音频、renderer graph、时间线与控制。

## 构建与测试

```sh
swift test
./script/build_ffmpeg.sh
./script/probe_dolby_vision_compressed.sh
```

Package.swift 只发布 PlaybackCore library。仓库不提供可运行 App target。

## 真相源

- CONTEXT.md：术语。
- ARCHITECTURE.md：模块、所有权与 seam。
- docs/core-spec.md：活跃行为规格。
- docs/acceptance/verification-system.md：核心验证规则。
- docs/acceptance/evidence.md：当前核心证据。
- docs/adr/：历史决策收据。

PlaybackCore 使用 MIT License，详见 LICENSE。
