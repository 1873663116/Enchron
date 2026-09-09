# 播放引擎的外部约束与实测常数

本文记录 `Packages/PlaybackCore` 里那些**无法从代码本身读出**的事实：平台框架的实际行为、实测数字的出处、以及同类播放器在同一问题上的做法。可以由代码或断言表达的部分不写在这里——它们的真相源是 `Packages/PlaybackCore/Sources` 与 `Packages/PlaybackCore/Tests`，本文只在必要处指名对应的测试。

## 渲染器超前预算的单位

`RendererLeadBudget` 按**帧数**计量交付循环可以跑在时间线前面多远：从地板起步，稳定交付 1.5 秒后升到来源上限，本地 32 帧、远程 48 帧；系统内存压力把上限降到 24 帧（warning）或 16 帧（critical）。它不再按解码字节算，也不再读进程可用内存。

地板是 `max(reorder 深度, 2) + 2`，由停播 seek 决定：时间线在目标之后要再收到 `max(reorder 深度, 2) + 1` 帧（解码器的输出滞后加一）才落到目标上，目标帧本身也占 gate 一个名额，所以 gate 至少要放 `max(reorder 深度, 2) + 2` 帧，否则停播 seek 永远停在关键帧的时间上，位置与字幕都停在那里。`pausedSeekCoverageIsSettled` 与地板共用 `RendererLeadBudget.outputLagFrames`，断言 `theLeadFloorAdmitsTheFramesAPausedSeekNeedsToSettle` 把这条关系钉住。

2026-08-22 起的规则按「解码字节 ÷ 单帧解码大小」定帧数，200 MB 在 4K 十比特只给 8 帧，在 8K 只给 4 帧。2026-09-08 在 Vision Pro 上的二分与扫描证明这条规则就是掉帧的原因，并且证伪了它的前提：

| 片源 | 预读 | 每秒显示帧（采样计数，上限约 50） | 领先时钟 | 系统反压 | 进程 footprint |
|---|---|---|---|---|---|
| 4K60 十比特，3 帧重排 | 8 | 33–35 | 65 ms | 0 | |
| 同上 | 12 | 42 | 132 ms | 0 | |
| 同上 | 16 | 41–48 | 199 ms | 0 | |
| 同上 | 24 | 45–52 | 332 ms | 0 | |
| 同上 | 32 | 48–51 | 465 ms | 0 | |
| 同上 | 48 | 45 | 731–899 ms | 0 | 461–512 MB |
| 8192x4096 60p | 4 | 21 | 14–115 ms | 0 | 167 MB |
| 8192x4096 60p | 24 | 46 | 348–399 ms | 0 | 345–351 MB |

三条事实决定了单位：饱和点在 24 帧上下，与分辨率无关，是硬解流水线加 RealityKit 采样自身的深度；整个过程送帧从未晚于时钟、相邻送帧间隔从未超过一个帧周期，本地来源的抖动不是原因；渲染器并不把送入的样本全部解出来持有，8K 送 24 帧的 footprint 只有 350 MB，「送几帧就持有几张解码帧」不成立，因此按解码字节设界没有依据。receiver 在 48 帧内从未挂起过交付，所以帧数上限是保险，不是它的胃口。

苹果的文档没有给出送多深的数字：`isReadyForMoreMediaData` 只描述队列占用，`hasSufficientMediaDataForReliablePlaybackStart` 只命名一个不公开的预热水位，RealityKit 的 `VideoPlayerComponent(videoRenderer:)` 文档要求「喂到满、准备好再喂」。其他播放器公开的 2–4 帧是显示侧队列，整条链（重排 + 在飞解码 + 图片池）VLC 约 14 帧、Chromium 旧 VideoToolbox 路径 16–21 帧；push 模型里这个预读对应的是整条链。

seek 的代价仍然随持有帧数超线性增长（2026-08-22 在 8K60 上测得 frames^1.8），所以上限不由稳态一次性给满，而由爬坡给：打开和每次 seek 后 `startVideoDelivery()` 重置起点，连续拖动永远停在地板附近。

上限停在 32 帧的依据是 seek 的冲刷代价。2026-09-08 同一台 Vision Pro 上把预算钉住后连做五次 seek，`seekFlushMs` 是 teardown 到渲染器 flush 完成的时间，`seekTotalMs` 是到 `control.seek.completed` 的时间：

| 片源 | 在飞帧 | 冲刷 | 整次 seek |
|---|---|---|---|
| 4K60 十比特 | 16 | 42–65 ms | 120–157 ms |
| 同上 | 32 | 77–100 ms | 165–189 ms |
| 同上 | 48 | 111–131 ms | 195–225 ms |
| 同上 | 60 | 135–156 ms | 231–253 ms |
| 4K 24p | 32 | 63–70 ms | 74–93 ms |
| 8192x4096 60p | 32 | 166–202 ms | 264–293 ms |

冲刷随在飞帧数线性增长，4K 每帧约 2.5 ms、8K 每帧约 5.5 ms；32 帧已经到达显示计数的饱和点，再往上只在每次 seek 里多付这段时间。远程来源多给到 48 帧，换传输抖动的余量。`Scripts/verification/renderer_lead_sweep.py` 在真机上按给定预算序列重复这组测量。

## 内存压力下的降档

2026-09-09 之前的规则是一道悬崖：`os_proc_available_memory()` 跌破 512 MB 就把预算退回地板。这条规则是这份文档里唯一没有实测出处的常数，而它与同一份文档里的两张表相矛盾——8K 在地板（4 帧）上每秒只显示 21 帧，在 24 帧上显示 46 帧，换来的是约 183 MB。它也没有回滞，而爬坡需要 1.5 秒，所以进入与退出会以几秒为周期来回震荡。

替换后的阶梯只有两档，触发信号也换了：

| 档 | 上限 | 触发 |
|---|---|---|
| 正常 | 本地 32 / 远程 48 | 默认 |
| warning | 24 | `DispatchSource` 内存压力 warning |
| critical | 16 | 同上 critical |

第一档是免费的：上面那张扫描表里 24 帧与 32 帧的显示帧率没有差别（4K60 十比特 45–52 对 48–51，8K 在 24 帧就是 46），而 24 帧每次 seek 少冲刷 8 帧，8K 上约 44 ms。第二档 16 帧是阶梯的底，不再往下走到地板：再往下是用几十 MB 换掉一半画面帧率，而 footprint 在这之后仍然增长意味着我们自己在泄漏，饿死画面只会把它盖住。

`floorFrames` 仍然压过每一档——它是停播 seek 的正确性下界，不是降级目标；reorder 深度深到让地板高于 16 的流，按地板给。爬坡起点也留在地板，与压力无关：它存在的理由是连续拖动时让在飞帧数保持低位，每次 seek 的冲刷才便宜。

**进程可用内存不再是这条阶梯的输入。** 它等于额度减去 footprint，而额度不因别的进程忙起来而缩小，所以它下降几乎总是我们自己长出来的。它触发的应该是告警与缓存释放，不是静默降档——后者恰好掩盖了该被发现的问题。

`MemoryPressureMonitor` 持有 `DispatchSource` 并给抬升的档位加 10 秒驻留（`releaseDwellSeconds`），压力消失后不立即回落，避免与 1.5 秒爬坡形成拍频；`setOverride` 给测试与设备扫描钉住档位。当前档位写进 `PlaybackDiagnostics.videoLeadMemoryPressure`，而 `videoLeadFramesCeiling` 保持来源自身的上限，读数因此是 `16/32` 而不是自洽的 `16/16`。

