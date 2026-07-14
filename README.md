# PlaybackCore

PlaybackCore 是 macOS 与 visionOS 共用的音视频 sample-buffer 播放核心和验收 App。两条显式视频路线共用同一套音频、时间线、控制与 RealityKit 呈现；当前验证事实以 evidence ledger 为准。

```text
Media Source + Explicit Route
       ├─ Video Sample Provider
       │  ├─ Apple Compressed
       │  └─ FFmpeg Compressed
       │           │
       │           ▼
       │  compressed Video Sample Stream
       │           │
       └─ Shared FFmpeg Audio Track Provider
                   │
                   ▼
          Linear PCM Sample Stream
                   │
                   ▼
        Renderer Input Coordination
       ┌───────────┴───────────┐
       ▼                       ▼
 AVSampleBufferVideoRenderer  AVSampleBufferAudioRenderer
       └───────────┬───────────┘
                   ▼
     Shared AVSampleBufferRenderSynchronizer
                   │
                   ▼
        VideoPlayerComponent + RealityView
```

Apple Compressed 使用 `AVAssetReaderTrackOutput(outputSettings: nil)` 交付 storage-format compressed sample，只承担系统对照。FFmpeg Compressed 是产品主线：它自行解封装并标准化 compressed `CMSampleBuffer`，系统负责解码、HDR 解释与呈现。

## 当前目标与验证顺序

当前按事实层推进验证：先关闭双路线 compressed sample、共享音频 graph 与完整控制合同，再由 macOS Playback Lab 关闭真实 Provider、renderer、RealityKit 和持续播放的主要 L2；随后验证 visionOS 的独立 Control Window、单一 Playback Window、单一使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace` 与四种派生产品形态。Control Window 不含 `RealityView`；Playback Window 与 Immersive Space 只承载画面，不叠加播放控件。Flat Window 与 Portal Window 复用同一个窗口 `RealityView`；Docked 使用 RCP `world/screen` 的运行时 transform 建立纯 Entity anchor；Panorama 在同一个 `ImmersiveSpace` 中切换为黑场并请求 `.progressive` viewing mode。最后只把真实设备显示、HDR / EDR、可听输出、主观同步和实际空间观感留给 Vision Pro。

每一阶段都必须同时交付用户可操作入口、核心状态、运行时调试事实和独立证据。只存在内部方法、日志或结构化 record 不算用户能力完成。

## 验证原则

macOS Playback Lab 是主要播放与 RealityKit 集成验证入口。它可以证明真实 Provider、sample、renderer、timeline、RealityKit binding 和 displayed frame，但不能证明 Vision Pro 的 HDR 观感。visionOS Simulator 只证明平台目标和 macOS 不具备的 scene / API 集成。Vision Pro 验收是差分验收，不重新承担可由 L1 / L2 自动证明的基础排查。

每条路线、每个节点和每个验证用例独立记录结果。一个用例只有一个预期结果；一条路线成功不能推断另一条路线成功。

## 构建与诊断入口

- `./script/build_and_run.sh`：生成工程、构建并启动 macOS Playback Lab。
- `./script/build_and_run.sh --route-probe`：在一个 App 进程中依次验证两条路线。
- `./script/build_ffmpeg.sh`：构建 macOS、visionOS device 与 Simulator FFmpeg XCFramework。
- `./script/probe_dolby_vision_compressed.sh`：在一个 probe 进程中验证 Dolby Vision Profile 5、8.1、8.4 的 Apple Compressed 格式与 macOS displayed pixel buffer。
- `./script/probe_vision_device.sh --confirm-device-ready DEVICE_ID TEAM_ID [APMP_FIXTURE] [OUTPUT]`：只有操作者针对本次运行明确确认 Vision Pro 已佩戴、解锁且可测试后，才可传入确认参数并允许脚本签名、安装和启动 App。这个保留旧名称的脚本只负责授权门、fixture、启动与结果回收，不实现任何呈现转换；App 内代码驱动输入端在同一进程中调用 SwiftUI 使用的公开 `PresentationCommand`，验证双路线 cold switch、Flat Window、Portal Window、Docked、Panorama 和独立 Stereo 切换。脚本只接受当前 run ID 且同时满足 `completed = true`、`passed = true` 的结果，最后等待 cleanup 并退出。仅发现已连接设备或已有历史确认不构成执行授权。
- `PlaybackDebugCLI pause|play|rate|seek|route|snapshot|close|reopen`：通过原子 command inbox 控制同一个常驻 macOS App，并等待 completion acknowledgement；协议见 `docs/acceptance/live-debug.md`。
- Xcode 的 `PlaybackLabVision` scheme：执行 Vision Pro 人工差分验收；Simulator 只在确有平台差分需要时使用。

Simulator 只在平台差分验证时启动；取得运行证据后立即停止 App 并 shutdown 对应设备，避免调试环境长期占用内存。

## 真相源

- `CONTEXT.md`：当前术语。
- `ARCHITECTURE.md`：模块、所有权与 seam。
- `docs/core-spec.md`：活跃设计规格。
- `docs/acceptance/verification-system.md`：验证层级、节点推进与证据规则。
- `docs/acceptance/nodes/`：节点输入、输出、完成条件和失败边界。
- `docs/acceptance/evidence.md`：当前有效证据账本。
- `docs/acceptance/live-debug.md`：运行中 Snapshot、JSONL event、command inbox 与 acknowledgement 协议。
- `docs/migration/xr-fork-fusion-map.md`：旧 xr-fork 文档的迁移审计记录，不是运行规格。
- `docs/adr/`：难以回退的决策收据。

## License

PlaybackCore 使用 MIT License，详见 `LICENSE`。
