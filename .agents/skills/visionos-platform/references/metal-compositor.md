# Metal、Compositor Services、自定义 Render Loop

用于 custom Metal rendering、MPV layer output、未来 fully immersive renderer 工作、stereoscopic drawing、Compositor Services、frame timing 和 immersive Metal interaction。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

## 正确判断

- 如果 custom rendering 的原因是 3D video、Spatial Video、APMP 或 Apple Immersive Video，先读 `immersive-media-profiles.md`，并记录这项工作属于当前 mpv-first rendering、diagnostics，还是未来 Apple-native research。
- 用 custom Metal renderer 绘制 fully immersive content 时，使用 Compositor Services。
- `CompositorLayer` 是 custom Metal rendering 的 `ImmersiveSpace` content path。它支持的 immersion behavior 与 OS 版本和配置相关；决定前要在当前 Compositor Services 文档中验证 full、mixed 和 progressive 路径。
- Custom Metal immersive rendering 意味着 app 要拥有 stereoscopic rendering、frame timing 和 compositor contract。
- 如果 RealityKit 能表达这个 scene，优先 RealityKit，再考虑降到 Compositor Services。
- Progressive Metal immersion 需要明确支持当前 Compositor Services progressive-immersion contract。
- 不要把 render-loop 工作放进 SwiftUI body/update churn。

## iOS/macOS 冲突点

- 在 2D window 中能工作的 `MTKView` 或 `CAMetalLayer`，不是完整的 fully-immersive renderer。
- 除非有明确产品理由和所需 scene-role 配置，否则不要直接启动进入 full immersion。
- 不要假设 `CompositorLayer` 总是意味着 full immersion，也不要假设 SwiftUI immersion style modifier 对每种 Compositor Services 配置都有相同效果。
- 不要把 desktop Metal swapchain 假设用于 visionOS compositor 工作。
- 不要把 HDR layer configuration 当成 immersive RealityKit 或 compositor output 正确的充分证据。
- 如果 projection metadata、spatial styling、audio、captions 和 comfort behavior 都在 custom renderer 之外，不要因为 APMP、AIV 或 Spatial Video frame 可解码可绘制就宣称格式支持。

## Enchron 检查点

- Window mode 下的 MPV `CAMetalLayer` output、panorama bridge output，以及任何未来 fully immersive renderer，都应记录为彼此独立的 render contract。
- 当声明的是 visual output 时，HDR/EDR Metal 改动应包含 device verification。
- MPV output 与 RealityKit texture 之间的 compute/copy path 需要明确 color space 和 timing 的 ownership。
- Custom media renderer 需要有理由，并且要绑定到具名 media profile，以及正在研究的当前 mpv 能力或未来平台行为。