断言在 `PlaybackCoreTests`：`theLeadBudgetRampsFromTheReorderFloorToTheSourceCeiling`、`theLeadBudgetNeverSitsBelowTheEncoderReorderDepth`、`theLeadBudgetStepsDownUnderSystemPressureAndStopsAtSixteen`、`theCorrectnessFloorOutranksEveryStepOfTheMemoryLadder`、`theLeadBudgetIgnoresTheProcessAllowanceThatOnlyOurOwnGrowthMoves`。

2026-09-09 在真机上用 `renderer_lead_sweep.py` 扫过 `HNVR-158_H_4096p_8K_LR_180_clip`（4096p 8K 左右眼 180），补上了这两档的代价：

| 预读 | 显示帧率中位 | 最低 | 样本 | 轮次 |
|---|---|---|---|---|
| 16 | 34.8 | 0.0 | 19 | A |
| 24 | 46.6 | 41.5 | 16 | A |
| 24 | 44.0 | 6.0 | 12 | C |
| 32 | 45.6 | 39.9 | 17 | B |
| 32 | 43.6 | 36.5 | 15 | C |

**24 与 32 在显示帧率上无法区分**，两轮独立测量都是如此，C 轮更是在同一轮内相邻测得 44.0 对 43.6。warning 档因此确实不花帧率，这条成立。

**16 帧在 8K 上要付约四分之一的显示帧率**（34.8 对 46.6）。critical 档不是免费的，它只是远好过旧规则退回的地板——同一片源上地板给出 21 帧。这是内存真正紧张时愿意付的代价，不是常态。

这一轮**没能分离出预算本身对 footprint 的影响**。三轮里 footprint 都随会话时间单调上升，与预算的升降无关：A 轮升序读到 307／492／499 MB，B 轮降序读到 468／478／484 MB，C 轮升序读到 315／494 MB。窗口内的 footprint 峰值由预热主导，要测预算的内存代价需要另设计一轮（每档冷启、等 footprint 稳定后再采）。

因此常态上限是否该从 32 降到 24 仍未定：帧率上二者等价已经证实，但支持 24 的理由只剩 seek 冲刷，而冲刷数据只有 A 轮干净（16 帧 71.6–99.1 ms，24 帧 76.2–102.9 ms，32 帧 137.8–162.4 ms），B、C 两轮的冲刷区间互相重叠。要动这个上限，需要一轮专门测冲刷的扫描。

## 呈现帧率无法在进程内测量，六十帧的片源并没有掉帧

2026-09-09 一度记录「60 fps 片源只呈现约 50 帧」。**该结论错误，由 Instruments 推翻。**

当时的测法是按场景节拍（约 88 Hz）轮询 `AVSampleBufferVideoRenderer.displayedPixelBuffer()`，比对 IOSurface 的 ID，ID 变化计一帧。读数：4K 24p 精确 24，4K 60p 得 31–46，8K 60p 立体得 34–51，与分辨率和预读均无关。

同一次 4K 60p 播放的 Instruments trace（`Display` 与 `RealityKit Frames` 两个 instrument，真机，SIGINT 停止后导出 `metal-io-surface-access`）给出相反的事实：

| | |
|---|---|
| 3840×2160 表面被合成器访问 | 1616 次 / 27.2 秒 |
| 访问速率 | **59.3 / 秒** |
| 相邻访问的 surface id 变化 | **1614 / 1615（100%）** |
| 池中不同 surface | **4 个**（3113、3160、3161、3167） |

每一次访问拿到的都是新的 surface，速率 59.3/s，与源帧率 59.94 相符。**画面以满帧率呈现，管线没有丢帧。**

因此 `displayedPixelBuffer()` 轮询不是有效的帧计数器：24 fps 下帧间隔足够宽，读数准确；60 fps 下它会合并，读出约六到八成。引擎自己的 `observeDisplayedFrame()` 用同样的 ID 比对识别帧，带有同样的误差——`renderer_lead_sweep.py` 那栏「上限约 50」正是这个误差，不是被测对象的上限。凡是基于该栏得出的显示帧率结论都需要重新审视。

读数条因此不再报呈现帧率。进程内能诚实陈述的只有送帧速率对源帧率（`ENQ 60/59.940`），其余要用 Instruments。

**顺带测到解码帧池深度为 4。** 这是唯一一次直接观察到的池大小，可用于校准 `VID≈` 的深度假设（当前为 3 加重排深度）。

## 交付滞后恢复的实测数字

`PlaybackBufferingPolicy` 的四个常数各有出处：

- `seekAudioLeadSeconds = 0.2`：起点是 mpv 的 0.2 秒音频输出缓冲。Vision Pro 上 TrueHD 按 0.1 秒一个缓冲到达，因此这个值恰好容纳两个缓冲。
- `deliveryLagRecoveryTriggerSeconds = 0.5`：2026-08-17 的 Vision Pro 基线在迟到 0.527–0.873 秒处恢复出有界交付；0.5 秒是当时止住无界滞后的触发点。
- `deliveryLagRecoveryLeadSeconds = 1.0`：起点是 mpv 的一秒欠载恢复参考。同一条 2026-08-17 基线显示，把目标放到五秒会在远程 4K HEVC + TrueHD 上造成 6.8–13.1 秒的停顿。
- `opportunisticAudioMaximumLeadSeconds`：音频仍按媒体秒设界。解码音频体积小、渲染器 flush 便宜，对视频帧错误的那个单位在这里是对的。

`audioPrerollTimeout` 的五秒是 **provider 或渲染器故障的界，不是缓冲媒体的策略**；5 毫秒轮询让激活在该界内保持响应。它与 `seekProgressStallTimeout` 同为五秒是历史巧合，分开命名以免与已删除的"五秒媒体储备"混淆。

`seekProgressStallTimeout = 5 s` 从**最后一次观察到进展**起算，不是从等待开始起算，seek 的两条协调循环（视频与纯音频）都没有绝对上界。进展指四个信号中任意一个发生变化：会话 `sourceReadMeter.totalBytesRead` 增加、`lastVideoSample` 换了 `sourceEventID` 或呈现时间、`lastAudioSample` 换了流 epoch 或呈现时间、`lastAcceptedRendererInput` 换了 `sourceEventID` 或流 epoch。取消与关闭仍然当场中断等待。绝对上界是错的判据：2026-09-09 真机上 seek 到 999.9 s 落在 990.57 s 的关键帧，驱动器给出 4.3 MB/s 而该流需要 7.4 MB/s，到达目标要约 16 秒；五秒时解码样本数正从 745 走到 866，seek 仍在推进，却以 `seekTimedOut` 报错、记录失败、关闭会话，画面冻在原处。等待超过五秒墙钟而仍有进展时发一次 `session.seek.stalled seconds=<target> lastProgressMs=<n>`，慢而活着的 seek 因此在 trace 里可见；真正停摆时的失败记录带上 `progressAgeMilliseconds`，说明距上一次进展有多久。断言见 `aSeekThatKeepsMakingProgressCompletesAfterTheOldDeadline` 与 `aSeekWithNoProgressFailsAfterTheStallTimeout`（`Packages/PlaybackCore/Tests/PlaybackCoreTests/PlaybackCoreTests.swift`）。

恢复要求为什么被帧预算封顶：交付 gate 最多持有 `leadFrames` 个 presentation end 落在时间线之后的帧；跨越 `timelineTime` 的那一帧在它之后不足一帧就结束，所以这些帧能达到的最深 end 比 `leadFrames / nominalFrameRate` 少一帧。要求整段跨度，就是提出一个 gate 永远无法满足的条件。音频有自己按媒体秒的 gate，因此不受该封顶影响——否则恰好在读取最慢的那些流上放弃实测得到的恢复储备。断言见 `deliveryLagRecoveryNeverAsksForMoreThanTheGateAdmits`。

