# Window Playback Preview Fixture 调查与交接

> 持续更新文档。维护 `DesignPreview` / `DesignComps` 的 Window Playback Preview 前，先读本文件，再改 `WindowPlaybackPage.swift`。

## 目的

本文件记录 Window Playback Preview 的正确参考样本、Canvas / Simulator / 生产管线边界，以及当前 Canvas visual fixture 的实现约束。目标是避免后续 Agent 重新走一遍“手写 1920x1080 窗口、蓝色平面、双边界、错用 immersive sample、圆角/resize 猜测”的弯路。

当前任务边界：

- `Window Playback Preview` 是 DesignPreview 的 Canvas 可靠视觉 fixture。
- 当前阶段允许用一张图片代替视频内容，只验证窗口化普通平面视频播放器的视觉层级、显隐交互和 resize 语义。
- 不把生产 mpv、`CAMetalLayer`、`AVPlayer`、`AVPlayerViewController`、`VideoPlayerComponent` 接入作为本任务目标。
- 不把 Canvas 中的单页 `#Preview` 当作真实 `WindowGroup` lifecycle / scene placement / runtime resize 行为证明。

## 先读位置

- 本文档：`docs/solutions/best-practices/window-playback-preview-fixture.md`
- Preview 页面：`DesignPreview/DesignComps/Pages/Player/WindowPlaybackPage.swift`
- Preview 入口：`DesignPreview/DesignComps/DesignCompsPreviewGallery.swift`
- Scene 容器：`DesignPreview/DesignPreviewApp.swift`
- DesignPreview 规则：`DesignPreview/AGENTS.md`
- DesignComps 规则：`DesignPreview/DesignComps/AGENTS.md`
- 平台路由：`.agents/skills/visionos-platform/SKILL.md`
- Apple DocSet：
  - `~/DocSetQuery/docs/apple/Apple-Media-Device/avkit-adopting-the-system-player-interface-in-visionos.md`
  - `~/DocSetQuery/docs/apple/Apple-UI-Frameworks/swiftui.md`
- Apple samples：
  - `~/Documents/CodeReferences/Apple/visionOS/VideoPlayback/apple-official/zips/DestinationVideo.zip`
  - `~/Documents/CodeReferences/Apple/visionOS/VideoPlayback/apple-official/CreatingAMultiviewVideoPlaybackExperienceInVisionOS/`

## 正确参考范围

当前产品阶段是窗口化普通平面视频播放器。主参考顺序：

1. Apple AVKit 文档 `Adopting the system player interface in visionOS`
2. Apple sample `Destination Video`
3. Apple sample `Creating a multiview video playback experience in visionOS`

本地证据：

- AVKit 文档说明 visionOS 推荐使用 `AVPlayerViewController` 提供播放界面；它覆盖 standard 2D content 和 immersive 3D video，但本文当前只取 standard 2D / windowed player 语义。
- AVKit 文档说明 `AVPlayerViewController` 可在 visionOS windowed environments 中播放视频，并会根据 presentation 自适应 UI。
- AVKit 文档说明 inline player 只显示 standard 2D video；3D content 需要 fullscreen。这正好确认当前 flat video fixture 不应该被 immersive profile 牵走。
- `Destination Video` 的 visionOS full-window 路径是 `WindowGroup -> ContentView -> PlayerView -> SystemPlayerView -> AVPlayerViewController`。visionOS 端不是 macOS 那个单独 `PlayerWindow` scene。
- `Destination Video` 的 inline custom controls 路径是 `InlinePlayerView -> ZStack(VideoContentView, InlineControlsView)`，其中 `VideoContentView` 包装 `AVPlayerViewController` 并关闭系统 controls，然后把自定义 controls overlay 到视频内容上。
- `Creating a multiview...` 的 app scene 使用 `WindowGroup { ContentView().frame(minWidth: 1200, minHeight: 600) }.windowResizability(.contentSize)`；这个样本用于理解 window resize 约束如何配合内容 frame，而不是给 Canvas 写像素窗口。

不作为当前主参考的样本：

- `PlayingImmersiveMediaWithRealityKit`：该 sample 的内容库包含 Spatial Video、APMP 180、APMP 360、APMP Wide FOV、Apple Immersive Video。它服务于 RealityKit / `VideoPlayerComponent` / immersive media profile，不主导当前 flat 2D window fixture。
- `PlayingImmersiveMediaWithAVKit`：该 sample README 和数据源都指向 immersive media，包括 Spatial、Wide FOV、180、360、Apple Immersive Video。它不主导当前 flat 2D window fixture。

## 当前 Fixture 层级

Canvas fixture 按普通播放器的视觉语义建模，不接真实视频管线：

