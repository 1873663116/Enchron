# visionOS device build

> **Historical / stale.** 本文件记录废弃的独立 Portal Window、Fixed Immersive Screen 与多 `ImmersiveSpace` topology，只能证明当时的构建。当前事实以 `docs/core-spec.md` 和 `docs/acceptance/evidence.md` 为准；不得把下文的 “当前” 或 `verified` 沿用到现有实现。

唯一预期结果：当前 `PlaybackLabVision` 源码能够使用 visionOS device slice 完整编译并链接。

执行环境为 Xcode 27 beta 2、XROS 27.0 SDK、visionOS deployment target 26.0、generic visionOS arm64 destination，code signing disabled。构建使用 `PlaybackFFmpeg.xcframework` 的 xros device slice，并包含 PlaybackCore、PlaybackFFmpegBridge、共享音频控制，以及 Window、Portal、Fixed Immersive Screen、Panorama presentation adapter。

结果：`verified`，`xcodebuild` 返回 `BUILD SUCCEEDED`。该结果只证明 device target 的源码、API availability、FFmpeg slice 和链接闭合；它不证明真机启动、scene transition、空间投影、可听音频或 HDR / EDR 观感。
