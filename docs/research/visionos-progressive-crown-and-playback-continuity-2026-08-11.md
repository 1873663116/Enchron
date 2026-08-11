# visionOS 调研：progressive 沉浸下的 Digital Crown、跨场景连续播放、VideoPlayerComponent 初始化通道

日期：2026-08-11。全部结论取自 Apple 一手来源：developer.apple.com 文档（经 `developer.apple.com/tutorials/data/...json` 数据端点抓取原文）、Apple 官方示例源码（Destination Video zip，Apple docs-assets 分发）、WWDC session 文稿、Apple Vision Pro 用户指南（support.apple.com），以及 Apple DTS 工程师在开发者论坛的署名回复。文中"visionOS 26"为 2025 年发布的版本命名（自 visionOS 2 之后跳号），visionOS 27 于本文写作时处于 beta。

---

## 问题一：`.progressive` immersionStyle 下 Digital Crown 的系统行为

### 旋转表冠：在 App 定义的范围内调节沉浸量，不会越过下限

`progressive(_:initialAmount:)` 的文档明确描述了旋转行为："The system initially uses a radial portal effect that replaces passthrough in a portion of the field of view. People can interactively adjust the size of the portal by turning the Digital Crown, including down to a minimum amount of immersion defined by the app and up to the defined maximum amount of immersion." 即旋转只在 App 定义的最小值与最大值之间调节 portal 大小；文档没有给出"旋转到下限之后继续下旋会退出空间"的任何行为。
来源：https://developer.apple.com/documentation/swiftui/immersionstyle/progressive(_:initialamount:)

HIG 给出系统默认范围："people can use the Digital Crown to adjust the amount of immersion within either the default range of 120- to 360-degrees or a custom range, if you specify one."
来源：https://developer.apple.com/design/human-interface-guidelines/immersive-experiences

### `.progressive(range:initialAmount:)` 参数语义（visionOS 2.0+）

签名：`static func progressive(_ immersionRange: ClosedRange<Double>, initialAmount: Double? = nil) -> ProgressiveImmersionStyle`（另有 `PartialRangeFrom<Double>` 与 `PartialRangeThrough<Double>` 重载）。

- `immersionRange`："The lower bound and upper bound value of the range represent the minimum and maximum amount of the spherical field of view of the user that can be covered by the portal effect of the style. The lower bound value must be equal to or greater than 0.0 and smaller than the upper bound. The upper bound value must be greater than the lower bound and smaller than or equal to 1.0." 即沉浸量的语义是"portal 覆盖用户球面视野的比例"。
- `initialAmount`："If nil, a system default will be used. The value must be within the range defined by this style."
- 附带行为约束："In progressive immersion, windows always render in front of virtual content, no matter how someone positions the window or the content."

版本边界：`.progressive` 静态样式本身 visionOS 1.0+；带范围参数的 `progressive(_:initialAmount:)` 为 visionOS 2.0+（macOS 26.0+）。visionOS 1 上只能使用系统固定范围。
来源：https://developer.apple.com/documentation/swiftui/immersionstyle/progressive(_:initialamount:) ；https://developer.apple.com/documentation/swiftui/progressiveimmersionstyle

### 回调：`onImmersionChange` 与 `ImmersionChangeContext`（visionOS 2.0+）

`onImmersionChange(initial:_:)`（visionOS 2.0+）签名为 `func onImmersionChange(initial: Bool = true, _ action: @escaping (ImmersionChangeContext, ImmersionChangeContext) -> Void) -> some View`，闭包收到旧、新两个 `ImmersionChangeContext`；`ImmersionChangeContext` 只有一个成员 `let amount: Double?`。文档说明："Depending on the immersion style used for the Immersive Space in your app, the amount of immersion can be controlled by actions such as turning the Digital Crown."
来源：https://developer.apple.com/documentation/swiftui/view/onimmersionchange(initial:_:) ；https://developer.apple.com/documentation/swiftui/immersionchangecontext

各样式报告的 amount 有明确文档定义：

| 样式 | onImmersionChange 报告的 amount | 来源 |
|---|---|---|
| `.mixed` | 恒为 `0.0` | https://developer.apple.com/documentation/swiftui/mixedimmersionstyle |
| `.progressive` | 落在该样式定义的 range 内 | https://developer.apple.com/documentation/swiftui/immersionstyle/progressive(_:initialamount:)（"the immersion amount reported by the closure of onImmersionChange(initial:_:) is within the range of the immersion that this style is defined with"） |
| `.full` | 恒为 `1.0` | https://developer.apple.com/documentation/swiftui/fullimmersionstyle |

### App 能否感知"沉浸量降到下限"并自行处理

