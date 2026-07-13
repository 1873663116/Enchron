# PlaybackCore 取代 Enchron 内部 mpv 播放核心

- 状态：accepted
- 日期：2026-07-13

## 背景

Enchron 内部长期维护 `MPVPlayerAdapter`、MPVKit、Metal texture bridge、播放状态和媒体事实模型。独立 PlaybackCore 已经拥有 FFmpeg Compressed 产品路线、共享音频与时间线、Apple renderer、RealityKit binding、播放控制和诊断证据。继续维护两套核心会造成状态、renderer 和文档所有权冲突。

## 决策

Enchron 作为产品 composition root，直接依赖独立 PlaybackCore。Enchron 只保留 Playback App Adapter、产品启动协调、SwiftUI、文件来源、持久化和空间呈现。内部 mpv 播放核心、MPVKit 依赖、Metal texture bridge 和 engine routing 全部退役，不建立兼容层或备用产品核心。

Xrplay_scene 继续作为独立场景创作仓，只向 Enchron 交付 RealityKitContent / USD，不参与播放实现。

## 后果

旧代码在 PlaybackCore App Adapter vertical slice 建立后删除。迁移期间 FakeApp 只用于前端验证，不能被解释为生产播放实现。外部 PlaybackCore 仍在独立调试时，Enchron 不修改其源码。
