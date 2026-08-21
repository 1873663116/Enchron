# Hover 区域审计与统一修复

本次审计以 `defaf38792528a62b3712654a04cce9f067f8381` 为基准，覆盖 `Modules/DesignSystem/**`、`Modules/PlaybackPresentation/Views/**`、`Modules/MediaLibrary/**` 与 `Apps/Enchron/**` 的 65 个生产 Swift 文件，共检查 90 个 `Button` 或 `Menu` 控件。审计确认 10 个实现点会让 hover 高亮跟随扩大的注视命中区，而不是停在按钮的视觉范围。

## 判据

Apple beta5 SDK 的文档把 `ContentShapeKinds.hoverEffect` 定义为 hover effect 的预览形状，把 `ContentShapeKinds.interaction` 定义为命中测试形状；不带 kind 的 `contentShape` 走交互形状。由此，本次把下面三个条件同时成立的控件判为问题：

1. 按钮标签或菜单标签已经声明视觉 hover 形状，或者通过 Enchron 的 glass modifier 同时声明视觉 hover 形状和效果。
2. 外层 `Button` 或 `Menu` 随后通过 `frame`、`padding` 或通用 `contentShape` 把交互范围扩到更大的目标尺寸。
3. 扩大之后没有重新声明仅作用于 `.hoverEffect` 的视觉形状。

这个判据保留较大的 `.interaction` 范围，只检查 hover 是否在扩大后重新收束。Apple 文档入口为：

- <https://developer.apple.com/documentation/swiftui/view/contentshape(_:_:eofill:)>
- <https://developer.apple.com/documentation/swiftui/contentshapekinds/hovereffect>
- <https://developer.apple.com/documentation/swiftui/contentshapekinds/interaction>

`View+EnchronGlass.swift` 原注释所称“四层形状永远一致”只在 modifier 当时的 bounds 内成立。调用点后续增加外层 frame 或 padding 后，clip 和 glass 仍属于内层视觉视图，Button 的交互与默认 hover 却可以属于更大的外层，所以原声称对这些调用点不成立。

## 审计结果

下表的行号是基准 `defaf387` 中实际的 `Button` 或 `Menu` 起始行。最后一列给出修复后重新收束 hover 的位置。

| 控件实现 | 基准位置 | 扩大方式 | 修复位置 |
| --- | --- | --- | --- |
| `GlassCapsuleIconLabelButton` | `Modules/DesignSystem/Components/SettingsComponents.swift:107` | 视觉高度为 `Interactive.regular`，外层垂直 padding 扩到 `Interactive.large` | 同文件第 126 行 |
| `GlassCircleIconButton` | `Modules/DesignSystem/Components/SettingsComponents.swift:316` | `visualSize` 圆位于 `targetSize` 圆形命中区内 | 同文件第 347 行 |
| `GlassCircleIconMenu` | `Modules/DesignSystem/Components/SettingsComponents.swift:524` | `visualSize` 圆位于 `targetSize` 圆形命中区内 | 同文件第 559 行 |
| `SettingListGroupRow` 的 menu accessory | `Modules/DesignSystem/Components/SettingsComponents.swift:1134` | `Interactive.compact` 胶囊标签位于最小高度 `Interactive.large` 的菜单内 | 同文件第 1185 行 |
| `SettingListAccessoryButton` | `Modules/DesignSystem/Components/SettingsComponents.swift:1620` | 通用标签实际为 `SettingListActionChip`，其 `Interactive.compact` 胶囊位于最小高度 `Interactive.large` 的按钮内 | 同文件第 1661 行 |
| `GlassToggle` | `Modules/DesignSystem/Components/InputComponents.swift:106` | 50×30 的视觉胶囊通过水平和垂直 padding 扩到 large 命中范围 | 同文件第 129 行 |
| `BoundGlassToggle` | `Modules/DesignSystem/Components/InputComponents.swift:142` | 50×30 的视觉胶囊通过水平和垂直 padding 扩到 large 命中范围 | 同文件第 176 行 |
| `AnimatedDirectionalIconButton` | `Modules/DesignSystem/Components/AnimatedDirectionalIconButton.swift:47` | `visualSize` 圆位于 `targetSize` 圆形命中区内 | 同文件第 61 行 |
| `AppearanceModeButton` | `Modules/DesignSystem/Components/AppearanceModeButton.swift:30` | `visualSize` 圆位于 `targetSize` 圆形命中区内 | 同文件第 54 行 |
| `PlaybackTopSecondaryPanelButton` | `Modules/PlaybackPresentation/Views/PlaybackTopActions.swift:698` | `Interactive.regular` 圆位于 `Interactive.large` 圆形命中区内 | 同文件第 713 行 |

检查器还保留两个需要人工判断的项目。基准与修复后都存在这两项，因此它们没有被修复掩盖：