## 送帧滞后恢复就是播放中的缓冲态

- 送帧落后时间线 0.5 秒时，`beginDeliveryLagRecoveryIfNeeded` 在当前时间停住时基、进入预滚、等到 1 秒领先再恢复。这一步作废时间线看门狗，所以看门狗在网络饥饿时从不开口；饥饿的可见信号只能由滞后恢复自己发出。它发布 `detectionSource = deliveryLag` 的 `starved` 观测，这份观测保存在 run 之外，停住时基不会抹掉它，下一次时基变化（恢复、seek、暂停、关闭）以 `inactive` 清除。真机上 15 秒一次的读取延迟（`setSourceReadDelay`）让《黑客帝国》在 15.1 秒停住、时基 0，修复前 25 秒内没有任何指示，就是这条链；`deliveryLagRecoveryPublishesStarvationUntilTheTimelineChanges` 与 `deliveryLagStarvationClearsOnInactive` 钉住它。
- 读速率标签是每秒采样一次的字节增量。回环服务器按 1 MiB 整块转发，慢速后端上一块要等很久，标签在块与块之间读 0，这不表示没有在读。

## visionOS 的时基与速率激活

`AVSampleBufferRenderSynchronizer` 在 visionOS 上有一条必须绕开的行为：**只设媒体时间的 setRate 可以报告出请求的速率，而底层 timebase 在渲染器已被喂入之后仍停在零**。因此速率变化统一走 `setRateAtHostTime`——把同一个媒体时间绑定到一个近未来的 host time，给同步器一条显式的恢复边。由此派生出三条：

- 激活前重新锚定停住的 timebase，使速率变化施加在 preroll 队列填充之后的同一媒体位置上。
- `play()` 已经启动 timebase 之后不要再 stop 它：那会种下一个 rate-0 映射，大约一秒后才生效并把正在跑的时间线停住。
- 启动速率仍为 0（rebuild 入口按 startsPaused 打开）时跳过 host-time 激活，否则这里安排的 `setRate(0, atHostTime:)` 可能在稍后的 `play()` 之后才触发。

验证路径必须复用同一个 primitive，否则测的不是产品走的那条路；`PlaybackActivationObservation` 的注入点因此调用 `setRateAtHostTime`，并由 `audioPrerollsBeforeTimelineStartsAndResumeKeepsQueuedAudio` 断言 `activation.details["application"] == "setRateAtHostTime"`。

同一类异步边界还有一条：一个已 prepare 并 attach 的会话可以先报出 `ready`，而渲染器同步器的媒体时间锚定尚不存在。`waitUntilTimelineReadyForControl` 等的是第一个交付样本完成那次锚定，不是 `ready`。

## 时间线启动与激活的次序

启动路径上的次序不是风格问题，每一条都对应一个具体的错乱：

- 解码器 bootstrap 与（存在时）音频 preroll 都越过起点之前，时间线必须保持停止。首个视频 PTS 恰好等于请求起点时同样成立——PTS/DTS 非零的解码管线仍然需要 bootstrap 这道闸。断言见 `timelineRemainsStoppedUntilDecodeBootstrapReachesTheRequestedTime`。
- `play()` 可以在渲染器时间线已锚定、而 bootstrap 尚未激活它的窗口里到达。待激活状态必须跟随最新的传输意图，否则 bootstrap 会把会话较早的 starts-paused 状态恢复回来。断言见 `playDuringDecoderBootstrapBecomesTheTimelineActivationIntent`。暂停同理：对一个 bootstrap 未完成的时间线，暂停仍是权威意图。
- 普通打开没有可 preroll 的未来时间线目标，同步器在第一个被接受的样本之后启动，与既定的 `AVSampleBufferRenderSynchronizer` 启动路径一致。
- 被 seek 取消的交付任务可能仍停在记账调用内部，而 seek 已经清空账本。此后再记录会把一个 seek 之前的帧算到新流头上；向后 seek 时它会一直挂在那里，直到时间线重新走到它。
- 要求停在选定的一帧上，优先于 preroll 的待激活——否则后者会在它下面把时间线重新锚定。
- 时间线以已知速率前进，因此闸门打开的时刻是算术而不是轮询对象；时间线停住时不退休任何帧，只有状态变化能解锁它，所以那条路径退回到粗粒度间隔。
- 恢复停住时间线并要求一段以媒体秒表达的视频。表达帧闸门放行的范围需要帧率，因此一条不报帧率的流无法被定尺寸，宁可让它继续跑，也不要卡在一个它可能永远达不到的要求上。

## 逐帧步进两个方向都是 seek

暂停中的 `AVSampleBufferVideoRenderer`（经 `VideoPlayerComponent` 呈现）不会因为时钟移动而换画面。原来的前进一帧只把速率为 0 的 timebase 拨到队列里下一帧的 PTS，指望渲染器按新时钟重绘。2026-09-06 模拟器实测：连续 16 次前进，时钟每次恰好走一帧（10.187 → 10.721 s），渲染器 `displayedPixelBuffer()` 的亮度指纹连续 5 步、再连续 10 步不变，`droppedFrames` 计数全程停在 4——它没有因为时钟移动重新评估过队列；同一会话里每次后退（seek）显示的像素都变了。只有 flush 再重新入队才让它显示新的一帧，Apple 文档对速率为 0 时的行为没有任何说明。因此 `stepFrames(by:)` 不区分方向，都折成 `base + delta × 帧长` 的一次 `seek(to:after:.pause)`，落点由下文暂停 seek 的覆盖帧规则决定；每次步进付一次 flush + 重开（该流上约 106 ms + 104 ms），与后退一直在付的一样，连击由 runtime 的合并收敛。断言见 `forwardStepSeeksEvenWhileTheRendererHoldsTheNextFrame`（渲染器已持有下一帧时前进仍 flush 一次并以 seek 收场；delta 为 0 不动）。

## RealityKit 的 tagged buffer 契约

`CMTaggedBufferGroup` 描述的是**解码后的 pixel buffer**。把压缩样本包进 tagged buffer group，可以让渲染器在本来有效的高分辨率 HEVC 输入上拒绝或崩溃。压缩的 SBS/OU 始终是一个 codec sample，它的 packing 与 projection 留在 `CMVideoFormatDescription` 里。断言见 `VideoSampleFormatOverrideTests` 的 "compressed packed stereo stays a directly decodable renderer input"。

## Dolby Vision 的判读

Profile 7 把配置记录放在**增强流**而不是被解码的基础层上，因此 `dolbyVisionProfile` 必须扫描来源的每一条视频流才读得到。两层来源只交付基础层，`dolbyVisionHasEnhancementLayer` 因此是"来源声称的 Dolby Vision"与"佩戴者实际收到的画面"之间的分界。断言见 `PlaybackFFmpegBridgeTests`（profile7 的两条 `#expect`）。

