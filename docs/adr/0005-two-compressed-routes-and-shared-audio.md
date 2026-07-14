---
status: accepted
date: 2026-07-13
---

# 收敛为两条 compressed 视频路线并共享音频与控制

PlaybackCore 的活跃视频路线收敛为 Apple Compressed 对照层与 FFmpeg Compressed 产品主线。FFmpeg Decoded 已完成可行性比较，但不再属于当前 route matrix；其历史运行证据保留为 `stale`，不能推导当前完成状态。

两条路线只在 `VideoSampleProvider` 处分流，输出 compressed `CMSampleBuffer`，共同进入 Renderer Input Coordination、`AVSampleBufferVideoRenderer`、synchronizer、RealityKit binding 与 presentation adapter。音频由独立 FFmpeg Provider 解码为 Linear PCM，加入同一个 synchronizer。路线冷切换保留时间、暂停状态、倍速、音量、静音和可继续匹配的音轨选择。

当前不实现能力探测、自动选路或失败 fallback。Apple Compressed 的成功不推导 FFmpeg Compressed 成功；Dolby Vision 与设备显示结论仍按 route 和 profile 独立验收。

## Consequences

Renderer Input Coordination 当前只接受 compressed video input。decoded pixel transfer、VideoToolbox decoded route 与 mpv adapter 留在未来决策，不保留推测性接口。macOS Playback Lab 证明可持续播放、音频与控制；Vision Pro 证明设备呈现、HDR / EDR 与空间模式观感。
