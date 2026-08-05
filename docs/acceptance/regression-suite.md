# Enchron 回归验收方案

本方案定义 Enchron 候选版本达到发布质量门槛所必须通过的行为场景、证据和执行条件。它遵循 [`verification-system.md`](verification-system.md) 按被证明事实划分的验证职责；App、UI、RealityKit 与系统 Scene 的自动回归直接在物理 Vision Pro 上执行，PlaybackCore 与纯逻辑合同另行保留其大规模确定性覆盖。

真机用户路径、媒体组合、字幕与音轨、反复操作、预先查找的问题以及每类证据的分工，统一定义在 [`regression-matrix.md`](regression-matrix.md)。本文档负责总体通过含义、性能、功耗、远程来源验证职责、物理声学与 Playback Presentation 状态组合。

## 通过含义

回归验收只针对一个具有精确身份的候选版本。候选版本由产品代码树、测试媒体及其内容摘要、Xcode 与 visionOS 版本、Vision Pro 设备环境共同界定；工作树不能只用 Git revision 代替实际代码树身份。

当且仅当该候选版本通过所有被本方案定义为发布必过的场景、每个场景都取得规定证据，并且没有未解决的发布阻断失败时，回归验收才可以标记为通过。通过结论只证明该候选版本达到已经定义的发布质量门槛，不构成不存在任何未知缺陷的声明。

历史版本、不同测试媒体、不同产品代码树或不同设备环境的结果只能作为参考，不能替代当前候选版本的结果。

## 测试执行与证据判断

本方案统一组织仓库已有的单元测试、集成测试、XCUITest、生产状态诊断、视觉分析、性能采集、受控远程来源服务器和物理声学测量设备。它不建立另一套产品实现，也不以一个新的通用测试框架替换 XCTest、Swift Testing、Instruments、OSLog 或 `.xcresult`。

系统由以下相互独立的职责组成：

- 回归场景目录为每个场景定义候选版本身份、前置产品状态、用户操作、操作后必须达到的产品与系统状态、成功后置条件、失败分类和证据要求；本文件是该目录的产品级入口。
- Swift Testing 与 XCTest 的单元和集成测试直接验证产品规则、PlaybackCore 合同、远程来源适配、故障注入和资源清理，不通过 UI 间接证明能够直接观察的内部合同。
- XCUITest 从 App 外部驱动真实 Enchron 入口、Accessibility 元素和 visionOS 系统交互。每次用户操作后都必须等待并断言产品与平台后置条件；找到元素、成功发送合成输入或没有崩溃均不构成通过。
- Enchron 的只读自动化探针只投影生产状态、Media Session identity、stream epoch、Renderer Consumer Binding、Playback Lifecycle、Playback Presentation 与输出诊断。探针不能维护第二套状态机、替换真实来源或绕过生产播放路径。
- 编排脚本负责设备与测试基础设施预检、测试媒体和远程服务器准备、测试选择、执行顺序、超时、外部录音或性能采集，以及证据文件汇总。机械步骤由脚本执行，场景是否满足产品成功标准由场景中明确写出的判定规则决定。
- 状态、视觉、时间、音频、网络、资源和性能分别使用能够直接观察相应事实的判定规则。定点截图用于操作后静态后置条件，完整佩戴者视野录制及按操作时间定位的前后帧用于动态过程；两者都必须结合明确的界面结构、Diagnostic Media 标记、连续帧或人工感知标准解释，不能自行构成通过。
- 每次执行产生可复核结果包，至少包含 `.xcresult`、Accessibility hierarchy、产品状态、OSLog、操作后定点截图、完整佩戴者视野录制、按操作与检查点抽取的代表帧、外部测试设备或服务器产生的证据文件，以及记录各项结论和依据的 JSON。结果明确区分产品通过、产品失败、测试基础设施失败和未评估；设备锁定、XCTest worker 未启动、测试服务器不可达、零测试匹配或必需录制缺失不能成为产品结论。

