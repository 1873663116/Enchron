# Current visionOS Presentation Contract — 2026-07-13

## Scope

本记录描述当前 49-case presentation 合同的主机验证边界。先前 host output 与 generic visionOS build 不跨 working tree 继承；下列结果来自当前改动完成后的同一 working tree。本记录不包含 Simulator、App 或 Vision Pro 运行结果。

## Prepared contract

- manifest 固定为 49 个 case：4 个无媒体 lifecycle、8 个双路线 Shape、2 个 Window 播放中 Scene open / close 不迁移、8 个 Stereo round-trip、4 个 Scene restoration、3 个合法 edge、18 个原子播放控制、1 个 cold route switch 与 1 个 final cleanup。
- SwiftUI 与代码驱动输入调用同一个公开 `PresentationCommand`；保留 probe 名称的脚本只负责本次授权门、fixture、启动和结果回收，不拥有 scene、binding、mode 或 rollback 编排。
- Projection / Stereo 共用 sample-format override、target-first transaction、Scene lifecycle 独立性、Scene intent 恢复、fail-closed evidence schema、完整 cleanup barrier 和结果 provenance 均进入同一主机合同。
- Scene asset 为 `Sources/PlaybackLabVision/Fixtures/Immersive_Space.reality`，regular file，43,746,155 bytes，SHA-256 `4449b75f4074bbba2799bc4f99e2d4879ffe8bd77dd9b21abda1528519d55ecd`；它与 `/Users/xiongzhipeng/Applications/EnchronWorkspace/Xrplay_scene/Immersive Space/Immersive Space/Immersive_Space.reality` 字节相同。

## Confirmed host results

- `swift test`：47/47 passed。
- `script/test_vision_presentation_domain.sh`：`GREEN vision presentation domain`。
- `script/test_video_sample_format_override.sh`：`GREEN video sample format override`。
- `script/check_vision_presentation_contract.sh`：`GREEN vision presentation command contract`。
- `xcodebuild -project PlaybackCore.xcodeproj -scheme PlaybackLabVision -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build`：`BUILD SUCCEEDED`。

## Boundary

本次没有启动 Simulator 或 App，没有进行签名、安装、`devicectl` / `simctl` 操作，也没有连接或启动 Vision Pro。本文只声明 host tests 和 generic build 通过；不声明 RealityKit acknowledgement、scene 交接、displayed pixel 或 49-case 设备回归通过。