可以由已文档化的 API 组合出来：`onImmersionChange` 报告的 amount 被限定在 range 内，因此 `amount == range.lowerBound` 即为"已到下限"；此时 App 可以调用 `dismissImmersiveSpace` 环境动作关闭空间、退回窗口呈现（"To dismiss an open space, use the dismissImmersiveSpace action."）。但文档没有提供"用户试图旋转越过下限"的专门事件，也没有承诺表冠事件本身可被 App 读取——HIG 明确："visionOS apps don't receive direct information from the Digital Crown."
来源：https://developer.apple.com/documentation/visionos/creating-fully-immersive-experiences ；https://developer.apple.com/design/human-interface-guidelines/digital-crown

HIG 同时要求 App 提供自己的退出控件而不是依赖系统控制："Avoid requiring people to use system controls to reduce immersion in your experience."、"provide a clear action to enter or exit immersion so people can decide when to be more immersed in your content, and when to leave."
来源：https://developer.apple.com/design/human-interface-guidelines/immersive-experiences

### 按压表冠一次的行为：文档与实机行为存在已确认的不一致

Apple 面向用户的权威描述（Vision Pro 用户指南"Digital Crown"释义）：旋转 = 调沉浸量或音量；单次按压 = "open Home View"；双击 = "switch between your content and a view of your surroundings"。开发者侧 HIG 的表冠职责列表也包含 "Exit an app and return to the Home View"。开发者文档（SwiftUI/visionOS 章节）没有按样式区分描述按压行为。
来源：https://support.apple.com/guide/apple-vision-pro/aside/dev1b8eda1e7/visionos ；https://developer.apple.com/design/human-interface-guidelines/digital-crown

实机行为由 Apple DTS 工程师在论坛署名确认（2025-04，标记为 Recommended 回复）：当沉浸空间与 App 窗口同时呈现时，按压一次只关闭沉浸空间、窗口保留在共享空间，需要第二次按压才回到 Home View；DTS 原话确认 "this behavior is present on both device and simulator" 且 "it is indeed inconsistent with documentation that suggests only one press of Digital Crown is sufficient to return to the Home View"，并建议提交 Feedback。也就是说：对于 Enchron 关心的场景（progressive 空间 + 窗口共存），截至 visionOS 2.x 的已确认行为是"按压退出沉浸空间、保留 App 窗口"，与用户指南文字冲突，且 Apple 将其归为待修复的不一致而非契约。
来源：https://developer.apple.com/forums/thread/774365

`.full` 样式下的按压行为有 WWDC23 文稿佐证："And by pressing the Digital Crown, you can go back to passthrough whenever you're ready to leave the experience."（WWDC23 10111 "Go beyond the window with SwiftUI"）。该句同样只承诺"离开沉浸回到 passthrough"，未承诺直接回 Home View。
来源：https://developer.apple.com/videos/play/wwdc2023/10111/

App 感知系统关闭空间的通道：没有专门回调；空间内容视图的 `onAppear`/`onDisappear`（以及 scenePhase）是官方示例实际使用的感知手段（见问题二 Destination Video 对 `immersiveSpaceState` 的维护）。

---

## 问题二：Destination Video 的跨窗口/沉浸空间连续播放做法

示例页：https://developer.apple.com/documentation/visionos/destination-video （要求 visionOS 2.0+、Xcode 16+；源码 zip：https://docs-assets.developer.apple.com/published/3248dcf174b4/DestinationVideo.zip ，本次已下载解压至 `/tmp/DestinationVideo-sample/` 并核读源码）。

### 核心事实：视频从不迁移进沉浸空间，沉浸空间只承载环境

场景拓扑（读自 `DestinationVideo/DestinationVideo.swift`）：

```
App
├── WindowGroup ── ContentView
│     ├── presentation == .inline      → DestinationTabs（库 + 内嵌试片播放器）
│     └── presentation == .fullWindow  → PlayerView（AVPlayerViewController 全窗口）
│                                         └─ .immersiveEnvironmentPicker { ... }
└── ImmersiveSpace(id: "ImmersiveEnvironmentView")   ← 只渲染 Studio 环境，不含播放器
      └── RealityView { content.add(environment.rootEntity) }
      .immersionStyle(selection: .constant(.progressive), in: .progressive)
```

打开沉浸环境时，播放器不发生任何重建或 re-parent：`ImmersiveSpace` 内的 `ImmersiveEnvironmentView`（`Views/visionOS/ImmersiveEnvironmentView.swift`）只把 Reality Composer Pro 的 Studio 场景实体加进 `RealityView`；全窗口播放器仍留在 `WindowGroup` 场景中，由系统把它停靠进环境里的 docking 区域。停靠位置由 RCP 场景中的 `RealityKit.CustomDockingRegion` 组件声明（`Packages/Studio/Sources/Studio/Studio.rkassets/scenes/Common.usda` 中 `def RealityKitComponent "CustomDockingRegion"`，对应文档所述 DockingRegionComponent "Customizes the docking location for the video player in a custom environment"）。播放连续性因此是平凡成立的：切换"窗口内观看 ↔ 环境中观看"只增删了周围的环境场景，播放器实例、AVPlayer、播放进度全部原样不动。

