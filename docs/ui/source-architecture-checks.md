# UI 源码架构检查

Enchron 的 UI 源码按职责形成四层。Token 数值层位于 `Modules/DesignSystem/DesignTokens.swift`，只表达颜色、间距、圆角、字体、尺寸和动效等视觉值。生产组件结构层位于 `Modules/DesignSystem` 与各 feature 模块，拥有可复用 View、交互、样式以及 `Card.folder(...)` 这类具名变体工厂。页面组合层位于生产页面，只选择生产组件、排列页面并绑定产品状态。DesignPreview 陈列层位于 `Apps/DesignPreview`，只提供确定性的 fixture 状态和陈列排列，不定义生产样式、组件变体或平行业务界面。

`Scripts/verification/verify_design_source_architecture.py` 对 Swift 类型系统尚未覆盖的关系执行快速源码检查。它阻止 `DesignTokens.swift` 新增 View、`ViewBuilder`、Shape 或样式实现；阻止 DesignPreview 新增 `ButtonStyle`、`ToggleStyle`、`ViewModifier`、Shape 等平行视觉类型；阻止陈列文件扩展生产类型、直接创建新的原生交互控件，或使用新的视觉数值字面量；同时要求新增的 DesignPreview View 文件至少导入一个生产模块。Token 专用陈列、App 壳和通用预览舞台不按组件陈列文件处理，因为它们只负责显示 token 或承载预览，而不表达产品组件。

检查失败时输出 `file:line: error: [rule] message` 并返回非零状态。Enchron 与 DesignPreview 的 Xcode Target 在编译源码前运行同一检查；已有的 `verify_package_membership.py` 和 `verify_organic_architecture_xcode.sh` 也会经过它。因此本地产品构建和使用现有架构验证入口的 CI 得到相同结果。Xcode User Script Sandbox 模式通过 `SCRIPT_INPUT_FILE_*` 只读取 Build Phase 逐项声明的 DesignPreview Swift 文件、`DesignTokens.swift`、基线和检查脚本，不扫描 `Assets.xcassets` 等资源目录；普通 CLI/CI 模式仍发现全部 DesignPreview Swift 文件，并检查两个 Build Phase 的显式 Swift 输入与磁盘源码完全一致。新增 Swift 文件而没有同步构建输入会使仓库级检查失败。只运行一个与产品构建无关的任意命令不构成 Enchron 验证入口，也不宣称执行了这项检查。

当前历史违规记录在 `Config/design_source_architecture_baseline.json`。每项 allowance 由规则、文件、规范化后的源码行和允许出现次数共同确定，不是目录通配符；相同行为增加一次就会失败。历史代码被修复后，检查会以 `baseline-stale` 要求同步缩小基线，不能把空出的 allowance 留给未来代码。除非是在确认现有历史事实后建立或收缩基线，不得用 `--write-baseline` 处理普通失败。

轻量验证命令为：

```sh
python3 Scripts/verification/verify_design_source_architecture.py
python3 -m unittest Tests.Infrastructure.test_design_source_architecture
python3 Scripts/verification/verify_package_membership.py
```

这项检查不是 Swift 语法分析器，也不能判断两个外观近似的 View 是否在语义上复制了同一产品组件。它不能证明 fixture 没有藏入业务状态机，不能判断一个硬编码数值是否恰好等于 token，也不能阻止开发者把错误结构先放进生产模块再由 DesignPreview 调用。Target 依赖、访问控制、代码审查、生产组件测试和运行时验收仍分别负责这些边界；源码检查只负责稳定、可机械定位且适合在每次构建前执行的最小规则。
