# Enchron

Enchron 是 visionOS 产品 App，拥有 SwiftUI 界面、文件浏览、产品状态、播放入口与空间呈现。播放能力来自同级工作区外的独立 `PlaybackCore`；RCP3 场景内容来自 `Xrplay_scene`。

开始工作前依次阅读 `AGENTS.md`、`CONTEXT.md` 与 `ARCHITECTURE.md`。产品原则见 `docs/product_philosophy.md`，行为账本见 `docs/use_cases.md`，架构决策见 `docs/adr/`。

当前迁移阶段仍保留旧的内置 mpv 播放代码以维持工程可编译；新的功能不得继续建立在它上面。完成外部 `PlaybackCore` 的 App Adapter 纵向切片后，再整体删除旧实现与依赖。