系统最大化 Agent 可以重复执行和判定的范围。人工验收只承担现有自动化观测边界之外的自然注视与手势体验、双眼空间观感、HDR/EDR 主观质量、运动与长时佩戴舒适度等最终感知校准；其中任何一项仍可按产品标准成为发布阻断条件。

## 性能通过模型

性能是候选版本发布成功的独立证据维度，不能由功能断言、没有 crash 或短时间播放成功代替。最终性能结论只使用物理 Vision Pro 上的 Release 构建；Debug 构建的数据只用于定位并与发布指标分开保存。

每项发布性能指标必须同时满足绝对体验门槛和相对基线回归门槛。绝对体验门槛规定候选版本自身必须达到的最大延迟、最小持续能力或最大资源消耗；相对基线回归门槛规定同一 Vision Pro、visionOS、Release 配置、测试媒体、网络条件、空间环境与热状态下，候选版本不能显著劣于已经接受的基线。历史基线本身未达到绝对体验门槛时，候选版本不能因没有继续恶化而通过。

绝对体验门槛由外部调查、可比产品或平台参考、Enchron 分阶段测量和定量预算共同确定，不能直接复制某一次当前实现的测量结果。每个门槛都必须保存来源、适用范围、归一化条件、计算方法和不确定性；外部参考负责约束用户体验上限，分阶段测量负责说明 Enchron 在受控设备、媒体和网络条件下如何消耗这项预算。当前实现慢于外部体验上限时应形成优化缺口，不能自动提高上限使其通过。

不同调查或标准中的数值不能直接加权平均。它们只有在用户群体、设备、内容、网络条件和指标起止边界能够归一化时才可以参与同一项计算；否则分别承担体验风险上限、指标定义或测量方法依据。对于来源 `s`，绝对门槛按以下约束取最严：

```text
C_s = min(C_external_UX, C_Local + B_s)
```

`C_external_UX` 是由外部用户行为研究、平台参考与 Enchron 在 Vision Pro 上的主观校准共同确定的体验上限；`C_Local` 是独立接受的 Local 启动目标；`B_s` 是 SMB 或 WebDAV 相对 Local 的受控协议与网络增量，Local 的增量为零。`B_s` 必须来自同一设备、测试媒体、热状态和缓存状态下交错执行的配对测量，并分别覆盖规定的连接、认证与缓存条件。增量在校准后作为门槛依据锁定，不能由每个新候选版本重新计算宽限。

当前性能校准以 Local 播放为主。SMB 与 WebDAV 只在固定服务器、正常受控局域网以及已声明连接与认证状态的条件下，检查远程播放相对 Local 增加的时间是否稳定、可重复并且不超过规定值。带宽不足、高网络延迟、丢包、服务器过载或外部网络中断暂不进入性能门槛，它们继续由 Remote Source 功能失败、恢复与错误呈现回归覆盖。

候选版本必须同时满足两项条件：采样与计算结果支持至少 95% 的实际可比运行不超过 `C_s`，并且这套采样与计算方法错误宣称达到该比例的概率不超过 5%；候选版本相对已接受基准版本的退化不超过预先声明的比例。统计方法必须写明样本如何取得、计算过程以及如何把错误判断的概率限制在 5% 以内，不能用“取一个保守值”等未定义说法代替。相对容差受绝对门槛的剩余空间约束；测量变化大到无法识别该比例时，该测试条件记为不稳定和未评估，不能通过放宽门槛得出产品通过结论。

启动时间、操作响应时间、功耗和其他连续数值还必须分别规定单次运行的最大允许值。任何一个符合测试条件的有效样本超过该值时，该项性能直接失败，不能被其余较快或资源消耗较低的样本抵消。这个最大允许值与 `C_s` 一样，必须由外部参考、当前设备测量和明确接受的计算依据确定，不能根据候选版本的结果临时放宽。

播放无法开始、crash、hang、音视频停止推进、Presentation 状态错误或证据缺失属于正确性失败，不进入上述比例计算；发布要求执行的任一次场景出现这些结果都直接失败。长时间连续热稳定性测试同样要求每次完整运行都满足全部正确性条件。

