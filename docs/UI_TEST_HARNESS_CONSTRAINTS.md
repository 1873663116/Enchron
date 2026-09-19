# UI 测试通道与 visionOS 自动化的约束

本文记录 `Tests/EnchronAppUI`、`Tests/EnchronApp` 与 App 侧测试通道里**无法从代码本身读出**的事实：XCUITest 在 visionOS 上的实际行为、可用的观察通道、以及若干时序容差的来由。旅程词汇、证据受理判据与设备保留清单归 `.agents/skills/vp-e2e/`，本文不重复它们，只记录测试代码自身依赖的平台行为。

## 观察通道

- **测试宿主的 stdout 既不进 xcodebuild 日志，也不进设备上的 result bundle**。app 容器进得去（经 devicectl），所以测量报告写进容器而不是打印出来。解码能力矩阵就落在容器里的 `video-decoder-matrix.tsv`。
- **`XCUIScreen.main` 在当前 visionOS 构建上返回 1×1 图像**，读起来像一张黑帧而不是一次抓取失败。application element 仍然能抓，所以退化的屏幕图像要回退到它。
- **模拟器截图 lane 没有点进模拟器的通道**，想看的那一屏必须在启动时就可达；启动参数因此是到达某一屏的唯一途径。
- **探针日志 192 KB，Dock 里曾几十秒就把因果链冲掉**（2026-09-08 真机：docked 的 `settlement` 每秒约 10 行、每行 1.5 KB，选集失败的错误类别与音频重开的触发点都只剩证据行）。原因是结算签名没把淡入期间每帧变化的 `surfaceOpacity` 排除，两侧宿主各维护一份排除列表且沉浸侧漏了它；现在两侧共用 `PlaybackSettlementProbeSignature`。压缩策略改为：证据超过压缩目标时按最新保留（LRU）并置 `evidenceOverflowed`，不再整本清空；诊断行在证据之外保有 `compactionTarget / 4` 的保底额度。渲染器所有权（`rendererOwnership.*`）、离场实体释放、空间拓扑写入、attachment 放置、`conversionFailed` 都改为证据级，真机回捞时这些跃迁必在。
- **应答里的元素读数取两次，因为被作用的那个元素在应答写出来之前就可能已经不在层级里了**。`matchedElement` 是动作之前那一次读数，`elementAfterAction` 是动作之后那一次，元素离开层级时后者为 null。`snapshot` 只读不改，它的 `matchedElement` 直接用动作之后那一次，两次读的是同一个状态。这样一次点掉自己目标的 tap 仍然说得出它点的是什么。判定「该元素当时在不在」看 `matchedElement`，判定「这次动作把它变成了什么」看 `elementAfterAction`。`tapSequence` 按同一条规则处理路径，每一步在 `element.tap()` 之前把该步解析到的元素记进 `routeElements`，否则应答里只剩下标识符字符串，路径上每个元素的 label 无处可取。三个字段都由 `Scripts/verification/regression_operation_adapter.py` 消费。
- **`matchedElement.frame` 的单位是点，截图是像素，应答里没有任何字段记录屏幕的点尺寸**。帧直接来自 `XCUIElementSnapshot.frame`（`Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:765`），点到像素的比例因此推不出来，按 `matchedElement` 在截图上裁出对应区域这件事做不了。异常包逐条说明为什么产不出裁切图，而不是按猜的比例裁一块出来配上裁决文字——错的区域配上区域观察文字比不裁更糟。
- **真机上过渡过程只能靠 runner 内的连拍看清**。真机没有录屏通道，逐条 `snapshot` 每帧都要走一次 devicectl 往返（秒级）。runner 的 `screenshotBurst` 动词在进程内连拍：可选先 tap `--identifier`，随后按 `--count`／`--interval-milliseconds` 连续 `XCUIScreen.main.screenshot()` 写入 `responses/<id>-burst-<序号>-<epochMillis>.png`，响应的 `attachmentRelativePaths` 列出全部帧，控制端一次性拷回 `<output>/<id>-burst/`。真机上每帧约 100–300 ms，文件名里的毫秒时间戳用来与探针对齐。
- **模拟器的 `simctl io recordVideo` 可用与否取决于宿主授权，不是平台约束**。它和 `screencapture` 一样受 macOS 屏幕录制权限（TCC）管辖，未授权时以 -12204 失败；授权后正常出片（2026-09-10 本机实测：4 秒录得 3840×2160、h264、204 帧、3.4 秒时长的 `.mov`）。因此这条通道的可用性是每台机器各自的状态，换机器要重新确认，不能当作永久结论写进计划。`Scripts/verification/harness/recording.py` 的分段录屏建立在它之上。
- **分段录屏的形状由 simctl 的四条行为定死**，四条都在已启动的模拟器上核实过。`xcrun` 是 exec 而不是 fork，`Popen` 拿到的 pid 就是 simctl 本身，`SIGINT` 直达录制器；整个录制期间 simctl 只往 stderr 写 131 字节且都在起录时写完，因此不读 stderr 也不会把管道写满；输出文件在开始录制的瞬间就以 0 字节创建、结束时才写入内容，这是不必解析 stderr 的就绪信号；输出路径已存在时 simctl 直接拒绝（`NSPOSIXErrorDomain 17`，`cannot save recorded video output into a file that already exists`），断链的符号链接同样算存在，所以起录前的清理认 `lexists` 而不是 `exists`。
- **macOS 的 `TMPDIR` 是 per-user 而不是 per-process**。两台设备跑同一个 NodeID 的同一个 attempt 时（fan-out 下 attempt 编号按节点计，两台设备都从 1 开始）会写同一个路径：先起的那个的文件被后起的清理删掉，就绪信号被对方的 0 字节文件满足，两次停止都报成功而证据目录里只有一个文件。段因此落在 `TMPDIR/enchron-segments/<udid>/`，文件名仍然只绑定 NodeID 与 attempt。
- **ffmpeg 把相对路径中第一个 `/` 之前的冒号读成协议前缀**。在段所在目录下 `ffprobe node:playback:seek-1.mp4` 报 `Protocol not found`，`./node:playback:seek-1.mp4` 与绝对路径正常。NodeID 的形状是 `node:<slug>(:<slug>)*`（`Scripts/regression/core/ids.py`），而抽帧器的调用方是人和 Agent，谁都可能先 `cd` 进证据目录，所以段名把冒号编码成 `--` 而不是 `-`：slug 的形状不含连续连字符，`node:a-b:c` 与 `node:a:b-c` 因此不会塌缩到同一个名字。
- **`VISUAL_BLACK_YAVG` 与 `VISUAL_BLACK_YMAX`（`Scripts/verification/playback_mode_matrix.py:875-876`）是在 limited-range BT.601 亮度上量的**。那条路径把 RGB 交给 ffmpeg，ffmpeg 按 limited range 转换，纯黑在那里是 16 而不是 0，所以 18.0 是地板加 2，换算到全范围约等于 2.3；把 18.0 直接套在全范围亮度上会宽 7.7 倍，一帧正在播放、菜单完整展开的画面因此被判成全黑。纯标准库解码 PNG 的判读路径先把亮度换算进 limited range 再比（`Scripts/regression/tools/pixel_heuristics.py` 的 `LIMITED_RANGE_OFFSET` 与 `LIMITED_RANGE_SPAN`）。峰值上限 40.0 不是可选装饰：一帧几乎全黑但带一条纯白带的画面均值仍在门槛之下，只有峰值能挡住它。