环境入口是系统播放器的环境选择菜单：`PlayerView` 挂 `.immersiveEnvironmentPicker { ImmersiveEnvironmentPickerView() }`，按钮内调用 `openImmersiveSpace(id:)`（`Views/visionOS/ImmersiveEnvironmentPickerView.swift`）；空间开闭状态通过 `ImmersiveEnvironment.immersiveSpaceState` 在 `onAppear`/`onDisappear` 中维护，这也是该示例感知系统侧关闭（含表冠按压）空间的唯一通道。

### AVPlayer 生命周期：单实例贯穿全程，切换呈现不重建

`Player/PlayerModel.swift`：`PlayerModel` 在 `App.init` 中创建一次，`AVPlayer` 在 `PlayerModel.init` 中创建一次（`private var player: AVPlayer`），此后从不重建；换片只走 `player.replaceCurrentItem(with:)`。inline（详情页试片）与 fullWindow（正片）是同一 `AVPlayer` 的两种呈现：`loadVideo(_:presentation:)` 更新 `presentation` 枚举，`ContentView` 据此在 `DestinationTabs` 与 `PlayerView` 之间切换视图树。`AVPlayerViewController` 每次呈现由 `makePlayerUI()` 新建，但源码注释明确要求保存其引用以覆盖窗口外呈现："the view controller also manages the presentation of the media outside your app's UI such as when using AirPlay, Picture in Picture, or docked full window. To ensure the view controller instance is preserved in these cases, the app stores a reference to it here as an environment-scoped object."（`PlayerModel.playerUI`）。`InlinePlayerView.onDisappear` 只在"不是切往 fullWindow"时才 `reset()`，保证 inline→fullWindow 的切换不清空播放器。

### 共享状态跨 Scene 的传递方式

App 级 `@State`（`PlayerModel`、`ImmersiveEnvironment`）通过 `.environment(...)` 注入：`PlayerModel` 只注入 `WindowGroup`（沉浸空间不需要它——播放器不在那个 Scene）；`ImmersiveEnvironment` 同时注入 `WindowGroup` 与 `ImmersiveSpace`，即"谁需要谁拿"，而不是把播放状态搬进沉浸空间。

### 该示例不使用 VideoPlayerComponent

Destination Video 的播放通道是 AVKit 的 `AVPlayerViewController`（3D 内容要求全窗口呈现："Playing 3D content in your app requires that you display AVPlayerViewController full window"，示例页；AVKit 文档同样写明 inline 只播 2D："When you present the player inline, it only displays standard 2D video. To play 3D content, present it fullscreen."）。RealityKit 只用于环境（光照探针、混响、docking）。因此"把播放实体 re-parent 到另一个 RealityView"不是 Apple 在该场景给出的做法；Apple 的做法是**播放留在一个 Scene，沉浸空间作为加法叠加，系统负责把播放器停靠进环境**。
来源：https://developer.apple.com/documentation/visionos/destination-video ；https://developer.apple.com/documentation/avkit/adopting-the-system-player-interface-in-visionos

---

## 问题三：`VideoPlayerComponent` 的初始化通道

组件总览：https://developer.apple.com/documentation/realitykit/videoplayercomponent

### `init(avPlayer:)`：visionOS 1.0+

`init(avPlayer: AVPlayer)`——visionOS 1.0+、macOS 15.0+、iOS/iPadOS/Mac Catalyst 18.0+、tvOS 26.0+（availability 已从文档 JSON 原文核对）。约束："You can't use the same AVPlayer object with more than one VideoPlayerComponent."`avPlayer` 属性为只读，换内容通过 `AVPlayer.replaceCurrentItem` 完成。
来源：https://developer.apple.com/documentation/realitykit/videoplayercomponent/init(avplayer:)

该通道承载全部高级内容分类能力：visionOS 26 起 "VideoPlayerComponent supports all of the same immersive video profiles that Quick Look and AVKit now support"（APMP 180/360/宽视场、Apple Immersive Video、spatial video），配置入口都是把承载相应媒体的 `AVPlayer` 交给组件（WWDC25 296 文稿与 "Playing immersive media with RealityKit" 文章的示例都只用 `VideoPlayerComponent(avPlayer:)`）。
来源：https://developer.apple.com/videos/play/wwdc2025/296/ ；https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit

### `init(videoRenderer:)`：存在，visionOS 2.0+

