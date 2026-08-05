# Enchron 真机 XCTest 临时迁移清单

本文件只保存现有 XCTest 向 [`SCENARIOS.md`](SCENARIOS.md) 当前共享真机场景迁移的一次性工作。它不是产品规格、回归场景目录、Test Plan 或运行证据；迁移完成一项就删除对应记录，全部完成后删除本文件。

迁移有效断言时遵守 [`AGENTS.md`](AGENTS.md)，不沿用绕过正常 Media Library 的 autoplay 输入、与当前产品合同冲突的预期、只能证明控件存在的弱断言或问题关闭后仍冻结内部实现的诊断入口。

## 基础播放与媒体矩阵

- “本地媒体 Window 基础播放闭环”需要从现有连续媒体测试与 `VisionProDeviceAcceptanceUITests.testRealPlaybackCapturesPhysicalScreenAndState()` 迁移 checkpoint、持续推进和附件能力，补齐固定媒体、Pause、Resume、播放态 Seek、开头与结尾、Ended、Replay、物理声音边界和公开退出。Seek 的实现缺口由 PlaybackCore 统一拥有已知可 Seek 范围与非有限输入合同；SwiftUI 与 `PlaybackRuntime` 不分别维护范围权威。
- `VisionProIssueDiagnosticsUITests.testLoadingUsesSystemWindowAndProductSpinner()` 并入基础闭环的确定性延迟首帧启动变体。删除允许完全未观察到 Spinner 也通过的现有方法，改用加载机械状态、加载阶段画面和首帧后画面共同判断。
- `SequentialMediaPlaybackUITests.testTwoRegisteredMediaOpenSequentiallyWithoutSessionOrSurfaceLeakage()` 重写为“连续媒体 Session 隔离”，使用确定的不同媒体组合，不沿用任意两个卡片标识。
- `VisionProIssueDiagnosticsUITests.testEveryLibraryVideoPlaysOrFailsOnlyForUnsupportedCodec()` 由登记媒体矩阵的独立用例取代；删除生产 Media Library 遍历和笼统接受 unsupported codec 的实现。现场遍历只在发现候选时按需运行。
- `VisionProDeviceAcceptanceUITests.testRealVideoAACDiagnostic()` 的有效覆盖进入固定媒体与音频媒体矩阵。`testRealVideoSufficientRateReapplyDiagnostic()` 只在对应问题开放时留在 Issue Diagnostics，问题关闭后连同专用开关、字段和 helper 删除。
- `VisionProDeviceAcceptanceUITests` 中五条 AVAudioEngine、AVSampleBufferAudioRenderer 与 Audio Session mode 校准 tone 方法退出产品回归，只保留一个最小外置麦克风、时间基准和分析链校准工具。`testRealPlaybackAcousticTimeline()` 的 marker 能力进入基础播放闭环；没有物理采集时，声音离开设备保持未评估。

## Media Library 与来源

- `DeviceFixtureImportUITests.testImportsGeneratedBaselineFixtureFromICloudDriveAndStartsPlayback()` 重写为“本地 Media Reference 删除与重新添加”，补齐删除虚拟引用、确认原来源仍存在、重新添加和再次播放。
- `PhotosPlaybackDeviceUITests.testFreshPhotosImportStartsRealPlayback()` 重写为固定 Photos 登记素材的首次添加与播放；删除清空整个 Media Library、任意选择首个 Photos 资源和只检查 `playing` 字段的实现。
- `VisionProIssueDiagnosticsUITests.testInventoryLibraryMediaCards()` 删除。现场媒体清单只作为具体调查附件，不形成测试方法或通过条件。
- `VisionProIssueDiagnosticsUITests.testLibraryGridCardHeightsAreAligned()` 删除，以“Media Library Grid 自适应布局”的三个确定性数据用例取代；生产 `GridCard` 的固定外部高度由快速组件布局测试覆盖。
- `FilesBrowsingUITests.testSearchFiltersCatalog()` 按“Media Library 当前层级搜索”重写，使用用户可见显示名、当前层级、大小写变化和首尾空白规则，不匹配包含扩展名的原始名称。
- `FilesBrowsingUITests.testCreatesVirtualLibraryFolder()` 按“Library Folder 管理”的目录结构与引用组织两个用例重写；生产模型补齐名称清理、同级重名拒绝、跨父级同名和递归移除合同。
- `FilesBrowsingUITests.testWebDAVSourceFormIsReachable()` 删除。静态字段与基本校验进入快速测试，物理 Vision Pro 使用真实 WebDAV 来源建立、浏览与播放场景。
- `FilesBrowsingUITests.testSMBSourceFormRequiresShare()` 删除。表单启用条件进入快速测试，物理 Vision Pro 分别执行账号认证与 Guest 的真实 SMB 场景。
- `FilesBrowsingUITests.testSystemTabBarHasAllTabs()` 删除。Files 启动由冒烟入口承担，Settings 由实际导航场景承担，Environment 由 Environment Card 请求或聚焦场景承担。
- `FilesPlaybackUITests.testFilesScreenShowsFixtureCatalog()` 降为测试前置；`testTappingFilmCardOpensPlayer()` 的有效媒体点击进入 Window 基础播放闭环，然后删除两个独立入口。

