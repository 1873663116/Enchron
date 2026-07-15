# Apple 官方 visionOS 调试与自动化能力调查

调查时间：2026-07-14
本机工具链：Xcode 27 beta 2（27A5209h）、visionOS 27 SDK
项目现状：Enchron 的 App、DesignPreview 与 UI Test target 均以 visionOS 27.0 为最低部署目标。

## 结论

Apple 官方工具已经足以承担 Enchron 的构建、单元与集成测试、原生 visionOS UI 自动化、测试结果归档、日志、交互式调试、性能分析、Simulator 与真机管理。当前不应建设一个复制这些能力的 Enchron CLI。

Apple 网页文档与当前 beta 工具链存在冲突：网页仍称原生 visionOS App 不支持 XCUIAutomation，[XCUIAutomation：UI testing availability](https://developer.apple.com/documentation/xcuiautomation)；但本机 Xcode 27 beta 2 的 XROS / XRSimulator SDK 已包含 XCUIAutomation，隔离探针也在 visionOS 27 Simulator 上成功启动原生 App、查询 accessibility element、点击按钮并断言状态变化。这说明网页结论至少对当前 Xcode 27 beta 已过时，不能继续作为 Enchron 的架构前提。

visionOS 27 新增的 AppIntentsTesting 仍未在同一环境中打通。隔离探针能够编译、发现 intent 并启动 App，但执行 intent 时稳定返回 `AppIntentsServicesSecurityErrorDomain Code=800`。统一 Development Team、显式指定 `.main` execution target，以及在 test-only / 普通可发现 intent 之间切换，均未消除拒绝。因此当前只能确认框架存在，不能把它当作 Enchron 已可用的语义控制通道。

方向应是“官方测试工具优先，暂不建设 CLI 或自定义 bridge”：可见用户流程用 XCUIAutomation，产品逻辑用 Swift Testing / XCTest，连续运行事实用 OSLog，性能与 RealityKit 用 Instruments。只有未来出现这些官方入口无法表达的、已经重复发生的具体调试需求，才补最薄的 Enchron 专属入口。

## 能力边界

| 官方工具 | 已确认能证明 | 不能单独证明 |
| --- | --- | --- |
| Swift Testing / XCTest | 可直接调用代码的单元测试与集成测试；异步行为、输入组合、错误传播和确定性状态转换 | 另一个正在运行的 App 进程当前处于什么产品状态；最终空间画面是否正确 |
| `xcodebuild` / `.xcresult` / `xcresulttool` | 可重复执行测试、筛选测试、保存失败、日志、附件与覆盖率结果，适合 Agent 和 CI 消费 | 不定义 Enchron 的产品命令和产品状态 |
| Xcode / LLDB | 附加已运行进程、断点、变量、调用栈、内存图、运行时问题；断点动作可在自动继续时记录表达式 | 稳定、版本化、可长期维护的产品级自动化协议 |
| `Logger` / OSLog / Console | 持久或实时事件、严重级别、subsystem/category、signpost 时间区间 | 发出产品命令；仅凭若干历史事件证明当前最终状态 |
| Instruments / RealityKit Trace | 帧截止、render server 瓶颈、RealityKit metrics、CPU/GPU、主线程与 power 问题 | 功能正确性；Simulator 的时间数据不能替代真机 |
| Simulator / Device Hub / `devicectl` | 构建、安装、启动、设备管理、屏幕查看、诊断采集和脚本化设备操作 | 真实硬件特性与最终设备行为；Apple 明确要求硬件特性在真机验证 |
| XCUIAutomation | Xcode 27 beta 2 + visionOS 27 Simulator 已实测原生 App 的启动、元素查询、点击与断言 | Xcode 26 / visionOS 26 行为；真实空间画面、硬件播放和真机一致性 |
| AppIntentsTesting | SDK 接口、intent metadata 提取和测试 runner 均已确认存在 | 本机 Simulator 实测被安全层拒绝；连续事件、视觉正确性和既有播放会话控制均未证明 |

Apple 对测试的推荐仍是以大量单元测试、较少集成测试和少量高保真测试组成测试金字塔。Swift Testing 用于直接调用代码的单元和集成测试；XCTest 继续承担传统测试与性能测试。[Testing in Xcode](https://developer.apple.com/documentation/xcode/testing)、[Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)

`xcodebuild test` 可以从命令行运行全部或筛选后的测试，并产生包含测试结果、覆盖率和日志的 `.xcresult`；`xcresulttool` 是 Apple 提供的结果读取工具。[Running tests and interpreting results](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results)、[Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)

## 原生 visionOS 的 XCUIAutomation 边界

### 文档与工具链冲突

Apple 当前网页仍写明：UI testing 不适用于使用 visionOS SDK 构建的 App，只支持使用 iOS SDK 构建并兼容运行于 visionOS 的 iPad/iPhone App。[XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation)

但 Xcode 27 beta 2 的 XROS 与 XRSimulator Developer Library 都包含 `XCUIAutomation.framework`，XROS header 中 `XCUI_UI_TESTING_AVAILABLE` 为 `1`。本次另建了不依赖 Enchron 的最小原生 visionOS App 与 UI test target，并在 visionOS 27 Simulator 上运行：

- `XCUIApplication.launch()` 成功启动原生 App；
- `app.staticTexts["probe-state"]` 与 `app.buttons["probe-button"]` 成功解析；
- `button.tap()` 成功改变 SwiftUI 状态；
- 测试以 0 failure 结束，结果保存在本机 `/tmp/NativeVisionAutomationProbe/UIAutomation.xcresult`。

因此，对当前工作区应采用更强的本机运行证据：Xcode 27 已经可以对原生 visionOS App 执行基本 XCUIAutomation。这个结论只覆盖 Xcode 27 beta 2 与 visionOS 27 Simulator；不能反推 Xcode 26、visionOS 26 或所有空间交互都支持。

### 容易混淆之处

AppIntentsTesting 要求测试位于标准 XCUITest bundle。WWDC26 示例同时使用 AppIntentsTesting 和 XCUIAutomation；本机实验已经证明这种组合在原生 visionOS 27 上至少能够执行 XCUI 部分。[WWDC26: Validate your App Intents adoption with AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/)

## Xcode、日志与性能工具

Xcode 能启动 App 并自动附加 debugger，也能附加已经运行的进程。LLDB 适合定位某次故障：暂停、检查变量、逐步执行、检查调用栈；breakpoint action 还能记录变量并自动继续，减少对时序的干扰。[Diagnosing and resolving bugs in your running app](https://developer.apple.com/documentation/xcode/diagnosing-and-resolving-bugs-in-your-running-app)

这属于调试器能力，不是稳定的回归接口。断点位置、内部类型与表达式会随实现变化；LLDB 还可能暂停或扰动实时播放。把它作为 Agent 的诊断工具是合理的，把它当作 Enchron 产品命令协议则不合理。此处为基于工具语义的架构推论。

Apple Unified Logging 已提供 `Logger`、subsystem/category、Console、Xcode console、`log` 命令和 OSLog 程序化读取。`OSSignposter` 可把关键阶段记录为 Instruments 时间区间。[Viewing Log Messages](https://developer.apple.com/documentation/os/viewing-log-messages)、[Logger](https://developer.apple.com/documentation/os/logger)、[OSSignposter](https://developer.apple.com/documentation/os/ossignposter)

日志适合作为运行事实的事件记录，但它本身不是命令通道，也不是当前状态快照。Enchron 应使用带 session ID、阶段和结果的结构化 `Logger` 事件；Agent 若要断言“当前已经进入 playing”，仍应查询一个明确的当前状态，而不是从日志文本猜测。

RealityKit Trace 可以在 Simulator 或真机上记录 RealityKit Frames、RealityKit Metrics、Runloops、Time Profiler、Hangs 和 Metal Application。Apple 明确说明 Simulator 的软硬件差异使时间信息不可依赖，最准确、可操作的性能证据来自真机。[Analyzing the performance of your visionOS app](https://developer.apple.com/documentation/visionos/analyzing-the-performance-of-your-visionos-app)、[WWDC23: Meet RealityKit Trace](https://developer.apple.com/videos/play/wwdc2023/10099/)

Apple 同样明确说明 Simulator 不复制物理设备的全部性能与特性；硬件专属能力必须在物理设备测试。[Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

Device Hub 和 Xcode command-line tools 已覆盖设备/Simulator 管理、安装、屏幕交互、诊断采集与脚本化工作流。官方命令包括 `xcodebuild`、`devicectl`、`xcdebug`、`xcresulttool` 与 `xctrace`。[WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)、[Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)

这些工具能够替代自建 CLI 中的构建、安装、启动、测试、结果解析、trace 和设备管理部分，但它们不知道 Enchron 的 `Media Session`、renderer binding 或 presentation mode 等产品语义。

## AppIntentsTesting

### 平台与成熟度

Apple 将 AppIntentsTesting 定义为对 App Intents、entities、queries 以及 Siri/Spotlight 集成进行跨进程测试的框架。测试无需链接 App target，而是通过 bundle identifier 和字符串标识取得 intent 定义。[App Intents Testing](https://developer.apple.com/documentation/appintentstesting)、[WWDC26: Validate your App Intents adoption with AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/)

本机 Xcode 27 beta 2 的 Apple SDK 已核实：

- XROS 与 XRSimulator 的 Developer Library 均包含 `AppIntentsTesting.framework`。
- public Swift interface 将其 API 标注为 `@available(visionOS 27.0, *)`。
- `AnyAppIntent.run()` 返回 `ResolvedIntentResult`，结果支持动态读取返回值。
- `IntentExecutionTargets.main` 同样从 visionOS 27.0 开始可用。

Apple 当前文档将 AppIntentsTesting 和 `IntentExecutionTargets` 标为 beta / preliminary technology，要求在最终系统软件上重新测试。[IntentExecutionTargets](https://developer.apple.com/documentation/appintents/intentexecutiontargets)

因此它目前不能成为唯一、不可替代的 V1 验收基础。Enchron 的最低系统已是 visionOS 27，AppIntentsTesting 的平台要求不再形成产品兼容性冲突；是否采用它仍取决于它能否覆盖具体产品行为，而不是为了兼容 visionOS 26 建立额外路径。

### 本机运行验证

本次隔离探针使用与 App 相同的 Development Team，intent metadata 能成功生成，测试 runner 也能通过 bundle identifier 找到 intent。以下变体全部在 `AnyAppIntent.run()` 阶段收到同一安全拒绝：

- `#if DEBUG` + `isDiscoverable = false` 的 test-only intent；
- 普通可发现 intent；
- 默认 execution target；
- `supportedModes = .foreground(.immediate)` 与 `allowedExecutionTargets = .main`。

错误为 `AppIntentsServicesSecurityErrorDomain Code=800`，内容为目标 App 无权执行请求。它证明当前 Xcode 27 beta 2 / visionOS 27 Simulator 组合不能直接承担 Enchron 的语义控制；原因可能是 beta 实现缺陷、Simulator 限制或尚未公开的配置要求，本次证据不足以进一步归因。

### 进程与返回值

Apple 给出的执行模型是：测试在独立 XCUITest runner 进程，App 在另一个设备进程；runner 通过完整 App Intents stack 执行 intent，并接收执行结果，不导入 App 代码、也不共享内存状态。[WWDC26: How AppIntentsTesting works](https://developer.apple.com/videos/play/wwdc2026/295/)

App Intent 可以返回值给发起方；AppIntentsTesting 能读取该结构化结果并执行断言。[IntentResult](https://developer.apple.com/documentation/appintents/intentresult)、[ReturnsValue](https://developer.apple.com/documentation/appintents/returnsvalue)

Apple 还允许用 `IntentExecutionTargets.main` 指定 intent 在主 App 进程执行。WWDC26 说明，默认启发式在 App 已运行时倾向选择 App；显式 `.main` 可要求主 App 处理。[WWDC26: Discover new capabilities in App Intents](https://developer.apple.com/videos/play/wwdc2026/345/)、[IntentExecutionTargets](https://developer.apple.com/documentation/appintents/intentexecutiontargets)

Apple 的 App Intents 示例通过 `AppDependencyManager` 把 App 正在使用的 navigation model 注册为 dependency，intent 的 `perform()` 随后操作同一个 model。[Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)

由此可以合理推论：如果 Enchron 把播放协调器和观测快照以 dependency 形式注册，并让测试 intent 在 `.main` 目标执行，intent 理论上可以操作主 App 进程中的产品对象，而不是另一套假实现。

但以下内容仍未被 Apple 文档直接证明：

- 原生 visionOS App 已经打开 ImmersiveSpace 并正在播放时，调用 test intent 是否始终复用同一 App process 和同一产品会话。
- intent 执行是否会引起 scene activation、前后台转换或其他可能打断 RealityKit / AVFoundation 播放的生命周期变化。
- 长时间等待播放状态变化时，intent 的执行期限和取消语义是否适合作为回归等待器。
- Simulator 与 Vision Pro 上的行为是否一致。

这些是 Enchron 必须实测的边界，不能从 iPhone 上的 WWDC 演示直接推导。

### Test-only intents

Apple 明确建议创建只服务于测试的 intent，用于建立已知数据、直接导航和包装尚未对外暴露的内部能力。官方做法是设置 `isDiscoverable = false`，并用 `#if DEBUG` 使其只存在于调试构建。[WWDC26: Test-only intents](https://developer.apple.com/videos/play/wwdc2026/295/)

这说明 Enchron 可以通过 Apple 官方通道提供调试专用命令，而不必把它们变成用户可见的 Siri 或 Shortcuts 功能。它也符合“SwiftUI 使用产品能力子集，Agent 测试可以拥有调试扩展”的方向。

### 它不是完整的 live debug protocol

AppIntentsTesting 提供的是一次请求、一次结果的语义调用，也能调用 entity/query；Apple 没有在该框架中提供任意内部状态浏览或连续事件订阅 API。持续事件仍应交给 Unified Logging 或 Instruments，当前快照则由 query intent 返回。

截至本次调查，没有发现 Apple 提供一个单一官方接口，同时完成以下四件事：

1. 向正在运行的原生 visionOS App 发出产品语义命令；
2. 查询强类型当前状态；
3. 订阅连续产品事件；
4. 操作原生 visionOS UI。

官方能力是组合式的：App Intents / AppIntentsTesting 负责语义请求与结果，OSLog 负责事件，Xcode/LLDB 负责现场诊断，Instruments 负责性能，Device Hub 负责设备交互。此结论是对上述一手接口范围的归纳，不是 Apple 的直接声明。

## 对 Enchron 的方向建议

现阶段不批准完整 Enchron CLI，也不批准自建 socket、文件 inbox 或网络调试协议。先建立以下 Apple 官方基线：

1. 产品逻辑与 PlaybackCore 使用 Swift Testing / XCTest。
2. App、PlaybackCore 和 RealityKit 协调阶段统一使用 `Logger` 与 session correlation ID；性能阶段使用 signpost。
3. Agent 通过 `xcodebuild` 执行测试，通过 `.xcresult` / `xcresulttool` 获取断言、失败和附件，通过 `devicectl` 与 `xctrace` 管理设备和 trace。
4. 在 Xcode 27 / visionOS 27 上把 `XrPlayerUITests` 恢复为原生 UI 自动化入口；fixture 只驱动生产 UI，随后用真实 PlaybackCore 覆盖产品路径。
5. Xcode、Device Hub 和真机继续负责无法由语义测试证明的视觉、空间、硬件解码与最终呈现。

当前不应立即把 AppIntentsTesting 接入 Enchron；隔离探针已经在进入产品代码前暴露平台阻塞。待 Xcode / visionOS 后续 beta 或正式版更新后，先重跑同一隔离探针。只有它通过，才值得让 Enchron 暴露 snapshot 与 command test intents。

### 决策门槛

当前验证结果是：XCUIAutomation 通过，AppIntentsTesting 被安全层拒绝。这个结果仍不足以批准自建 CLI，因为可见产品流程已经有官方自动化入口，运行事实也有 OSLog、LLDB 与 Instruments。只有在真实 Enchron 回归中反复出现“UI 无法触发、日志无法判断、单元测试无法覆盖”的同一个语义缺口，才对该缺口单独设计最薄传输层。
