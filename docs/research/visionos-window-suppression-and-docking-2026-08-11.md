# visionOS 调研：沉浸期间窗口场景的隐藏/存活能力、AVKit docking 的窗口场景语义、任意内容的环境停靠

日期：2026-08-11。全部结论取自 Apple 一手来源：developer.apple.com 文档（经 `developer.apple.com/tutorials/data/...json` 数据端点抓取原文）、WWDC session 文稿、Apple Vision Pro 用户指南（support.apple.com）、HIG，以及 Apple DTS 工程师在开发者论坛的署名回复。"visionOS 26"为 2025 年发布版本，"visionOS 27"为 2026 年（WWDC26）发布、写作时处于 beta 的版本。凡文档未覆盖之处均显式标注"未验证"，不以推断充当事实。

背景：Enchron 进入 `.progressive` ImmersiveSpace 时会 dismiss 全部窗口；此后单次表冠按压关闭空间、因无窗口场景而直达 Home View，App 自身的收拢机制再开窗抢走焦点。本文核查"能否让一个窗口场景存活但视觉缺席"，以及 Apple TV 播放器停靠机制的窗口场景语义。

---

## 问题一：有无公开 API 在 ImmersiveSpace 打开期间隐藏/挂起/视觉抑制自己的窗口场景

### 核心结论：没有"隐藏一个存活窗口场景"的公开 API；DTS 明确指认 dismissWindow

系统只自动隐藏**别的 App** 的窗口："Your app can display any number of windows together with an immersive space. However, when you open a space from your app, the system hides all windows that belong to other apps. After you dismiss your space, the other apps' windows reappear. Similarly, the system hides your app's windows if another app opens an immersive space."
来源：https://developer.apple.com/documentation/visionos/presenting-windows-and-spaces

DTS 工程师（署名 Greg，2025）对"进入 full 沉浸时隐藏本 App 其它窗口"的提问回复："When your app opens an immersive space, the system hides all other visible apps. The system does not hide your app's windows automatically."并给出唯一方案："If you would like to dismiss your app's windows when you open your immersive space, use the dismissWindow action."
来源：https://developer.apple.com/forums/thread/779736

即：对自己的窗口，官方通道只有关闭（dismissWindow），不存在"存活但不可见"状态的第一方开关。以下逐项核对了问题清单里的候选 API。

### 候选 API 逐项核对

| 候选 | 实际语义 | 能否达成"存活但视觉缺席" | 版本 |
|---|---|---|---|
| `defaultLaunchBehavior(.suppressed)` | 只影响启动呈现与"无可见窗口时点按 App 图标"的呈现选择 | 否（不作用于运行中的场景） | visionOS 26.0+ |
| `restorationBehavior(.disabled)` | 只影响跨进程/跨启动的场景恢复与锁定持久化 | 否 | visionOS 26（WWDC25 290 介绍） |
| `pushWindow` | 用另一窗口"顶替"当前窗口，被顶替场景后台化且保活，弹出窗关闭后自动重现 | 部分——是唯一文档化的"场景保活但不可见"原语，但必须有一个可见的顶替窗口 | visionOS 2.0+ |
| `persistentSystemOverlays(.hidden)` | 对 WindowGroup 影响 window chrome 可见性；对 ImmersiveSpace 影响 Home indicator；仅为偏好 | 部分（只隐藏 chrome，不隐藏窗口内容/玻璃） | 修饰符 visionOS 1.0+ |
| `.windowStyle(.plain)` | 无装饰的窗口样式（默认样式的玻璃属于样式的一部分） | 部分（去玻璃；chrome 是否仍现、空内容窗口是否可见，文档未述） | visionOS 1.0+ |
| UIKit `UISceneSessionActivationRequest` / `activateSceneSession` | 只能请求**激活**（呈现）场景 | 否 | iOS 17+（visionOS 可用） |
| UIKit `requestSceneSessionDestruction` | 关闭场景并从 App 切换器移除（等价 dismissWindow 的 UIKit 面） | 否 | visionOS 1.0+ |
| UIKit `requestSceneSessionRefresh` | 请求刷新场景的系统 UI | 否 | iOS 13+ |

关键条目的原文依据：

- `defaultLaunchBehavior` discussion 的 visionOS 段落（verbatim）："On visionOS, the system may background the last dismissed scene instead of closing it. Thus, the suppressed behavior additionally specifies that the scene should not be presented when tapping on the application icon with no visible windows." availability：macOS 15.0+、visionOS 26.0+。该修饰符全部语义都围绕"launch 时/无可见窗口点图标时是否呈现"，与运行中隐藏无关。
  来源：https://developer.apple.com/documentation/SwiftUI/Scene/defaultLaunchBehavior(_:)