- **window bar 的关闭按钮不在 app 的可访问性树里，runner 点不到**。DEBUG 测试通道的 `app-command --verb closeMainWindow` 对前台 `windowApplication` scene 调 `requestSceneSessionDestruction`，走与佩戴者关闭相同的 `UIScene.didDisconnectNotification`；探针里应依次出现 `testcmd closeMainWindow`、`mainWindowScene disconnected trigger=wearer`、`mainWindowScene closedByWearer stoppingPlayback`。窗口关掉后 app 没有前台 scene，播放一停就会被系统挂起，测试通道随之失联，验证结果只能从容器里的探针文件读；`Scripts/verification/wearer_close_probe.py` 按这个顺序驱动并出裁决。
- **渲染器预读只能在真机上量**。DEBUG 测试通道的 `app-command --verb setRendererLeadFrames --arg frames=N` 把 `RendererLeadBudget` 钉在 N 帧，不带 `frames` 回到爬坡；`seekNormalized --arg position=P` 按时长比例 seek。`Scripts/verification/renderer_lead_sweep.py` 按预算序列钉住、保持、seek，再把这段探针里的 `windowSettlement` 行归约成每个预算一格：显示计数速率、最小送帧领先、最大送帧间隔、footprint 与每次 seek 的冲刷时间；显示计数是采样值，只在同一台机器的预算之间比较。
- **慢速远程后端只能在应用内模拟**。真实网盘的高峰期无法按需复现，DEBUG 测试通道的 `app-command --verb setSourceReadDelay --arg ms=N` 让回环服务器在把每次读取转发给 WebDAV／SMB／Emby 来源之前先等 N 毫秒，不带 `ms` 清除；`Scripts/verification/source_read_delay.py` 是它的宿主。容器索引缓存命中的读取不经过这段延迟，所以已经打开过的条目会立刻打开、几秒后才停住。
- **精确时间轴由 scrubber 的双击打开**，合成的单次 tap 打不开它。runner 的 `doubleTap` 动词发出 `XCUIElement.doubleTap()`，`Tests/EnchronAppUI/Spatial/SpatialHandoffUITests.swift` 以它断言时间轴展开；`Scripts/verification/reachability_matrix.py` 的 `precision_timeline_scenario` 走同一条路径，在四个呈现上到达展开后的 `PlayerPanel-precision-timeline-back` 并按 `precisionTimeline.close` 探针判定。逐帧步进按钮不带 accessibility identifier，仍然只能走测试通道的 `frameStep`。
- **真机的进程表按可执行文件路径列出进程，bundle id 不出现在其中**。`…/Enchron.app/Enchron` 与 `…/EnchronAppUITests-Runner.app/…` 都含有 `Enchron`，所以 `Scripts/verification/interactive_visionpro_ui.py` 用这一个 marker 同时匹配 app 与 runner。
- **模拟器上 `launchctl list` 按 bundle id 标注 app，而不是按可执行文件路径**，同一次进程观察的 marker 集合因此随 transport 变化。`Scripts/verification/interactive_visionpro_ui.py` 在模拟器上要在路径 marker 之外再加上 app 与 runner 的 bundle id。
- **`devicectl device copy` 以目录为单位整体复制**，而 deferred 应答批次就是一个目录。`Scripts/verification/enchron_target.py` 的模拟器分支必须整树复制来对齐这一行为；只复制文件会把每一条批量应答留在模拟器容器里。
- **哪一台头显由环境变量指认，仓库里没有核对它们的机制**。`ENCHRON_TARGET_DEVICE` 选 xcodebuild destination，`ENCHRON_CORE_DEVICE` 选 `devicectl` 用的 CoreDevice，两者都经 `Scripts/verification/enchron_target.py` 读取。这两个值是否仍然指向在场的那台设备，仓库无从判断；一次跑通的真机运行是它们当时仍然正确的唯一证据。头显更换后以 `xcrun devicectl list devices` 为事实来源重新取值。
- **ffmpeg 把纯文本 demux 成 ANSI art 视频，并报出可信的时长与帧率**。暂存的 xcresult 把 runner 的 stdout 与附件放在一起，Staging 扫描会把两者一并递给探针，所以 `Scripts/verification/extract_visionpro_ui_recording.py` 不检查容器格式就会把 app 自己的日志当成录屏取回。
- **xcresult 里的录屏是 anamorphic 的：2732x2048 像素承载一幅 16:9 画面，且不带 aspect 元数据**，方形像素的查看器会把它纵向拉伸。`Scripts/verification/extract_visionpro_ui_recording.py` 抽帧时归一到 XCUIScreen 截图通道交付的同一 16:9 几何。
- **麦克风放在头显扬声器一小段距离外时，一次音调清晰可辨的采集落在 -55 dBFS 附近**，把静音阈值设在该电平会把真实采集报成静音。`Scripts/verification/journey_audio_probe.py` 取 -75 dBFS，低于仍然带 25 倍峰值的最安静一次采集；真正把音调与本底分开的是 `dominantPeakRatio`。
- **200 Hz 以下的房间噪声可以压过被测音调**，此时 band 内最响的 bin 指认的是房间而不是音轨。`Scripts/verification/journey_audio_probe.py` 因此把 fixture 的四个脉冲频率互相排序，而不取 band 内的全局最大值。
- **播放问题弹窗是系统场景，不在 app 自己的视图树里，截图与像素门都不把它当作失败**。弹窗在 `app.debugDescription` 的层级文本里以 `Alert` 子树出现，`Scripts/verification/interactive_visionpro_ui.py` 从每条应答的 `hierarchy` 解析出 `alerts`（标题、正文行、按钮标识符），任何读应答 JSON 的脚本或 agent 都能直接判定。runner 里多加一次 `app.alerts.allElementsBoundByIndex` 查询被否决：模拟器 relaunch 后那次查询把 runner 挂住超过 70 s（2026-09-06 探测段 `probe-main-window-browser` 连续两次 response-timeout），真机 lane 的 tap 均值也从 2 s 升到 9 s；`Scripts/verification/playback_mode_matrix.py` 的落点等待另读控制面 `error` 字段与探针 journal 的 `conversionFailed` 行，命中即判 `PRODUCT_ERROR`，落点正确也不放行。2026-09-06 的 Dock 返回失败就是弹窗被人眼看到、脚本按 tap 成功放行的案例。
- **播放窗口比模拟器抓得到的画面大，镜头又不能动，所以 chrome 摆在哪里在模拟器里看不见**——截图通道对控件位移这一类回归是瞎的，2026-09-10 之前它只能靠佩戴者在真机上用眼睛发现。帧树是唯一能看见它的通道：`app.debugDescription` 给每个元素带上 `{{x, y}, {w, h}}`，而这些坐标是窗口局部的——每个 `Window` 子树从自己的原点开一套新坐标系，ornament（`PlayerPanel-controls`）是与 `Window (Main)` 平级的独立 `Window`，所以包含判定只能对最近的 `Window` 祖先做，对场景容器做会错：2026-09-10 模拟器 docked 时场景容器仍报 1280×720，其中的 `Window (Main)` 已经是 360×315。`Scripts/verification/interactive_visionpro_ui.py` 的 `chrome_containment_violations` 按这条规则解析每一条应答，结果以 `chromeContainment` 挂在应答上，`operation:` 系列的 post-action 状态缺这个字段就拒收（`_post_action_state`，`Scripts/verification/regression_operation_adapter.py`）。判定只覆盖产品自己命名的元素：匿名的框架内部件自带帧，浏览器 tab bar 被隐藏后会塌成 0×0 并在窗口原点上方 10 pt 处留下一个 68×20 的残件（2026-09-10 模拟器），那是框架的摆放不是产品的。容差 0.5 pt——这条检查存在的位移都是几十 pt 量级（内容矩形 1278×844 撑在 905×1018 的窗口里）。一次控制器往返约 1 s，几何变更中间那一两帧的溢出抓不到，判定的是稳定下来之后的摆放。
- **ornament 从后台回来之后可能整个不出现在可访问性树里，屏幕上却在**。2026-09-10 模拟器：从播放返回浏览器后，四个 `Navigation-Ornament-tab-*`／`Emby-Navigation-Tab` 按钮连续四轮都不在 `app.debugDescription` 里，浏览内容（`FileBrowsing-FilesScreen`、侧栏、12 个格子）全在；佩戴者看屏幕确认 tab bar 是回来了。`6cce03fb` 与 `bc342b01` 表现一致，与产品改动无关。所以 ornament 的"在不在"不能用帧树判定，`chrome_containment_violations` 也只对树里有、却跑出窗口的元素说话——ornament 整个消失它不会报，也报不了。
- **控制面读不到就是沉浸式落点的签名**。沉浸式呈现清空主窗口，控制面随之消失，落点判定只能改读容器里的探针文件。见 `Scripts/verification/playback_open_sweep.py`。
- **docked 与 panorama 内可以驱动剧集切换，但走的是与 window 不同的一套标识符**。deck ornament（`PlaybackPanel.swift`）用 `PlayerPanel-menu-more`／`PlayerPanel-menu-episodes` 打开 More 菜单，window host（`WindowPlayerDeck.swift`）用 `PlayerUI-TopAction-more`／`PlayerUI-menu-episodes`；两者的剧集条目标识符都以 `{category}-{item.id}` 收尾，`item.id` 是运行期 UUID，无法预先寻址，只能改用 `operation:accessibility.activate@2` 的 `labels`（配 `labelsAfterIdentifiers: true`）按可见文本命中。`operation:accessibility.activate@2`／`accessibility.inspect@2`／`evidence.capture-frames@1` 的 `context` 允许值集合（`CONTEXTS`，`Scripts/verification/regression_operation_adapter.py`）本就包含 `docked` 与 `panorama`，因此可以在这两种呈现内选中菜单项、读 `PlayerUI-spatial-state`、并抓帧取像素证据。**Scenario 里每一次剧集切换之后都必须有 `evidence.capture-frames`**：2026-09-08 docked 内选 180_3D.mp4 黑屏有声，可访问性树与窗口控制面都照样通过，只有像素能拒绝它；`Scripts/rules/check_episode_switch_captures_frames.py` 对蓝图强制这条规则。
- **探针健康判据现在把 `compactionCount` 一并计入，不再只看 `evidenceOverflowed`**。App 侧 `probeStatus` 的 `ok` 字段只在字节上限溢出、`evidenceOverflowed` 或写失败时才置 false（`TestCommandChannel.swift` 的 `probeStatus` 分支），一次非零的 compaction 单独不会翻转它——但 compaction 说明 journal 在真正溢出之前已经在设置沉降噪声下丢数据，那次尝试的证据不可信。两处消费者都已改为拒绝非零 compaction：`operation:harness.assert-channels@2` 新增 `_require_healthy_probe_journal`（`Scripts/verification/regression_operation_adapter.py`），在 Scenario 的 operations 列表中作为不产出 obligation 的硬门槛，compaction 非零或 overflow 为真时直接抛错终止该次 attempt；`Scripts/verification/reachability_matrix.py` 的 `parse_probe_status_response` 把 `passed` 的判据从「compaction 计数存在即可」收紧为 `compaction_count == 0`。
- **结构化检查的产物要自带一行 `ENCHRON_ASSERTION` JSON**。退出码与 `--filter` 名字只说明进程跑完了，不说明它观测到什么，而判定生命周期、media session 身份与 seek 之后的视频位置要的是读数。`STRUCTURED_ASSERTION_CHECKS`（`Scripts/verification/regression_operation_adapter.py`）列出六项检查，`playback-core-network-resilience` 与五项 `audio-retirement-*`，每项跑一个 Swift 测试并绑定它的 artifact；`_evidence_structural_test_1` 在 stdout 里逐行找这个标记并解析进 `assertionPayloads`，这六项里任何一项不是恰好一行就抛错终止该次 attempt。发这行的测试助手按字段拼接字符串而不走编码器（`Packages/PlaybackCore/Tests/PlaybackCoreTests/PlaybackCoreTests.swift` 的 `expectRetiredAudioAllowsSeek`，与 `HTTPMediaSourceRangeTests.swift` 里网络韧性那条），因为每个值都是标识符、UUID 字符串、Bool 或有限 Double，不含需要转义的字符；缺席的视频样本打 `null`，不打无法解析的 infinity。新增字段要守住这条，否则那一行不再是合法 JSON，整次 attempt 被拒收。