```text
WindowGroup(id: DesignPreviewNavigationModel.windowPlaybackWindowID)
└─ WindowPlaybackPage
   ├─ .aspectRatio(16:9, contentMode: .fit)
   ├─ .frame(depth: 1)
   ├─ scaledPlaybackBoundary
   │  └─ playbackBoundary
   │     ├─ renderSurface fixture fills the same boundary
   │     ├─ chromeToggleTarget handles non-control-area taps
   │     └─ playbackChrome
   │        ├─ top/bottom gradient masks
   │        └─ controls over masks
   └─ WindowPlaybackSceneResizePreference
      └─ UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .uniform)
```

Z 轴顺序必须保持：

1. 图片 fixture / render surface
2. 上下渐变蒙版
3. 顶部按钮和底部播放控件

这样能保证“播放控件下面是蒙版”，而不是控件和蒙版处在两个不同边界里。

当前实现用 `renderSurface` 上方、`playbackChrome` 下方的透明 `chromeToggleTarget` 做非控件区域点击显隐，不把整面板包成 `Button`，避免整张播放面产生不需要的 button hover / focus 外观。`playbackChrome` 在可见时参与 hit testing，让返回、Expand 和底部播放控件保持标准 Button / control 语义；蒙版本身继续禁用 hit testing，避免全尺寸渐变层吃掉“再次点击窗口隐藏”的命中。

## Canvas 实现规则

- `WindowGroup` 只保留播放窗口容器语义；页面自身只表达一个 `16:9` playback boundary。
- 图片 fixture、返回按钮、Expand 按钮、上下渐变蒙版共享同一个 boundary。
- 顶部只保留左上返回按钮和右上 Expand。
- 点击播放边界的非控件区域切换 chrome：隐藏时只显示内容；点击后显示蒙版和 controls；再次点击非控件区域隐藏。
- 非控件区域点击语义当前由 `chromeToggleTarget` 承担，不使用整面板 `Button`，也不使用 `SpatialTapGesture`；可见 chrome 内的按钮和 controls 必须能正常命中。
- chrome 隐藏时立刻把进度条收回一级进度条；二级精度时间轴状态不能跨隐藏 / 显示循环保留，也不能在下一次显示时才播放退场动画。
- 当前底部 controls 放在 playback boundary 内。若未来要半露出边界，需要先用 runtime / Canvas 截图证明不会被系统或 fixture shape 错误裁切。
- 删除 `1920x1080` 手动窗口/分辨率建模、蓝色平面、小屏幕布局、外层灰框、`WindowPlaybackResizeConfigurator` 等脱离 playback boundary 的实现。
- 不接入生产 mpv、`CAMetalLayer`、`MTKView`、`AVPlayer`、`AVPlayerViewController`、`VideoPlayerComponent`。

## Canvas 交互验证记录

2026-05-28 本轮已验证：

- Xcode Canvas direct preview 可渲染初始 hidden 状态：单一圆角 16:9 图片面板，无外层灰框 / 内层小图双边界。
- 临时把 `isChromeVisible` 设为 `true` 时，Canvas 可渲染 visible 状态：上下蒙版、返回按钮、Expand、底部 controls 共享同一个播放边界，且 controls 在蒙版之上。
- `SpatialTapGesture` 曾导致 Xcode `PreviewShell` 崩溃，不适合作为当前 Canvas fixture 的整面板点击方案。
- 本轮用 Computer Use 点击 Xcode visionOS Canvas 内容时，没有触发 SwiftUI 状态切换；这只能说明 Computer Use 不能作为本轮 Canvas 点击事件的可靠证明工具，不能推出“Canvas 不能模拟该界面”。需要人工在 Xcode Canvas 中点击，或升级到 Simulator / runtime，才能证明事件分发。

因此交付时要分清：

- Canvas 静态视觉和两个状态都能验证。
- 通过代码结构可以表达点击显隐。
- Computer Use 截图可以辅助看视觉，但不要把 Computer Use 点击 Xcode Canvas 的失败当成产品结论。

## 圆角与窗口形状

正确判断：

- Apple flat/window player 参考样本没有在 `PlayerView` / `SystemPlayerView` 上手写播放器窗口 `cornerRadius`。
- visionOS window chrome 和 AVKit system player 外观是系统呈现语义；Canvas 中的自定义图片 fixture 不会自动得到完整系统播放器外观。
- `DesignTokens.Radius` 里已有项目规则：Window chrome is system-managed，不要把 Canvas fixture 的圆角模拟升级成生产窗口手写圆角规则。

当前 fixture 取舍：