- **命名规则的三个 fixture 里，前两个的 level 与 cross compatibility ID 朝相反方向背离**，这排除了两个字段按惯例总是相等的可能。`Scripts/rules/check_dolby_vision_premises.py` 的 `FIXTURES_WHERE_LEVEL_AND_CROSS_ID_DISAGREE` 选中它们正是为此。
- **第三个命名 fixture 是唯一走到"完全省略数字"那条分支的文件**：`Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4` 发布为 Dolby Vision Profile 5，level 为 1、cross compatibility ID 为 0，按 level 命名会读成 Profile 5.1。见 `Scripts/rules/check_dolby_vision_premises.py`。
- **构造"携带无关 Dolby Vision 轨道"的容器时，第一条流必须是 `av_find_best_stream` 会挑中的那条**（`-disposition:v:0 default`、`-disposition:v:1 0`），否则配置记录会落在被解码的流上，`detect_dolby_vision` 中关于其他流的那条规则根本不会被触及。见 `Scripts/rules/check_dolby_vision_premises.py`。

## 诊断把判定与文本分开

`rendererFailedToDecode` 与 `rendererError` 是两个字段：判定归判定，框架文本归文本。产品表面因此永远不需要解释框架措辞。同类的分工还有 `audioRetired`——音频可以离开活动图而视频继续，断言见 `audioRendererFailureRetiresAudioAndVideoContinues`（以及 `audioProvider.openFailed.videoContinues`、`audioProvider.readFailed.videoContinues` 两条 stage 名）。

## 呈现转换换渲染器而不换会话

一次呈现转换需要的是一个新 RealityView Entity 从未绑定过的渲染器。做法是在同一条时间线、同一个已打开来源之上替换 renderer graph，代价是一次文件内 refill，而不是第二个 demuxer、第二次轨道枚举和第二次网络打开。

三条随之而来的约束：

- `AVSampleBufferVideoRenderer` 在加入 video target 之前拒绝 enqueue，所以替换后视频样本交付保持挂起，由调用方绑定 Entity 后经 `restartVideoSampleDelivery(at:)` 重新填充。
- 离场渲染器留在同步器上显示它的最后一帧，直到 `retireDepartingVideoRendererGraph()`；转换期间离场 Scene 因此始终有画面。
- 调用方必须已经挂起视频样本交付，替换发生时离场 sink 不能有 enqueue 在飞。

一次**实时格式修订**走的是另一条路：不替换 renderer graph，而是建立一次解码器不连续——provider 向后 seek 把压缩流从一个可解码的同步边界重启，渲染器 flush 清掉所有按旧呈现格式分类的样本。

## 流选择与格式探测

- reader 用 `av_find_best_stream` 挑视频流，并以 `stream:<index>` 报告挑中哪一条。文件的第一条视频流可能是附图或预览，直接取第一条会描述一帧解码器根本不产出的画面。
- 一张合格的 MOV 流表可以让 open 跳过 `avformat_find_stream_info`，被跳过的探测本该填的字段留在零值。渲染器超前预算花的正是这些字段，而一个静默的零读作"这帧不花钱"，会把为 720p 准备的上限发给 8K 流。已知缺口是 Sony 那条 4:2:2 十比特 H.264：真实成本每像素四字节，但 H.264 解码器在解出一帧之前不选定像素格式，`avcC` atom 本身也带不回色度格式，估计因此落到 4:2:0 八比特——高估预算而不是饿死它。强制探测能买到精确数字，代价是每次 open 都读媒体字节，而这条路径存在的目的正是避免它。
- CoreMedia 只在 `create_h264_format_from_avcc` 调用的参数集构造里展开 SPS 的颜色声明。仅由 `avcC` atom 构建的描述会丢掉 primaries、transfer、matrix 与 range 四项。相关 fixture 把这四项只声明在 SPS 里，正是为了钉住这条。
- 从来源格式描述读出的 projection kind、view packing kind 与左右眼视图标志，用途是让产品在渲染器发布之前拒绝 Apple Immersive Video。它们**不构成来源格式替换的授权**：codec payload 与聚合来源仍归 bridge 所有。
- **内嵌字幕只能顺着容器读出来，而共享来源只跟着播放头走。** MKV 里的字幕包与视频包交错，没有独立索引；`FFmpegSubtitleProvider` 在共享 demux 来源上取字幕时，来源的读线程受 150 MB 前向预算与已订阅队列的目标时长约束，停在播放头前方约九十秒处，只随视频消费前进。因此共享来源上的字幕渲染器**不得在创建时读到流末尾**——那意味着按播放速度等到片尾，而且构造过程持有 `FFmpegDemuxSession.operationLock`，同一把锁上的 seek 与 close 都会随之死等，下一次 open 又等 close。约束的落点：`PBSubtitleFrameRendererCreateWithDemuxSource` 只订阅并取走已排队的包，订阅随渲染器存续，`PBSubtitleFrameRendererIngestAvailablePackets` 在每次发布字幕时非阻塞地折入新到的包；seek 后来源会重读同样的包，渲染器按包身份去重，位图字幕按显示时间插入以保持顺序解码。`PBFFmpegDemuxSourceUnsubscribe` 会清空该流已排队的包，而小文件的共享读线程早已到 EOF，所以共享来源上的渲染器要按轨道在会话内保留（`FFmpegSubtitleProvider.sharedRenderers`），换轨不销毁旧渲染器，重选才拿得回它已持有的包。共享来源的读线程从上一次 seek 目标（或打开位置）起排队每一条字幕流的包，有没有订阅者都排（`prebuffersSubtitle`），所以字幕的"积压"只是覆盖起点被 seek 挪动后的修补：覆盖从 0 开始时它是空操作。seek 之后，开始时间早于 demuxer 回退关键帧落点的 cue 不再靠读文件找回，它随该轨道的下一条 cue 出现。曾经的做法（1fff3e46）是为此打开第二个 FFmpeg 上下文把整个文件读到片尾：66 GB 的远端 MKV 上那是约 1.8 小时的顺序读，且没有 interrupt 回调，结果是字幕选择永不落定、`closeAndWait` 永远等字幕任务、下一次 open 永远等 close，用户看到的是之后每一部都停在 0 B/s。远端来源上选择内嵌字幕不打开第二个输入、不发起新的 Range 请求。断言在 `PlaybackCoreTests`：`sharedSourceSubtitleRendererFoldsInQueuedCuesWithoutDuplicatesAfterASeek`、`aSubtitleRendererCreatedAfterAForwardSeekReceivesTheCuesThatFollow`、`sharedSourceSubtitleSelectionCommitsWhileVideoIsStillQueued`、`reselectingASubtitleTrackAfterTheSharedReaderEndedKeepsItsFrames`、`selectingAnEmbeddedSubtitleOpensNoSecondInputOnTheRemoteSource`、`selectingASubtitleTrackCommitsWhileTheRemoteSourceStalls`。
- **字幕路径打开的每个 FFmpeg 上下文都随会话关闭被打断。** `PBFFmpegSourceReadMonitor` 带 `interrupted` 标志，bridge 的 interrupt 回调 `publish_source_bytes_and_check_cancellation` 每次轮询都查它；`SampleBufferPlaybackSession.interruptSourceReadsForClose` 在 `closeAndWait` 取消并等待字幕任务之前把它置位，与共享 demux 的 `PBFFmpegDemuxSourceInterrupt` 并列。FFmpeg 的 HTTP／TCP 协议在等数据时轮询该回调，卡住的读在一次轮询内以 `AVERROR_EXIT` 返回；file 协议不轮询，本地文件的读只受文件大小约束。字幕文档（外挂 SRT／ASS 等）的渲染器只能经 `PBFFmpegMonitoredSourceOpen`（`PlaybackFFmpegBridgeInternal.h`）借到上下文，`SubtitleFrameRenderer.c` 里没有 `avformat_open_input`；被打断或截断的文档读让构造失败，而不是返回一条更短的轨道。字幕文档的读还随 Swift 任务取消中止：`PBFFmpegReadCancellation` 是一个粘性的 `atomic_bool` 句柄，与 monitor 并列进入同一个 interrupt 回调，只作废用它打开的那些上下文；`FFmpegSubtitleProvider` 的两条文档分支都在 `withTaskCancellationHandler` 内执行，闭包持有句柄直到读结束，取消时置位。seek、换字幕轨与移除外挂字幕源依赖这条通路——它们取消 `activeSubtitleSelectionTask` 并等待其值，在此之前一次卡住的文档读要等到用户离开该片才返回。规则 `Scripts/rules/verify_subtitle_reads_interruptible.py` 钉住上下文只从 `allocate_format_context`／`open_media_source` 产生、字幕构造器带 monitor 与 cancellation、monitored 门与字幕 reader 不以 NULL 标志分配上下文、扫描不再回来。断言在 `PlaybackCoreTests`：`anInterruptedSourceReadMonitorAbortsSubtitleOpensOnAStalledSource`、`aSubtitleDocumentCutOffMidReadFailsInsteadOfReturningAShorterTrack`、`interruptingAReconnectedSourceStopsItsReadThread`、`cancellingASubtitleSelectionReturnsWhileTheRemoteSourceStalls`、`closingTheControllerWhileASubtitleSelectionIsInFlightSettles`、`cancellingAnExternalSubtitleLoadReturnsWhileItsSourceStalls`、`cancellingAnExternalSubtitleRendererReturnsWhileItsSourceStalls`。
- **离开播放的关闭有一秒上界，越界就强制拆除。** `PlaybackRuntime.beginStop` 让关闭序列与 `PlaybackCloseBudget.deadline` 赛跑，先到者定局。这个界限来自实测：渲染器 flush 实测 85 ms；FFmpeg 在等网络数据时每 100 ms 轮询一次 interrupt 回调，被打断的读在一次轮询内返回；读线程退出与 URLSession 取消各在数十毫秒量级；设备上整次关闭实测 109 ms。一秒是这条路径上的三倍余量。**这个上界只覆盖关闭里的每一次 await。** 关闭体与 deadline 任务同在 MainActor 上，deadline 只能在关闭体让出 MainActor 的挂起点之间跑起来：`SampleBufferPlaybackSession.close()` 里的队列 sync 这类同步工作没有挂起点可抢，它跑多久就占多久，越界的判定与强制拆除都要等到下一次挂起才发生。关闭先落定时取消仍在休眠的 deadline 任务，按原样结束；deadline 先到时关闭体继续在后台跑完，它最终返回时留下的 `runtime.close.lateSettled` 与 `runtime.close.end` 是它到底在等什么的唯一证据，此时它不再释放来源访问与外挂字幕访问——`forceTeardown` 已经放过一次，而其后的 open 用 `ensureActive()` 重新武装同一个 lease，迟到的释放掐掉的是一条活着的租约。运行时走 `forceTeardown`：`RendererTransferCoordinator.abandonClose` 先把状态置回 empty（此后被放弃的会话的终态回调过不了 active driver 门），再让其中每个 driver 经 `PlaybackCoreController.abandonActiveSession` 打断来源读、不等待地取消 seek／格式／字幕与退休任务、清掉待清理会话标识使迟到的回调被忽略，并唤醒卡在 `closeAndWait` 上的等待者；`PlaybackAudioSessionLifecycle.abandonDeactivation` 丢掉卡住的停用任务并把状态压回 inactive，否则下一次 open 在 `activateIfNeeded` 里等的正是这个 `.deactivating` 任务；来源访问与外挂字幕访问随即释放。**放掉 media slot 只对被放弃的那个 controller 有意义**：每一次关闭都让 coordinator 回到 empty，下一次 open 造的是新的 driver 与新的 `PlaybackCoreController`，旧 controller 不再被打开，它的 slot 只是不能一直记着上一个会话。`closingTask` 只在越界的那次关闭仍然是当前那次时置空——A 越界时 B 已经在跑就轮不到 A 清，否则下一次 open 不等 B；residency 同理，只有当前那次关闭落定才回到 browsing。修订这个数字的依据是 `runtime.close.begin`、`runtime.close.end` 与 `runtime.close.overran`（带 elapsed、reason 与 abandonedDrivers）三条 trace 上的实测 elapsed，以及 `closeOverran` 证据探针里的 reason 与 elapsedMs。断言在 `Tests/PlaybackFeaturePackageTests/PlaybackResidencyTests.swift`：`aCloseThatCannotFinishOverrunsAndReleasesTheNextOpen`（停用卡住，下一次 open 必须整个跑完才放行）与 `aDriverCloseThatCannotFinishIsAbandoned`（driver 的关闭卡住，abandonClose 放弃它并留下 `controller.close.abandoned`）。
- **`PlaybackFFmpegBridge` 只按 `codec_type` 判定一条流属于哪一类**。m4a 里的封面图因此被算作视频流，带封面的音频文件的 mediaKind 是 video 而不是 audioOnly；要一个真正 audioOnly 的资产，只能选完全不带视频流的那种。见 `Scripts/rules/test_fixture_registry.py`。