首个用于校准的候选版本在门槛经过调查、测量和明确接受之前只能标记为性能未评估。它产生的样本可以建立后续相对比较的候选基线，但不能自行证明该基线达到发布质量。门槛一旦接受，后续修改必须保留原始依据和重新校准理由，不能因为单次回归失败而直接放宽。

性能判定使用多次重复测量的分布，不采用单次最好结果。每次测量记录设备与环境条件、原始样本、聚合统计和异常值处理；候选版本超过绝对门槛或超过允许的相对退化时，该项性能失败。失败结果必须保留对应 XCTest metric、OSSignposter、AVFoundation renderer metrics 或 Instruments/RealityKit Trace 证据文件，以便定位失败阶段。

### 重复测量次数与停止条件

候选版本和已接受的基准版本在同一设备、测试媒体、Release 配置、网络条件、空间设置和起始设备热状态下交错运行。每一对测量随机决定先运行候选版本还是基准版本，避免设备随时间升温或后台状态变化总是偏向其中一方。长时间连续测试的一条记录是一个样本；不得把同一条记录切成多个时间片并当作相互独立的样本。

测试开始前必须写明首次运行次数、结果不明确时每次增加的运行次数、允许运行的最大次数、计算方法和允许判断出错的概率。只在这些预先规定的次数完成后检查结果，不能根据中途看到的数据临时决定继续或停止。

对于 `C_s`，计算结果只有在能够支持至少 95% 的实际可比运行满足门槛，并且错误作出该结论的概率不超过 5% 时才通过。对于候选版本与基准版本的差异，计算方法必须根据全部成对测量给出实际差异可能所在的数值区间，并明确说明：如果在相同条件下重复整个采样与计算过程，该方法有多大比例会得到包含实际差异的区间。只有整个区间都不超过允许退化时才通过；整个区间已经超过允许退化时失败；区间跨越门槛时按照预定次数增加样本。达到最大次数后仍跨越门槛，说明当前测试条件和样本不足以作出结论，结果记为未评估。无论统计结果如何，任何有效样本超过单次运行最大允许值都直接失败。

建立或重新校准基准版本时，必须直接证明它满足 `C_s`。在不假定测量结果服从某种特定分布的情况下，如果没有任何有效样本超过 `C_s`，至少需要 59 次相互独立的有效测量；因为当实际恰好只有 95% 的运行满足门槛时，59 次全部满足门槛的概率为 `0.95^59`，约为 4.85%。如果出现超过 `C_s`、但尚未超过单次运行最大允许值的样本，这条 59 次全部满足的计算不再适用；必须按照测试开始前写明的其他计算方法增加样本，或者把结果记为未评估。

后续候选版本优先与已接受的基准版本成对运行。只有当基准版本已经证明的结果，加上成对测量所允许的候选版本最大增加量，仍然不超过 `C_s` 时，候选版本才满足绝对门槛。计算必须把基准结果和候选版本差异两部分可能判断错误的概率合并计算，并保证错误通过的总概率不超过 5%；不能让两部分各自使用 5% 后仍声称整体为 5%。候选版本还必须满足相对基准版本的允许退化和单次运行最大允许值。

如果成对测量达到预定最大次数后仍不能证明上述条件，候选版本必须补充与建立基准时同等严格的直接测量；未完成时记为未评估。Vision Pro 设备、visionOS、Xcode、测试媒体、Release 配置、测量方法、空间设置或影响指标的环境条件发生变化时，旧基准不再适用于直接比较，必须重新校准。能够证明某项变化不影响特定指标时，可以只重新校准受影响的指标，但必须保存该判断的依据。

### App 与媒体启动工况

App 冷启动是 Enchron 进程不存在时发起启动，到 Media Library 达到稳定可交互状态。App 热激活是 Enchron 进程仍然存活时，从非活动状态恢复当前 Scene，到该 Scene 再次达到稳定可交互状态。两者分别测量，不把系统重新创建进程的结果记为热激活。

媒体冷打开是 App 已经可以交互、当前没有 Media Session，且同一 Enchron 进程尚未打开过该测试媒体时，从 Enchron 接受媒体打开意图到形成可用音视频输出。这个工况只定义 App 与媒体管线的冷状态，不声称 visionOS 文件系统或硬件缓存已经被清空。

