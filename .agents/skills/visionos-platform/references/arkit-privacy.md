# ARKit、传感器、隐私、世界理解

用于 ARKit 数据访问、world/scene/hand tracking、真实世界周边、相机访问、传感器隐私，以及任何询问用户正在做什么或真实世界物体在哪里的功能。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Adopting best practices for privacy" "visionOS" "ARKit"`
  用于平台隐私和用户偏好指导。
- `"Setting up access to ARKit data" "requiredAuthorizations"`
  用于 provider 授权设置。
- `"Bringing your ARKit app to visionOS" "Full Space"`
  用于迁移指导。
- `"Incorporating real-world surroundings in an immersive experience" "visionOS"`
  用于周边环境和 scene-sensing 指导。
- `"Tracking points in world space" "visionOS"`
  用于 world-space tracking 指导。
- `"Accessing the main camera" "visionOS" "enterprise"`
  用于相机 entitlement 约束。

### 官方 Web fallback

- WWDC25 287 `What is new in RealityKit`

## 正确判断

- 标准 gaze 和 hand input 不会向 app 暴露原始 gaze/hand position。普通输入中的私密传感器数据由系统处理。
- 普通交互优先使用标准 SwiftUI/UIKit event handling。
- 只有系统交互模型无法表达功能时，才请求 ARKit 数据。
- 大多数 world、hand 和 scene-sensing ARKit provider 需要 Full Space presentation，但规则是 provider-specific 的。要在当前 Apple 文档中逐个确认 provider 的 presentation context、support check 和 authorization requirement。
- 描述可用性时使用 "Full Space"、"presentation context" 和精确 provider 名称。不要把 "immersive space" 松散地当作所有 sensing requirement 的同义词。
- RealityKit `SpatialTrackingSession` 和高层 anchoring API 可以提供 RealityKit 形态的 ARKit 数据路径。只要涉及敏感数据，它们仍然需要 capability check、authorization handling 和 fallback story。
- 请求敏感数据前，添加 provider-specific usage description。
- 检查 provider-specific `requiredAuthorizations`；不要猜。
- 对被拒绝和后续被撤销的授权提供可用 fallback。
- 主相机访问是 enterprise entitlement 路径，不是通用 app 能力。

## iOS/macOS 冲突点

- 不要假设 app 可以读取用户正在看哪里。
- 不要用 hand tracking 实现普通按钮点击、slider 或 selection。
- 不要把 iOS ARKit 当成显示栈。visionOS ARKit 主要用于 sensing/world data；presentation 属于 SwiftUI、RealityKit 或 Compositor Services。
- 不要把 RealityKit 访问路径当成隐私降级或权限绕过。
- 不要发布一个在 ARKit 授权被拒绝时没有 fallback 的核心 UI 功能。
- 不要从相似 provider 名称推断权限要求。要查当前 Apple 文档中的精确 provider。
- 不要假设每个 ARKit provider 都只能在 Full Space 使用。Accessory tracking 和未来 provider-specific API 可能有不同 presentation 约束。

## Enchron 检查点

- Enchron 播放控件应首先通过标准输入工作。
- Scene positioning 和 screen placement 可以使用 spatial state，但添加 ARKit provider 前必须明确隐私边界。
- 任何未来 world-aware scene 功能都需要先有 permission/fallback story，再进入实现。
- Provider adoption 应命名精确 provider、`isSupported` 行为、authorization type、presentation surface，以及 Simulator/device 支持。
- 采用 RealityKit `SpatialTrackingSession` 时，应命名 tracked anchors 或 scene-understanding capabilities、unavailable-capability 行为、authorization 行为，以及是否需要手动 `ARKitSession` 访问。
