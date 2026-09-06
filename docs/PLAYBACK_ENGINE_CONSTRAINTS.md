# 播放引擎的外部约束与实测常数

本文记录 `Packages/PlaybackCore` 里那些**无法从代码本身读出**的事实：平台框架的实际行为、实测数字的出处、以及同类播放器在同一问题上的做法。可以由代码或断言表达的部分不写在这里——它们的真相源是 `Packages/PlaybackCore/Sources` 与 `Packages/PlaybackCore/Tests`，本文只在必要处指名对应的测试。

## 渲染器超前预算的单位

`RendererLeadBudget` 按**解码帧数与解码字节**计量交付循环可以跑在时间线前面多远，不按媒体秒。

媒体秒是错的单位：一次 seek 等的是渲染器 flush，而 flush 的开销跟随排队帧的数量与单帧大小，不跟随它们的时长。2026-08-22 在 Vision Pro 上对 8192x4096、59.94 fps 的流做的扫描，测得 flush 时间按 frames^1.8 增长；两条流持有同样多的"秒"，为一次 seek 付出的代价可以相差两个数量级。

成熟实现没有一个在解码侧按秒设界：VLC 按 field count 对齐编码器声明的 reorder depth 给 VideoToolbox 配速，Chromium 把并发解码请求固定封在四个，mpv 的可选解码队列在触及它那个两秒上限之前，先被帧数或字节数触发。

预算的三个界与它们的理由：

| 界 | 含义 |
|---|---|
| `schedulingSlackFrames` | 交付循环可以超出编码器 reorder 延迟的帧数。一帧是渲染器正在显示的，另一帧覆盖 provider read——它与交付跑在同一个任务上，因此整段读取时间里交付是停住的。只留一帧时，任何一次读取超过一个帧周期渲染器就跑空，而远程来源日常如此。 |
| `maximumFrames` | 解码字节不再是约束之后渲染器仍可持有的帧数上限。小帧单帧便宜，但每帧仍有拆除成本，所以字节数远低于上限的流也不允许无限排队。 |
| `maximumDecodedBytes` | 解码字节上限，预算随分辨率缩放靠的就是它。取 200 MB 时，8-bit 4:2:0 的 8192x4096 单帧 50.3 MB，该流落在四帧附近——与 VLC、Chromium 对大画幅收敛到的深度一致；1280x720 单帧 1.4 MB，仍停在帧数上限。 |

reorder floor 优先于两个上限：队列比编码器自身的重排还浅会直接饿死解码器。8K 十比特的极端下，一帧 100 MB，字节上限要的比编码器重排需要的还少，由 floor 决定——那条流每次 seek 付出的代价超过它的字节预算，这是"绝不饿死解码器"的明码标价。

断言在 `PlaybackCoreTests`：`theLeadBudgetSpendsDecodedBytesRatherThanMediaSeconds`、`theLeadBudgetNeverSitsBelowTheEncoderReorderDepth`。

## 交付滞后恢复的实测数字

`PlaybackBufferingPolicy` 的四个常数各有出处：

- `seekAudioLeadSeconds = 0.2`：起点是 mpv 的 0.2 秒音频输出缓冲。Vision Pro 上 TrueHD 按 0.1 秒一个缓冲到达，因此这个值恰好容纳两个缓冲。
- `deliveryLagRecoveryTriggerSeconds = 0.5`：2026-08-17 的 Vision Pro 基线在迟到 0.527–0.873 秒处恢复出有界交付；0.5 秒是当时止住无界滞后的触发点。
- `deliveryLagRecoveryLeadSeconds = 1.0`：起点是 mpv 的一秒欠载恢复参考。同一条 2026-08-17 基线显示，把目标放到五秒会在远程 4K HEVC + TrueHD 上造成 6.8–13.1 秒的停顿。
- `opportunisticAudioMaximumLeadSeconds`：音频仍按媒体秒设界。解码音频体积小、渲染器 flush 便宜，对视频帧错误的那个单位在这里是对的。

`audioPrerollTimeout` 与 `seekTargetCoordinationTimeout` 的五秒是 **provider 或渲染器故障的界，不是缓冲媒体的策略**；5 毫秒轮询让激活在该界内保持响应。二者同为五秒是历史巧合，分开命名以免与已删除的"五秒媒体储备"混淆。

恢复要求为什么被帧预算封顶：交付 gate 最多持有 `leadFrames` 个 presentation end 落在时间线之后的帧；跨越 `timelineTime` 的那一帧在它之后不足一帧就结束，所以这些帧能达到的最深 end 比 `leadFrames / nominalFrameRate` 少一帧。要求整段跨度，就是提出一个 gate 永远无法满足的条件。音频有自己按媒体秒的 gate，因此不受该封顶影响——否则恰好在读取最慢的那些流上放弃实测得到的恢复储备。断言见 `deliveryLagRecoveryNeverAsksForMoreThanTheGateAdmits`。

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
- **内嵌字幕只能顺着容器读出来，而共享来源只跟着播放头走。** MKV 里的字幕包与视频包交错，没有独立索引；`FFmpegSubtitleProvider` 在共享 demux 来源上取字幕时，来源的读线程受 150 MB 前向预算与已订阅队列的目标时长约束，停在播放头前方约九十秒处，只随视频消费前进。因此共享来源上的字幕渲染器**不得在创建时读到流末尾**——那意味着按播放速度等到片尾，而且构造过程持有 `FFmpegDemuxSession.operationLock`，同一把锁上的 seek 与 close 都会随之死等，下一次 open 又等 close。约束的落点：`PBSubtitleFrameRendererCreateWithDemuxSource` 只订阅并取走已排队的包，订阅随渲染器存续，`PBSubtitleFrameRendererIngestAvailablePackets` 在每次发布字幕时非阻塞地折入新到的包；seek 后来源会重读同样的包，渲染器按包身份去重，位图字幕按显示时间插入以保持顺序解码。`PBFFmpegDemuxSourceUnsubscribe` 会清空该流已排队的包，而小文件的共享读线程早已到 EOF，所以共享来源上的渲染器要按轨道在会话内保留（`FFmpegSubtitleProvider.sharedRenderers`），换轨不销毁旧渲染器，重选才拿得回它已持有的包。断言在 `PlaybackCoreTests`：`sharedSourceSubtitleRendererIngestsOnDemandInsteadOfScanningTheSource`、`sharedSourceSubtitleSelectionCommitsWhileVideoIsStillQueued`、`reselectingASubtitleTrackAfterTheSharedReaderEndedKeepsItsFrames`。
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
