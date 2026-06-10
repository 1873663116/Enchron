# MPV 生产播放、Apple AV 参考、HDR

用途：让 visionOS media decision 经过 Apple 平台来源和 Enchron playback boundary。
状态：Active visionOS reference。
负责人/范围：mpv production playback、AVKit/AVFoundation reference behavior、MPV comparison、HDR/EDR、subtitles/tracks、video surfaces 和 playback diagnostics。Media-profile specific immersive playback 位于
`immersive-media-profiles.md`。
本文件不是 product contract；active Enchron contracts 位于
`docs/contracts/`.

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"Destination Video" "visionOS" "AVPlayerViewController"`
  用于 sample app baseline。
- `"Determining whether to bring your app to visionOS" "Picture in Picture"`
  用于 migration constraints 和不可用的 iOS media affordances。
- `"Playing immersive media with RealityKit" "VideoPlayerComponent"`
  用于文章级 immersive RealityKit walkthrough。

### 官方 Web fallback

- `https://developer.apple.com/av-foundation/`
- `https://developer.apple.com/av-foundation/Apple-Movie-Profiles.pdf`

## 正确判断

- Enchron 当前 production playback 方向是 mpv-first。Production playback 工作应围绕 mpv 收敛。
- mpv 是当前 playback、compatibility、open formats、复杂 subtitles/tracks、remote I/O、HDR experiments 和未来 immersive rendering exploration 的 production basis。
- Apple 推荐在 visionOS 中用 `AVPlayerViewController` 做 system video playback integration。在 Enchron 中，除非未来架构决策把 Apple AV 提升为 production，否则这个事实属于 reference 和 diagnostics 证据。
- 对 Spatial Video、APMP、Apple Immersive Video 或 immersive 3D playback research，做平台声明前先读 `immersive-media-profiles.md`。
- 在 reference/future research 中改变 presentation transitions、system playback UI 或 spatial-audio behavior 时，打开 Destination Video sample；它是具体平台 baseline，不只是 sample link。
- 如果使用 MPV + Metal，app 要拥有系统播放器通常提供的东西：controls、readiness、errors、dynamic range behavior、subtitles/tracks、accessibility，以及进入 immersive experiences 的 transitions。
- AVFoundation 是跨 Apple 平台的 time-based media framework，可用于 metadata、diagnostics、HDR/EDR observation 和未来 Apple-native media research。它不是当前 production playback route。
- `preferredDisplayDynamicRange` 只有在 API 可用且 content/display 支持 HDR 时才有意义。采用前用 `DocumentationSearch` 或 SDK 编译器 `@available` 确认它在 visionOS 的可用性，不要靠某个文档源查不到反推；HDR label 必须跟随证据，而不是 toggle。
- Audio session、interruptions、route changes、spatial-audio behavior、captions/subtitles、external subtitle files 和 remote-command expectations 都是 media surface 的一部分。不要把它们当成通用 iOS 细节。
- 对 `AVPlayerLayer`、`CAMetalLayer` 或 `MTKView`，UIKit `UIViewRepresentable` bridge 可以是合适的。它是 implementation bridge，不是让 app 变成 UIKit-shaped 的许可。
- Window Metal output、RealityKit texture playback 和 fully immersive Metal rendering 是不同 surface。

## iOS/macOS 冲突点

- 不要把 iOS full-screen player 假设当成目标体验。
- 不要假设 macOS `AVPlayerView` 模式是 visionOS 上的系统答案。
- 没有检查 owning visionOS surface 前，不要假设 iOS/macOS `AVPlayer` 模式在 visionOS 上正确。
- 不要把 AVKit reference behavior 变成 Enchron 当前 production route。
- 不要 subclass `AVPlayerViewController`；Apple 文档说明这种 subclassing behavior 不受支持。
- Apple migration docs 将 Picture in Picture 和 AV routing 列为 visionOS 不可用。不要围绕这些 iOS affordance 设计 Enchron playback UX。添加 conditional fallback behavior 前要检查当前 API 可用性。
- 不要把“AVPlayer 可以做到这个”等同于“MPV 已经做到这个”。把 AVKit 用作证据和对照。
- 不要把 AVKit system UI 当成 Enchron 的 product state machine。
- 不要把可工作的 MPV surface 当成未来 Apple-native immersive media research 已完成的证明。
- 不要把这个 baseline playback reference 当成 APMP、Apple Immersive Video、Spatial Video 或 immersive 3D 决策的唯一来源。
- 不要把 2D `CAMetalLayer` 或 `MTKView` 路径视为自动适用于 RealityKit immersive rendering。
- 不要从文件名、用户 toggle 或 UI label 推断 HDR。使用 media metadata、output contract 和 display behavior。

## Enchron 检查点

- Playback mode decision 留在 `PlayerUI`；`PlaybackCore` 只报告事实。
- Enchron 当前 production media direction 是 mpv-first。
- Apple AV / AVFoundation / AVKit 是 reference、diagnostics、主观视觉对照、HDR/EDR observation 和未来 platform investigation surface。
- Apple AV 不是当前 production `PlaybackEngine`、default fallback 或当前 engine-routing target branch。
- AVKit 证据不能证明 mpv 正确。
- mpv 行为不能证明未来 Apple-native media profile 支持。
- APMP、Apple Immersive Video、Spatial Video 和 immersive 3D playback 在声明支持或未来方向前，需要先查 media-profile reference。
- Production engine routing 由 `docs/contracts/playback-engine-routing.md` 定义。
- Diagnostic Apple reference playback 不是已选中的 production `PlaybackEngineRoute`。
- `PlayerUI` 不得按 mpv vs Apple reference playback 分支。它必须使用共享 playback 和 domain semantics。
- HDR/EDR 改动应包含证据路径：metadata、必要时的 AVKit comparison、MPV output contract、layer/display configuration，以及需要时的 device verification。
- 如果提出未来 Apple AV production playback，需要新的明确架构决策、capability boundary、测试和文档更新，然后才能把它当成实现指导。
