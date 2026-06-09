# App 场景、窗口、Volume、Immersive Space

用于 `XrPlayer/App`、`MainView`、`AppModel`、`DesignPreviewApp`、scene
声明、窗口打开、immersive-space 打开、默认尺寸、启动行为、恢复和摆放。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Presenting windows and spaces" "visionOS" "WindowGroup" "ImmersiveSpace"`
  用于查找文章级窗口/space 生命周期指导。
- `"Positioning and sizing windows" "visionOS" "defaultWindowPlacement"`
  用于查找文章级摆放和尺寸指导。
- `"Creating SwiftUI windows in visionOS" "openWindow" "WindowGroup"`
  用于查找当前 visionOS 窗口创建示例。
- `"Adopting best practices for scene restoration" "visionOS"`
  用于查找持久 UI 和恢复指导。

### 官方 Web fallback

- WWDC25 290 `Set the scene with SwiftUI in visionOS`

## 正确判断

- 标准 window 用于有边界的 2D app UI。
- Volume 是带 `.windowStyle(.volumetric)` 的 `WindowGroup`，用于用户可从多个角度查看的有边界 3D 内容。
- `ImmersiveSpace` 用于由 app 控制的无边界空间内容。
- `Window` scene 不支持 volumetric window style。
- 没有检查项目 deployment target 和当前 SwiftUI scene API 前，不要对 volume 尺寸或摆放做绝对判断。围绕固定 volume 尺寸的旧指导，可能已经不能完整描述较新的 visionOS scene 能力。
- 第一个窗口的启动和大部分摆放由系统拥有。不要把产品逻辑建立在 app 可控制屏幕坐标的假设上。
- visionOS 26 为启动行为、恢复、把 window 或 volume 锁定在物理空间、unique windows 增加了 scene 生命周期和 persistent UI API。只有当目标系统和产品行为确实需要 persistent scene 时才使用它们。
- visionOS 26 的 volume 能力包括 surface snapping 和 clipping margins。当 Apple 文档要求权限或支持检查时，把 snapped-surface 细节视为 ARKit 或 capability-gated 数据。
- Scene bridging 允许 UIKit 生命周期 app 请求 SwiftUI window、volume 或 immersive space。它是迁移桥梁，不是让 Enchron 变成 view-controller-first 架构的理由。
- `openImmersiveSpace` 是异步的，并且有成功、失败、取消结果。
- 同一时间只能打开一个 immersive space。
- `dismissImmersiveSpace` 没有 id，因为同时只能存在一个 immersive space。
- 如果没有声明 immersive style，mixed 是默认样式。
- Scene restoration 可以重新打开有意义的窗口；对临时窗口应抑制恢复，只恢复用户拥有的空间上下文。
- 当窗口由用户拥有的数据标识时，例如 library item、source、playlist 或 preview context，使用基于值的 `WindowGroup` 和 `openWindow(value:)`。默认不要把这种身份集中到全局 app state。

## iOS/macOS 冲突点

- 不要为播放设计经典 iOS/macOS full-screen 路径。使用更大的 window、AVKit expanded experience、volume 或 immersion。
- 不要期待 app 代码在呈现之后移动或调整窗口尺寸。
- 不要假设旧版 volume 行为就是完整平台契约。依赖较新的 locking、snapping、clipping 或 bridging 行为前先检查可用性。
- 不要用 macOS 屏幕坐标心智模型理解首次启动。
- 不要把 `openImmersiveSpace` 调用散落在各个 feature view 中。保持一条协调过的生命周期路径，以处理一次一个 space 的行为。
- 不要把 volume 建模成“更大的窗口”或看起来 3D 的 card。
- 除非内容本身是空间性的，否则不要把 volume 用于密集 2D 设置或 library 导航。
- 不要把 scene bridging 当成把 UIKit 生命周期假设引入产品架构的许可。
- 当 SwiftUI scene values 能解决问题时，不要发明手写 scene identity/restoration。

## Enchron 检查点

- 除非架构被刻意改变，`MainView` 应继续作为实际调用 `openImmersiveSpace` / `dismissImmersiveSpace` 的规范位置。
- Feature view 应通过 app state 或 coordinator 请求 immersive 状态变化。
- `DesignPreview` 的 window shell 应使用真实 `WindowGroup` scene settings 做 scene 级审查，而不是在 Canvas 里伪造大型圆角矩形。
- Enchron 的主播放器 UI 仍然是 window surface；immersive playback 仍然是 `ImmersiveSpace`。未来的 volume 应保留给真正具有 3D 或空间语义的内容，而不是密集设置、library 列表或控制面板。
