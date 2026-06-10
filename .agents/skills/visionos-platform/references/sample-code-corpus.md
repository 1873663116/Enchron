# visionOS 示例代码语料库

用途：将 implementation-pattern research 路由到 Apple sample projects 和精选 open-source visionOS media apps 的稳定本地副本。
状态：Supporting reference，不是 API authority。
负责人/范围：video playback、`WindowGroup` sizing、AVKit player surfaces、RealityKit media playback、immersive-media transitions、ornaments 和相关 scene composition patterns。
采集时间：2026-05-28，本地副本位于 `~/Documents/CodeReferences`。

本文件不是 product contract，也不能替代 Apple documentation、SDK headers、`DocumentationSearch` 或当前 Enchron runtime evidence。

## 优先级

先通过 `DocumentationSearch` 或 SDK headers 检查当前 Apple documentation，并明确相关 Enchron project boundary 后，再使用这个 corpus。

把 Apple sample code 视为 Apple 在完整项目中组合 API 的 implementation guidance。Open-source projects 只作为 comparison material。Sample 可能已经过时，可能绑定旧版 Xcode 或 visionOS release，也可能为了教学而简化。

## 本地 Corpus

根目录：

`~/Documents/CodeReferences/Apple/visionOS/VideoPlayback`

### Apple 官方示例

这些是下载下来的官方 sample projects；source folders 和原始 zip files 都保存在 Enchron repo 外。本地副本采集于 2026-05-28。

- `apple-official/PlayingImmersiveMediaWithAVKit`
  - Source:
    `https://developer.apple.com/documentation/avkit/playing-immersive-media-with-avkit`
  - 用于：使用 `AVPlayerViewController`、`AVExperienceController`、expanded/immersive experience routing、Spatial Video、APMP 和 Apple Immersive Video 的 immersive-media profile playback。
  - 不要作为 Enchron 当前 windowed flat 2D playback fixture 的主要 reference。
- `apple-official/PlayingImmersiveMediaWithRealityKit`
  - Source:
    `https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit`
  - 用于：使用 `VideoPlayerComponent`、`GeometryReader3D`、`RealityView`、Spatial Video、APMP 和 Apple Immersive Video 的 immersive-media profile playback。
  - 不要作为 Enchron 当前 windowed flat 2D playback fixture 的主要 reference。
- `apple-official/CreatingAMultiviewVideoPlaybackExperienceInVisionOS`
  - Source: Apple Developer sample "Creating a multiview video playback experience in visionOS"。
  - 用于：SwiftUI 中 flat/windowed `AVPlayerViewController`、`windowResizability`、expanded playback 和 multiview player coordination。
- `apple-official/zips/DestinationVideo.zip`
  - Source:
    `https://developer.apple.com/documentation/visionos/destination-video`
  - 用于：Destination Video、windowed/full-window flat playback、`PlayerView` / `SystemPlayerView` composition、custom immersive environments、docking regions、media reflections 和 SharePlay。
  - 大型 archive；只有调查需要 source details 时才解压。

### 开源对照仓库

这些是完整本地 clone，不是浅层临时 checkout。本地 clone 采集于 2026-05-28。

- `open-source/openimmersive`
  - Upstream: `https://github.com/acuteimmersive/openimmersive`
  - 用于：围绕 immersive video player 的 app-level composition。
- `open-source/openimmersivelib`
  - Upstream: `https://github.com/acuteimmersive/openimmersivelib`
  - 用于：RealityKit immersive playback implementation、custom controls，以及 `VideoPlayerComponent` / renderer handling。
- `open-source/AVP-Simple-Video-Player`
  - Upstream: `https://github.com/Netruk44/AVP-Simple-Video-Player`
  - 用于：最小 `AVPlayerViewController` wrapping patterns。
- `open-source/NetflixVisionPro`
  - Upstream: `https://github.com/barisozgenn/NetflixVisionPro`
  - 仅用于：早期 visionOS media UI comparison。

## 如何探索

跨这个 corpus 做广泛探索时，优先使用 subagent，避免主线程吸收整个 sample project。把本文件路径、具体问题和所需证据形态交给 subagent。

以下情况在主线程直接检查：

- 相关文件已经收窄到少数 source files；
- 答案会影响 Enchron architecture 或 platform behavior；
- sample finding 与当前 Apple docs 或 SDK headers 冲突；
- 用户要求 grounded final recommendation。

在决策中引用这些 sample 时，记录 sample name、local path、已知 download/clone date，以及当前仍支持该 pattern 的 Apple-doc 或 SDK 证据。

## 护栏

- 不要在未适配 ownership、tokens、accessibility、platform availability 和 product boundaries 的情况下，把 sample code 复制进 Enchron。
- 不要把 sample 缺少某条 code path 当成 API 做不到某事的证明。
- 不要让 open-source projects 覆盖 Apple docs、SDK headers 或 local runtime evidence。
- Sample projects 保持在 Enchron 外部，使 Xcode indexing、target membership、git status 和 project search 保持干净。