- WWDC25 290 "Set the scene with SwiftUI in visionOS" 对两者的定位（verbatim）："I can do this by adding the defaultLaunchBehavior(.suppressed) modifier to my tools window. This tells the system not to bring this window back when relaunching the app from the Home view."；"In general, you should prefer the .suppressed defaultLaunchBehavior on secondary scenes to avoid getting people stuck in an unexpected state."
  来源：https://developer.apple.com/videos/play/wwdc2025/290/
- `pushWindow`（visionOS 2.0+）discussion（verbatim）："This action opens the requested window in place of the window the action is called from. The scene this action is called from will be backgrounded. … Closing the requested window will result in the backgrounded scene reappearing."约束："Calling this action from a pushed window is not allowed."被顶替场景的"backgrounded 且保活、自动重现"正是 Enchron 想要的场景语义，但它要求前台始终有一个可见的顶替窗口——形态上等于"小的常驻控制窗"，只是附赠了"关闭小窗自动恢复主窗"的系统机制。文档未描述 pushWindow 与 ImmersiveSpace 的交互（顶替窗口打开沉浸空间后表冠按压的行为未见文档）。
  来源：https://developer.apple.com/documentation/swiftui/environmentvalues/pushwindow
- `persistentSystemOverlays(_:)`（visionOS 1.0+）discussion（verbatim）："For a WindowGroup, the modifier affects the visibility of the window chrome."；"For an ImmersiveSpace, it affects the Home indicator."并且它只是偏好："You can indicate a preference with this modifier, but the system might or might not be able to honor that preference."
  来源：https://developer.apple.com/documentation/swiftui/view/persistentsystemoverlays(_:)
- 窗口的玻璃与控件是默认样式的一部分（HIG，verbatim）："The default window style consists of an upright plane that uses an unmodifiable background material called glass and includes a close button, window bar, and resize controls that let people close, move, and resize the window."`PlainWindowStyle`（visionOS 1.0+）文档只有摘要"The plain window style"，未说明 plain 样式下 chrome 的呈现规则；"完全透明内容 + plain 样式的窗口在共享空间里是否还有任何可见残留（chrome、命中区域）"没有任何文档回答，属于需真机裁决的问题。
  来源：https://developer.apple.com/design/human-interface-guidelines/windows ；https://developer.apple.com/documentation/swiftui/plainwindowstyle
- UIKit 面三个入口的职责边界：`UISceneSessionActivationRequest` 只用于 `activateSceneSession(for:errorHandler:)` 的激活请求；`requestSceneSessionDestruction(_:options:errorHandler:)`（visionOS 1.0+）"Asks the system to dismiss an existing scene and remove it from the app switcher"。UIKit 场景会话 API 中不存在隐藏/挂起动作。
  来源：https://developer.apple.com/documentation/uikit/uiscenesessionactivationrequest ；https://developer.apple.com/documentation/uikit/uiapplication/requestscenesessiondestruction(_:options:errorhandler:)

### visionOS 26 / 27 SDK 增量核查

- visionOS 26 的场景管理增量（WWDC25 290、317）：窗口/volume/widget 的房间锁定与持久化、`restorationBehavior`、`defaultLaunchBehavior`、surface snapping、unique `Window` 场景。没有任何"隐藏存活窗口"的 API。注意反向事实："immersive spaces are not restored"（WWDC25 290）。
  来源：https://developer.apple.com/videos/play/wwdc2025/290/ ；https://developer.apple.com/videos/play/wwdc2025/317/
- visionOS 27（WWDC26）："What's new in visionOS 27" 页与 WWDC26 visionOS guide 列出的新增为：宽高比 portal 支持（RealityKit 与 AVKit）、CompositorServices 上 macOS、Spatial Preview、Foveated Streaming、object tracking 增强、RealityKit 光照/布料/高斯泼溅等。两处均无窗口场景隐藏/抑制类 API。
  来源：https://developer.apple.com/visionos/whats-new/ ；https://developer.apple.com/wwdc26/guides/visionos/
- SwiftUI updates 变更日志的 June 2026 小节（General、Transitions、Images、Toolbars、Documents、Tab bars、Alerts、Gestures）不含 Scene/window 可见性条目。
  来源：https://developer.apple.com/documentation/updates/swiftui

### 与收拢机制直接相关的两条既有约束

- "In iPadOS and visionOS, the system ignores the dismiss action if you use it to close a window that's your app's only open scene."以及"Because you can't programmatically close the last open window or immersive space in a visionOS app, be sure to open a new scene before closing the old one."——先开新场景再关旧场景的次序是官方要求。
  来源：https://developer.apple.com/documentation/visionos/presenting-windows-and-spaces