## visionOS 的系统中文字体只有 hvgl 轮廓，FreeType 要带 Apple HVF 驱动才打得开

visionOS 上 CoreText 为汉字回退选出的系统字体是 `PingFangUI.ttc`（`/System/Library/PrivateFrameworks/FontServices.framework/CorePrivate/`），字形只在 Apple 私有的 `hvgl` 表里，没有 `glyf` 或 `CFF`。libass 的 CoreText provider 按路径打开这个面时，普通 FreeType 报 "unknown file format"；libass 在一个候选字体打开失败后不再尝试下一个候选，整个 `ASS_Font` 里的这些字都落成缺字方框。这条回退不看语言——`ass_coretext.c` 的 `get_fallback` 对 验、日、體 都返回 PingFang——所以在 libass 路径上简体、繁体、日文一起失效，只有样式自己点名 Hiragino 的行借日文字体活下来。运行时里没有任何带 `glyf`／`CFF` 的面覆盖简体常用字（Hiragino 系列对 32 个简体专用字只覆盖 5 个），换系统字体走不通。

出路是 FreeType 的 Apple HVF 驱动（`freetype` 提交 `c39ca391`，`-DFT_DISABLE_HVF=FALSE`，链接系统 `libhvf`）：带上它，`FT_New_Face` 以 HVF 驱动打开 PingFangUI.ttc 的 47102 个字形并交出真实轮廓，`hvgl` 表按文件映射，渲染器 RSS 约 44 MiB。`Scripts/build_subtitle_renderer.sh` 因此对 `xros` 与 `xrsimulator` 两种 SDK 都走 HVF 分支；2026-09-06 之前只有真机 slice 带 HVF，模拟器 slice 是普通 FreeType，这就是"模拟器上 ASS 中文全是方框"的来源。macOS 宿主用不到 HVF：那里 CoreText 把 `PingFang SC` 指向 `AssetsV2` 里带 `CFF` 的资产字体，普通 FreeType 打得开，所以 macOS 测试通道对这条约束没有区分度。曾经的 `PBSubtitleSystemFontCopyChineseFallback` 把 CoreText 回退面的表重新打包成内存字体交给 `ass_add_font`，它从未打开过——没有 HVF 是 "unknown file format"，有 HVF 是 Invalid_Table——却让每个 ASS 渲染器多持有两份约 57 MiB 的拷贝（RSS 213 MiB 对 43 MiB），已删除。