- **Settings 里的菜单格子改的是持久化偏好，跑完必须恢复**。`reachability_matrix.py` 的 `settings_menu_scenario` 为了证明投递会给每个 Settings 菜单选一个非当前项（默认倍速选 0.5），这些值写进 `UserDefaults`（`PreferencesStore.swift`），真机上一直留到下一次人手改回；2026-09-08 佩戴者发现每次播放都是 0.5 倍速。现在每个格子在投递证明之后用 `selected_menu_item` 读到的原选项调 `selectMenuItem` 恢复，结果记在结果文档的 `settingsRestorations`。
- **`The runner did not answer tap within 30 seconds.` 不等于 tap 没落**。2026-09-12 真机上 AX 传输在播放中反复卡住，超时的 tap 有时延迟落到了目标上（`snapshot` 超时同理）。判动作是否生效要看控制面——探针里的 `lifecycle`、PTS 推进、`testcmd` 行——不能只凭 runner 回的错误文本。
- **探针日志的写入不经过 AX**。`Documents/surface-tap-probe.log` 的控制面行由 app 自己写，AX 卡死期间照常推进，经 `devicectl` 拷容器即可读——2026-09-12 的整轮内存采样就是在 AX 不通的窗口里由它完成的。

## XCUITest 与 visionOS 的场景