媒体热重开是同一 Enchron 进程已经成功打开并完整关闭同一测试媒体后，再次从接受打开意图到形成可用音视频输出。前一次 Media Session 的 provider、renderer input、consumer binding 和访问资源必须已经按 Close 合同释放；热重开建立新的 Media Session，但可以受益于仍然合法存在的系统缓存。

Pause/Resume、Seek 和 Window/Docked/Panorama 转换是独立的操作响应指标，不属于 App 热激活或媒体热重开。

### 媒体启动可用延迟

媒体启动可用延迟用于衡量 Enchron 自身完成一次媒体播放启动所需的时间。标准发布测量使用包含视频和音频的受控媒体。开始时间是 Enchron 接受用户媒体打开意图的时刻；结束时间是同一 Media Session 的当前 stream epoch 首次形成可用音视频输出的时刻。

可用音视频输出必须同时满足：当前 renderer 已绑定到当前播放表面；当前 stream epoch 的画面已经显示并开始持续推进；底层 timebase 的实际播放 rate 大于零；video sample 与 renderer accepted input 持续增加；存在音轨时，当前 stream epoch 的 audio sample 持续增加、audio renderer 处于 rendering 且系统 audio session 与输出 route 有效。只出现一张静止画面、加载界面消失、Playback Lifecycle 变为 Playing 或请求给 synchronizer 的 rate 已设置，都不能结束这项测量。

来源解析与访问租约、provider open、track model、decoder bootstrap、renderer attach，以及目标表面完成 renderer 绑定并达到对应 Presentation 的成功后置条件，分别记录为诊断阶段，但这些阶段不能替代端到端的发布指标。App 与媒体启动分别覆盖冷、热工况；XCUITest 发出用户操作至 Enchron 接受媒体打开意图的输入响应单独计量。Local 使用受控媒体建立主要绝对门槛与基线；SMB 与 WebDAV 只在规定的正常受控网络下验证相对 Local 的固定增量。

性能回归至少覆盖冷、热工况下的 App 与媒体启动、Pause/Resume/Seek 响应、Window/Docked/Panorama 转换、UI 与其他用户操作响应、持续播放的掉帧与停顿、内存增长、CPU/GPU 帧截止、hang、各代表工况的功耗和设备热状态。每项指标分别定义用户可观察的起止事件、诊断阶段、测试条件、绝对门槛、基线容差和证据来源。

### 自动性能采集职责

每次性能回归使用 XCTest metrics、`OSSignposter`、Playback 输出诊断和 AVFoundation renderer metrics 采集低开销指标。该层自动判定启动与操作延迟、CPU、内存、UI hitch、displayed frame、掉帧和持续播放异常，并把原始 measurement 与 `.xcresult` 保存在同一结果包。

定期性能回归和每个发布候选在固定时长的 Media Library idle、Window 播放、Docked、Panorama 与密集 UI 操作工况中运行 `xctrace`。Power Profiler、RealityKit Trace、SwiftUI 与 Animation Hitches 分别采集功耗、热状态、CPU/GPU 帧截止、render server、主线程响应和界面更新事实。只有某个 Instruments 模板已经具有经过当前 Xcode 和 visionOS 验证的稳定导出结构、明确的指标含义和可重复执行的通过条件时，它才可以自动给出通过或失败结论；成功生成 `.trace` 只证明采集完成。

指标越界和定期深度诊断按失败类型选择 Time Profiler、Allocations、Leaks、System Trace 或其他高开销模板。该层负责定位 CPU 热点、分配增长、泄漏、线程调度和系统级等待，不作为每条功能场景的默认执行步骤。

编排器使用 `xctrace` 在指定 Vision Pro 上启动或附加进程、等待录制就绪、运行同一条 XCUITest 工况、限时停止并保存 `.trace`。能够稳定导出的表格进入机器判定 JSON；尚无稳定导出的内容保留原始 `.trace` 并标记为待分析，不能产生自动通过。

