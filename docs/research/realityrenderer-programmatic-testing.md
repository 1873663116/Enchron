# RealityRenderer 程序化验证边界

本文回答一个具体问题：Apple 现有工具是否足以让 Agent 程序化验证 Enchron 的 RealityKit 视频呈现，以及还需要补充什么最小测试设施。

结论是：`RealityRenderer` 可以成为测试工具，但不能成为新的运行时，也不能代替 Xcode、XCTest、visionOS `ImmersiveSpace` 或 Vision Pro。它最适合在既有 Apple 测试体系中承担“可重复的 RealityKit 离屏渲染探针”：把 Enchron 实际使用的 `AVSampleBufferVideoRenderer` 接入 `VideoPlayerComponent`，观察语义事件，并将 RealityKit 结果渲染到测试提供的 Metal texture。它能缩短像素进入 RealityKit 之后的验证路径，但不能独立证明系统合成、沉浸空间切换、头显观感、硬件解码或 HDR 显示。

## API 事实

公开 API 的精确名称是 RealityKit 的 [`RealityRenderer`](https://developer.apple.com/documentation/realitykit/realityrenderer)、RealityKit 的 [`VideoPlayerComponent`](https://developer.apple.com/documentation/realitykit/videoplayercomponent)，以及 AVFoundation 的 `AVSampleBufferVideoRenderer`。Xcode 27 beta 2 的 macOS、visionOS 和 visionOS Simulator SDK 中均没有公开的 `VideoPlayerRenderer` 类型；代码和文档不应继续使用这个名称。

`RealityRenderer` 不是 WWDC26 才新增的 API。本机 SDK 将它标记为 visionOS 1.0、macOS 15.0、iOS 18.0、Mac Catalyst 18.0 和 tvOS 26.0 可用。Apple 将它定义为嵌入已有 Metal 工作流的 RealityKit renderer；其 [`CameraOutput`](https://developer.apple.com/documentation/realitykit/realityrenderer/cameraoutput) 由调用方提供 Metal texture 和 viewport，随后通过 [`updateAndRender`](https://developer.apple.com/documentation/realitykit/realityrenderer/updateandrender%28deltatime%3Acameraoutput%3Awhenscheduled%3Aoncomplete%3Aactionsbeforerender%3Aactionsafterrender%3A%29) 更新并渲染。因此它支持真正的程序化、离屏输出，但本身并不创建窗口、SwiftUI scene 或 visionOS immersive space。

本机 SDK 证据：

- visionOS：`/Applications/Xcode-beta2.app/Contents/Developer/Platforms/XROS.platform/Developer/SDKs/XROS27.0.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/RealityFoundation.swiftmodule/arm64e-apple-xros.swiftinterface:2022`
- visionOS Simulator：`/Applications/Xcode-beta2.app/Contents/Developer/Platforms/XRSimulator.platform/Developer/SDKs/XRSimulator27.0.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/RealityFoundation.swiftmodule/arm64-apple-xros-simulator.swiftinterface:2022`
- macOS：`/Applications/Xcode-beta2.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/RealityFoundation.framework/Versions/A/Modules/RealityFoundation.swiftmodule/arm64e-apple-macos.swiftinterface:2021`

三处声明均包含接收 `[MTLTexture]` 与 viewport 的 `CameraOutput.Descriptor`、`singleProjection(colorTexture:)` 和 `updateAndRender(...)`。Apple 的 [`RealityRenderer` 文档](https://developer.apple.com/documentation/realitykit/realityrenderer)还明确说明，RealityKit 的资源、entity 和 component API 可以用于该 renderer。

`VideoPlayerComponent(videoRenderer: AVSampleBufferVideoRenderer)` 在 visionOS 2.0、macOS 15.0、iOS 18.0、Mac Catalyst 18.0 和 tvOS 26.0 可用。本机 SDK 位置：

- visionOS：上述 XROS swiftinterface `:13407`
- visionOS Simulator：上述 XRSimulator swiftinterface `:13309`
- macOS：上述 macOS swiftinterface `:13415`

Apple 对 [`VideoPlayerComponent`](https://developer.apple.com/documentation/realitykit/videoplayercomponent) 的定义很关键：组件会根据当前视频及组件属性自行创建 mesh 和 material。也就是说，全景投影不是 Enchron 应当另写的一组“复杂画面参数”，但测试仍必须提供具有有效格式与投影元数据的视频。只创建一个空的 `AVSampleBufferVideoRenderer`，然后设置模式，并不会触发或证明球形投影。

## 平台差异

在 macOS 上，`RealityRenderer` 和 `VideoPlayerComponent(videoRenderer:)` 都可用，可以验证平面视频的 sample 是否进入 RealityKit、组件是否到达 ready 状态、视频尺寸，以及输出 texture 是否出现预期的粗粒度像素变化。本次调查还在普通 macOS 命令行进程中实际运行了 64 × 64 的离屏 smoke test：`RealityRenderer` 将红色 camera background 写入调用方提供的 `bgra8Unorm` Metal texture，在 `onComplete` 后读取到 16,384 个非零字节。这确认了 macOS 进程可以承载离屏 RealityKit 测试；它不是对视频投影的证明。

macOS 不能验证沉浸视频模式。`desiredImmersiveViewingMode` 和实际的 `immersiveViewingMode` 在 macOS SDK 中被明确标记为 unavailable；equirectangular、half-equirectangular 和 parametric immersive 等内容类型也不可在 macOS 使用。对应声明位于 macOS swiftinterface `:13346`、`:13356` 附近。因此 macOS 测试不能证明 180°、360°、`.portal`、`.full` 或 `.progressive` 的投影和切换。

visionOS Simulator SDK 同时提供 `RealityRenderer` 和沉浸视频 API。`desiredImmersiveViewingMode` 与实际 `immersiveViewingMode` 位于 XRSimulator swiftinterface `:13212`、`:13222`；内容类型事件的 equirectangular、half-equirectangular 与 parametric immersive case 位于 `:8043`、`:8050`、`:8057`；rendering status 事件位于 `:8118`。因此 Simulator 至少具备编译和运行组件级能力探针的 API 条件。

2026-07-15 在 Xcode 27 beta 2 / visionOS 27 Simulator 上的实测进一步缩小了边界。`XrPlayerUITests/RealityRendererProgrammaticTests.swift` 中的纯 `RealityRenderer` 测试能够完成 `updateAndRender`，并从调用方提供的 64 × 64 `bgra8Unorm` texture 读到非零像素；它已进入常规 Simulator 回归。随后两次独立的 `VideoPlayerComponent` 探针都使 `XrPlayerUITests-Runner` 崩溃：第一次挂载空 `AVSampleBufferVideoRenderer`，第二次先 enqueue 带 `kCMFormatDescriptionProjectionKind_Equirectangular` 与 360° horizontal field-of-view 的 BGRA sample。两次都在第一次 `RealityRenderer.update` 前后出现 RealityKit Video 的 `Default Value Not Found`，尚未产生 content type、ready 或实际 immersive mode 事件。失败记录分别位于 `/tmp/Enchron-RealityRenderer-20260715-2023.xcresult` 与 `/tmp/Enchron-RealityRenderer-Projected-20260715-2026.xcresult`。

因此，当前 Simulator 可以作为通用 RealityKit 离屏渲染回归宿主，但还不能把 `VideoPlayerComponent` 的离屏探针放入常规通过矩阵。下一步应改用符合 Apple Projected Media Profile 的真实压缩 fixture，并先在独立的普通 visionOS unit-test host 中重试；在该路径稳定前，Enchron 的 VideoPlayerComponent 仍由产品 `RealityView` 的 Simulator / Vision Pro 集成测试覆盖。会导致 Runner 崩溃的实验代码不保留在常规测试 target 中。

但是 Simulator 不等于设备。Apple 的[模拟器与真机说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)明确提醒 Simulator 不复现物理设备的全部性能和硬件能力。离屏 camera texture 也不是 visionOS compositor、头部姿态、Digital Crown 控制的 progressive immersion 或头显显示结果。硬件解码、HDR/EDR 最终映射、性能和佩戴观感仍须 Vision Pro 验证。

## 模式切换应观察什么

`desiredImmersiveViewingMode` 只是请求值。有效证据应来自实际的 [`immersiveViewingMode`](https://developer.apple.com/documentation/realitykit/videoplayercomponent/immersiveviewingmode-swift.property)、[`ImmersiveViewingModeDidChange`](https://developer.apple.com/documentation/realitykit/videoplayerevents/immersiveviewingmodedidchange)、[`RenderingStatusDidChange`](https://developer.apple.com/documentation/realitykit/videoplayerevents/renderingstatusdidchange) 和内容类型变化事件，而不是把 desired property 写入后再读回来。

Apple 在 [WWDC25 的沉浸媒体介绍](https://developer.apple.com/videos/play/wwdc2025/296/)与[沉浸媒体示例](https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit)中说明了两层条件：`VideoPlayerComponent` 的 mode 与 SwiftUI `ImmersionStyle` 都会影响实际呈现，且二者需要匹配。`.full` 和 `.portal` 自 visionOS 2.0 可用，`.progressive` 自 visionOS 26 可用；`portalSize` 则是 visionOS 27 API。只在 `RealityRenderer` 中设置 mode，无法证明应用的 `ImmersiveSpace` 已成功切换，也无法证明 progressive space 或系统 passthrough 的行为。

因此，当前程序化测试如果仅执行以下动作：

```swift
component.desiredImmersiveViewingMode = .full
XCTAssertEqual(component.desiredImmersiveViewingMode, .full)
```

它只能证明一个可变属性保存了写入值。它不能证明媒体被识别为全景内容、组件生成了相应 mesh、系统接受了模式、texture 中出现正确投影，或用户所在 scene 发生了变化。

更有价值的 Simulator 探针需要使用符合 Apple profile 的确定性测试媒体，并通过实际 PlaybackCore sample assembly 输入 `AVSampleBufferVideoRenderer`。测试应订阅内容类型、rendering status 和实际 immersive mode 的事件；然后在固定 camera 朝向下离屏渲染。若使用带方向色块或网格标记的 equirectangular fixture，可以通过多个已知 yaw 的粗粒度区域检查，判断投影是否明显错误。精确逐像素 golden image 容易受采样、色彩转换和 SDK renderer 变化影响，不适合作为首要契约。

即便该探针成功，它也只证明：有效投影元数据经 PlaybackCore 到达 AVFoundation，RealityKit 识别了内容，组件进入 ready/实际模式，并在测试 camera 下生成了与预期大致一致的图像。它不证明：真实 `ImmersiveSpace` 的系统切换、窗口与空间生命周期、head tracking、compositor passthrough、Digital Crown 行为、硬件解码、HDR 显示或最终佩戴体验。

如果实际 mode 在 `RealityRenderer` 单独运行时始终不确认，也不能立即判为产品缺陷；原因可能是测试没有配套的 `ImmersiveSpace` 和 `ImmersionStyle`。此时测试应记录这是 `RealityRenderer` 的能力边界，并把模式确认移到 visionOS UI integration test，而不是继续扩建自定义运行时。

## Enchron 当前实际接口

Enchron 没有使用 `RealityRenderer` 作为产品运行时，也没有使用名为 `VideoPlayerRenderer` 的 API。当前链路是：

- `Enchron/XrPlayer/App/PlaybackRuntime.swift` 持有 `AVSampleBufferVideoRenderer?`；fixture 路径创建该 renderer，真实运行时由 PlaybackCore session 提供。
- `Enchron/XrPlayer/PlayerUI/Views/PlaybackVideoSurface.swift` 使用 `VideoPlayerComponent(videoRenderer: renderer)`，并请求 panorama `.full`、其他模式 `.portal`。
- `Enchron/XrPlayer/SpatialScene/Scenes/ImmersiveSpaceView.swift` 使用相同 initializer，并请求 panorama `.full`、docked `.portal`。

这已经符合“AVFoundation/RealityKit 负责视频呈现与投影，Enchron 负责组合和请求模式”的边界。当前缺口不是再造一个 renderer，而是没有把实际 `immersiveViewingMode`、内容类型、rendering status 和模式变化事件纳入可观测证据。单独的 `print` 或 desired property 断言不足以填补这个缺口。

## 最小可行测试

第一项值得实现的测试不是一个大型 Enchron CLI，而是一个运行于 visionOS Simulator 的 XCTest capability probe：使用一段带明确方向标记、符合 Apple 投影 metadata/profile 的短测试媒体；让它经过真实 PlaybackCore sample assembly，取得与 SwiftUI 完全相同的 `AVSampleBufferVideoRenderer`；创建 `VideoPlayerComponent(videoRenderer:)` 并挂到 `RealityRenderer`；订阅 content type、rendering status 与实际 immersive mode；在固定 camera 朝向下输出少量离屏帧并做粗粒度区域断言。

该测试先只回答四个问题：媒体是否被 RealityKit 识别为预期投影类型，组件是否 ready，平台是否确认请求的实际模式，以及 camera texture 是否出现方向上合理的投影结果。如果前三项中的模式确认因为缺少真实 `ImmersiveSpace` 而无法成立，就停止扩大离屏 harness，把模式切换留给一个窄的 XCUITest/visionOS integration test。最后保留一次 Vision Pro 验收，覆盖真实沉浸空间、硬件解码、HDR 和佩戴体验。

macOS 可并行保留更便宜的 flat-path smoke test，证明 PlaybackCore 的 sample 能进入 `VideoPlayerComponent` 并产出非空离屏 texture；不要把它命名或解释为 panorama 验证。

Apple 对投影元数据的格式定义可参考其 [Stereo Video ISOBMFF Extensions](https://developer.apple.com/av-foundation/Stereo-Video-ISOBMFF-Extensions.pdf)。RealityKit API 的版本演进记录见 [RealityKit updates](https://developer.apple.com/documentation/updates/realitykit)。