- **Application element 不属于任何一个 visionOS Scene**。对它合成事件会在 Scene 查找上失败，而这个失败会结束这个长驻测试方法并把 app 一起拆掉。正确做法是让那条命令失败，而不是把整个会话拖走。
- **Panorama 与 Dock 会有意关闭主窗口**。那个 Scene 离场期间不要读它的 accessibility value：元素可能在 `exists` 与 `value` 之间消失，XCTest 把这种情况报成 application failure 而不是"节点不存在"。同理，目标控制面一出现，提交转换就可能关掉来源窗口，从那一刻起以目标状态为准。
- **被遗弃的常驻会话会让 testmanagerd 把证据一直留在头显上直到测试返回**，所以空闲的会话必须自己结束。
- **`xcodebuild` 把 `TEST_RUNNER_ENCHRON_*` 去掉前缀转发进 runner 进程**。对一个不重启的常驻 runner 来说，这是调用方够到 app 环境变量的唯一路径。
- **沉浸空间关闭之后场景输入所有权会丢**，需要显式恢复，而不是靠重启 app——重启会把当前状态一起丢掉。
- **自动隐藏的 chrome 熬得过一次控制器往返，熬不过四次**，所以菜单序列必须落在同一条命令里。
- **`tapSequence` 先点 `label`，再按顺序点 `identifiers`**，所以一条以可见文本收尾的路径要用 `trailingLabel` 而不是 `label`。嵌套菜单的叶子行没有标识符，只能按 label 命中，而它要等上面几步标识符把子菜单打开之后才存在。`trailingLabel` 在 identifiers 全部点完之后再按 `label == %@` 找一次，把这一步留在同一条命令里；拆成第二条命令时菜单撑不到那时候。适配器一侧的入口是 `operation:accessibility.activate@2` 的 `labelsAfterIdentifiers: true`（`Scripts/verification/regression_operation_adapter.py:4279`），它要求恰好一个 label、至少一个 identifier，且 gesture 是 tap。
- **runner 对 stop 的反应是结束自己的测试，而不是写一条应答**，所以一次超时的 stop 应答不表示 stop 被忽略。等 `xcodebuild` 退出是唯一能区分两者的观察，那次退出也正是 result bundle 与录屏写完的时刻，`Scripts/verification/interactive_visionpro_ui.py` 的 halt 以它为准。
- **runner 在 XCTest 拆掉测试之前就应答 stop**，带录屏的会话把这段拆解时间用于把视频从头显上拉下来并写 result bundle。在此期间杀掉 `xcodebuild` 会留下一个没有 Info.plist 的 bundle 和一段没有 moov atom 的录像；没有录屏的会话远在这段时间之内就自己退出。`Scripts/verification/interactive_visionpro_ui.py` 的 `resultBundleWritten` 报告的是 xcodebuild 有没有自己退出。

## Harness 的失败模型与原语边界

- **超时不是判决，是取证触发器**。每个 runner 动作只有两种终态：带正向证据的成功，或带类型的失败。等待到期本身不说明产品坏了，只说明该去取证了，因此没有任何一条判定以"等够了"结束。

- **失败分两类，分类权分层**。产品失败（product）是有效证据，记录后继续；仪器故障（instrument）宣告后续观测不可信，终止当前段落并进入恢复。runner 报告它能观测到的失败；调用方库只补判 runner 自身死亡的情形——进程崩溃、JSON 不可解码、subprocess 超时——这些天然是仪器故障。产品失败以强类型值返回（`ProductFailure`），仪器故障以异常抛出（`InstrumentFault`）。两份 kind 清单在 `Scripts/verification/harness/failures.py:11-26`：`PRODUCT_KINDS` 两个，`INSTRUMENT_KINDS` 十个。`response-timeout` 属于仪器故障，由 runner 自己在应答死线到期时以 instrument 类发出。

- **人类层的入口条件只认四种超时 kind**：`transport-timeout`、`response-timeout`、`wait-expired`、`provisional-budget-expired`（`Scripts/regression/core/runview.py:112-119` 的 `HARNESS_TIMEOUT_KINDS`）。同一节点连续两次 attempt 都落在这四种之内才允许推迟给人。产品慢不在其中，产品慢是 `Violated`。

- **超时预算一律由测量导出，禁止手写字面量**。这条由 `Scripts/rules/harness_primitives_gate.py` 强制：它扫描 `Scripts/verification` 与 `Scripts/regression` 下的 Python，禁止出现 `subprocess`、`timeout=`、`time.sleep`、`time.monotonic`、`devicectl` 五个记号。豁免只有三类——`harness/` 包自身、`interactive_visionpro_ui.py`、`enchron_target.py`——以及 `Config/harness_primitives_allowlist.json` 里逐条列出的既有违例文件。该清单当前 29 条，每完成一次迁移删一行，清空后这道门即为无例外强制。清单本身就是迁移进度表，不是永久豁免。

