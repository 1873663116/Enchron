# PlaybackCore

PlaybackCore 是 macOS 与 visionOS 共用的音视频 sample-buffer library。它读取媒体容器、解封装音视频并组装 compressed `CMSampleBuffer`，再交给 Apple AVFoundation 的 sample-buffer renderer。Apple 负责解码、HDR / Dolby Vision 解释和最终渲染。

```text
Media Source -> Media Session -> Demux Provider
                                  | compressed audio/video samples
                                  v
                         Renderer Input Coordination
                                  v
       AVSampleBufferVideoRenderer + AVSampleBufferAudioRenderer
                                  v
                  AVSampleBufferRenderSynchronizer
                                  v
                         Consumer App Adapter
```

核心到 active video renderer、播放状态、轨道和诊断事实为止。消费方负责来源长期授权、renderer consumer、SwiftUI、RealityKit 和产品呈现。

## 构建与测试

```sh
swift test
./script/build_ffmpeg.sh
```

当前行为只在 `docs/core-spec.md` 定义，验证规则和最近证据位于 `docs/acceptance/`；`docs/adr/` 只保存历史决策。

PlaybackCore 使用 MIT License，详见 `LICENSE`。