### 各功耗工况允许的资源范围

功耗不使用一个覆盖整个 App 的单一平均值。每项功耗结论都属于没有用户操作且播放暂停的状态、持续播放状态，或者用户操作引起的短时变化，并绑定固定的 Playback Lifecycle、Playback Presentation、Environment Context、测试媒体、空间设置与测量窗口。

没有用户操作且播放暂停的测量覆盖 Media Library idle 和媒体 Paused。正式测量开始前，必须等待读取量、sample 产出、renderer input、内存、CPU、GPU、网络和功耗不再出现超出测量噪声的持续上升或下降。Paused 期间实际 timebase 保持为零，media time 不推进，显示内容不继续变化，扬声器不继续输出媒体音频；已经开始的读取、解复用或解码可以完成，并且允许按照明确声明的时间长度、字节数或队列中最多保留的条目数进行有限预取。正式测量开始后，读取量、sample 产出、renderer input、内存和远程网络活动不得持续增长；CPU、GPU、网络与功耗分别满足为 Paused 规定的最大值和相对基准要求。恢复播放继续使用同一 Media Session；预取策略、允许的最大值与实际占用都必须可观测。

持续播放测量分别覆盖 Window、Docked 与 Panorama。每种 Playback Presentation 分别规定 CPU、GPU、内存和功耗的允许范围，同时必须保持音视频推进、按时完成每帧、没有 hang、内存不持续增长并且设备热状态符合规定。某个 Presentation 确实需要更多资源时，只能依据调查和校准修改该 Presentation 的允许范围，不能改变其他 Presentation 的标准。

用户操作引起的短时变化覆盖 App 与媒体启动、Seek、Presentation Transition 和密集 UI 操作。它们可以出现高于持续播放状态的短时峰值，但峰值、持续时间以及各项指标恢复到目标暂停状态或持续播放状态允许范围所需的时间都必须符合规定。操作结束后仍保持高活动、持续无法按时完成每帧或设备热状态继续恶化属于失败。

每种功耗工况同时观察 Power Profiler 或 RealityKit Trace 能够稳定导出的功耗数据、CPU/GPU 工作、内存、每帧是否按时完成、hang 和设备热状态；任何单一指标不能替代其他通过条件。

#### 固定功耗发布工况

发布候选使用 Local 受控媒体执行以下九个固定工况。每个 Paused 与 Playing 工况都使用相同媒体、空间设置和测量窗口，以便比较生命周期与呈现形式本身增加的资源消耗：

| 类型 | 固定工况 |
|---|---|
| 静息 | Media Library idle，Environment Context 为 none |
| 静息 | Media Library idle，Environment Context 为 active，并使用校准后负载最高的 Environment Effect |
| 静息 | Window Paused，Environment Context 为 none |
| 静息 | Docked Paused，并使用校准后负载最高的 Environment 与 Environment Effect |
| 静息 | Panorama Paused；Environment Context 为 none，只保留黑色周围环境与视频投影球面 |
| 稳态 | Window Playing，Environment Context 为 none |
| 稳态 | Docked Playing，并使用与 Docked Paused 相同的 Environment 与 Environment Effect |
| 稳态 | Panorama Playing；Environment Context 为 none，只保留黑色周围环境与视频投影球面 |
| 组合检查 | Window Playing，同时保持 Environment Context 为 active |

第九个工况检查 Window 视频与独立 Environment 同时运行时，资源消耗是否明显高于两者分别运行时的结果之和，并计入已经测得的正常变化范围。若超出该范围，发布测试增加 Window Playing/Paused 与 Environment Context none/active 的四种组合；否则不增加这些重复组合。

App 冷启动、App 热激活、媒体冷打开、媒体热重开、Seek、密集 UI 操作以及 Window/Docked/Panorama 转换作为独立瞬态工况采集峰值、持续时间和恢复时间，不混入上述长窗口静息或稳态测量。