- **`harness/` 包内不写注释**。14 个 Python 文件当前注释行为零。无法用代码表达的约束写进本文，断言信息与日志字符串承担行内文档职责。这与 `Scripts/rules/verify_product_source_comments.py` 对全仓 Swift 与 Python 的要求是同一条规则，此处记录的是它对 harness 的具体含义：读者要找"为什么"，只能来本文，不要指望源文件。

## 预算与合成输入的实测常数

2026-09-02 在模拟器与真机两条 lane 上实测得出，证据在当轮 reachability 运行的 raw 目录里：

- **XCUITest 的 `tap()` 在合成事件前等待 app 静默，等待上限约 60 秒**。导入媒体后的缩略图与库落盘工作让 app 长时间不静默，所以任何由空闲期样本推出的 p95 预算都会结构性地卡在这个窗口里、把一次正常的慢 tap 杀成 transport-timeout。合成输入类动词的预算地板由 `provisional_budgets.json` 的 `floorSeconds` 承载（当前 75 秒），高于该上限。
- **样本不足 5 条时等待动词的临时预算取 60 秒上限，而不是猜测值**。`identifier-appearance`／`any-identifier-appearance`／`identifier-absence`／`identifier-value`／`probe-needle`／`presentation-settle` 曾是 8–45 秒的猜测，落在 tap 静默窗口之内，一次正常的慢出现会被杀成 wait-expired；上限 60 秒与 tap 的静默等待对齐，元素真的不出现时仍然以上限失败。`Budget.provenance` 里以 `provisional ceiling 60s` 标出未实测的上限，与合成输入等非等待动词的 `provisional <n>s` 猜测区分。
- **提交凭据的场景只能在真机 lane 跑**。模拟器里的 app 对 `Mac-mini.local:445` 报 Server unreachable，而宿主上 `nc` 能连通该端口；连接成功后系统的 Save-Password 面板在真机上能按 label 点掉，在模拟器上按钮出现在 `debugDescription` 里却查询不到（2026-09-06 `probe-main-window-browser` 段）。`harness/scenario_lanes.py` 把代码里能到达 `FileBrowsing-SourceConnection-*-connect` 字面量的场景划到真机，与打开播放的场景同一规则。侧栏删除只在有可删远程源时出现在调试菜单里，所以 `source-sidebar` 场景在删除一步之前自己连一个 WebDAV 源，并因此落在真机 lane。
- **视图模式由控件自述**。`FileBrowsing-FilesScreen-viewMode` 的 accessibility value 为 `grid` 或 `list`，`reachability_matrix.require_library_grid_mode` 以它为准；控件不在层级里时才退回按卡片、列表容器与空态（`FileBrowsing-FilesScreen-emptyState`，空文件夹或远端列举为空时都会显示）推断。2026-09-03 的 fail-closed 版本只看卡片，在新建文件夹后一进去就报错；空态与列举失败在内容层面无法区分，所以推断只是退路。
- **`reachability_matrix.py` 不带 `--emby-credentials` 时视为已登录并跳过 Emby 场景**，13 个 Emby cell 因此静默变成 unmeasured。参数默认指向 `Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json`（存在时）；该文件不入版本控制，没有它时 `ensure_emby_sign_in` 记一条 `embySignIn` 拒绝事件并给连接 cell 写明理由，Emby 场景以可见的失败收场而不是静默跳过。
- **`run_verification.py` 的 Tree hygiene 层要求整轮运行不改动受版本控制的文件**。此前 `test_reachability_matrix.py` 与 `test_seed_source_connection.py` 用默认 `BudgetProvider()` 把 wait 样本写进 `controller_timings.*.json`，预推送门每跑一次就让工作树偏离冻结摘要，之后所有冻结会话在 ensure-session 被拒。门把 `ENCHRON_TIMINGS_DIRECTORY` 指向本次运行目录，`BudgetProvider` 与 `interactive_visionpro_ui.py` 的默认 timings 目录都跟随它，门内任何测试或工具写的样本都落在运行目录里。
- **段尾整树拷贝 `Documents/test-responses` 不能共用探针小文件的 `probe-copy` 预算**。探针文件的实测样本把预算压到 5 s，而一个 800 步的真机段在段尾要一次拷回全部延迟应答，2026-09-06 window／portal／docked 三段因此在最后一步 transport-timeout、整段证据作废。批量应答拷贝走自己的 verb `app-responses-copy`（临时预算 300 s，下限 120 s），样本按 verb 分开累积。
- **冻结运行的等待样本落在当次输出目录的 `timing-samples.jsonl`**，每行一个 `{"verb", "lane", "seconds", "censored", "at"}`，`results.json` 以 `timingSamples: {"path", "count"}` 指认它。冻结运行不写 `controller_timings.<lane>.json`（受版本控制，写它会破坏冻结），样本归属由构造 `BudgetProvider` 的一方注入输出目录；非冻结运行仍直接写 `controller_timings.<lane>.json`。
- **冻结样本由 `Scripts/verification/fold_timing_samples.py` 按 lane 折回 `controller_timings.<lane>.json`**，按 `(verb, at)` 去重、每动词保留最近 `SAMPLE_LIMIT`（40）条。同一输入跑两次第二次无改动；某动词折入 5 条以上后 `budget()` 即按 p95 × 1.5 给出实测预算，不再走临时上限。
- **runner 的应答等待默认 30 秒**（`--timeout-seconds`），必须由调用方随预算下发，否则预算高于 30 秒的调用会先撞 runner 自己的死线，报出的 kind 是 `response-timeout` 而不是 `transport-timeout`。
- **模拟器 lane 打开本地媒体的合成 tap 会吊死 app 主线程**，而不是无害失败；这是"打开本地媒体必须经真实点击"（vp-e2e simulator.md）的更强形式。分段的 lane 跟随场景：`reachability_matrix.SCENARIO_LANES` 从 harness 源码静态推导出每个场景是否会经由 `MediaLibrary-grid-video-*`／`FileBrowsing-grid-video-*`／`Emby-Detail-Resume|PlayFromBeginning` 打开播放，会打开的场景与所有播放呈现上下文由 device lane 分段驱动，浏览面其余场景归 `probe-main-window-browser`（simulator）。分段计划中 lane 与场景不一致、进程 `ENCHRON_TARGET_DEVICE` 与分段 lane 不一致，都在启动前拒绝；模拟器 lane 上仍打到打开播放的 identifier 时，`tap()` 抛 instrument fault `playback-open-on-simulator-lane`，该段以 `channel-continuity-failed` 结束而不是等待 6 分钟超时。
- **无人佩戴的真机上，场景 phase 事件跨场景销毁不触发**：主窗口在播放期间被撤销再重开后，其 `scenePhase` 直接继承 active 而没有 background→active 转换。任何"等到 active 再行动"的门槛必须以布防后的新转换为准，否则会立即放行。
- **撤销一个窗口可能把整个 app 送进 background 并被系统挂起**（进程存活、命令通道与 AX 全部无响应），即便另一个窗口刚刚 appeared。播放→主窗交还因此把撤销延迟到主窗布防后的下一次 active 转换；等不到就保留双窗，绝不冒挂起风险。
- **段间复用常驻 runner 省去每段 `ensure-session` 的 115–286 秒建会话与 30–56 秒 `halt`，四段合计 10–20 分钟（device lane 关键路径约 57 分钟的 20–35%）**，段证据对齐由 runner `sessionID`（`ready.json`）改为每段新建的 `evidenceSession`（`evidenceSession=<uuid>`，`reachability evidence session=<uuid>`）。
- **模拟器 lane 的 `ensure-session` 约 24 秒到 `stage: ready`**，与真机 lane 每段 115–286 秒的建会话不是一个量级。判据是返回的 stage 而不是耗时；`halt` 返回空 `remaining` 才算停净。
- **一次普通命令往返在设备繁忙时的实测中位数是 2.6 秒**，所以 5 秒的 stop 应答死线会在一个只是正在播放的会话上过期，并让 halt 整个跳过 graceful 路径。`Scripts/verification/interactive_visionpro_ui.py` 取 30 秒，这条死线只有在 runner 真的不应答时才会走完。

