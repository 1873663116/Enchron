---
status: route model superseded by ADR 0017; records and macOS L2 remain active
date: 2026-07-13
---

# 以 route-neutral records 深化 Provider seam，并优先使用 macOS L2

本 ADR 的 route-neutral records 与“事实等价优先”的 macOS L2 决策仍有效；三条 route、uncompressed input 和 compressed / uncompressed dispatch 已由 ADR 0005 取代。当前活跃路线只以 `docs/core-spec.md` 与 ADR 0005 为准。

## Context

xr-fork 的完整对象模型把 nodes 3–6 固定在 mpv container snapshot、demux envelope 和 compressed sample assembly 上；本 ADR 作出时，PlaybackCore 曾同时存在 Apple Compressed、FFmpeg Compressed 与 FFmpeg Decoded 三条路线。若直接复制旧节点，Apple route 和当时的 decoded route 会被迫伪装成 mpv compressed pipeline。若只保留 `copyNextSample() -> CMSampleBuffer?`，session、track、epoch、format revision 与 provenance 又无法成为稳定验证面。

旧验证模型还把 L2 固定为 visionOS Simulator，但当前 macOS Playback Lab 使用同一 Provider、Apple renderer、synchronizer、RealityKit binding 和 video entity，能够更直接地证明大多数播放与承载事实。

## Decision

仍有效的决策是：`VideoSampleProvider` 是唯一上游分流 seam；稳定 interface 使用 Provider Open Snapshot、Video Track Model、Route Media Event 和 Video Sample records；nodes 3–6 使用 route-neutral schema，各 adapter 保留自己的 AVFoundation / FFmpeg implementation。

已被取代的部分是 route count 与 input-kind dispatch。当前只有 Apple Compressed 与 FFmpeg Compressed 两条 route，Renderer Input Coordination 当前只接受 compressed video input；具体边界见 ADR 0005。

L2 采用“事实等价优先”：macOS Playback Lab 证明真实 Provider、renderer、RealityKit 与 displayed frame；只有 macOS 不具备的 visionOS scene / API 事实进入 Simulator。Vision Pro 只承担无法等价验证的设备显示与 HDR / EDR。

## Consequences

- 裸 `CMSampleBuffer` 不再是完整 Provider 合同；所有 sample 必须可追溯到 Media Session、route、track、epoch、revision 和 source event。
- mpv 可在未来作为第四个 adapter 评估，但不再出现在公共节点语义中。
- 当前 `SampleBufferPlaybackSession` 需要拆出 Media Session / operations、Provider records、Renderer Input Coordination 和 diagnostics，而不是继续成为所有职责的单体。
- macOS L2 evidence 必须明确待证明事实与 visionOS 是否等价；scene lifecycle、HDR 观感和设备性能不能借 macOS 结论越界。