- `SettingsComponents.swift:1347`，修复后为第 1383 行。这里的 `SettingListCardSelectionCard` 只先固定高度，外层 `frame(width: cardWidth)` 同时向卡片视觉 shape 提供宽度，并没有在较小卡片周围增加空白命中边。
- `Modules/MediaLibrary/Views/BreadcrumbView.swift:24`。这里的显式 `.enchronHoverEffect(.lift)` 位于 60×60 frame 之前，后面的 `.contentShape(.rect)` 是交互形状；源码中没有“内层显式 hover 加外层 Button 默认 hover”的双层结构。

`Apps/Enchron/MainView.swift` 与 `Modules/PlaybackPresentation/Views/PlaybackPanel.swift` 没有发现满足上述判据的问题，且本提交没有修改这两个文件。

## 统一修复

`Modules/DesignSystem/View+Platform.swift` 新增 `EnchronInsetHoverShape`，并为 `enchronHoverContentShape` 增加接收 `EdgeInsets` 的重载。调用点在扩大交互范围之后声明一次视觉 shape 和视觉边距。重载把外层 bounds 映射回内层视觉矩形，再只写入 `.hoverEffect` content shape。

这对 10 个实现点采用同一套规则。圆形控件四边使用 `(targetSize - visualSize) / 2`，只扩大高度的胶囊只设置上下边距，Toggle 使用现有水平和垂直 padding。原有 frame、padding、ButtonStyle、通用 `contentShape` 与 `.interaction` 声明均未删除或移动，因此扩大的注视命中区和按压反馈测量范围保持不变。

代价是各调用点仍需写出视觉尺寸与目标尺寸的差值，因为只有调用点知道这两个尺寸；shape 的坐标换算和 content-shape kind 决策集中在 `View+Platform.swift`。没有采用外层 `hoverEffectDisabled`，因为 Apple 文档规定祖先禁用会覆盖后代，连内层明确配置的视觉 hover 也会一起关闭。

`View+EnchronGlass.swift` 的文档同时改为准确约束：四层 shape 只在 modifier 当前 bounds 内一致，后续扩大交互 bounds 的包装器必须调用带 insets 的重载。

## 可重复检查

运行：

```sh
Scripts/verification/check_hover_region_clipping.py
```

脚本会先运行内置的违规、已修复、同尺寸三组自测，再扫描四个生产目录。确定违规会返回状态 1；无法仅靠源码尺寸规则确定的布局进入人工判断清单，不会伪装成零误报。

在 `defaf387` 的临时导出上运行，结果是 9 个确定违规和 3 个待判断项。逐项读取通用标签的调用方后，`SettingListAccessoryButton` 是第 10 个实际问题；另两个待判断项如上所述不满足问题判据。

修复后原样运行的输出是：

```text
Scanned 65 production Swift files and 90 Button/Menu controls.
Confirmed violations: 0
Human-review candidates: 2
  Modules/DesignSystem/Components/SettingsComponents.swift:1383: Button: visual hover declaration precedes layout growth that the high-confidence size rules cannot classify
  Modules/MediaLibrary/Views/BreadcrumbView.swift:24: Button: hover effect precedes a larger layout, but the source does not declare a visual hover content shape
```

脚本是源码结构检查器，不是 Swift 语义分析器。它对已知尺寸 token、`targetSize` 和通用标签包装器给出确定结果，对任意动态布局保留人工判断项。

## 验证与证据边界

当前工具链为 `/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer`，`xcodebuild -version` 返回 Xcode 27.0、build 27A5237l。

以下检查通过：

- `git diff --check`
- `Scripts/verification/check_hover_region_clipping.py`
- `python3 Scripts/verification/verify_design_source_architecture.py`
- `swift build --target DesignSystem --triple arm64-apple-xros27.0 --sdk "$(xcrun --sdk xros --show-sdk-path)" --scratch-path /Volumes/Cortisol/BuildArtifacts/Enchron-hover-clipping-swiftpm`
- `xcodebuild -project Enchron.xcodeproj -scheme DesignPreview -destination 'generic/platform=visionOS' -derivedDataPath /Volumes/Cortisol/BuildArtifacts/Enchron-hover-clipping-xcode CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project Enchron.xcodeproj -scheme Enchron -destination 'generic/platform=visionOS' -derivedDataPath /Volumes/Cortisol/BuildArtifacts/Enchron-hover-clipping-xcode CODE_SIGNING_ALLOWED=NO build`
- `git diff --exit-code defaf387 -- Apps/Enchron/MainView.swift Modules/PlaybackPresentation/Views/PlaybackPanel.swift`

两条 Xcode 构建都返回 `** BUILD SUCCEEDED **`。这个独立 worktree 缺少 gitignored 的 `PlaybackFFmpeg.xcframework`，构建时临时链接了主 checkout 已有的同路径产物；构建结束后已移除链接，工作树没有留下该依赖改动。

没有启动 visionOS 模拟器，也没有连接或操作物理 Vision Pro。DesignPreview 构建编译了预览宿主与相关 `#Preview` 源码，但没有在禁止启动模拟器的条件下渲染 Xcode Canvas。因此，佩戴者实际看到的注视高亮像素、Canvas 视觉结果与物理设备上的 gaze 命中行为都未验证；本报告只主张源码结构、检查脚本和编译证据。
