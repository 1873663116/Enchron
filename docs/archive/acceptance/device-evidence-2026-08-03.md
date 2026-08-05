# 2026-08-03 Window 空间呈现入口真机记录

本次结果绑定的产品树摘要为 `d698a33b0f9518fd1f07098df92ca80e156a7087704f14af1ce7e06b03ac70ea`。测试在物理 Vision Pro 上通过 Media Library 登记条目进入生产播放路径，只执行以下两个 Test Plan 已登记方法：

- `SpatialHandoffUITests.testDockedTargetIsReadyBeforeWindowStopsBeingTheUsableSurface`
- `SpatialHandoffUITests.testPanoramaTargetIsReadyBeforeWindowStopsBeingTheUsableSurface`

结果为执行 2 个、通过 0 个、失败 2 个、跳过 0 个，Xcode 结果值为 `Failed`。Xcode 在每个失败后重新启动 UI Test Runner，最后一次启动没有匹配到待执行方法；结果验证器仍按两个计划内方法的实际结果判定失败，没有把零测试启动改判为通过。完整结果位于 `/private/tmp/enchron-validation-evidence/visionpro-spatial-input-current-20260803-173434/`，其中包括构建和测试 `.xcresult`、测试汇总、设备状态诊断、日志和产品树 manifest。

两个方法在执行空间操作前都取得了相同类型的直接播放证据：Window 中显示真实视频帧，时间线、video sample 和 renderer accepted input 持续推进，`VideoPlayerComponent` 已显示画面；存在音轨，audio sample 持续推进且 audio renderer 为 `rendering`。佩戴者视角截图也显示视频和 Window 播放控件已经实际渲染。

Docked 方法打开了可见的 Dock 面板，Day 选项存在、启用且由 XCUITest 报告可命中。通过该 Accessibility 元素点击 Day 后，产品没有产生 Docked Presentation request：状态仍为 Window，Presentation Transition 为 `none`，Immersive Space 为 `closed`，空间目标状态元素不存在；同时 `tapTrace` 记录视频表面将播放控件切换为隐藏。点击后的截图显示视频仍在 Window 中播放，Dock 面板与播放控件已经消失。

Panorama 方法打开了 Video Format 面板，并找到存在、启用且可命中的 360° 选项。点击该选项后 Apply 不再存在，产品没有产生 Panorama Presentation request；失败状态仍为 Window，Presentation Transition 为 `none`，Immersive Space 为 `closed`，`tapTrace` 同样记录视频表面将播放控件切换为隐藏。失败截图显示视频继续播放，格式面板和播放控件已经消失。

本次运行证明该产品树上可见二级面板的 Accessibility 点击结果与相应产品操作不一致。该版本源码把 Dock 与 Video Format 面板作为顶部圆形按钮的 `overlay`，再把面板偏移到按钮布局范围之外；真机结果与面板绘制范围和实际命中范围不一致相符。第一处失败边界是 Window 播放界面的 SwiftUI 输入处理。Docked/Panorama 的 Player Controls Window、Immersive Space、Environment、Anchor、Entity、纹理和返回路径均未到达，因此该结果不构成这些 RealityKit 或系统 Scene 后置条件的失败证据。

## 同期基础集记录

同一时期的真机参考运行中，`SmokeLaunchUITests.testAppLaunchesToInteractiveMainWindow` 完成 Media Library surface 与 Files tab 的存在、启用和可命中断言，佩戴者视角截图确认主窗口和媒体条目已经实际渲染。`SequentialMediaPlaybackUITests` 也使用两个 Media Library 登记条目依次建立新 Media Session，取得持续推进的画面、音频和时间线，并在每次返回后未观察到前一 Session 泄漏。

同期执行的六方法基础集没有通过：结果包记录了两个通过和其余失败，并在失败后的 Runner 重启中产生了额外测试记录。结果验证器按计划内方法的实际结果判定失败，没有把零测试启动改判为通过。

临时远程测试媒体曾在设备端返回连接被拒绝；该结果属于当时的测试媒体基础设施失败，不能归因于 Docked 产品路径。
