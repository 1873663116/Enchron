# DesignPreview

DesignPreview 是生产组件的代码化展示入口。它使用 `../../Modules` 中各所有者的生产组件与 DesignSystem token；不维护产品导航、平行页面行为或独立 FakeApp。

修改 UI 前先搜索现有生产组件。跨 feature 的外观、交互和动画在 DesignSystem 中修改；feature 特有组件进入其模块；全局视觉值在 `DesignTokens` 中修改；页面特有排列在生产页面中修改。只有现有组件无法表达一个明确的新视觉角色时才新增组件，并在 DesignPreview 中展示。

探索结论被接受后，直接修改生产页面或生产组件，不把探索实现复制成第二份。fixture 只提供组件状态，不得成为产品行为来源。

普通布局、样式、状态和局部交互优先使用 Xcode Canvas 验证。跨 `WindowGroup`、volume、`ImmersiveSpace`、运行时生命周期或真实媒体呈现升级到 Simulator；硬件播放、HDR/EDR、性能和最终空间体验升级到 Vision Pro。

组件的 interface、参数和变体由 Swift 代码、`#Preview` 与测试表达，不建立逐组件 Markdown contract。注释只解释代码无法表达的平台原因或约束。
