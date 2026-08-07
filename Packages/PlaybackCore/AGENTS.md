# PlaybackCore

PlaybackCore 是 Enchron 仓库内可独立构建和测试的播放模块，不是独立产品。当前模块组成、依赖和测试入口以本目录的 `Package.swift`、`Sources` 与 `Tests` 为准；仓库根 [`ARCHITECTURE.md`](../../ARCHITECTURE.md) 只提供所有权导航。

修改前检查本目录及其 App 适配代码的工作树和调用关系。不要从产品文档推导 sample、时间线、renderer 或并发机制，也不要把未验证实验写成模块合同。需要理解 Apple 媒体框架行为时，先查官方 API 和示例，再用当前代码与最小可复现实验验证。

修改后在本目录运行相关测试。涉及 Enchron App、Apple 平台或物理设备的结果由对应的 App 测试继续验证。
