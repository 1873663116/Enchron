## 仓库指引

实现事实来自代码、构建配置和运行结果。文档帮助定位这些事实，不替代它们：
- Enchron 术语 `docs/CONTEXT.md`；
- 当前代码所有权与依赖入口 `ARCHITECTURE.md`；
- 合并证据强度、改动分类与授权裁决 `docs/MERGE_EVIDENCE.md`；
- 自动回归的合同权威与执行、评审、判定协议 `Regression/`；
- 播放引擎无法从代码读出的外部约束与实测常数 `docs/PLAYBACK_ENGINE_CONSTRAINTS.md`；
- 设计系统的结构规则与平台约束 `docs/DESIGN_SYSTEM_CONSTRAINTS.md`；
- 播放呈现层的 RealityKit／SwiftUI 平台约束 `docs/PLAYBACK_PRESENTATION_CONSTRAINTS.md`；
- 浏览、Emby 与来源的外部约束 `docs/BROWSING_AND_SOURCES_CONSTRAINTS.md`；
- UI 测试通道与 visionOS 自动化的约束 `docs/UI_TEST_HARNESS_CONSTRAINTS.md`；
- 回归 harness 的失败模型、等待策略与超时预算契约 `Scripts/verification/harness/CONTRACT.md`；
`docs/archive/` 保存历史材料。


## 工具链

项目构建在 Xcode 27.0（27A266a）与同版本 visionOS SDK 上，active developer directory 不在默认的 `/Applications`；以 `xcodebuild -version` 和 `xcode-select -p` 为准。

API 可用性与行为：Executor `apple_developer_docs`

`Packages/PlaybackCore` 链接两个 vendored 二进制。`PlaybackSubtitleRenderer.xcframework` 在版本控制内；`PlaybackFFmpeg.xcframework` 约 380 MB，由 `Packages/PlaybackCore/.gitignore` 排除，克隆不带它，缺它则 PlaybackCore 无法解析。用 `Scripts/provision_vendored_ffmpeg.sh` 补齐：无参数时就地重建，参数给一个已持有该二进制的克隆路径时改为链接过去，worktree 与 CI 走后一条。重建由 `Packages/PlaybackCore/Scripts/build_ffmpeg.sh` 完成，按固定 SHA-256 取 FFmpeg 9.0.1 源码、套用 `Packages/PlaybackCore/Vendor/FFmpeg/Patches` 下的补丁，产出 macOS、visionOS 与 visionOS 模拟器三个 library。

Xcode IDE 的工具，包括构建、运行、测试、调试、工程结构读写和 Apple 文档语义检索，有两条到达路径：Executor 的 `xcode_ide_docs_build_debug_device_tools` 直连，以及 XcodeBuildMCP 的 `xcode_ide_call_tool` 代理。两条通向同一批工具，默认走直连。

XcodeBuildMCP 工具承担 Xcode IDE 的缺口：SwiftPM、代码覆盖率、macOS 目标。

两者都由 Xcode 工具链 `mcpbridge` 提供，无需 Xcode 图形界面运行。

## 模拟器安装

向模拟器安装 Enchron.app 必须走 `Scripts/build/install_to_simulator.sh`（用法见脚本头注释），它会先校验包带签名再 `simctl install`。禁止直接 `simctl install` 未经校验的包：模拟器构建是 ad-hoc 签名，而 `CODE_SIGNING_ALLOWED=NO` 产出的测试构建完全无签名，装上后应用丢失 keychain 身份，读写凭证报 OSStatus -34018，已存的 Emby 会话随之中断。测试产物复用于安装前，先跑 `install_to_simulator.sh --check` 确认签名。