发布功耗认证使用两个测量时长。九个固定工况全部在各项指标不再持续上升或下降后，执行相同长度的测量并重复运行；校准阶段测得功耗最高的一个或两个 Playing 工况，以及第九个工况接近门槛时，再执行长时间连续测试。长时间测试必须证明功耗和设备热状态不持续恶化，CPU/GPU 没有因设备温度升高而降低处理能力并导致更多帧无法按时完成，播放没有新增停顿、掉帧、hang 或内存增长。

从操作结束到正式测量开始的等待时间、每次测量的持续时间、长时间连续测试的持续时间和重复次数，都在校准阶段确定。确定这些数值时使用当前 Xcode 与 Vision Pro 上的 Instruments 预实验，观察各项指标停止持续变化所需的时间、重复测量之间的变化，以及统计判断允许的错误概率；在这些依据完成前不得凭经验写成发布门槛，也不得因为缩短测试更容易通过而修改。

## 风险维度与组合方式

RealityKit 空间呈现和 Remote Source 是两个分别覆盖自身行为的主要回归维度，不对两者执行完整笛卡尔积。

空间呈现回归使用稳定、受控，并且能够根据画面标记与时间标记明确判断结果的 Diagnostic Media，完整覆盖 Window、Docked 与 Panorama 的合法转换、返回、失败回滚、系统中断恢复和转换期间的持续播放合同。该维度负责证明 Presentation Transition、Renderer Consumer Binding、Environment Context、Media Session 连续性和目标表面的最终结果。

远程来源回归分别覆盖 SMB 与 WebDAV 的连接、认证、只读浏览、媒体解析、Range 读取、Seek、网络中断、重连、失败呈现和访问资源释放。除交叉场景外，这些行为在 Window 中验证，以便将来源失败与空间呈现失败分离。

交叉回归只保留能够证明两个维度之间合同的代表场景。SMB 与 WebDAV 都必须至少完成一次从 Window 进入空间呈现并返回 Window 的往返，并证明访问租约在整个 Media Session 内有效、Presentation 迁移没有重开 Media Session、远程读取继续服务当前 stream epoch，且画面、时间线与存在音轨时的音频继续推进。交叉回归不重复空间呈现或远程来源各自已经覆盖的完整矩阵。

### Remote Source 验证职责

Remote Source 的同一项发布结论必须由以下三类工作中与该结论对应的证据支持。某一类结果不能替代另一类要求的事实。

适配器测试使用预先规定的 SMB 或 WebDAV 请求、响应和错误，验证路径规范化、服务器与账号身份、凭据隔离、目录解析、Range 请求与响应、读取分块、错误转换、取消和资源释放。这些测试可以控制每个协议分支，因此负责覆盖数量较多的输入与错误组合；它们不证明真实服务器兼容性或 Vision Pro 界面。

真实服务器测试分别连接实际 SMB 与 WebDAV 服务。服务器可以与测试控制端位于同一台 Mac，但目录浏览和媒体字节必须真正经过对应协议；这类本机服务器端到端验证不能退化成直接文件读取或协议单元测试。每种协议都必须完成连接与认证、列出目录和媒体、解析播放地址、读取指定字节范围、播放期间 Seek、浏览连接结束后继续保持当前 Media Session 所需的访问权限，以及关闭 Media Session 后取消未完成读取并且只释放一次访问资源。凭据不得出现在播放 URL、日志或结果文件中。

位于另一台设备或独立网络环境中的服务器用于独立设备服务器端到端验证，补充本机服务器不能证明的跨设备连接、网络中断与恢复行为。只访问本机地址或由同一测试进程直接提供媒体字节不能形成这项证据；独立设备验证也不替代每种协议的本机可重复回归。

Vision Pro 真机测试从正常 Enchron 界面创建 SMB 或 WebDAV 来源，浏览目录，把远程媒体引用加入 Media Library，打开并持续播放，执行 Seek，关闭媒体，然后从保存的 Media Reference 再次打开。测试必须使用生产 adapter、真实凭据存储和真实服务器，不能直接注入来源状态或播放 URL。除成功路径外，另行规定的用户可见失败与恢复场景也必须在真机执行。

