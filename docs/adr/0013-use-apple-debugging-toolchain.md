---
status: accepted
date: 2026-07-15
amended: 2026-08-08
---

# Enchron 使用 Apple 官方工具链调试，不建设自定义 CLI

Enchron 的运行时观察、交互式调试和自动化验证使用 Apple 官方工具链：`Logger` / OSLog 提供可实时过滤和事后读取的运行事件，Xcode 与 LLDB 提供断点、变量和调用栈检查，Instruments 与 RealityKit Trace 提供性能证据，XCTest 与 XCUIAutomation 负责操作和断言，`xcodebuild`、`.xcresult` 与 `xcresulttool` 负责脚本执行和结果归档。

物理设备上的运行时单步决策由常驻 XCUITest runner 执行。测试基础设施可以在 Mac 控制器与 runner 的测试数据容器之间使用最薄的临时命令传输，并在会话结束后由 `.xcresult` 提供录屏和结果证据；这条通道只属于测试 Target，不进入生产 App，也不承载产品状态。

Enchron 不建设由生产 App 承担的 CLI、socket、文件 inbox、网络 bridge、调试界面或第二套状态系统。AppIntentsTesting 当前不可用也不构成产品自建控制协议的理由。只有真实设备工作无法由 UI 自动化触发、无法由 XCTest 验证且无法由 OSLog 或 LLDB 诊断时，才为该缺口重新评估最薄的测试专用适配器。
