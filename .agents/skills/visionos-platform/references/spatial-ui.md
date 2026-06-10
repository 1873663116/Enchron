# Spatial UI、SwiftUI Controls、Gaze、Ornaments

用于 `PlayerUI`、`DesignPreview`、`Shared/DesignSystem`、`Settings`、SwiftUI controls、gaze hover、ornaments、spatial layout、menus、buttons、sliders、accessibility 和 component behavior。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Improving accessibility support in your visionOS app" "accessibilityLabel"`
  用于 visionOS-specific accessibility 文章指导。

### 官方 Web fallback

- `https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos/`
- `https://developer.apple.com/design/human-interface-guidelines/spatial-layout/`
- `https://developer.apple.com/design/human-interface-guidelines/eyes`
- `https://developer.apple.com/design/human-interface-guidelines/gestures`
- `https://developer.apple.com/design/human-interface-guidelines/buttons`
- `https://developer.apple.com/design/human-interface-guidelines/windows`
- `https://developer.apple.com/design/human-interface-guidelines/ornaments`
- `https://developer.apple.com/design/human-interface-guidelines/going-full-screen`

## 正确判断

- visionOS primary interaction 是系统中介的 gaze/focus 加 indirect gesture。App code 接收 semantic interaction signals，而不是 raw gaze。
- Standard controls 带有 custom gestures 没有的平台行为。
- 除非交互确实需要 custom gesture data，否则优先 `Button`、`Toggle`、`Slider`、`TabView`、toolbars、menus 和 sheets。
- Hit regions 需要 visionOS spacing。Target size 和 spacing 使用 Apple HIG 值；不要继承 iOS-only target 假设。
- 用 `hoverEffect` 和 `contentShape(.hoverEffect, shape)` 定义 SwiftUI focus 或 gaze affordance。
- 保持 controls semantic。Custom hover effects 可以使用，但必须通过 SwiftUI hover APIs 或 button styles 实现，并保留 hit region、focus behavior、accessibility 和 comfort。
- 把 `onHover` 当成 pointer-style behavior。它不是 gaze API；成为产品行为前需要 device verification。
- RealityKit hover effects、targeted gestures、`GestureComponent` 和 `ManipulationComponent` 是 entity interaction layers。不要用它们替代标准 SwiftUI controls。
- Interactive RealityKit entities 需要清晰 input path：input target、collision shape、gesture 或 component interaction；如果可被发现或激活，还需要 accessibility metadata。
- Spatial accessories 和 Apple Pencil 相关 API 需要当前 availability 和 device-support checks。不要一概接受或拒绝。
- Toolbars 和 tab bars 在 visionOS 中可以成为 ornaments。Custom ornaments 用于与 window 相关、应该保持在附近但不挤占内容的 controls。
- Glass shape、clip shape、content shape 和 hit region 需要有意对齐。
- 明确 SwiftUI points、RealityKit meters、ARKit/world space 和 entity-local coordinates。跨 2D/3D surface 时使用官方 conversion APIs，不要用手调 layout constants。
- 避免让视觉密度像漂浮在空间里的 desktop chrome。

## iOS/macOS 冲突点

- Pointer hover 和 gaze hover 是不同交互。
- `onHover` 不是 raw gaze，也不能证明 headset gaze behavior。
- 44 pt touch target 不足以作为默认 visionOS target。
- `TapGesture` 不是 semantic `Button`；gesture 用于非按钮交互，或 location data 必不可少的场景。
- 不要为了 custom hover 外观把 semantic `Button` 换成 raw gesture。先保留系统语义，再做自定义。
- 不要为了装饰给文本加 depth。Depth 可能降低可读性和舒适度。
- 不要盲目导入密集 macOS sidebar/inspector。Spatial layout 重视 comfort 和 field-of-view discipline，高于 desktop information density。
- 不要假设每种 iPad-style popover/sheet layout 在 spatial window 中都舒适。
- 不要把 RealityKit `ManipulationComponent` 或 hand tracking 用于普通播放控件；这些控件应继续是 semantic buttons、sliders 或 menus。

## Enchron 检查点

- `DesignTokens` 仍然是 style values、spacing、animation 和 press feedback 的来源。
- Component-library 改动在新增 shape 前，应对照 `DesignPreview/AGENTS.md` 和现有 components。
- Window 和 immersive playback 共享的 controls 应为两个 surface 设计，而不是只优化 window path。
- 对 custom RealityKit controls，说明交互使用 SwiftUI targeted gestures、`GestureComponent`、`ManipulationComponent` 还是其他 component path。
- 用 `accessibilityIdentifier` 做测试定位。Icon-only 或 custom controls 使用显式 label，text controls 验证派生 label，并为非标准 playback controls 添加 accessibility actions。
- 对可被发现或激活的 RealityKit entities，添加合适的 `AccessibilityComponent` metadata，并用 VoiceOver 或文档化 assistive features 测试。