## Settings

- `SettingsUITests.testNavigatingToSettingsAndSwitchingCategory()` 重写为 Playback、Storage & Privacy、About 三个分类的机械与视觉联合场景。
- Resume Playback、End of Playback、Default Speed 与 Controls Auto-Hide 分别建立设置驱动场景变体；Thumbnail Cache 与 Playback Progress 进入对应数据场景；Privacy Notice、Version & Build、Support & Feedback 和 Open-source Licenses 使用快速 UI 测试。

## 字幕与轨道选择

- `DeviceFixtureImportUITests.testFolderImportAutomaticallyAssociatesMatchingSubtitleFilesWithoutSelectingOne()` 的有效部分进入“打开媒体时自动关联同目录独立字幕”；字幕候选在打开媒体时取得，不把文件夹添加误写为候选发现行为。
- 现有文件夹关联用例中的 ASS 选择与 Off，以及中文 SubRip 画面检查，进入“播放期间选择字幕与关闭字幕”的媒体覆盖。
- `DeviceFixtureImportUITests.testReopeningMediaRestoresAudioSubtitleAndSubtitleOffSelections()` 重写为“重新打开媒体时恢复轨道选择”；保留稳定身份、状态恢复和字幕画面检查，补齐第二音轨的实际独有输出。
- `DeviceFixtureImportUITests.testPlaybackWithoutAssociatedSubtitleCanAddAndSelectAnExternalSubtitleWithoutReplacingSession()` 及其 Test Plan 选择删除；同时清理已经取消的手动 Choose Subtitle File 生产入口与失效规格。
- `PlaybackDeckUITests.testWindowMoreMakesExternalSubtitleSelectionReachable()` 与 `testSpatialMoreMakesExternalSubtitleSelectionReachable()` 删除，不迁移已经取消的手动字幕文件入口。

## Window 输入与播放控件

- `SpatialHandoffUITests.testWindowSurfaceAndVisibleControlsDoNotCauseAnExtraVisibilityToggle()` 作为“Window 播放输入归属”的基础，删除对 Video Format、More 与 Pause/Resume 的重复完整验证，分别证明 Window SwiftUI 命中层与空间 RealityKit 碰撞输入只在所属 Presentation 活动。
- `VisionProIssueDiagnosticsUITests.testProductionRealityViewTapTogglesControls()` 删除。生产路径点击和显隐变化迁入 Window 输入归属，并证明 Window RealityKit 碰撞输入未启用。
- `VisionProIssueDiagnosticsUITests.testWindowTopChromeReceivesTapAboveRealityViewTarget()` 删除。顶部操作命中、表面显隐不意外变化和视觉证据进入 Window 输入归属，不重复验证完整 Video Format 功能。
- `VisionProIssueDiagnosticsUITests.testSurfaceTapTogglesControlsAndResetsExpandedPanels()` 删除。shown → Precision Timeline expanded → hidden → shown and ordinary Progress Bar 进入 Window 输入归属。
- `VisionProIssueDiagnosticsUITests.testProgressTimeBubbleStaysInsidePlayerControlsAtBothEnds()` 删除。0% 与 100% 气泡几何由快速组件布局测试证明；真机端点 Seek、frame、连续录制、汇总图和关键帧进入 Window 基础播放闭环。
- `PlaybackDeckUITests.testPolishedDeckIsLivePlaybackSurface()`、`testTransportChangesPlaybackState()` 与 `testWindowDeckKeepsTransportAndPresentationActionsSeparated()` 的有效行为进入 Window 基础播放闭环，生产组件几何留给快速布局测试。
- `PlaybackDeckUITests.testWindowActionsAndDeckShareOneControlPlane()` 进入 Window 输入归属；`testTopActionsExposeDockMenu()` 与 `testDockTransitionReplacesTheWindowSurfaceWithoutCrashing()` 的有效目的分别进入 Docked 完整往返、轨道选择和 Docked Placement 场景。