- Canvas 需要呈现“不是直角矩形”的播放器面板，所以 `WindowPlaybackPage` 使用 `DesignTokens.Radius.panel` 作为 review-only playback boundary mask。
- 这个 mask 只服务 Canvas visual fixture；它不证明真实 AVKit / mpv /系统窗口最终圆角数值，也不是生产播放窗口 contract。

## Resize 调查结论

不要再把 `1920x1080` 当成实际显示分辨率、scene 尺寸或强制窗口尺寸。

已知事实：

- AVKit 文档把 `AVPlayerViewController` 作为 visionOS system player baseline；其 UI 会按 presentation 自适应。
- `Destination Video` 的 visionOS full-window player 直接把 `PlayerView` 作为 `ContentView` 的 full-window 状态，而不是在内部再建一个“小屏幕”。
- `Creating a multiview...` 用 `.windowResizability(.contentSize)` 配合内容 `.frame(minWidth:minHeight:)` 表达窗口 resize 限制。
- SwiftUI `defaultSize` 只影响新窗口首次出现的默认尺寸；状态恢复和用户后续 resize 可以覆盖它。
- SwiftUI `windowResizability(.contentSize)` 需要和内容 frame 约束一起使用，才能表达 min/max resize 范围。
- UIKit / visionOS 的 `UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .uniform)` 是当前 SDK 中表达“用户 resize 保持当前 aspect ratio”的 API；它是 scene-level preference，不是播放管线、分辨率或 render surface。

2026-05-29 resize 复盘：

- Canvas 左右边缘的白色弯曲控件不是页面里的 SwiftUI `Button`，可称为系统 window resize handle / resize affordance。
- 出现“图片等比，但按钮和播放控件不等比”的直接原因是：图片被 `.aspectRatio(.fit)` / render surface sizing 保护住了，但 chrome 使用固定 token 尺寸；当外层 window proposal 被压扁时，固定尺寸控件不会自动按播放面缩放。
- 出现“resize handle 可以被任意上下拖”的直接原因是：`WindowGroup` 只保留了 `.windowStyle(.plain)`，没有 `.windowResizability(.contentSize)` 和内容 min/ideal/max frame 共同给系统提供 content-size resize 范围，也没有 scene-level `.uniform` resize preference。
- 当前修正把 `WindowPlaybackPage` 放进 16:9 设计坐标系，图片、蒙版、返回按钮、Expand、progress strip、control bar 一起 uniform scale；`DesignPreviewApp` 的 `WindowGroup` 同步声明 default 逻辑尺寸和 `.windowResizability(.contentSize)`；页面内部用 `WindowPlaybackSceneResizePreference` 请求 `.uniform` 用户 resize。
- 这里的 `1280x720` / `960x540` / `1600x900` 是 Canvas fixture 的逻辑内容尺寸范围，不是生产播放分辨率，也不是 `1920x1080` 手写窗口模型。
- 如果 Xcode Canvas 仍允许把 window resize handle 拖成非 16:9，需要把它记录为 PreviewShell / Canvas 对 scene geometry preference 的疑似不完整模拟，然后用 visionOS Simulator runtime 或设备验证 `UIWindowScene.GeometryPreferences.Vision`。不要把 Canvas handle 行为直接等同于生产窗口行为。

2026-05-29 官方 sample resize 复核：

- `Destination Video` 的 visionOS path 是 `WindowGroup -> ContentView -> PlayerView -> SystemPlayerView -> AVPlayerViewController`。源码没有显式调用 `UIWindowScene.GeometryPreferences.Vision` 或 `resizingRestrictions`。
- `Destination Video` 只在 primary content window 上使用 `.frame(minWidth:maxWidth:minHeight:maxHeight:)` 和 `.windowResizability(.contentSize)`；full-window player 是 app content state 切换，不是单独 visionOS player `WindowGroup`。
- `Destination Video` 的 `PlayerWindow` / `windowIdealPlacement` / zoom aspect-ratio 计算只在 macOS 条件编译内，不是 visionOS resize handle 方案。
- `Creating a multiview...` 使用 `WindowGroup { ContentView().frame(minWidth: 1200, minHeight: 600) }.windowResizability(.contentSize)`，视频 surface 是 `AVPlayerViewController` wrapper；源码没有 `.uniform`。
- `PlayingImmersiveMediaWithRealityKit` 的 window player scene 是 `WindowGroup(id: PlayerWindow.sceneID) { VideoPlayerView(...).aspectRatio(16:9, .fit).frame(depth: 1).ornament(...) }.windowStyle(.plain)`，源码没有 `.windowResizability(.contentSize)` 或 `.uniform`。
- `PlayingImmersiveMediaWithAVKit` 使用 `AVPlayerViewController` 和 `experienceController.transition(to: .expanded)` 进入系统播放体验；源码没有手写 scene resize handle 约束。
- 公开 SDK 中明确表达“用户 resize 保持当前 aspect ratio”的 API 是 `UIWindowScene.GeometryPreferences.Vision(resizingRestrictions: .uniform)`；`windowResizability(.contentSize)` 只根据内容提供 min/max size 策略，不等价于 aspect-ratio lock。
- 因此，Apple demo 里看到的“只能斜向等比 resize”如果来自 AVKit system player / expanded experience，应视为系统播放器行为；如果要在 Enchron 自绘 / mpv / Canvas fixture 路径复刻，需要用真实 scene 上的 `.uniform` geometry preference 证明，而不能只靠 `#Preview` 的 SwiftUI view tree。
- Xcode Canvas 的 `#Preview("Window Playback", windowStyle: .plain) { WindowPlaybackPage() }` 不是 `DesignPreviewApp` 里的真实 `WindowGroup`，不会天然继承 scene-level `.windowResizability(.contentSize)`；即便 view 内部请求 `UIWindowScene.GeometryPreferences.Vision`，PreviewShell 是否执行这个 scene geometry request 仍需单独验证。