## xcodebuild 的测试选择与执行计数

- **XCTest reporter 的执行计数是嵌套的**：每个 bundle 打印自己的总数，外层的 `Selected tests` 或 `All tests` suite 再打印聚合值。取最大值得到的就是那个聚合值，求和会把内层 suite 数两遍。`Scripts/verification/xcodebuild_test_selection.py` 按这条读执行数。
- **前置条件缺失的 suite 把计数打成 `Executed 6 tests, with 1 test skipped and 0 failures`**。跳过子句夹在计数与失败数之间，只按两段式写的模式会把整轮运行读成零，从而拦下一次本该通过的 suite。`Scripts/verification/xcodebuild_test_selection.py` 的 `XCTEST_EXECUTED` 模式与 `Scripts/rules/check_xcodebuild_test_selection.py` 的 xctest 腿依赖这条。
- **在 Swift Testing 报出总数之前被截断的运行也读作执行了零个测试**，与"过滤器什么都没选中"读数相同，但两者对下一步的指示不同。`Scripts/verification/xcodebuild_test_selection.py` 因此在两条同时成立时分别报出。
- **`-retry-tests-on-failure` 会在 SUCCEEDED 终局裁定旁边留下非零的失败计数**，出现在某个测试先失败一次随后通过时。终局裁定是运行是否通过的权威，所以 `Scripts/verification/xcodebuild_test_selection.py` 把这种失败计数作为提示报出，不当作矛盾。
- **一个 `-only-testing:` 值选不中任何测试时，最常见的原因是 Swift Testing 函数漏写了括号**，其余原因少得多。`Scripts/verification/xcodebuild_test_selection.py` 因此把加括号的形式作为修复给出，而不是并列几种猜测。
- **保留下来的枚举 fixture 里，插进标识符中间的那段 xcodebuild 进度输出是六行**（`Tests/Fixtures/xcodebuild-test-selection/test-enumeration-salvaged.json`）。`Scripts/verification/xcodebuild_test_selection.py` 的 `SALVAGE_LOOKAHEAD_LINES`（40 行）以此为界，超出这个量级属于另一类损坏，应当报出而不是猜。
- **没有任何捕获到的日志既选中六个测试又只执行其中一部分**，所以把 shortfall 规则压上负载的那一种形状由 `Scripts/rules/check_xcodebuild_test_selection.py` 从真实运行的日志构造，做法与 `Scripts/rules/check_dolby_vision_premises.py` 混流出样本树里不存在的容器相同。

## AX 标识符在 visionOS 上丢失的地方

- **`.alert` 里的 `TextField` 丢掉 `.accessibilityIdentifier`**，而同一个 alert 的按钮保留。字段因此只剩 placeholder 这一个把手，输入动词要从标识符退回 label 谓词、再退回 placeholder，而不是让这个操作无法驱动。
- **`.alert` 的 `message` 里的 `Text` 丢掉 `.accessibilityIdentifier` 与 `accessibilityValue`**（模拟器 2026-09-06 实测：`PlayerUI-presentation-conversion-diagnostic` 读回空标识符、无 value），按钮保留。弹窗正文只能按 alert 标题与 label 匹配，诊断值要从探针 journal 的 `conversionFailed` 行读。
- **SwiftUI `Menu` 在真机 visionOS 上可能报 `isHittable == false`，却仍然接受语义 tap**。可观察的契约是"菜单可用 → 公共选项可用 → 设置标题变了"，`isHittable` 单独不足以否决这个系统控件。
- 系统 `Menu` 里只有 `Button` 行保留标识符、`Section` 会吞掉内部每一行的标识符——两条见 `docs/DESIGN_SYSTEM_CONSTRAINTS.md`。

## 时序容差的来由

- **seek 飞行期间 runtime 发布的位置是请求的目标**，落地后才跟随渲染器，而 `waitForState` 每 0.1 秒轮询一次，所以一个 Playing 快照可能比目标多走一次轮询。
- **在 tap 之前立刻读 accessibility 状态**。用更早那次连续性等待返回的播放值，会把一个 Playing 的相对 seek 目标按 UI 准备所花的时间整体平移。
- **谓词只钉 epoch**，否则后续的自然播放会把一个本来打错的传输目标变成通过的结果。
- **30 秒的 fixture 是有意的**：证完 Cancel 语义之后要倒回，让这次往返测的是活动会话替换，而不是与媒体的自然结束赛跑。
- **一次启动可能恢复任意滚动偏移**，所以要在库的开头归一化，再按它稳定的排序去搜索。
- **比一次轮询还短的片子会在被看到可见之前结束**。FATE 的 ProRes 向量只有 70 ms，这类结果记为未判定；停在 ready 或 playing 而屏幕上没有东西才是失败。见 `Scripts/verification/playback_open_sweep.py`。