## Playback Presentation 与 Environment

- “Window 与 Docked 完整往返”合并 `SpatialHandoffUITests.testWindowFadesWhileDockedPreparesThenDockedBecomesUsable()` 与 `testDockReturnRemainsPausedUntilWindowPlayThenDisplaysContinuousFrames()` 的有效断言，补齐 Docked 显式 Play 和实际输出，删除重复进入、返回与弱控件点击测试。
- `SpatialHandoffUITests.testDockedControlsDeckRemainsClickableAfterThePresentationTransition()` 删除；其公开 Play 操作和实际输出后置条件进入 Docked 完整往返。
- “Window 与 Panorama 完整往返”以 `SpatialHandoffUITests.testWindowFadesWhilePanoramaPreparesThenPanoramaBecomesUsable()` 为基础，删除 opacity、source-removal-to-bind 和并行准备断言，补齐两端 Paused、显式 Play、实际连续输出和合适的 Panorama Diagnostic Media。
- `PlaybackDeckUITests.testWindowFormatMenuRequiresAnExplicitApply()` 与 `testTopActionsExposeOrthogonalVideoFormatMenu()` 删除。草稿无副作用、Cancel 恢复与 Apply 唯一提交边界进入 Panorama 完整往返，编辑决策由快速状态测试穷举。`testPanoramaTransitionReplacesTheWindowSurfaceWithoutCrashing()` 的有效目的进入同一场景。
- `SpatialHandoffUITests.testPanoramaSuspendsAnActiveEnvironmentAndRestoresItOnReturn()` 精简为活动 Environment 下的 Panorama 交叉场景，不重复基本播放、投影和转换条件。
- 修正 `SpatialHandoffUITests.testDockedInheritsActiveEnvironmentAndRestoresItOnReturn()`：进入前 Night、选择 Dock with Day 时，Docked 使用 Day，返回 Window 后恢复 Night。
- `DockedPlacementUITests.testDockDayAndNightApplyDistinctSkyboxOpacityWithoutAffectingPlaybackSurface()` 改用稳定 Environment identity、Effect 与最终可见内容语义，不把临时 Skybox 名称和固定 opacity 写成产品合同。
- 合并 `DockedPlacementUITests.testPlacementControlsChangeTheActualSurfaceAndPersistAcrossRoundTrip()` 与 `testRestoreDefaultsUsesTheSpecifiedFourMeterDistance()`；补齐新 Media Session、App 进程重启、不同 Environment 隔离和 Day/Night 共享。
- `SpatialPresentationAcceptanceUITests.testRealPlaybackDockedAndPanoramaRoundTrips()` 与整个 `SpatialPresentationAcceptanceUITests.swift` 删除，不迁移 autoplay helper、转换后继续 Playing 的旧预期或合并 Docked/Panorama 的弱往返。
- `VisionProDeviceAcceptanceUITests.testDockAndPanoramaRoundTripsInOneLaunch()` 删除；独立 Docked 与 Panorama 完整往返已经拥有其有效目的。

## 基础设施入口

- `SmokeLaunchUITests.testAppLaunchesToInteractiveMainWindow()` 保留为轮换前的 App 进程、主窗口、Media Library 表面和最低公开 Accessibility 冒烟检查，不登记为共享真机场景或产品通过。
- `SmokeLaunchUITests.testSpatialRegressionLaunchesBeforeMediaSelection()` 的必要前置断言进入各空间场景；确认调用关系后删除独立 Test Plan 入口和方法。
- 使用 `ENCHRON_AUTOPLAY_FILE` 或 `ENCHRON_UI_TESTING` 绕过正常 Media Library 的 fixture helper 不迁移为真实用户旅程端到端入口。
