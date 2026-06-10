# RealityKit、SpatialScene、Volume、虚拟屏幕

用于 `SpatialScene`、`RealityView`、RealityKit entities、attachments、panoramas、virtual screens、environment domes、volumes 和 immersive scene presentation。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Adding 3D content to your app" "visionOS" "RealityView"`
  用于文章级 scene setup path。
- `"Playing immersive media with RealityKit" "desiredImmersiveViewingMode"`
  用于 immersive-media walkthrough。

### 官方 Web fallback

- WWDC25 287 `What is new in RealityKit`
- `https://developer.apple.com/design/human-interface-guidelines/spatial-layout/`
- `https://developer.apple.com/design/human-interface-guidelines/immersive-experiences`

## 正确判断

- UI-centric 2D 工作使用 window。
- 用户需要从多个角度查看的有边界 3D object 使用 volume。
- 无边界 spatial experience 使用 immersive space。
- 2D window 内的 3D content 可能被裁切；如果内容主要是 3D，考虑 volume。
- 初始 RealityKit content creation 放在 `RealityView` make closure 中。对 state-driven 和 per-frame 变化，使用可选 update closure、RealityKit systems 或 scene update events，不要因 SwiftUI body churn 反复重建昂贵的 RealityKit state。
- RealityKit interaction 需要正确组件：targeted SwiftUI gesture、`InputTargetComponent` 和 collision shapes。
- 属于 RealityKit content 的 SwiftUI controls 使用 attachments。
- 未来 Apple-native immersive media research 中，同时考虑 `VideoPlayerComponent` 和 `VideoMaterial`。`VideoPlayerComponent` 是 RealityKit 中 immersive media controls、viewing modes、captions/subtitles、passthrough tinting 和 transition events 的路径。
- 在 RealityKit 中处理 APMP、Apple Immersive Video 和 Spatial Video 时，先读 `immersive-media-profiles.md`。`VideoPlayerComponent` 是系统理解的 immersive media profile 的核心 RealityKit route，不是 `VideoMaterial` 的小替代技巧。
- Progressive 或 full immersive playback 中，`desiredImmersiveViewingMode` 必须与 SwiftUI `ImmersionStyle` 匹配。把 portal、progressive 和 full 当成行为与舒适度选择，而不仅是视觉样式。
- Attachments 可以通过 `RealityView` attachments closure 创建，也可以通过 `ViewAttachmentComponent` 等 component-based API 创建；选择与本地代码和 OS target 匹配的当前 API。
- 在 immersive space 中显式设置 transform 和 position。不要依赖未经检查的 origin。

## iOS/macOS 冲突点

- 不要默认从 iOS 带入 `ARView` / `ARSCNView` 显示习惯。在 visionOS 中，SwiftUI 和 RealityKit 是 presentation model；ARKit 在需要时提供 sensing data。
- 不要把每个 spatial feature 都做成 immersive space。
- 不要因为更“空间化”就把密集 2D controls 做进 volume。
- 不要把大型 UI anchor 到用户头部；Apple 警告 head-anchored content 可能让人感到受困。
- 不要用明亮运动或高对比动画填满 peripheral vision。
- 不要把 RealityKit setup 放进 SwiftUI body-driven code path。
- 不要假设 “RealityKit video” 只意味着 `VideoMaterial`。
- 不要只凭 generic texture 就宣称 APMP、Apple Immersive Video 或 Spatial Video production support。要说明工作属于当前 mpv-first rendering、diagnostics，还是未来 Apple-native research。
- 不要把 progressive RealityKit video 与 non-progressive `ImmersionStyle` 组合。

## Enchron 检查点

- `SpatialScene` 拥有 spatial presentation，不拥有 non-spatial playback control。
- Virtual-screen geometry 和保存的位置应具有物理意义，而不是任意 2D layout constants。
- Panorama 和 virtual-screen 路径应明确说明它们的 surface：RealityKit material/texture、volume、immersive space 或 future compositor。
- Immersive media 工作应说明它使用的是当前 mpv-first texture bridging、diagnostics、未来 AVKit / RealityKit `VideoPlayerComponent` research、`VideoMaterial`，还是 future Compositor Services。
- 如果任务触及 APMP、Apple Immersive Video、Spatial Video 或 3D media playback，在选择 RealityKit API 或复用现有 panorama sphere 路径前，先回答 media profile 问题。
