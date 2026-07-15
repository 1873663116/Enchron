---
status: accepted
date: 2026-07-14
---

# Enchron 拥有端到端产品运行时可观测性

Enchron 为每次产品播放启动建立可关联的运行时事实链，覆盖来源授权、启动协调、PlaybackCore Media Session、renderer binding、窗口与沉浸呈现。各模块继续拥有并使用 `Logger` / OSLog 发布自己的事实，Enchron 统一关联标识和阶段语义，不聚合第二份运行时状态，也不复制 PlaybackCore 状态机。性能阶段使用 signpost；运行中的观察与诊断交给 Xcode、LLDB、Console 和 Instruments，自动化判定交给 XCTest 与 XCUIAutomation。日志只记录事件，不能代替测试断言或当前状态证明。
