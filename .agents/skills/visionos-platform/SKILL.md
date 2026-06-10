---
name: visionos-platform
description: 用于 Enchron/XrPlayer 中触及 visionOS-specific Swift、SwiftUI、RealityKit、Reality Composer Pro、Shader Graph、Metal、ARKit、AVKit/video playback、scene/window lifecycle、spatial interaction、privacy、performance、networking、persistence，或任何 iOS/macOS Swift 直觉可能与 Apple Vision Pro 行为冲突的工作。这是平台判断指南：先用官方 Xcode DocumentationSearch（MCP）获取 Apple 事实，再按 visionOS surface 和 Enchron 边界过滤。
---

# visionOS 平台判断指南

这个 skill 防止 iOS/macOS 习惯静悄悄变成 Enchron 的 visionOS 决策。它是判断指南，不是 checklist，也不是静态 Apple-docs router。

用它保持几个正确的“方向盘”始终可见：

- 证据方向：Apple 平台事实先来自官方 Xcode DocumentationSearch（MCP），再考虑记忆；
- 探索方式：陌生领域先 broad，已知 API 可直接 search，命中后必须读上下文；
- 平台过滤：Apple docs 覆盖多个平台，命中并不自动等于 visionOS 结论；
- 项目过滤：读完 Apple docs 后，回到 Enchron 的 module、surface、architecture boundary 和 verification risk；
- 轻量逃生口：小、明显、可逆的工作应保持轻量。

## 核心规则

当 Apple platform behavior、API availability、rendering、privacy、media/HDR、ARKit permissions、performance、lifecycle 或 compatibility 事实重要时，优先使用官方 Xcode `DocumentationSearch`（`mcp__xcode__DocumentationSearch`），而不是凭记忆或泛化 web 搜索。

搜索结果是候选入口，不是结论。依赖结果前，先下钻 doc 详情页或命中的项目代码。

如果任务很小、可逆，并且已经由本地代码或已读来源支撑，不要因为触发了这个 skill 就增加仪式感。

## 文档查询（DocumentationSearch）

官方 Xcode MCP 工具 `mcp__xcode__DocumentationSearch` 是 Apple 平台事实的权威源：它对运行中的 Xcode 做语义搜索，**跟随当前安装的 Xcode 版本**，返回带 overview 和代码示例的结果，以及可下钻的 doc uri。

前提：Xcode 必须在运行（IDE-attached）。

当 API、type 或 concept 已经具名时，直接 search（`frameworks` 收窄到相关 framework 提升精度，不确定时省略做全局语义搜索）：

```
DocumentationSearch(query: "ShaderGraphMaterial", frameworks: ["RealityKit"])
DocumentationSearch(query: "VideoPlayerComponent")
DocumentationSearch(query: "Compositor Services")
```

`DocumentationSearch` 缺失，或主题超出 API reference 范围（HIG、WWDC videos、technotes、PDF、streaming examples）时，才走官方 Apple web pages。本地 DocSet 已淘汰，不再作为证据源。

availability（`@available(visionOS, …)`）**不在 search 结果里直接给出**——它返回符号/摘要。确认 availability 用本节下方的 SDK typecheck probe 或读 doc 详情页；不要靠“某个源查不到”反推不可用。

有用的 query seeds 是提示，不是强制阅读清单：

- RealityKit / RCP / materials: `Reality Composer Pro`, `ShaderGraph`,
  `ShaderGraphMaterial`, `CustomMaterial`, `MaterialX`,
  `RealityKit materials and shaders`.
- Metal: `Metal shader libraries`, `Metal compute shader`,
  `CustomMaterial SurfaceShader`, `Metal HDR content`,
  `Compositor Services Metal`.
- Scene and UI: `ImmersiveSpace`, `RealityView`, `volumetric window`,
  `GeometryReader3D`, `ornament`, `hover effect`.
- Media: `VideoPlayerComponent`, `VideoMaterial`, `AVExperienceController`,
  `Apple Projected Media Profile`, `Apple Immersive Video`, `spatial video`.
- ARKit and sensing: `ARKit`, `SpatialTrackingSession`, `WorldTrackingProvider`,
  `HandTrackingProvider`, `SceneReconstructionProvider`.
- Files and persistence: `FileDocument`, `UTType`, `SwiftData`, `Keychain`,
  `Network`, `URLSession`, `Security`.

## 平台过滤

`DocumentationSearch` 覆盖 Apple documentation 的多个平台：iOS、macOS、tvOS、watchOS、visionOS 和 cross-platform frameworks。命中 Apple 页面本身还不够。

按风险提出对应平台问题：

- 哪个 visionOS surface 拥有这个行为：window、volume、`ImmersiveSpace`、RealityKit scene、AVKit/system video、custom Metal/Compositor Services、ARKit sensing，还是 file/network/persistence service？
- 该来源描述的是 generic API behavior，还是 platform-specific lifecycle、rendering、input、privacy、media 或 performance rule？
- 与 iOS/macOS 相比，visionOS 是否需要不同的 presentation model、permission check、comfort constraint、renderer contract 或 verification surface？
- 这个 API 在 Enchron 的 deployment target 上是否可用？不支持的行为是否需要 availability guard、capability check 或明确降级 fallback？

