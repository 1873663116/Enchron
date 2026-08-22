# Enchron 物理 Vision Pro UI 测试

本文件补充 Enchron 当前测试通道的项目约束。

/Users/xiongzhipeng/Desktop/TestMedia 与 /Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia 是同一份文件，但桌面的 TestMedia 经过 iCloud 上传，可能会留下空路径，这是一种正常情况。文件名相同就代表了它们是相同的文件。
上传到 iCloud 中，Enchron 因此可以直接导入 test media。

本目录通过公开产品界面验证 Enchron 在物理 Vision Pro 上的用户结果。具体场景、操作、断言和执行组合由当前 XCTest 源码与选用的 `.xctestplan` 表达。

## 默认入口：端到端调试

/vp-e2e

## 稳定回归准入

回归集的 xcui 脚本用于节省时间，根据情况判断并提升。
只有 Agent 请求和用户共同确认一项行为和操作路径已经稳定，并且同意将其作为重复验收项目时，才新增或扩大预编排 XCTest 及其 `.xctestplan` 选择。未获得该共同确认时，继续把运行结果作为交互式调试证据处理，不创建回归项目。

稳定回归预先定义操作和断言，并归档 `.xcresult`、截图、录屏及相应的派生证据。它与交互式调试共享 XCUIAutomation 和产品 Accessibility 接口。
