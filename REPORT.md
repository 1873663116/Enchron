# 纯逻辑测试迁移报告

本次审计覆盖 `Tests/EnchronApp/` 在基座 `414286a6` 中的全部 22 个 Swift 测试文件。裁决只问断言的真假由谁决定。项目代码、内存替身、临时文件和 `UserDefaults` 决定的测试进入 `EnchronDomainTests`。物理解码器、真实服务器、设备音频、RealityKit 编译资源或佩戴者所见画面参与裁决的文件继续留在 `EnchronAppTests`。

迁移后的 17 个文件包含 213 个测试函数。最终 `.xcresult` 中能找到这 213 个函数的测试节点，而且全部通过。没有修改任何测试断言。MediaLibrary 和 MediaSource 测试删除了不再需要的 import。三个依赖 App 主 actor 语义的套件增加了显式 `@MainActor`。

## 逐文件裁决

| 文件 | 原目标 | 新目标或结论 | 裁决理由 |
| --- | --- | --- | --- |
| `SMBDataSourceAdapterTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | 测试使用进程内 loopback server 和自有 byte-range 替身，断言 adapter 与范围读取规则，不访问局域网服务器。 |
| `WebDAVDataSourceAdapterTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | `URLProtocol` 替身生成全部 HTTP 响应，断言由 WebDAV adapter 代码决定。 |
| `PlaybackSourceAccessTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaSourceTests` | 测试 `MediaAccessLease` 和 `ResolvedMediaSource` 的所有权规则，不需要真实服务器或设备。 |
| `FakeFileDataSourceTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | 文件树、错误和路径都来自确定性的内存 fake。 |
| `LocalDataSourceAdapterTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | 测试只操作临时目录和本地 adapter 生命周期，没有物理解码或佩戴者画面。 |
| `MediaLibraryTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | 断言是媒体库导航、历史和引用更新规则，依赖内存模型与 fake source。 |
| `SortCriteriaTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/MediaLibraryPackageTests` | 排序输入固定，结果完全由项目 comparator 决定。 |
| `DolbyVisionLabelTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackFeaturePackageTests` | 只验证已经给定的 profile facts 如何映射成标签，不探测解码器。 |
| `UnmetCapabilityTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackFeaturePackageTests` | 输入是构造出的 capability facts，断言项目策略如何分类和阻止播放。 |
| `UnmetCapabilityRuntimeTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/EnchronAppLogicTests` | runtime 使用 fake playback controller，验证自有状态映射和重置规则；该文件仍需导入 App module。 |
| `PreferencesPersistenceTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/EnchronAppLogicTests` | 使用隔离的 `UserDefaults` suite 验证序列化与默认值；该文件仍需导入 App module。 |
| `EnvironmentSceneMappingTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 只验证 environment 标识、映射表和默认配置，没有加载或显示 RealityKit 场景。 |
| `PlaybackPanelExpansionTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 输入和输出都是 panel expansion 状态机事件。 |
| `PlaybackPresentationEdgeTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 只验证 presentation 枚举之间的合法边和派生目标。 |
| `PlaybackPresentationStateTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 使用 mock scene actions 和构造状态验证编排策略，不读取真实画面、音频或解码结果。 |
| `ScreenPositionPersistenceTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 使用隔离的 `UserDefaults` suite 验证位置数据的持久化与迁移。 |
| `WindowPlaybackPageGeometryTests.swift` | `EnchronAppTests` | `EnchronDomainTests`，`Tests/PlaybackPresentationTests` | 断言是固定输入下的尺寸、宽高比和 presentation 几何计算。 |
| `PlaybackRealityPresenterTests.swift` | `EnchronAppTests` | 留下 | 文件混合了自有 presenter 状态测试和 RealityKit 编译场景加载、Entity component 行为；后者由 Apple 资源加载黑盒决定。 |
| `PlaybackSourceAndAudioSessionTests.swift` | `EnchronAppTests` | 留下 | 文件混合了状态测试、真实本地媒体、PlaybackCore 解码、音频会话、`UIWindow` host 和 RealityView pixel 行为。 |
| `WebDAVLiveIntegrationTests.swift` | `EnchronAppTests` | 留下 | 环境变量启用后会通过真实 `URLSession` 访问 WebDAV 服务器并读取真实字节范围。 |
| `ProResDecodeOnDeviceTests.swift` | `EnchronAppTests` | 留下 | `AVAssetReader` 对真实 ProRes 样本的结果取决于设备解码器。 |
| `VideoDecoderAvailabilityTests.swift` | `EnchronAppTests` | 留下 | 测试直接查询 VideoToolbox 硬件 decoder availability。 |

## 工程变更和代价

`Tests/PlaybackPresentationTests`、`Tests/EnchronAppLogicTests` 和 `Tests/MediaSourceTests` 是新的 synchronized root group，归属 `EnchronDomainTests`。`EnchronAppLogicTests` 隔离仍需 App module 的测试，避免把它们放入同时属于 SwiftPM test target 的 package 测试目录。`MediaSourceTests` 表达 `PlaybackSourceAccessTests` 的实际模块所有权。Domain 目标新增 `PlaybackPresentation` package product。部分搬入测试仍需访问 `Enchron` app 内部编排类型，因此 `EnchronDomainTests` 现在由 `Enchron` 托管，并显式依赖 App target。这个选择没有扩大生产 API 的可见性，但模拟器目标会构建和启动 App host。最终增量测试会话耗时 23.709 秒，其中 XCTest 的 8 项耗时 0.236 秒，Swift Testing 的 268 项耗时 0.371 秒。

`PlaybackRealityPresenterTests.swift` 最初进入了模拟器目标。实际执行时，四个场景资源测试报 `resourceNotFound("world")`。给测试传入明确的 RealityKit resource bundle 仍由 Apple loader 报相同错误。这个结果证明该文件不是纯逻辑测试，因此最终迁移撤回，没有改写资源名、fixture 或断言来制造通过结果。

## 验证结果

工具链为 Xcode 27.0，build `27A5237l`。模拟器是 visionOS 27.0 的 `Apple Vision Pro`。

模拟器实际命令如下。`TrackSelectionPreferenceTests.swift` 是任务说明中的既有 package-access 编译问题。`EmbyLiveIntegrationTests.swift` 需要本地凭据文件和真实服务器，基线运行在当前环境中因此失败；本次纯逻辑验收只在命令行排除这两个文件，没有把排除写入工程默认行为。

```sh
xcodebuild test -project Enchron.xcodeproj -scheme EnchronDomainTests -testPlan EnchronDomain -destination 'platform=visionOS Simulator,name=Apple Vision Pro' CODE_SIGNING_ALLOWED=NO EXCLUDED_SOURCE_FILE_NAMES='TrackSelectionPreferenceTests.swift EmbyLiveIntegrationTests.swift' -resultBundlePath /tmp/EnchronDomain-final3.xcresult
```

结果为 `TEST SUCCEEDED`。`.xcresult` 记录 276 个 test case，276 个通过，0 个失败。输出分别报告 XCTest 8 个通过，以及 Swift Testing 268 个测试、21 个 suite 全部通过。按函数名将 17 个搬入文件与 `.xcresult` 对照后，213 个测试函数全部被发现并通过。

真机目标编译使用任务指定的命令，没有附加排除项。

```sh
xcodebuild build-for-testing -project Enchron.xcodeproj -scheme Enchron -testPlan Enchron -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO
```

结果为 `TEST BUILD SUCCEEDED`。`EnchronAppTests`、`EnchronAppUITests` 和它们的 App host 均完成 generic visionOS build-for-testing。本次没有在物理 Vision Pro 上执行测试。