- "On visionOS, the system may background the last dismissed scene instead of closing it."（"may"，非承诺）——最后一个被 dismiss 的场景可能被后台化而非关闭；这是否影响"空间关闭瞬间无窗口场景→直达 Home"的判定，文档未说明。
  来源：https://developer.apple.com/documentation/SwiftUI/Scene/defaultLaunchBehavior(_:)

---

## 问题二：AVPlayerViewController 停靠期间，宿主窗口场景是否存活

### 结论：文档直接确认停靠对象就是"窗口场景"本身——停靠即窗口场景被锚定，而不是被关闭或替换

- `DockingRegionComponent`（RealityKit，visionOS 2.0+）摘要与总览（verbatim）："A component that docks a scene within a region of an immersive space."；"A docking-region component establishes a fixed area within an immersive environment that an AVPlayerViewController window scene anchors to, which prevents a person from moving the window with a pinch-and-drag gesture."——被停靠的实体在文档措辞中就是 "AVPlayerViewController **window scene**"，停靠的效果是锚定与禁用拖动，不涉及场景销毁。
  来源：https://developer.apple.com/documentation/realitykit/dockingregioncomponent
- visionOS 官方文章对停靠流程的描述："In visionOS, AVPlayerViewController participates in the system docking behavior. When you play video in a full-window player then open an immersive experience, the system docks the video screen in a fixed location and presents streamlined playback controls… The system determines the docking location for the scene by default."（注意 "for the scene"）。
  来源：https://developer.apple.com/documentation/visionos/building-an-immersive-media-viewing-experience
- WWDC24 10115 对停靠的定义："Docking enhances the fullscreen experience in an immersive space by placing the video screen into a fixed location. By default, the system determines the docking location, but now you can customize this location by specifying a custom docking region."
  来源：https://developer.apple.com/videos/play/wwdc2024/10115/
- AVExperienceController（visionOS 2.0+）的体验模型同样以窗口场景为载体：WWDC25 296 文稿——"The Expanded experience allows AVPlayerViewController to consume the entire UI window Scene"；immersive 体验的放置配置 `Configuration.Placement.over(scene: UIScene)`（visionOS 26.0+，"Place the video over the provided scene"）；"If the AVPlayerViewController is already contained in the view hierarchy, AVExperienceController will assume that the window scene where it is contained, is the desired placement scene."即使转入 immersive 体验，API 语义仍是"呈现在某个 UIScene 之上"，场景是持续存在的锚点。
  来源：https://developer.apple.com/videos/play/wwdc2025/296/ ；https://developer.apple.com/documentation/avkit/avexperiencecontroller ；https://developer.apple.com/documentation/avkit/avexperiencecontroller/configuration-swift.struct/placement-swift.struct/over(scene:)

### 表冠按压与停靠环境关闭：无直接文档，仅有一致性推论（标注为未验证）

没有任何官方文档描述"停靠中的播放器所在环境被表冠关闭时会发生什么"，也没有 Apple TV App 行为的开发者文档。可作一致性拼接的事实是：(a) 停靠期间播放器窗口场景存活（上节）；(b) DTS 已确认"沉浸空间与窗口共存时，按压一次只关空间、窗口保留"（https://developer.apple.com/forums/thread/774365 ，visionOS 2.x 时期）。二者合起来与"Apple TV 表冠按压回到窗口而非 Home"的观察一致，但"Apple TV 正因窗口场景存活而免于直达 Home"这句因果链本身**未被任何官方文字陈述**，只能标注为高度一致的推论。

---

## 问题三：第三方能否把任意窗口/内容停靠进沉浸环境

### 结论：不能。停靠是 AVPlayerViewController 专属的系统行为；第三方可控的只有停靠位置

- `DockingRegionComponent` 是第三方唯一能触碰的停靠 API，而它的作用被文档限定为给 "AVPlayerViewController window scene" 提供锚定区域（原文见问题二）。没有任何 API 把任意 WindowGroup/Window/自绘内容声明为可停靠对象。
  来源：https://developer.apple.com/documentation/realitykit/dockingregioncomponent
- visionOS 26 的新增（AVExperienceController 的 immersive 体验、`withTransitionGroup` 等）全部挂在 AVKit 播放器体系上；visionOS 27 的新增（宽高比 portal、nonstandard aspect ratio portal window，"in both RealityKit and AVKit-based apps"）扩展的是**媒体 portal 呈现**，同样没有"任意窗口停靠"。
  来源：https://developer.apple.com/documentation/avkit/avexperiencecontroller ；https://developer.apple.com/visionos/whats-new/
