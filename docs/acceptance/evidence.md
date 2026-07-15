# PlaybackCore 当前证据

## 2026-07-15 Swift 6.4 / AVFoundation Receiver 升级

- Code revision：`89310ad` 加当前未提交升级工作区。
- Toolchain：Xcode 27.0 beta 2（`27A5209h`）、Apple Swift 6.4（`swiftlang-6.4.0.23.5`）、macOS 27 SDK、visionOS 27 SDK。
- Commands：`script/build_ffmpeg.sh` 与 object-level `vtool -show-build`；PlaybackCore 在全新 scratch path 执行 `swift test`；两个保留诊断工具以 `xcrun swiftc -swift-version 6 -typecheck` 检查；Enchron `swift test`；`XrPlayer` 与 `DesignPreview` 的 `generic/platform=visionOS` 无签名构建。
- Result：FFmpeg XCFramework 的 macOS arm64、visionOS arm64、visionOS Simulator arm64 / x86_64 object 均声明 minOS 27.0 与 SDK 27.0；PlaybackCore 全新冷构建 56 tests passed；两个诊断工具无警告通过 Swift 6 类型检查；Enchron 31 tests passed、1 个需外部 WebDAV 环境的测试 skipped；两个 visionOS scheme 构建成功，XrPlayer 另以全新 DerivedData 链接重建后的 FFmpeg 成功。
- Proven：现有 provider、Media Session、控制与 renderer graph 已在 Swift 6.4 工具链编译；Apple reader 使用 `AVAssetReaderOutput.Provider`；audio/video 输入使用 AVFoundation Receiver async enqueue、Receiver flush 与 rendering event；正常接受、解码警告、flush cancellation、requires-flush failure、backpressure cancellation 与 cleanup 有确定性回归。
- Not proven：Vision Pro 硬件解码、HDR / Dolby Vision、RealityKit 最终呈现和长时间真机行为；单一公开 sample-buffer 路径、compressed audio、subtitle interface 与移除 route selection 仍属于后续架构迁移。

当前 Xcode 27 beta 2 SDK 声明的 video Receiver requires-flush rendering event 与本机 macOS 27 beta Swift runtime 符号不一致。实现不直接引用该不匹配 case，并把未识别的 video terminal event 保守记录为 requires-flush failure；更新到匹配的 Xcode / macOS beta 后必须重新验证并移除此兼容边界。

## AVFoundation reference evidence

既有 macOS probe 已证明 Dolby Vision Profile 5、8.1 与 8.4 的 storage-format sample 保留对应 codec configuration，并被 Apple renderer 接受产生 displayed pixel buffer。既有 Vision Pro 人工对照记录显示三类样片的 Apple Compressed 画面与系统播放器一致。

这些结果证明 AVFoundation reference path 的系统能力，不证明 PlaybackCore 当前 FFmpeg sample assembly 已经满足同一合同；产品路径迁移后必须使用相同 profile 重新验证。
