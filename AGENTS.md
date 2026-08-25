## 仓库指引

实现事实来自代码、构建配置和运行结果。文档帮助定位这些事实，不替代它们：
- Enchron 术语 `docs/CONTEXT.md`；
- 当前代码所有权与依赖入口 `ARCHITECTURE.md`；
`docs/archive/` 保存历史材料。


## 工具链

项目构建在 Xcode beta6 与同版本 visionOS SDK 上，active developer directory 不在默认的 `/Applications`；以 `xcodebuild -version` 和 `xcode-select -p` 为准。

API 可用性与行为：Executor `apple_developer_docs`

Xcode IDE 的工具，包括构建、运行、测试、调试、工程结构读写和 Apple 文档语义检索，有两条到达路径：Executor 的 `xcode_ide_docs_build_debug_device_tools` 直连，以及 XcodeBuildMCP 的 `xcode_ide_call_tool` 代理。两条通向同一批工具，默认走直连。

XcodeBuildMCP 工具承担 Xcode IDE 的缺口：SwiftPM、代码覆盖率、macOS 目标。

两者都由 Xcode 工具链 `mcpbridge` 提供，无需 Xcode 图形界面运行。

## 验证

端到端调试与回归读取 `.agents/skills/vp-e2e`。
指令文档中的路径由 `Scripts/verification/verify_documentation_references.py` 核对：路径必须存在，已移除的登记在 `Config/retired_documents.json`。
