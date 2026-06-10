# 性能、调试、Simulator、设备

用于 performance planning、Simulator/device 差异、RealityKit render cost、video/HDR validation、thermal/power、Instruments、visual debugging 和 QA evidence。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Creating a performance plan for visionOS app" "RealityKit Trace"`
  用于 performance planning。
- `"Analyzing the performance of your visionOS app" "Instruments"`
  用于 profiling workflow。
- `"Understanding the visionOS render pipeline" "render server" "compositor"`
  用于 render-pipeline ownership。
- `"Reducing the rendering cost of RealityKit content on visionOS"`
  用于 RealityKit-specific render-cost guidance。
- `"Diagnosing issues in the appearance of your running app" "Xcode"`
  用于 visual debugging workflow。
- `"Running your app in Simulator or on a device" "visionOS"`
  用于 Simulator/device gaps。
- `"Interacting with your app in the visionOS Simulator"`
  用于 Simulator interaction workflow。

## 正确判断

- Simulator 有用，但它不是 rendering、input、audio/video、hardware features、HDR 或 thermal behavior 的权威证据。
- 性能声明要在 physical device 上 profile。
- 跟踪 launch/load time、responsiveness/latency、render frame pacing、power、memory、network 和 task efficiency。
- Shared Space 和 Full Space 有不同的 performance/coexistence profile。当功能可运行在两个 context 中时，两者都要测试。
- Multi-app coexistence 是 Shared Space performance model 的一部分。不要假设 Enchron 在 Full Space 之外拥有全部 render 或 attention budget。
- Background 或 inactive scene state 不一定意味着用户看不到或听不到相关 app 内容。要有意识地保存状态并减少工作。
- RealityKit render-server stalls 和 entity commits 是一等性能问题。
- 对 RealityKit/render-server bottleneck、commits、dropped frames、high power use、animation、physics 和 spatial systems，使用 RealityKit Trace template。
- 用 visionOS render-pipeline 文档判断 bottleneck 位于 app main-thread work、RealityKit/Core Animation commits、render server、compositor，还是 Metal/Compositor Services frame submission。
- 需要时用 visible axes、bounds、overlays 或临时 diagnostic entities 调试 immersive placement。
- Immersive media profile 声明需要 device check，尤其是 comfort mitigation、spatial audio、captions/subtitles、power 和 long-viewing behavior。
- 性能声明使用接近 release 的配置；Debug build 用于功能诊断。

## iOS/macOS 冲突点

- 不要把“Simulator 中可用”当成 spatial、video、HDR 或 performance 路径在设备上正确的证据。
- 不要只根据 Debug-build metrics 做优化。
- 不要忽视 thermal pressure；Apple 文档说明当资源使用把设备推过限制时，会有用户可见影响。
- 不要把 2D layout inspection 当成 immersive content 的充分检查。
- 不要因为短暂 Simulator playback 能启动，就把 APMP、Apple Immersive Video、Spatial Video 或 high-motion immersive playback 视为已验证。
- 不要假设 macOS desktop profiling 信号能直接映射到 Vision Pro comfort 或 spatial frame pacing。
- 不要只通过 RealityKit 信号 profile Compositor Services 工作；Metal immersive rendering 需要 Metal/compositor timing 证据。

## Enchron 检查点

- UI-only 改动通常可以用 build 加 visual review 验证。
- HDR、MPV Metal output、RealityKit texture bridge 和 immersive scene 声明需要明确 Simulator/device risk notes。
- 即使 docs 和 builds 都通过，APMP、Apple Immersive Video、Spatial Video 和 custom immersive video paths 仍需要 human headset verification notes。
- QA report 应区分 automated verification 和 human headset checks。
