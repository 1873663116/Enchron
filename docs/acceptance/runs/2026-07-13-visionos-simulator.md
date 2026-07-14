# visionOS Simulator adapter run

> **Historical / stale.** 本文件记录旧三路线与旧 presentation topology 的 Simulator 截图，不证明当前双路线、单窗口 / 单 `ImmersiveSpace` 实现。当前事实以 `docs/core-spec.md` 和 `docs/acceptance/evidence.md` 为准。

环境：Apple Vision Pro Simulator，xrOS 27.0；scheme `PlaybackLabVision`；bundle identifier `com.xiongzhipeng.PlaybackLabVision`。

唯一预期结果：visionOS App scene 与 RealityKit presentation adapter 能够在 Simulator 中实际启动并呈现。

结果：`verified`。XcodeBuildMCP 完成 build、boot、install 与 launch，App process ID 为 `1761`。运行截图为 `800 × 450`，可见 “Choose a video to begin”、视频选择入口、Apple Compressed、FFmpeg Compressed、FFmpeg Decoded 三条显式路线，以及 play / pause 控制；因此本用例证明应用进程落在实际 visionOS UI 与 RealityKit 容器，而不是只有 build success。

边界：本用例未选择视频，不证明 Provider、sample、renderer displayed frame、Vision Pro scene lifecycle、HDR / EDR 观感或设备性能。完成取证后已停止 App，并将 Simulator device `6D3B4D6F-D370-4133-95E3-4BE4F23BCA0D` shutdown；最终状态为 `Shutdown`。