落点：文本类字幕（subrip、webvtt、mov_text、text）的帧由 `CoreTextSubtitleFrameRenderer` 用 CoreText 光栅化，系统字体回退由 CoreText 完成；libass 只服务 ASS／SSA 与位图字幕，ASS 样式点名的字体缺席时由 libass 的 CoreText provider 回退到 PingFang。断言在 `PlaybackCoreTests`：`assSubtitleRendererDrawsHanCharactersInsteadOfMissingGlyphBoxes`（五个单字帧两两不同，缺字方框彼此相同；只在 visionOS 模拟器通道上有区分度）、`textSubtitleRendererDrawsDistinctCJKCharactersInsteadOfMissingGlyphBoxes`。

## 文本字幕的默认样式来自画布分数与系统字幕外观

`CoreTextSubtitleFrameRenderer` 的样式是 `CoreTextSubtitleStyle`：画布分数与 Media Accessibility 用户域字幕外观（`MACaptionAppearance*`，`.user`）的合成，不再是绝对像素常数。字号 = 画布高的 5% × `RelativeCharacterSize`（默认 1.0，系统的 "Outline Text" 1.5、"Large Text" 1.75），字体来自 `CopyFontDescriptorForStyle(.default)`（visionOS 27 与 macOS 27 上都是系统字体 Medium；描述符不带字号，5% 由应用负责），填充色与不透明度来自 `CopyForegroundColor`／`GetForegroundOpacity`；边缘始终有 0.06 em 的纯黑外描边，只在用户选了 Raised／Depressed／Drop Shadow 时按 WebKit 的几何（±0.1 em 偏移、0.16 em 模糊）加阴影；行距 1.2 em，左右与底边距各为画布的 5%，块高最多三行，超出的行不画。汉字仍由 CoreText 级联回退到 PingFang。这组数字落在主流播放器的带宽内：mpv 5.28%H、描边 4.3% em、无阴影；VLC 6.25%H、描边 4% 字高；FFmpeg 给 SRT 的 libass 头 5.56%H、描边 6.25% em、无阴影；Apple 自己的渲染器（WebKit）5% 最小边 × 字符比例、SF Medium、默认无描边。`MACaptionAppearanceGetDisplayType` 只管字幕是否自动开启，不参与样式。用户改字幕外观时 `kMACaptionAppearanceSettingsChangedNotification` 让渲染器重解析样式并作废缓存帧，下一帧带新的 `changeIdentifier`。`default_ass_header`（只给无头 ASS 流的 libass 样式）保持同一组数字。断言在 `PlaybackCoreTests`：`subtitleStyleDerivesFromTheCanvasAndTheCaptionFont`、`subtitleStyleScalesWithTheUserCaptionCharacterSize`、`subtitleBlockNeverExceedsThreeLines`、`subtitleDefaultStyleDrawsNoShadowUnlessTheUserPicksAnEdgeStyle`。

## 换音轨要走 seek 的重新武装路径

换音轨时会话停住时间线、冲掉音频渲染器并重新打开音频 provider；共享 demux 来源同时需要 seek 回当前位置并重新打开视频 provider。此后直接 `setRate(rate, time:)` 恢复速率，在 visionOS 上得到的是请求速率为 1 而实际时基为 0 的时间线（见"visionOS 的时基与速率激活"）：新音轨还没有 preroll，同步器不会启动，画面停住而 UI 仍显示播放。正确的恢复与 seek 相同——`hasStartedTimeline = false`、`timelineStartRate = rate`、`requestedTimelineStart = 当前时间`、重置 decoder bootstrap 并冲掉视频渲染器（保留已显示的画面）——让 bootstrap 与音频 preroll 之后的 `setRateAtHostTime` 激活时间线。断言在 `PlaybackCoreTests`：`audioTrackSelectionWhilePlayingRestartsTheTimelineThroughPreroll`。

## 诊断工具的时间基准

`Tools/RemoteMediaProbe` 的跨度限制一律从**第一个 presentation time** 起算，而不是从零。Apple 的 projected-media 示例首样本的时间戳接近十秒，按绝对界计量时它们在交付第二帧之前就已满足要求。

## 连续播放证明与用户暂停

`playAndVerifyRendererGraphContinuity` 在 play 之后最多等三秒，要求 accepted input、实际时基速率、显示进度三者都前进。这三秒里用户可以再按一次暂停：时基速率归零是用户的意图，不是渲染器的故障。证明因此在每轮采样先看 `currentRate()`，速率为零即返回 `supersededByPause`，`explicitPlayMayContinue` 为真，运行时不报 `Playback Error`。断言在 `PlaybackCoreTests`：`explicitPauseDuringTheContinuityProofSupersedesTheProofInsteadOfFailingIt`。

## 显示证据为什么要两次身份变化

一个非空的 displayed pixel buffer 只证明存在一张图像。同一个 IOSurface 身份可以在后续帧写入时被复用，因此"这个 renderer graph 呈现了更晚的帧"要由 Core Video 身份的变化来记，且转移门要求两次这样的变化。`RendererGraphPlaybackContinuity` 刻意把 accepted input、同步器的实际速率、显示进度三者分开，就是因为其中任何一条单独都不足以判定。

## Package 平台声明里的 macOS

产品只在 visionOS 出货，但设备上跑一次测试要经过构建、安装、启动。若不在 `Package.swift` 声明 macOS，引擎自己的测试就只能经 app 的测试目标到达，而它们并不在其中。该条目为的是保住 `swift test --package-path Packages/PlaybackCore` 这条入口。

## 解码能力只能问 VideoToolbox

PlaybackCore 判定一个编码"可渲染"，靠的是它的四字符码能否映射到已知的 `CMVideoCodecType`——那是一次**映射检查，不是能力检查**。设备上没有解码器的编码因此照样到达渲染器，并在那里失败成一扇静默的黑窗。

区分"设备没有解码器"与"渲染路径不收这个编码"的方法：

- **采样缓冲渲染器接受每一个 ProRes 样本，然后报 `readyWithDecodeFailures` 与 "Cannot Decode"**。这句话两种情况都说得通，所以它不能作判据。`AVAssetReader` 两者都不是，它的失败把界限落在设备本身。
- **`VTDecompressionSessionCreate` 的状态码才是答案**：从未找到解码器报 `kVTCouldNotFindVideoDecoderErr`（六种 ProRes 全部如此），找到了但拒绝这份描述报别的码。
- **HEVC 把参数集放在 extradata 里**，裸描述对两种 HEVC 都开不了会话、两个状态码都不是 `noErr`；但上面那条区分仍然成立。要求两种类型返回同一个状态码是错的标准——不同解码器描述"描述不完整"的方式本来就不同。
- **H.264 是对照组**：它是这里唯一一个样本描述在没有 extradata 时也完整的编码。一次连它都开不了会话的运行，测到的是别的东西，不是解码器可用性。
- **矩阵用例不断言任何一侧**，它把整份答案记下来，因为有用的是模拟器运行与真机运行之间的差；一个把某一侧答案写死的用例产生不出这个差。报告落在 app 容器里的 `video-decoder-matrix.tsv`。
- 被探测的轴是 `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c` 的 `codec_type()`——它是决定什么能到达渲染器的唯一一处；被它映射到 0 的编码过不了 `compressed_codec_is_renderable`，根本到不了 VideoToolbox，探测它等于在测平台而不是测这个产品。

相关用例：`Tests/EnchronApp/VideoDecoderAvailabilityTests.swift` 与 `Tests/EnchronApp/ProResDecodeOnDeviceTests.swift`（真机 lane 专有；模拟器上按构造失败）。