## 控件自动隐藏窗口的覆盖

- **常驻 runner 以 300 s 的控件自动隐藏启动 app**。Preparation 不覆盖它时，任何"菜单打开时控件仍在"的读数都由 harness 保证，成对的 controls=hidden 判据永远不会触发。见 `Scripts/verification/regression_preparation_adapter.py`。
- **secondary-menu-pins-audio-controls 在 9000 ms settle 之后探测 controls=shown**，audio-only Preparation 因此把自动隐藏窗口压到 8 s。见 `Scripts/verification/regression_preparation_adapter.py`。
- **window-surface-controls-toggle-and-autohide 从三次 Device Hub 捏合读出 shown-hidden-shown**。一次捏合是一次 `device_hub_canvas.py` 往返加一次控制器快照，各需数秒；8 s 的空闲窗口会在两次捏合之间触发，25 s 覆盖整段序列，并且短于该 Scenario 收尾的 30000 ms 探测 settle（适配器上限）。见 `Scripts/verification/regression_preparation_adapter.py`。
- **audio-only 集合里的 FATE 片长在 0.107 s 到 11.9 s 之间**，撑不到 tap 之后三次控制器往返的那次控制面读数；181 s 的生成资产是集合里唯一能撑到的。见 `Scripts/rules/test_fixture_registry.py`。

## 可达性清单的字符串扫描

- **清单扫描每个源文件里的每一个字符串，而不是只扫 `.accessibilityIdentifier` 的实参**。只有这个宽度才抓得到在别处拼装、再由另一处修饰符施加的标识符。见 `Scripts/verification/generate_reachability_inventory.py`。
- **同样的宽度会捞进只向证据日志描述控件的字符串**。由这类字符串派生出的格子在屏幕上没有可驱动的对象，`NON_VIEW_IDENTIFIER_LITERALS` 因此逐条排除它们并写明每一条的理由。见 `Scripts/verification/generate_reachability_inventory.py`。

## DEBUG 选择通道呈现的是此刻能点到的项

- **通道给出的条目集合必须与菜单当前允许点的集合相同**。`DebugMenuSelectionItem` 没有禁用位，所以不可点的项以**不出现**表达：Files 的 manage 家族在浏览来源时返回空列表（按钮此时整颗灰显），`selectMultiple` 在媒体库没有条目时不出现（按钮此时 `.disabled`），排序键家族不列出当前层级回答不了的键（那一行此时 `.disabled`）。两边一旦分叉，自动化就能驱动一个佩戴者点不到的控件，用它取得的证据描述的是不存在的产品。
- **由此，一个家族返回空列表是合法结果，不是通道故障**。控制端遇到空列表要判定为“此屏此刻不提供这个家族”，而不是重试或报错。

## 状态复位的语义

App 侧测试通道的复位不是"删掉一切"：

- **TestMediaInbox 是 harness 拥有的暂存区，不是 app 状态**。在这里清掉它，等于强迫每个用例重新推一遍所有媒体文件。
- **内存中的媒体库必须最先清**：它在变更时与终止时都会把自己重新持久化，留着它就会把这次复位刚删掉的引用复活。
- **记住的服务器证书是 app 状态**，落在自己的前缀下，而产品没有"遗忘"入口；不清它，信任提示在第一次接受之后就再也不会出现。
- **已保存的远程来源是复位要删的状态**。`resetState` 经 `removeDataSource` 逐个移除 `savedDataSources`，凭据无共享时 Keychain 条目跟着删除；段结束时侧栏回到只有 Media Library。
- **复位必须报告它建立出来的状态**，只报删除数量会把下一个单元真正依赖的东西——库里现在有什么——藏起来。
- **视图模式偏好活过 relaunch**：`MediaLibraryUIState.viewMode` 落盘在 `enchron.mediaLibrary.uiPreferences` 里，relaunch 不清它。切过视图模式的场景必须在同一场景内把它切回 grid 并验证网格标识回到层级里；复位走 DEBUG 通道的 `setViewMode` 而不用合成 tap——该控件按落点半区选择模式，而 visionOS 对合成事件上报的落点不可靠，同一条 `coordinateTap` 在不同会话阶段会落到不同半区。`resetState` 删掉该 key 的同时把内存里的 viewMode 置回 grid。新建文件夹、打开文件夹、导航、多选链开头断言 grid 模式，不满足时以 `library-view-mode-not-grid` 失败，不得自适应到 list 行继续。
- **空间验收测试从隔离的播放状态开始，但同一个测试内部的进程重启必须保住它正在验证的格式**。新的 reset token 表示新测试，同一个 token 表示该测试内部的一次冷重启。

## 真机会话要先把设备叫醒

真机闲置一段时间后 `devicectl` 仍报 `connected`、仍能装并启动产品 app，但装 UI test runner 会以 `IXRemoteErrorDomain code 6`（Connection interrupted）失败，`ensure-session` 连续两次拿到 transport-timeout 与 runner-crashed。先用 `devicectl device process launch --terminate-existing` 启动一次产品 app，同一条段命令立刻跑通。`ensure_session` 因此在真机 lane 上先做一次 `wake-device`，事件记为 `wakeTargetDevice`。

**自动化之前必须预授权 world-sensing 与 hand-tracking**。RealityKit 的 RKSARProvider 在启动时请求这两项（Info.plist 键的硬需求与崩溃证据见 `docs/PLAYBACK_ENGINE_CONSTRAINTS.md`）；授权弹窗出现期间 AX 通道整段不应答，2026-09-12 真机上它把 tap 与 snapshot 双双打成超时，允许之后才恢复。

## xctrace 在 visionOS 真机上是不可靠通道，先验活再驱动

xctrace 与 devicectl 走的是**两条不同的设备通道**：devicectl 是控制面（CoreDevice 隧道上的小请求），xctrace 要在设备端拉起 `instruments.remoteserver` 并维持一条持续高带宽的 kdebug/trace 流。前者的 connected/online 状态**不代表**后者可用——2026-09-13 实测：devicectl 全程能装能控能拷文件，xctrace 同时段十几次录制全部在开录约 10 秒后以 `Device got disconnected` 中断，留下只有目录结构、0 行数据的空心 trace。

这两个故障都是 **Apple 官方论坛记录在案的已知问题，没有文档化规避手段**，重试、换参数、改命令形式都无意义：