适配器测试负责证明协议分支的处理规则；真实服务器测试负责证明生产 adapter 与服务器之间的协议交互；Vision Pro 真机测试负责证明用户通过公开界面能够完成相同行为并看到正确结果。三类结果分别记录，不能合并成一个笼统的 Remote Source 通过结论。

### 远程播放失败与重试

首次可用音视频输出形成前，分别在连接、来源解析和 Media Session 打开阶段使服务器或受控 adapter 产生可恢复失败。测试必须断言 Enchron 只在预先规定的次数和总等待时间内自动重试；每次失败尝试都有独立可追踪的 Media Session 身份，其会话和来源访问资源在下一次尝试前已完整关闭和释放。最终成功时只有一个活动 Media Session 并形成本方案定义的可用音视频输出；超出规定范围仍未成功时显式进入 failed，不得继续后台重试。

首次可用音视频输出已形成后，在持续播放和 Seek 后持续播放两种情况下中断 SMB 与 WebDAV 读取。测试必须断言音视频不再推进、Playback Lifecycle 显式进入 failed、不存在背景自动创建或替换 Media Session，并且原 Media Reference 仍被保留。Window 的失败界面和 Docked/Panorama 的 Player Control Dock 都必须显示 Retry 与 Close；在用户选择 Retry 前，Media Session 数量不得增加。

用户选择 Retry 后，测试必须断言 Enchron 重新解析原 Media Reference 并创建一个新 Media Session，不切换 Remote Source、provider 或播放实现。当新的 Content Revision 与失败前一致时，测试在网络中断前按固定频率保存连续的输出观测；只有同时证明当前 Media Session 和 stream epoch、时间线前进、画面显示与持续推进，以及存在音轨时音频 sample 推进、audio renderer 正在 rendering 且系统音频路由有效的观测，才可以提供起始 media time。新 Media Session 必须从失败前最后一次满足这些条件的观测所记录的 media time 开始；使用原始打开位置、最后一次界面 Seek 请求位置，或来自其他 Media Session 与 stream epoch 的位置都必须失败。

受控服务器分别在 Retry 时返回已变化的 Content Revision，以及仍可读取媒体但无法可靠提供 Content Revision 的响应。两种场景都必须断言旧位置未被使用、新 Media Session 从 media time 零开始、播放没有等待第二次用户确认，且 Window 或空间 Player Control Dock 中出现不阻塞播放的说明，准确区分“内容已变化”与“无法确认与失败前的内容一致”。远程来源仍无法访问时，测试必须断言播放保持 failed、Retry 与 Close 继续可用，且没有新的活动 Media Session。

## 音频证据与物理声学认证

所有包含音轨的 Vision Pro 发布必过场景都必须取得数字音频链路证据。证据至少证明当前 stream epoch 的 audio sample 持续推进、audio renderer 处于 rendering 且没有 error、renderer 没有 mute 或零 volume，并且系统 audio session 与输出 route 有效。Pause、Resume 与 Seek 场景必须分别证明操作后的数字音频状态符合对应 Playback Lifecycle，不能用视频时间线或播放按钮状态推断音频成功。

外置麦克风与 UR12 只承担声音已经离开设备扬声器的物理声学认证，不与全部 Remote Source、媒体格式和 Playback Presentation 组成排列组合。标准声学场景使用能够与实际时间对齐的 Play、Pause、Resume、播放态 Seek 与最终 Pause 标记，并按照 [`verification-system.md`](verification-system.md) 的声压差阈值分析和保存原始 WAV、录音起始时间、`.xcresult` 与分析 JSON。

以下任一条件成立时，物理声学认证是发布门槛：

- V1 或其他正式发布候选版本进行最终验收；
- audio provider、Renderer Graph、synchronizer、系统 audio session、Pause/Resume、Seek 或 rate 恢复逻辑发生变化；
- Xcode、visionOS 或设备音频环境升级；
- 数字音频证据与实际听感、视频表现或历史结果不一致；
- 新增尚未完成物理声学认证的媒体格式或音频轨道类型。

只改变空间布局、视觉界面或远程来源浏览逻辑，且数字音频证据继续通过时，不触发重复的物理声学认证。

## Playback Presentation 真机成功矩阵