## AVFoundation 打开无扩展名来源要靠 provider 自报的 MIME

AVFoundation 判断一个 HTTP 或本地文件资源属于什么容器，靠的是 URL 的路径扩展名或显式声明的 MIME；两者都缺时 `AVURLAsset` 打开失败于 `AVErrorFileFormatNotRecognized`（-11828，底层 -12847，"Cannot Open"），即使字节本身合法、Range 请求也答得正确。loopback 字节流服务器与 Emby 的媒体源名称都落在这个空档：Emby 的 `MediaSources[].Name` 本就没有扩展名，服务器对每个响应发送的 `Content-Type` 是固定的 `application/octet-stream`。

`VideoSampleProvider` 在决定要不要向 AVFoundation 求证格式之前，已经从 FFmpeg 读出了容器判定——`MediaSourceInformation.containerSupportsSourceFormatDescription`，对应 demuxer 名 `mov,mp4,m4a,3gp,3g2,mj2`。构造 `AVURLAsset` 时把这个判定转成 `AVURLAssetOverrideMIMETypeKey: "video/mp4"`，覆盖掉 URL 扩展名与服务器 Content-Type 两条信号——这是唯一同时知道 FFmpeg 判定、又要把结果交给 AVFoundation 的地方，不需要 loopback 服务器或 Emby 桥接层就文件名达成任何约定。断言见 `avFoundationAssetOptionsDeclareVideoMP4OnlyForTheMovFamily`。

Apple Immersive Video 的分类查询是建议性的，不是权威判定。它与旁边的 `uniqueSourceVideoFormatDescription` 面对同一个 AVFoundation 资源，原先却不对称：后者的探测失败被吞掉，前者直接上抛。任何一次探测失败——包括上面这类原本打不开的资源，或者一次瞬时的网络故障——因此都会让整次 open 变成 "Cannot Open"，即使 FFmpeg 一侧已经成功建立了压缩样本读取。现在两者对齐：探测错误一律当作"没有沉浸式元数据"处理，仅当来源已知是 MVHEVC 时才上抛。集成断言见 `extensionlessHTTPMovFamilySourceOpensThroughTheRealVideoProvider`（无扩展名 loopback 服务器 + 真实 provider 路径）。

## 帧步进是一次 seek，遇到进行中的 seek 要被取代而不是被拒绝

`PlaybackCoreController.stepFrames(by:)`（`stepFrame(_:)` 是它 delta 为 ±1 的特化）内部把请求的位置换算成 `base + delta × frameSeconds` 后交给同一个 `seek(to:after:)`；它与滚动条拖动、快进快退共享同一条 `activeSeekTask` 生成号机制。因此一次帧步进击中正在进行的 seek 时，正确的行为与拖动命中正在进行的 seek 完全一致——取消旧任务、把新目标接管过去，旧调用方收到 `.seekSuperseded`——而不是让 `rejectIfSeekIsInProgress()` 拦下来抛 `operationInProgress(.seek)`。两个方向的 delta 都折成一次 `seek(to:after:.pause)`（原因见"逐帧步进两个方向都是 seek"）；delta 为 0 不动。断言见 `stepFramesByDeltaLandsMultipleFrameDurationsFromBase`（落点相对 base 的帧数倍数正确）与 `frameStepDuringInFlightSeekSupersedesInsteadOfRejecting`（命中飞行中 seek 时不再抛 `operationInProgress`，早先那次 seek 以 `.seekSuperseded` 收场）。

单帧步进按钮被连续敲击时，`PlaybackRuntime.frameStep` 在 runtime 层把这些请求合并：敲击只把 ±1 累加进一个待处理增量，若已有一个步进任务在飞行就直接返回；那个任务耗尽当前累积的增量、落地后再检查增量是否又变为非零，非零则继续消耗，直至归零才清空任务槽；任务因错误或被取代而提前退出时，积压的增量随之作废，不会叠加到下一次敲击上；准备新会话与停止播放时任务被取消、代数递增，旧任务的收尾不会碰新任务的槽位。一串敲击因此折叠成远少于敲击次数的实际步进，而不是敲一下发起一次要等到 5 秒审计超时的全量拆卸重建。集成断言见 `testRapidFrameStepBurstCoalescesIntoOneFurtherStepAndNeverAlerts`（`Tests/EnchronApp/PlaybackSourceAndAudioSessionTests.swift`）：五次连击只产生两次落地，会话真实位置恰好前进五帧，全程不产生 `userVisibleIssue`。`replay()` 内部的 seek 现在也像滚动条与快进快退一样只忽略 `.seekSuperseded`，不再把它当成播放失败上报。

## 暂停中的 seek 停在覆盖目标的那一帧上，不停在解码越过目标的那一帧上

FFmpeg 的 seek 落到目标之前的关键帧，样本按解码顺序送进渲染器；时间线先锚在关键帧的 PTS（`session.firstSample … timelineStart=关键帧`），等解码越过目标再把时间线停到最终位置。暂停中的 seek 原来用两条信号决定"越过了"：接受样本的 DTS ≥ 目标，以及当前样本的 PTS ≥ 目标；最终位置取的是当前样本的 PTS。两条都靠不住：B 帧流里第一个 PTS 越过目标的样本是一枚 P 帧，它比覆盖目标的 B 帧先到、PTS 却晚好几帧（模拟器实测：目标 19.3537 s，时间线停在 19.521 s，后退一帧表现为前进四帧）；而桥接层给 Matroska 样本的 DTS 并不单调（P 帧的 DTS 等于自己的 PTS），按 DTS 判"越过"会提前触发，时间线停回关键帧（目标 18.652 s 停在 18.021 s）。

现在的规则只看呈现时间：会话在 preroll 期间记下**最大的 PTS ≤ 目标**（`prerollCoveringPresentationTime`），并数**PTS 大于目标的已接受帧数**（`prerollFramesBeyondTarget`），当这个数**超过重排深度**（取流的 `videoReorderDepth` 与 2 的较大值）时判定覆盖帧已经齐了，时间线停在覆盖帧的 PTS 上；流在此之前结束也算齐。依据是解码顺序里一帧最多被"重排深度"个 PTS 更大的帧抢先，所以第 重排深度 + 1 个更晚的帧到达时，所有 PTS ≤ 目标的帧都已经到齐。按 PTS 距离判（最大已接受 PTS ≥ 目标 + (重排深度 + 1) × 帧长）不行：覆盖帧的参考帧恰好在它前面 3 帧的 PTS 上，却只比它早一个解码位到达，距离条件在参考帧到达那一刻就满足，覆盖帧还没来（模拟器实测：从 10.254 s 前进一帧目标 10.2874 s，参考帧 10.388 s 先于覆盖帧 10.288 s 到达，时间线停回 10.254 s，此后每次前进都卡在那里）。只有整段流都在目标之后（目标早于首帧）才停在最早接受的那一帧。"覆盖"允许 1 ms 的容差：控制器按标称帧率算出的目标（当前帧 PTS − 1/30）与 Matroska 毫秒量化的 PTS 会差零点几毫秒，不给容差就会错选上一帧（模拟器实测：从 18.521 s 后退一帧目标 18.48767 s，帧 PTS 18.488 s，无容差落到 18.454 s）。停在帧的 PTS 而不是请求的目标本身，是为了让暂停中的位置永远落在帧边界：后退一帧的目标（当前帧 PTS − 帧长）被上一帧覆盖，停在上一帧的 PTS；再前进一帧的目标是上一帧 PTS + 帧长，被原来那帧覆盖（毫秒量化留下的零点几毫秒由那 1 ms 容差吸收），恰好回到原来那帧。断言见 `pausedSeekLandsOnTheFrameThatCoversTheTarget`（P 帧的 DTS 与 PTS 相同、先于它的 B 帧到达；红：1.05 s 的暂停 seek 停在 1.2 s → 绿：停在覆盖它的 1.0333 s 帧），以及 `pausedSeekWaitsForTheCoveringFrameBehindItsLaterReferences`（B 金字塔顺序 0 4 2 1 3 8 6 5 7 …，目标比第 5 帧低 0.6 ms；红：停在第 4 帧 → 绿：停在第 5 帧）。

