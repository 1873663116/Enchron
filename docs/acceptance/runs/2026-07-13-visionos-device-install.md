# visionOS physical-device signed build and install

> **Historical / stale.** 本文件记录废弃 presentation topology 下的一次签名与安装，不证明当前独立 Control Window、单一 Playback Window、单一 progressive `ImmersiveSpace` 与现行回归 manifest。当前事实以 `docs/core-spec.md` 和 `docs/acceptance/evidence.md` 为准。

唯一预期结果：当前 `PlaybackLabVision` 工作树能够为已连接的物理 Vision Pro 完成签名构建、安装，并把 APMP fixture 复制到 App container。

环境为 Xcode 27 beta 2、XROS 27.0 SDK、visionOS deployment target 26.0、物理 Vision Pro destination、development team `JFLYK8F636`。当前工作树包含 Apple Compressed、FFmpeg Compressed、共享音频 renderer / synchronizer、普通观看控制、Window / Portal / Fixed Immersive Screen / Panorama adapter，以及 FFmpeg APMP projection handoff。

结果：`verified`。

- signed device build：`BUILD SUCCEEDED`。
- 安装：`com.xiongzhipeng.PlaybackLabVision` 安装成功。
- probe fixture：30 秒、2048×1024、HEVC `hvc1` 的真实 APMP 文件已复制到 App `Documents/presentation-probe-apmp.mov`，CoreMedia 独立读取 `ProjectionKind = Equirectangular`，设备侧文件大小 4.1 MB。

本轮明确没有启动设备 App，也没有运行 `script/probe_vision_device.sh`。因此这条记录不包含 presentation transition、actual mode、displayed frame、可听音频或观感结论。