- `Waiting for device to boot` 后超时（[Forums #694698](https://developer.apple.com/forums/thread/694698)）：Apple 工程师的答复是抓双侧 sysdiagnose 提 Feedback，重启可能缓解。
- 录制中途 `Device disconnected`（[Forums #652221](https://developer.apple.com/forums/thread/652221)）：设备端服务与 Instruments 版本的兼容性缺陷。

恢复手段只有设备侧：重启 Vision Pro 并**保持佩戴/亮屏**（摘下后省电路径会先挂起调试服务），或 Xcode → Devices 窗口重连配对。根治方案是 Developer Strap 有线连接——无线 localNetwork 隧道本身就是 Apple 公认的弱环节。

**驱动协议（录 trace 前必须执行）**：

1. `xctrace list devices` 确认设备在 `== Devices ==` 而非 `Devices Offline`；offline 时先 `devicectl device process launch` 启动一次产品 app 唤醒 instruments 服务（实测有效），仍 offline 则停，请用户处理设备。
2. 录一段 5 秒 `--all-processes --instrument 'Display'` 探针 trace 并立即导出验证非空。**这一步必须先于任何 app 驱动**——通道不通时绝不要花几十分钟把 app 驱进目标状态再发现录不了。
3. 录制从轻量集开始（`Display` + `RealityKit Metrics`，30 s 内），确认数据活着再补重 instrument；多 instrument + Time Profiler 的 90 s 录制在无线隧道上产生 GB 级流量，是压垮半死通道的负载。
4. 中途断连的 trace 保留并按 hollow 标注，一次会话内最多重试一次。
5. `--attach` 在 visionOS 上不可用（按名退出码 19、按 pid 退出码 21），只能 `--all-processes`。

## 段的完整与基线的重新证明

段的 `status` 由计划与实测的差集决定：`finish_segment` 把段计划里的 decision 与本段实际驱动出的 cell 相减，差集写进结果的 `plannedButNotDrivenCells`；计划由 `--mode final` 生成时，差集非空则 `complete` 降级为 `incomplete`。probe 计划把一个 context 的全部 cell 声明给它的每个 lane 段，差集是它要测量的东西而不是缺陷，因此只记录不降级；plan 文档的 `mode` 字段承载这一区分。在此之前，场景中途的静默 `return`／`continue` 不改变段的状态，一个几乎什么都没驱动的段照样报 `complete`。

`--require-baseline-coverage` 对基线里的 `known-defect` cell 与 `reachable` cell 一视同仁：本轮未重新驱动的 `known-defect` 记为 `old-known-defect-not-redriven` 并否决接受。缺这一条时 `known-defect` 是吸收态——cell 进得去、出不来，判定可以逐轮继承而永远不被重新证明。

## worktree 审计

- **`git branch --merged` 对在另一个 worktree 里检出的分支加 "+" 前缀而不是 "*"**，解析它的输出会把每一个这样的分支静默报成未合并。`Scripts/verification/worktree_audit.py` 改为用 `git merge-base --is-ancestor` 直接问祖先关系。
- **`du` 报的是逻辑大小，而 APFS 上各 worktree 通过写时复制共享块**，删掉它们释放的空间少于各自大小之和。2026-08-15 实测：15 个 worktree 的 du 合计 7.80 GB，删除后 df 只多出 4 GB。`Scripts/verification/worktree_audit.py` 打印的可回收量是上界，实际以 df 为准。

## `isHittable` 的失败会终结会话，护栏要接住它

`XCUIElement.isHittable` 对激活点落在可命中区域之外、又给不出替代命中点的元素不返回 false，而是记录一条 "Failed to determine hittability … Activation point invalid and no suggested hit points based on element frame" 的 XCTIssue；即便 `continueAfterFailure = true`，这条 issue 也会让 `testInteractiveDeviceSession` 结束，runner 离开自动化范围，段以 `channel-continuity-failed` 收场（2026-09-06 与 09-07 真机各一次，都在 `Emby-StillCard-3762`）。按窗口框预判活动点挡不住它：这张卡的中心 (2064, 284) 在 1536×864 的主窗口之外，却落在同一 app 的一个 2130×1396 的窗口框内。把 `isHittable` 包进 `XCTExpectFailure` 只能让这条 issue 不计失败，测试仍然在它之后立刻 Tear Down（2026-09-07 第三次真机复现：matcher accepted，随后 passed (129 s)，段照样 runner-gone）——UI Automation Failure 终结当前测试，与 `continueAfterFailure` 和 expected failure 无关。护栏因此改为**不去问**：从 `app.debugDescription` 解析 `Window (Main)` 的框（每条命令缓存一次），活动点不在主窗口框内直接判不可命中，`isHittable` 只对主窗口内的点调用；解析不到主窗口时才退回任一窗口框。`XCTExpectFailure` 包装保留为最后一道网。（`recordIssue:` 的 Swift 重写在本 SDK 上报 does not override，三种签名都试过。）

## 冻结核对测试包的来源，段在通道丢失处立刻结束

- **`freeze` 同时核对 app 与 UI 测试包的内嵌来源**。2026-09-07 两次 UI 测试 target 编译失败后，`Enchron.debug.dylib` 因产品代码未变而带着当前树摘要，旧的 `EnchronAppUITests.xctest` 却没有任何来源标记，冻结照样通过，两段真机回归跑在旧 runner 上。`EnchronAppUITests` target 现在也链接 `$(ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG)`，`_bind_lane` 解析 `EnchronAppUITests.xctest/EnchronAppUITests` 的 `__TEXT,__enchsrc`，与当前树摘要不一致即拒绝冻结（`test_bootstrap_freeze.test_a_stale_ui_test_bundle_refuses_to_freeze`）。编译失败的产物从此冻不进去。
- **段在场景阶段一旦通道丢失就结束当前场景**。原先 `run_segment` 只在场景之间检查 `channel_failures`，场景内部的每一步都还会得到"already failed"的拒绝文档并继续走完；runner 在第 31 步消失，段又发了二十多条注定失败的命令。现在 `controller` 在场景阶段（`scenario_phase`）遇到通道拒绝时抛 `SegmentChannelLost`，场景循环捕获后直接进入收尾；收尾阶段（probeStatus、拷贝、健康检查）不受影响。
- **每一步之后写 `progress.json`**。段输出目录下的这份文件只有几行：步数、最近一步与其成败、通道失败数、是否已停、结束状态。盯段的人读它，不读层级树。