preroll 期间会话报出的位置是请求的目标，不是锚点。时间线在第一个样本到达时锚在关键帧 PTS 并立刻发布诊断，约 100 ms 后才停到最终位置；`diagnostics.currentSeconds` 若照抄时钟，UI 的进度条、时间轴与时间字段就会经历"目标 → 关键帧 → 落点"的跳变（模拟器实测：每次 seek 的心跳先报 10.021 s 再报 10.187 s）。现在 `publishDiagnostics` 在 `isPrerolling`、或时间线已拆掉尚未重新锚定（`hasStartedTimeline == false`，这段窗口里时钟读数是 0）时报 `requestedTimelineStart`，激活后才跟随时钟；调试快照里的 `rendererState.currentTimeSeconds` 与心跳的 `timeSeconds` 仍是时钟本身。runtime 在 seek 或帧步进飞行期间同样只发布请求的位置（seek 报目标，帧步进报当前位置 ± 帧长，连击逐次累加），操作结束且没有别的 seek 或步进在飞行时再回到诊断报出的落点；这条路径覆盖程序化 seek 与逐帧步进（面板没在拖，`displayProgress` 一路走 `live`）。断言见 `prerollReportsTheSeekTargetNotTheKeyframeAnchor`（暂停 seek 期间报出的每个位置都不低于覆盖帧）与 `testSeekAndFrameStepPublishTheRequestedPositionUntilTheyLand`（`Tests/EnchronApp/PlaybackSourceAndAudioSessionTests.swift`：seek 与后退一帧在调用返回时就已发布请求的位置，之后发布的每个位置都不低于落点）。

进度条拖动松手另有一处 UI 交接，runtime 的位置保持覆盖不到：拖动中面板显示本地 `progress`，松手把 `isDragging` 置回 false 的当帧，`displayProgress` 就丢掉刚提交的本地目标改用 `live?.progress`，而 `live` 是上一轮 SwiftUI 快照，还停在拖动前的位置，一帧后才更新到目标——进度条因此向后弹一下再跳回（模拟器探针实测：从 0.449 拖到 0.502 松手，`displayProgress` 先回 0.4493 再到 0.5023）。面板保留一层已提交目标的保持（`pendingSeekTarget`）：松手时连同 `progress` 一起武装，`displayProgress` 在不拖动时优先显示它，直到 `live` 报出的位置落进目标附近再释放。释放判据按**秒**的绝对容差（0.25 s），不按时长的百分比——百分比在 30 秒的片子上是 0.6 秒、在两小时的电影上是 144 秒，同一个手势在长短片上表现天差地别；覆盖帧落点与请求目标最多差一帧，远在 0.25 s 内。逐帧步进不武装这层（走 runtime 的位置保持）。断言见 `committedTargetHoldsUntilTheReportedPositionCatchesUp`（`Tests/PlaybackPresentationTests/PlaybackPresentationStateTests.swift`：松手当帧显示目标而非旧的 live；释放判据随时长缩放，一帧漂移在两小时片上仍算到达）。

## seek 到结尾以"播放完毕"收场，不报错

拖到进度条最右端时 runtime 把目标夹到时长，核心按 |目标 − 时长| ≤ 1/60000 s 直接判"到头"（`control.seek.completedAtEnd`，不重开 provider）。这条判定原来几乎打不中：runtime 以 600 timescale 传目标，一次量化就差 0.83 ms，30.021 s 的片子拖到头传进来的是 30.02 s。落到普通路径后等待循环有三个洞（2026-09-06 模拟器实测，事件日志）：目标 30.02 s，视频送到最大 PTS 29.988 s 后输入结束，最后解码的是 B 帧 29.954 s，音频送到 30.016 s。"到达"只看最后解码的那枚样本（B 帧流里它不是 PTS 最大的一枚）；按最大 PTS 判到达的分支在要求音频对齐时被关掉；"到头"分支要求最后一帧的呈现末端严格小于目标（30.021 ≥ 30.02，不成立）且只会抛错。三条都不成立，循环等到 5 s 审计超时，以 `seekTimedOut` 报出 "Playback Error"。

现在：`clampedSeekTime` 以 60_000 timescale 量化，夹到时长的目标与时长相等，直接判到头。拖到最右端时 runtime 判出的 `.ended` 意图现在原样传到核心（`PlaybackAfterSeekBehavior.end` → `session.seek(endsPlayback:)`），不再靠数值巧合：以前驱动层把它折成 `.pause`，核心只能拿目标与时长比对，台上拖到头传进来的是 30.02 s（片长 30.021 s，落在最后一帧区间内），结果停在最后一帧暂停而不是播放完毕。重开 provider 之后，一旦本 epoch 的视频输入结束，等待循环立即裁决：有已接受的帧起于目标或之后、或最后一帧的呈现末端到达目标 → seek 完成（`control.seek.completedAtInputEnd`；音频若也已结束就不再等它）；否则 → 以到头收场（时间线停在时长上，`.ended(.seekToEnd)`，并把 `didReportEnd` 置位，免得随后的自然结束判定再报一次 `.ended(.naturalCompletion)`）。播放中的 seek 还有一种收场：输入在时间线激活之前就结束、且没有任何已接受的帧起于目标之后（目标落在最后一帧里或之后），激活永远不会发生，seek 却已"完成"，时间线停着而生命周期停在 playing（模拟器实测：播放中 seek 到 30.005 s 后卡在 Playing@30.005）。`finishDelivery` 在这种情况下直接结束播放（`timeline.ended reason=inputEndedBeforeActivation`，报 `.ended(.seekToEnd)`），到头的两条路径共用 `didReportEnd` 的一次性认领，谁先到谁报，另一条只收尾不再重复报。原来的 `seekTargetUnavailable` 错误删除——用户把进度条拖过最后一帧得到的是"播放完毕"，不是报错。断言见 `seekWithTheEndIntentEndsPlaybackWithoutMatchingTheDuration`（`.end` 意图不重开 provider、不比对时长，直接 `.ended(.seekToEnd)`）、`seekPastTheDeliveredVideoEndsPlaybackInsteadOfFailing`（输入在目标前结束 → ended 而非抛错，含没有任何样本的流）、`seekInsideTheLastFrameCompletesWhenTheInputEnds`（暂停中、B 帧最后解码、目标落在最后一帧区间内 → 立即完成并停在最后一帧）、`playingSeekIntoTheLastFrameEndsWhenTheInputEnds`（播放中同样的目标 → 输入结束时时间线尚未激活，以到头收场而不是卡在 Playing）与 `testSeekingToTheEndEndsPlaybackWhilePlayingAndWhilePaused`（`Tests/EnchronApp/PlaybackSourceAndAudioSessionTests.swift`：真实 30.021 s 夹具，播放中拖到时长、暂停中拖到时长前 0.5 ms 都进入 ended，不产生 `userVisibleIssue`）。
