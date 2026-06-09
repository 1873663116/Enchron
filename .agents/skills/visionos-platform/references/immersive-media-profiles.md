# 沉浸式媒体 Profiles、APMP、Spatial Video

用途：将 media-profile 事实与当前 production playback 方向分开。
状态：Active visionOS reference。
负责人/范围：2D video、3D video、Spatial Video、APMP 180、APMP 360 或 Wide
FOV、Apple Immersive Video、Quick Look preview、AVKit immersive playback、
RealityKit `VideoPlayerComponent`，以及针对非 2D media profile 提议的自定义 MPV、Metal 或 compositor 路径。
本文件不是 production playback-routing contract。

Enchron 当前 production playback route 是 mpv-first。除非新的架构决策将其提升为 production，本文件中的 Apple system media API 都只是 reference 和 future investigation surface。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Playing immersive media with RealityKit" "VideoPlayerComponent" "desiredImmersiveViewingMode"`
  用于查找文章级 RealityKit walkthrough；它不在 Dash Apple API Reference docset 中。

### 官方 Web fallback

- WWDC25 304 `Explore video experiences for visionOS`
- WWDC25 296 `Support immersive video playback in visionOS apps`
- WWDC25 297 `Learn about the Apple Projected Media Profile`
- WWDC25 403 `Learn about Apple Immersive Video technologies`
- `https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf`
- `https://developer.apple.com/streaming/examples/`

## 正确判断

- 选择 API、声明支持或声明未来研究路径前，先分类 media profile。
- 最小 profile 集合：2D flat video、3D flat 或 stereoscopic video、带 spatial metadata 的 Spatial Video / MV-HEVC、APMP 180、APMP 360 / Wide FOV、Apple Immersive Video，以及 custom 或 unknown media。
- 当前 Enchron production playback 仍然是 mpv-first。
- 当产品需求允许 system preview 时，file preview 和 library preview 默认使用 Quick Look 或 `PreviewApplication`。
- 未来 Apple-native playback research 中，标准长视频、电影、课程、体育、captions、audio behavior、system controls 和 HLS 应与使用 `AVPlayerViewController` 的 AVKit 对照。
- 未来 Apple-native expanded 或 immersive system video research 中，当 content profile 支持这些 experience 时，使用 AVKit 和 `AVExperienceController`。
- 未来 RealityKit-based immersive media research 中，在进入更低层 custom rendering 前，先评估 RealityKit `VideoPlayerComponent`。
- APMP 和 Apple Immersive Video 应保留官方 projection metadata、view packing、spatial audio、captions 和 comfort behavior。
- RealityKit progressive immersive playback 必须让 `desiredImmersiveViewingMode` 与 SwiftUI `ImmersionStyle` 匹配。
- 对 APMP high-motion playback，在选择 full immersion 前先查 WWDC/APMP fallback 证据；当当前证据支持 system comfort mitigation 时，优先 portal 或 progressive 行为。
- AVFoundation、Core Media、Video Toolbox、HLS tools 和 Immersive Media Support 是媒体创建、转换、metadata 和分发工具，不是默认绕过 system playback presentation 的理由。
- 对 APMP、AIV、Spatial Video 或 3D 内容使用 Custom Metal、Compositor Services 或 MPV texture bridging 时，必须说明正在验证的当前 mpv 能力，或正在研究的未来 Apple-native 行为。

## iOS/macOS 冲突点

- 不要把 `AVPlayerLayer`、`CAMetalLayer` 或 MPV window surface 当成 APMP、AIV、Spatial Video 或 3D video 的完整 visionOS media experience。
- 当 APMP metadata 和 system playback path 可用时，不要默认把 360 video 当成自定义 inside-out sphere 问题。
- 不要假设 inline 3D video 会以 stereoscopic 方式显示；expanded playback 才是 stereoscopic 3D movie viewing 的系统路线。
- 不要把 Spatial Video 等同于 side-by-side 3D。Spatial Video 依赖 MV-HEVC 和 spatial metadata。
- 不要把 Apple Immersive Video 当成普通高分辨率 180 或 360 video；它的 metadata 和 audio workflow 是格式的一部分。
- 不要丢弃 APMP 或 Apple Immersive Video metadata 后，仅因为 decoded frames 能画出来就宣称支持该格式。
- 不要对 high-motion APMP content 直接跳到 full immersion。
- 不要把 Simulator playback 当成 audio、captions、comfort、power、spatial styling 或 immersive transitions 的最终证据。

## Enchron 检查点

实现前回答两个路由问题：
  这个行为属于哪个 visionOS surface？
  这个内容属于哪个 media profile？
- `PlaybackCore` 负责 media facts 和 playback state，而不是 presentation mode decisions。
- `PlayerUI` 使用共享 domain semantics 负责 playback mode decisions，而不是依赖具体 engine identity。
- MPV 是当前 playback 和未来 immersive rendering exploration 的 production basis。
- 对 3D、Spatial Video、APMP 和 Apple Immersive Video，要把当前 mpv-first 支持与未来 Apple-native platform research 分开。Quick Look、AVKit 和 RealityKit 是 comparison 或 future adoption candidate，不是当前 production route。
- Custom panorama sphere 可以继续作为 legacy 或 unsupported open-format input 的实现路径。对 APMP 或 Apple-native immersive profile 的支持声明需要明确 media-profile 证据。
- Immersive profile 的验证需要 device risk notes，尤其是 comfort mitigation、spatial audio、captions/subtitles、power 和 long-viewing behavior。
- 如果未来提出 Apple AV / AVKit / RealityKit production playback，必须先有明确架构决策、capability boundary、测试和文档更新，再把它当成 Enchron 实现指导。

## 版本门槛

- 选择 visionOS 26 media API 前，确认项目 minimum deployment target。
- 如果 API 高于该 target，添加 availability guard、runtime capability check 或明确 fallback。
- 如果 fallback 行为有降级，命名产品层面的降级。
- 如果项目 target 已包含该 API，但该功能是播放核心，仍要在相关 plan 或 code review 中记录这个依赖。