处理 shader 工作时，保持概念分离：

- Shader Graph / MaterialX / `ShaderGraphMaterial`：asset-authored RealityKit material graphs，通常由 Reality Composer Pro 或 MaterialX content 产生。
- RealityKit `CustomMaterial`：由 custom shader stages 支撑的 RealityKit runtime material customization。对 Enchron 已安装 Apple toolchain 的当前判定：这不是 visionOS 路线。已安装的 XROS 和 XRSIMULATOR SDK 会把 `CustomMaterial` typecheck 为 `@available(visionOS, unavailable)`（见下方 probe）——availability 以 SDK typecheck 为准，不要靠“某个文档源查不到”反推。如果 shader 答案只把 `CustomMaterial` 当成“未确认”，力度太弱；除非更新后的当前 SDK/docs 证明相反，否则应说不可用。
- Metal shaders：`.metal` functions、shader libraries、render/compute pipelines、resource binding 和 GPU execution。
- Compositor Services：fully immersive custom Metal rendering，包含 compositor lifecycle 和 stereoscopic/frame-timing 职责。

shader 路线声明的最小 availability probe：

```bash
XROS_VER=$(xcrun --sdk xros --show-sdk-version)   # 跟随当前 Xcode 的 visionOS SDK，勿写死版本号
xcrun --sdk xros swiftc -target arm64-apple-xros${XROS_VER} -typecheck - <<'SWIFT'
import RealityKit
func check() {
    _ = CustomMaterial.self
    _ = ShaderGraphMaterial.self
}
SWIFT
```

当前机器上的预期结果是：`CustomMaterial` 在 visionOS 上 unavailable，而 `ShaderGraphMaterial` available。

## Enchron 过滤

读完 Apple docs 后，先回到 Enchron，再做决定。

重要时命名 owning module：

- `PlaybackCore`：loading、decoding、playback control、mpv integration。
- `PlayerUI`：playback interface 和 presentation decisions。
- `FileBrowsing`：local/SMB/WebDAV file browsing。
- `SpatialScene`：spatial presentation、RealityKit scenes、immersive content、virtual screens、panoramas 和 future scene rendering。
- `Persistence`：SwiftData、UserDefaults、Keychain、stored settings。
- `App`：launch、scene wiring、dependency injection。
- `Shared`：tokens、constants 和窄 Metal helpers 等低层稳定 utilities。
- `DesignPreview`：隔离的 design/prototype surfaces。

始终看见项目边界：

- 当前 Enchron production playback 是 mpv-first。Apple AV / AVKit / RealityKit media routes 属于 reference、diagnostics 或 future research，直到明确架构决策另行规定。
- Reality Composer Pro 和 MaterialX validation 属于 exploratory RealityKit asset/material surface，例如 `RealityKitContent`、`DesignPreview` 或有边界的 `SpatialScene` spike。它本身不应暗示 production playback 或 renderer route。
- `SpatialScene` 拥有 spatial presentation，不拥有 non-spatial playback control。
- Build 成功不能证明 spatial comfort、HDR/EDR correctness、long-viewing performance、device brightness behavior 或 human experience。
- Stable interface 或 active contract 变化需要对齐相关 active docs；exploratory spikes 和未证明实验不应制造过早 contract。

## 参考资料

`references/` 中的文件是项目边界说明，不是默认 Apple documentation 入口。当本地代码和 `DocumentationSearch` 已经识别平台区域后，如果它们能收窄 Enchron-specific decision，或代码闻起来像引入了 iOS/macOS 假设，再使用它们。

默认不要读取所有 references。优先选择能回答 project-boundary question 的最小 note。只有任务需要 API 事实之外的 complete-project examples 时，才使用 `references/sample-code-corpus.md`。

两份由 solutions 晋升的平台事实注记：`references/coremedia-dolby-vision-constants.md`（visionOS SDK 缺失 Dolby Vision CoreMedia 常量）、`references/swiftui-migration-pitfalls.md`（iOS→visionOS SwiftUI 迁移陷阱）；适用与过期条件见各自 frontmatter。

## 升级调查

对小且可逆的任务保持轻量。当工作陌生、platform-sensitive、rendering/media-related、privacy-sensitive、performance-sensitive、cross-module、contract-affecting，或容易与 iOS/macOS 行为混淆时，升级调查。

选择能看见风险的最小证据：

- package/domain logic：focused tests；
- app target、assets、target membership、scene lifecycle 或 RealityKitContent：匹配的 Xcode build；
- playback、Metal、CoreVideo、bridging、threading、HDR、remote I/O 或 persistence 风险：build 加相关 tests，并考虑 `xcodebuild analyze`；
- visual/spatial comfort、HDR/EDR credibility、device brightness、long-viewing behavior 和 interaction feel：Simulator/device/human verification，并明确命名。