`init(videoRenderer: AVSampleBufferVideoRenderer)`——visionOS 2.0+、macOS 15.0+、iOS/iPadOS/Mac Catalyst 18.0+、tvOS 26.0+（availability 已从文档 JSON 原文核对）。文档描述的使用模型是推送式采样缓冲：自建 `AVAssetReader`/`AVAssetReaderTrackOutput` 读样本，按 `isReadyForMoreMediaData` 向 renderer enqueue。文档注明的约束：

- "You need to synchronize the audio, captions, and playback rate separately in your app."——音频、字幕、速率同步全部由 App 自理；
- "You can't use the same AVSampleBufferVideoRenderer object with more than one VideoPlayerComponent."

来源：https://developer.apple.com/documentation/realitykit/videoplayercomponent/init(videorenderer:)

文档没有为 renderer 通道列出内容分类能力表（stereo、spatial、APMP、viewingMode 是否生效均未说明）；所有沉浸媒体与 spatial 相关文档、WWDC 文稿的示例都建立在 avPlayer 通道上。两通道的能力差异在文档层面只能得出："avPlayer 通道有完整的分类识别与沉浸呈现能力，renderer 通道文档只承诺'呈现你推入的视觉内容'且一切同步自理"。

### 运行中替换 renderer / 变更内容分类

`videoRenderer` 属性文档明确禁止运行中替换："Pass this renderer to the component as a parameter in the initializer; you can't replace it afterward."换 renderer 意味着构造新的 `VideoPlayerComponent` 并重设到 entity 上。对"运行中变更内容分类"（例如同一组件先播 2D 再换 APMP item），文档没有任何说明。
来源：https://developer.apple.com/documentation/realitykit/videoplayercomponent/videorenderer

### 相关能力的版本边界（均已从文档 JSON 的 availability 字段核对）

| API | visionOS 引入版本 |
|---|---|
| `init(avPlayer:)` | 1.0 |
| `desiredViewingMode`（stereo/mono） | 1.0 |
| `init(videoRenderer:)`、`videoRenderer` | 2.0 |
| `ImmersiveViewingMode` 枚举及 `.full`、`.portal` case；`desiredImmersiveViewingMode` | 2.0 |
| `ImmersiveViewingMode.progressive`（表冠调节覆盖比例；文档注明 "not available for Spatial Video"） | 26.0 |
| `desiredSpatialVideoMode` / `spatialVideoMode` | 26.0 |
| `portalSize` | 27.0（beta） |

WWDC25 296 对 progressive 沉浸观看模式的定位："Starting with visionOS 26, progressive immersive viewing mode is preferred over full immersive viewing mode for Apple Projected Media Profile videos, and Apple Immersive Video"；spatial video 的沉浸渲染 "is always configured with an immersive viewing mode of full"。
来源：https://developer.apple.com/documentation/realitykit/videoplayercomponent/immersiveviewingmode-swift.enum ；https://developer.apple.com/videos/play/wwdc2025/296/

---

## 官方文档未回答、需真机实验裁决的残留问题

1. **表冠单次按压的现行为**：DTS 确认的"先关空间、窗口保留、第二按才回 Home View"记录于 2025-04（visionOS 2.x）。visionOS 26 上该不一致是否已按用户指南文字"单按直达 Home View"修复，直接决定 Enchron 能否依赖"按压后窗口仍在"的降级路径。需在真机 progressive 空间 + 窗口共存下按压验证。
2. **旋转到 range 下限后的系统行为**：文档只说可调到 App 定义的最小值；继续下旋是否停在下限、是否有任何系统提示或退出行为，未见文档描述。
3. **`onImmersionChange` 的回调粒度**：旋转过程中回调频率、是否保证送达 `lowerBound` 的精确值（浮点比较容差）、progressive 下 `amount` 是否可能为 `nil`，文档均未说明；这些决定"以 amount == lowerBound 触发 dismissImmersiveSpace"方案的可靠性。
4. **visionOS 1 固定 range 与 amount 的数值映射**：HIG 给的默认范围是角度（120°–360°），`progressive(_:initialAmount:)` 的语义是球面视野比例，二者换算关系未在文档给出。
5. **videoRenderer 通道的内容分类能力**：stereo/spatial/APMP 内容经 `AVSampleBufferVideoRenderer` 推入时 `desiredViewingMode`、`ImmersiveViewingMode` 是否生效，文档未列明，需实验。
6. **运行中变更内容分类**：同一 `VideoPlayerComponent`（avPlayer 通道）在播放中把 item 从 2D 换成 APMP/spatial 时组件的网格与呈现模式如何迁移，文档无说明。
7. **表冠按压关闭环境瞬间的播放状态**：Destination Video 源码结构上播放器在窗口 Scene、推断不受影响，但"系统关闭空间的过渡期间播放是否有暂停/丢帧"没有文档承诺。