Presentation 成功回归同时观察 Playback Lifecycle、Playback Presentation、Environment Context 与 Immersive Space residency。Environment 是 Enchron 的场景内容身份；Enchron Immersive Space 是承载 Environment 或空间播放内容的平台容器。测试不得用 Environment Context 推断 Immersive Space 已经出现或消失，必须分别取得产品状态和平台生命周期证据。

Window 进入空间呈现具有四种必须验证的产品分支：

| Window 前置状态 | 用户操作 | 进入空间呈现的成功结果 | 返回 Window 的成功结果 |
|---|---|---|---|
| Environment Context 为 none | Dock · Dark 或 Dock · Light | 打开 Enchron Immersive Space，并在本次 Docked 期间临时使用 Default Scenic Environment 的 Night 或 Day Effect | 清除临时 Environment，关闭不再需要的 Immersive Space |
| Environment Context 为 none 或 active | Dock · Skybox | 打开 Enchron Immersive Space，并在本次 Docked 期间临时使用固定 Skybox Environment，不应用 Environment Effect | 返回 Window 时恢复进入 Docked 前的 Environment Context；原先为 none 时关闭不再需要的 Immersive Space |
| Environment Context 为 active | Dock | 复用当前 Immersive Space、Environment 与 Environment Effect | 原 Environment 与 Effect 继续活动 |
| Environment Context 为 none | 应用 panoramic Media Format | 为 Panorama 打开 Enchron Immersive Space；新的 Open Cycle 从 `1.0` Progressive Immersion Amount 开始；Environment Context 保持 none，只呈现黑色周围环境与视频投影球面 | 回到 Environment Context 为 none 的 Window，并关闭不再需要的 Immersive Space |
| Environment Context 为 active | 应用 panoramic Media Format | 复用当前 Immersive Space 并保持当前 Progressive Immersion Amount；停用自制 Environment 与 Effect，把它们保存为 Panorama Return Environment Context；Panorama 当前 Environment Context 为 none，只呈现黑色周围环境与视频投影球面 | 在同一 Open Cycle 内恢复原 Environment 与 Effect |

Vision Pro 发布候选必须执行以下六条往返，以覆盖每两项条件之间的组合；无需执行三项条件的全部排列。每一格都包含 Window 进入目标 Presentation 并返回 Window：

| Playback Lifecycle | Docked（进入前 Environment Context） | Panorama（进入前 Environment Context） |
|---|---|---|
| Playing | Environment Context 为 none | Environment Context 为 active |
| Paused | Environment Context 为 active | Environment Context 为 none |
| Ended | Environment Context 为 none | Environment Context 为 active |

这六条往返必须共同覆盖 Docked 与两种进入前 Environment Context、Panorama 与两种进入前 Environment Context、每个空间 Presentation 与 Playing/Paused/Ended，以及每个 Lifecycle 与两种进入前 Environment Context。Panorama 已绑定当前 renderer、画面达到对应成功标准并提交 Presentation 状态后，当前 Environment Context 必须为 none；进入前为 active 的格子还必须证明 Panorama Return Environment Context 保存原 Environment 与 Effect，并在返回 Window 后准确恢复。产品状态测试负责覆盖剩余六种三维组合，并证明组合结果与相同的状态合同一致。

Playing 场景必须证明转换前暂停、目标画面达到对应成功标准后恢复播放，并且音视频持续推进。Paused 场景不得发出暂停或恢复命令，并且目标表面保留当前画面。Ended 场景不得发出暂停或恢复命令，目标表面保持纯黑、系统 audio session 停用且 Replay 语义不丢失。所有场景都必须保持同一 Media Session；返回 Window 不能重新打开媒体。

Docked 与 Panorama 的空间视频表面不得提供可点击产品控件；召唤后的 Player Control Dock 是唯一的 App 界面。每条空间场景都必须断言播放控制、对应 Settings 与 Return to Window 可访问，并断言不存在直接退出当前媒体或返回 Media Library 的 Back。只有回到 Window 后，Window Back 才关闭当前 Media Session 并返回 Media Library。
