---
status: accepted
date: 2026-07-15
---

# Enchron 使用 Apple 官方工具链调试，不建设自定义 CLI

Enchron 的运行时观察、交互式调试和自动化验证使用 Apple 官方工具链：`Logger` / OSLog 提供可实时过滤和事后读取的运行事件，Xcode 与 LLDB 提供断点、变量和调用栈检查，Instruments 与 RealityKit Trace 提供性能证据，XCTest 与 XCUIAutomation 负责操作和断言，`xcodebuild`、`.xcresult` 与 `xcresulttool` 负责脚本执行和结果归档。`.xcresult` 是测试结果证据，不是实时调试通道。当前不建设 Enchron CLI、socket、文件 inbox、网络 bridge、调试界面或第二套状态系统；AppIntentsTesting 当前不可用也不构成自建协议的理由。只有真实回归中反复出现同一个无法由 UI 自动化触发、无法由 XCTest 验证且无法由 OSLog 或 LLDB 诊断的产品语义缺口，才为该缺口重新评估最薄的专用适配器。
