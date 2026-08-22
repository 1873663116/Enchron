## 仓库指引

实现事实来自当前代码、构建配置和运行结果。文档帮助定位这些事实，不替代它们：
- Enchron 术语 `docs/CONTEXT.md`；
- 当前代码所有权与依赖入口 `ARCHITECTURE.md`，以生产源码为准；
- `docs/adr/` 记录历史决策，`docs/archive/` 保存历史材料；二者不描述当前实现。

工作时读取与任务有关的入口，检查对应代码。代码与文档不一致时，综合二者并调查，判断是代码缺陷、文档漂移，还是尚未完成的实验。

`Scripts/verification/` 下的检查脚本是第三方，它们把产品模型抄成了自己的常量。脚本与文档互相矛盾时两边都可能已漂移，回到生产代码判断；不要因为某一边跑在设备上就采信它，那是谁在执行，不是谁为真。

`Scripts/verification/verify_documentation_references.py` 在 gauntlet 里强制：文档指向的路径必须存在，计划必须写状态行，被取代的 ADR 必须在 `docs/archive/adr/`。被删除文档的去向登记在 `Config/retired_documents.json`。

## 工具链

项目构建在 Xcode beta5 与同版本 visionOS SDK 上，active developer directory 不在默认的 `/Applications`；以 `xcodebuild -version` 和 `xcode-select -p` 为准。API 可用性与行为取自 Executor 的 `apple_developer_docs`，训练数据通常落后于当前 beta。

Xcode IDE 的工具，包括构建、运行、测试、调试、工程结构读写和 Apple 文档语义检索，有两条到达路径：Executor 的 `xcode_ide_docs_build_debug_device_tools` 直连，以及 XcodeBuildMCP 的 `xcode_ide_call_tool` 代理。两条通向同一批工具，直连把内容内联返回，代理把内容写成 artifact 文件需要再读一次，因此默认走直连。

XcodeBuildMCP 工具承担 Xcode IDE 的缺口：SwiftPM、代码覆盖率、macOS 目标。

两者都由 Xcode 工具链 `mcpbridge` 提供，无需 Xcode 图形界面运行。

## 构建产物

落点由 `Scripts/verification/enchron_artifact_paths.py`（及同名 `.sh`）给出，两个根都从 checkout 派生。脚本取路径时 import 它，不要写绝对路径，`xcodebuild` 的 `-derivedDataPath` 同样从它取。

分层的依据是能不能重新生成：

- `.scratch/` 收一切可重建的东西——DerivedData、SourcePackages、探针输出、日志、生成的 fixture。`zsh Scripts/scratch-prune.zsh` 按保留期（默认 14 天）整目录删除，所以不可重建的东西放进去就是丢了。
- `TestEvidence/` 收真机跑出来的证据，没有头显重建不了。不入库，按主题与日期分目录。
- 结论需要长期被引用时，把可读的报告移入 `docs/archive/acceptance/evidence/<主题>-<日期>/`，这一层入库。录屏与 result bundle 不进这一层。

SwiftPM 自己的 `.build/` 无需干预。

## 验证

端到端调试与回归读取 `.agents/skills/vp-e2e`。默认在 visionOS 模拟器上做；只有模拟器产生不出那个现象时才上物理 Vision Pro，判据与清单在该 skill 里。两条 lane 共用同一个 XCUITest 常驻 runner 与同一个控制器，区别只在传输。

visionOS 的合成输入只有 XCUITest 一条通道，模拟器与真机都是：Xcode 的 Device Interaction 只支持 iOS 与 watchOS 模拟器，XcodeBuildMCP 的 UI 自动化在 visionOS 模拟器上返回空的元素树。 