当前 Canvas fixture：

- `WindowPlaybackPage` 根部用 `.aspectRatio(16:9, contentMode: .fit)`，让 playback boundary 在任意 Canvas proposal 中保持 16:9。
- `WindowPlaybackPage` 用统一设计坐标系缩放整张 playback boundary，让固定 token 控件也跟着播放面等比例缩放。
- `WindowPlaybackFixtureSurface` 用 `GeometryReader` 读取当前 boundary 尺寸，把 fixture image frame 到同一个 boundary。
- fixture image 本身是 1920x1080 的 16:9 图片；这是素材像素尺寸，不是窗口/scene 建模。
- 图片用 `.aspectRatio(contentMode: .fill)` 填满 boundary，保持等比缩放，不拉伸。

需要 Simulator / runtime 的情况：

- 证明 `WindowGroup` 的真实 open / dismiss / restoration lifecycle。
- 证明 scene-level `windowResizability`、`defaultSize`、`UIWindowScene.GeometryPreferences.Vision` 的实际运行时效果。
- 证明系统 AVKit controls、system window chrome、scene placement 或 ornament 锚点。

必须走生产管线的情况：

- 证明 mpv 帧、`CAMetalLayer` / `MTKView` drawable size、HDR/EDR、字幕、远程 I/O、长时间播放性能。
- 证明生产播放器与系统 `AVPlayerViewController` 视觉或行为一致。

## 验证清单

修改 Window Playback Preview 后至少检查：

```sh
git diff --check
rg -n "1920|1080|RealityView|GeometryReader3D|ModelEntity|TextureResource|WindowPlaybackResizeConfigurator|UIImage|UIViewRepresentable|Color\\.blue|blue|SpatialTapGesture" \
  DesignComps/Pages/Player/WindowPlaybackPage.swift \
  DesignComps/DesignCompsPreviewGallery.swift \
  DesignPreviewApp.swift
```

2026-05-29 后 `WindowPlaybackPage.swift` 允许出现 `minimumSize` / `maximumSize`，但只应出现在 `WindowPlaybackSceneResizePreference` 里，用于 scene geometry preference。不要恢复旧的 `WindowPlaybackResizeConfigurator`。

需要编译证明时：

```sh
xcodebuild -project ../XrPlayer.xcodeproj \
  -scheme DesignPreview \
  -configuration Debug \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  build
```

Canvas 验收：

- 初始播放状态可只显示图片内容。
- 点击播放边界后，返回按钮、Expand 按钮、上下渐变蒙版和底部 controls 同时显现。
- 再次点击非控件区域后，controls 和蒙版同时消失。
- 隐藏 chrome 时二级精度时间轴已被收回；再次点击非控件区域唤出 controls 时，直接显示一级进度条，不出现二级时间轴退场动画。
- 只能看到一个明确的播放窗口边界。
- 图片内容、按钮、蒙版、controls 共享同一个 16:9 边界。
- 面板不是直角矩形。
- 不出现外层灰色大框 + 内层图片小框。
- 如果截图不符合，不要声称完成。

## 更新方式

后续每次对 Window Playback Preview 做边界调查、Apple sample 对照、Canvas/Simulator 结论或 resize 取舍时，都更新本文件。

更新时只写已验证事实：

- `证据来源`：代码路径、命令、截图、Simulator 行为、Apple docs 链接。
- `结论`：哪些能由 Canvas 验证，哪些必须 runtime，哪些必须生产管线。
- `影响`：是否改变 `WindowPlaybackPage.swift` 实现原则。
- `仍未证明`：不要把未验证推断写成规则。
