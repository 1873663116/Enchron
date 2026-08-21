## 仓库指引

实现事实来自当前代码、构建配置和运行结果。文档帮助定位这些事实，不替代它们：
- Enchron 术语 `docs/CONTEXT.md`；
- 当前代码所有权与依赖入口 `ARCHITECTURE.md`，以生产源码为准；
- `docs/adr/` 记录历史决策，`docs/archive/` 保存历史材料；二者不描述当前实现。

工作时读取与任务有关的入口，检查对应代码。代码与文档不一致时，综合二者并调查，判断是代码缺陷、文档漂移，还是尚未完成的实验。

## 工具链

项目构建在 Xcode beta5 与同版本 visionOS SDK 上，active developer directory 不在默认的 `/Applications`；以 `xcodebuild -version` 和 `xcode-select -p` 为准。API 可用性与行为取自 Executor 的 `apple_developer_docs`，训练数据通常落后于当前 beta。

Xcode IDE 的工具，包括构建、运行、测试、调试、工程结构读写和 Apple 文档语义检索，有两条到达路径：Executor 的 `xcode_ide_docs_build_debug_device_tools` 直连，以及 XcodeBuildMCP 的 `xcode_ide_call_tool` 代理。两条通向同一批工具，直连把内容内联返回，代理把内容写成 artifact 文件需要再读一次，因此默认走直连。

XcodeBuildMCP 工具承担 Xcode IDE 的缺口：SwiftPM、代码覆盖率、macOS 目标。

两者都由 Xcode 工具链 `mcpbridge` 提供，无需 Xcode 图形界面运行。

## 构建产物

- SwiftPM 构建默认落在 `.build/`，无需干预。
- `xcodebuild` 一律显式传 `-derivedDataPath .scratch/<日期>-<主题>/DerivedData`；缺省时会写到 `~/Library/Developer/Xcode/DerivedData`。
- 探针输出、xcresult、日志等一切临时文件只落 `.scratch/<日期>-<主题>/`（或系统 TMPDIR），不落卷根、`$HOME` 或仓库其他位置。
- 需要长期保存的验收证据移入 `docs/archive/acceptance/evidence/<主题>-<日期>/` 并附 manifest；其余临时产物在会话结束前删除，或运行 `zsh Scripts/scratch-prune.zsh` 清理超过保留期（默认 14 天）的条目。

## 验证

涉及佩戴者所见画面、物理音频、性能等结论需要物理 Vision Pro，读取 `.claude/skills/visionpro-xcuitest`。visionOS 真机的 UI 自动化只有该 skill 的 XCUITest 控制器一条通道；Xcode 的 Device Interaction 工具在 visionOS 上不可用，只支持 iOS 与 watchOS 模拟器。 