- 对无法使用 AVPlayerViewController 的 Enchron，官方给出的"视频进入沉浸空间"的替代通道不是窗口停靠而是 RealityKit 实体：`VideoPlayerComponent`（含 `init(videoRenderer: AVSampleBufferVideoRenderer)`，visionOS 2.0+），WWDC25 296 明言其适合沉浸观看模式并以 Destination Video 的 video docking 为例——但那是把视频渲染为空间内实体，位置由 App 自己经营，不是系统 docking 行为的参与者。该通道的能力边界详见同目录 `visionos-progressive-crown-and-playback-continuity-2026-08-11.md` 问题三。
  来源：https://developer.apple.com/documentation/realitykit/videoplayercomponent/init(videorenderer:) ；https://developer.apple.com/videos/play/wwdc2025/296/
- `pushWindow` 只做"窗口顶替窗口"，目标限 `WindowGroup` 与 `Window`，不提供进入沉浸环境的停靠语义。
  来源：https://developer.apple.com/documentation/swiftui/environmentvalues/pushwindow

---

## 问题四：progressive 空间 + 存活小窗时，单次表冠按压的现行官方口径

- visionOS 2.x 时期的 DTS 确认（2025-04，Recommended）：按压一次只关闭沉浸空间、窗口保留在共享空间，第二次按压才回 Home View；DTS 同时确认这与用户指南"单按开 Home View"的文字不一致并归为待修复项。此为既有证据，无更新版本的 DTS 表态。
  来源：https://developer.apple.com/forums/thread/774365
- visionOS 26 时期的新佐证（WWDC25 290 文稿，演示者叙述，verbatim）："Currently, if I dismiss the immersive space by pressing the crown and close the Tools window, I'll find this window coming back when launching the app again."——演示情境是 progressive/沉浸空间 + 独立 tools 窗口共存：按压表冠的效果被描述为"dismiss the immersive space"，tools 窗口仍需另行关闭。这与 DTS 描述的行为在 visionOS 26 上保持一致，虽非针对按压语义的正式契约陈述。
  来源：https://developer.apple.com/videos/play/wwdc2025/290/
- 用户指南口径未变：单次按压 = "open Home View"（Digital Crown 释义）；"Adjust immersion" 页另有"双击看现实、再按一次回到沉浸体验"的往返描述。文档与实机行为的矛盾在 Apple 侧仍未收敛为一份一致的契约。
  来源：https://support.apple.com/guide/apple-vision-pro/aside/dev1b8eda1e7/visionos ；https://support.apple.com/guide/apple-vision-pro/adjust-immersion-tan899d290e4/visionos
- 未找到 visionOS 26/27 上关于该行为的任何新 DTS 署名回复或文档更新。

---

## 官方文档未回答、需真机实验裁决的残留问题

1. **"视觉最小化存活窗"组合的实效**：`Window` + `.windowStyle(.plain)` + 透明内容 + `.persistentSystemOverlays(.hidden)` 在共享空间/沉浸空间共存时，window chrome 是否真被隐藏（文档只承诺"偏好"）、空内容窗口是否残留可见玻璃或命中区域、用户会不会误触。全链条无文档，需真机。
2. **pushWindow 与 ImmersiveSpace 的交互**：从 pushed window 打开沉浸空间是否允许；空间开启期间被顶替（backgrounded）的主窗是否计入"可见窗口"；表冠按压关闭空间后 pushed window 是否保留、dismiss pushed window 是否仍能唤回主窗。文档均未覆盖。
3. **表冠单按行为在 visionOS 26/27 的现状**：DTS 确认（visionOS 2.x）与 WWDC25 290 叙述一致，但 Apple 曾把它标记为"与文档不一致、建议 Feedback"，不排除后续版本改回"单按直达 Home"。需在目标 OS 真机上以 progressive 空间 + 存活小窗验证。
4. **"最后一个被 dismiss 的场景可能被后台化"的实际判定**：Enchron 现行"先 dismiss 全部窗口再开空间"的路径下，被 dismiss 的窗口场景是否处于后台化状态、表冠关闭空间后系统是否会自动呈现它（而非直达 Home），"may background" 无行为承诺，需真机。
5. **Apple TV 停靠播放器的表冠语义**：无任何开发者文档描述停靠环境被表冠关闭时的具体过渡；"窗口场景存活→按压回窗口"的因果只能在真机上对照观察（Apple TV App 与 Enchron 自建场景拓扑各录一次行为序列）。
