# UI 测试通道与 visionOS 自动化的约束

本文记录 `Tests/EnchronAppUI`、`Tests/EnchronApp` 与 App 侧测试通道里**无法从代码本身读出**的事实：XCUITest 在 visionOS 上的实际行为、可用的观察通道、以及若干时序容差的来由。旅程词汇、证据受理判据与设备保留清单归 `.agents/skills/vp-e2e/`，本文不重复它们，只记录测试代码自身依赖的平台行为。

## 观察通道

- **测试宿主的 stdout 既不进 xcodebuild 日志，也不进设备上的 result bundle**。app 容器进得去（经 devicectl），所以测量报告写进容器而不是打印出来。解码能力矩阵就落在容器里的 `video-decoder-matrix.tsv`。
- **`XCUIScreen.main` 在当前 visionOS 构建上返回 1×1 图像**，读起来像一张黑帧而不是一次抓取失败。application element 仍然能抓，所以退化的屏幕图像要回退到它。
- **模拟器截图 lane 没有点进模拟器的通道**，想看的那一屏必须在启动时就可达；启动参数因此是到达某一屏的唯一途径。
- **精确时间轴由 scrubber 的双击打开**，合成 tap 复现不了双击，所以逐帧步进按钮在测试里除了走测试通道之外不可达。
- **真机的进程表按可执行文件路径列出进程，bundle id 不出现在其中**。`…/Enchron.app/Enchron` 与 `…/EnchronAppUITests-Runner.app/…` 都含有 `Enchron`，所以 `Scripts/verification/interactive_visionpro_ui.py` 用这一个 marker 同时匹配 app 与 runner。
- **模拟器上 `launchctl list` 按 bundle id 标注 app，而不是按可执行文件路径**，同一次进程观察的 marker 集合因此随 transport 变化。`Scripts/verification/interactive_visionpro_ui.py` 在模拟器上要在路径 marker 之外再加上 app 与 runner 的 bundle id。
- **`devicectl device copy` 以目录为单位整体复制**，而 deferred 应答批次就是一个目录。`Scripts/verification/enchron_target.py` 的模拟器分支必须整树复制来对齐这一行为；只复制文件会把每一条批量应答留在模拟器容器里。
- **`Scripts/verification/enchron_target.py` 里的 `PHYSICAL_DESTINATION` 与 `PHYSICAL_CORE_DEVICE` 最后一次与头显核对是 2026-08-09**。头显更换后以 `xcrun devicectl list devices` 为事实来源重新核对这两个值。
- **ffmpeg 把纯文本 demux 成 ANSI art 视频，并报出可信的时长与帧率**。暂存的 xcresult 把 runner 的 stdout 与附件放在一起，Staging 扫描会把两者一并递给探针，所以 `Scripts/verification/extract_visionpro_ui_recording.py` 不检查容器格式就会把 app 自己的日志当成录屏取回。
- **xcresult 里的录屏是 anamorphic 的：2732x2048 像素承载一幅 16:9 画面，且不带 aspect 元数据**，方形像素的查看器会把它纵向拉伸。`Scripts/verification/extract_visionpro_ui_recording.py` 抽帧时归一到 XCUIScreen 截图通道交付的同一 16:9 几何。
- **麦克风放在头显扬声器一小段距离外时，一次音调清晰可辨的采集落在 -55 dBFS 附近**，把静音阈值设在该电平会把真实采集报成静音。`Scripts/verification/journey_audio_probe.py` 取 -75 dBFS，低于仍然带 25 倍峰值的最安静一次采集；真正把音调与本底分开的是 `dominantPeakRatio`。
- **200 Hz 以下的房间噪声可以压过被测音调**，此时 band 内最响的 bin 指认的是房间而不是音轨。`Scripts/verification/journey_audio_probe.py` 因此把 fixture 的四个脉冲频率互相排序，而不取 band 内的全局最大值。
- **控制面读不到就是沉浸式落点的签名**。沉浸式呈现清空主窗口，控制面随之消失，落点判定只能改读容器里的探针文件。见 `Scripts/verification/playback_open_sweep.py`。

## XCUITest 与 visionOS 的场景

- **Application element 不属于任何一个 visionOS Scene**。对它合成事件会在 Scene 查找上失败，而这个失败会结束这个长驻测试方法并把 app 一起拆掉。正确做法是让那条命令失败，而不是把整个会话拖走。
- **Panorama 与 Dock 会有意关闭主窗口**。那个 Scene 离场期间不要读它的 accessibility value：元素可能在 `exists` 与 `value` 之间消失，XCTest 把这种情况报成 application failure 而不是"节点不存在"。同理，目标控制面一出现，提交转换就可能关掉来源窗口，从那一刻起以目标状态为准。
- **被遗弃的常驻会话会让 testmanagerd 把证据一直留在头显上直到测试返回**，所以空闲的会话必须自己结束。
- **`xcodebuild` 把 `TEST_RUNNER_ENCHRON_*` 去掉前缀转发进 runner 进程**。对一个不重启的常驻 runner 来说，这是调用方够到 app 环境变量的唯一路径。
- **沉浸空间关闭之后场景输入所有权会丢**，需要显式恢复，而不是靠重启 app——重启会把当前状态一起丢掉。
- **自动隐藏的 chrome 熬得过一次控制器往返，熬不过四次**，所以菜单序列必须落在同一条命令里。
- **runner 对 stop 的反应是结束自己的测试，而不是写一条应答**，所以一次超时的 stop 应答不表示 stop 被忽略。等 `xcodebuild` 退出是唯一能区分两者的观察，那次退出也正是 result bundle 与录屏写完的时刻，`Scripts/verification/interactive_visionpro_ui.py` 的 halt 以它为准。
- **runner 在 XCTest 拆掉测试之前就应答 stop**，带录屏的会话把这段拆解时间用于把视频从头显上拉下来并写 result bundle。在此期间杀掉 `xcodebuild` 会留下一个没有 Info.plist 的 bundle 和一段没有 moov atom 的录像；没有录屏的会话远在这段时间之内就自己退出。`Scripts/verification/interactive_visionpro_ui.py` 的 `resultBundleWritten` 报告的是 xcodebuild 有没有自己退出。

## 预算与合成输入的实测常数

2026-09-02 在模拟器与真机两条 lane 上实测得出，证据在当轮 reachability 运行的 raw 目录里：

- **XCUITest 的 `tap()` 在合成事件前等待 app 静默，等待上限约 60 秒**。导入媒体后的缩略图与库落盘工作让 app 长时间不静默，所以任何由空闲期样本推出的 p95 预算都会结构性地卡在这个窗口里、把一次正常的慢 tap 杀成 transport-timeout。合成输入类动词的预算地板由 `provisional_budgets.json` 的 `floorSeconds` 承载（当前 75 秒），高于该上限。
- **样本不足 5 条时等待动词的临时预算取 60 秒上限，而不是猜测值**。`identifier-appearance`／`any-identifier-appearance`／`identifier-absence`／`identifier-value`／`probe-needle`／`presentation-settle` 曾是 8–45 秒的猜测，落在 tap 静默窗口之内，一次正常的慢出现会被杀成 wait-expired；上限 60 秒与 tap 的静默等待对齐，元素真的不出现时仍然以上限失败。`Budget.provenance` 里以 `provisional ceiling 60s` 标出未实测的上限，与合成输入等非等待动词的 `provisional <n>s` 猜测区分。
- **冻结运行的等待样本落在当次输出目录的 `timing-samples.jsonl`**，每行一个 `{"verb", "lane", "seconds", "censored", "at"}`，`results.json` 以 `timingSamples: {"path", "count"}` 指认它。冻结运行不写 `controller_timings.<lane>.json`（受版本控制，写它会破坏冻结），样本归属由构造 `BudgetProvider` 的一方注入输出目录；非冻结运行仍直接写 `controller_timings.<lane>.json`。
- **冻结样本由 `Scripts/verification/fold_timing_samples.py` 按 lane 折回 `controller_timings.<lane>.json`**，按 `(verb, at)` 去重、每动词保留最近 `SAMPLE_LIMIT`（40）条。同一输入跑两次第二次无改动；某动词折入 5 条以上后 `budget()` 即按 p95 × 1.5 给出实测预算，不再走临时上限。
- **runner 的应答等待默认 30 秒**（`--timeout-seconds`），必须由调用方随预算下发，否则预算高于 30 秒的调用会先撞 runner 自己的死线，报出的 kind 是 `response-timeout` 而不是 `transport-timeout`。
- **模拟器 lane 打开本地媒体的合成 tap 会吊死 app 主线程**，而不是无害失败；这是"打开本地媒体必须经真实点击"（vp-e2e simulator.md）的更强形式。分段的 lane 跟随场景：`reachability_matrix.SCENARIO_LANES` 从 harness 源码静态推导出每个场景是否会经由 `MediaLibrary-grid-video-*`／`FileBrowsing-grid-video-*`／`Emby-Detail-Resume|PlayFromBeginning` 打开播放，会打开的场景与所有播放呈现上下文由 device lane 分段驱动，浏览面其余场景归 `probe-main-window-browser`（simulator）。分段计划中 lane 与场景不一致、进程 `ENCHRON_TARGET_DEVICE` 与分段 lane 不一致，都在启动前拒绝；模拟器 lane 上仍打到打开播放的 identifier 时，`tap()` 抛 instrument fault `playback-open-on-simulator-lane`，该段以 `channel-continuity-failed` 结束而不是等待 6 分钟超时。
- **无人佩戴的真机上，场景 phase 事件跨场景销毁不触发**：主窗口在播放期间被撤销再重开后，其 `scenePhase` 直接继承 active 而没有 background→active 转换。任何"等到 active 再行动"的门槛必须以布防后的新转换为准，否则会立即放行。
- **撤销一个窗口可能把整个 app 送进 background 并被系统挂起**（进程存活、命令通道与 AX 全部无响应），即便另一个窗口刚刚 appeared。播放→主窗交还因此把撤销延迟到主窗布防后的下一次 active 转换；等不到就保留双窗，绝不冒挂起风险。
- **段间复用常驻 runner 省去每段 `ensure-session` 的 115–286 秒建会话与 30–56 秒 `halt`，四段合计 10–20 分钟（device lane 关键路径约 57 分钟的 20–35%）**，段证据对齐由 runner `sessionID`（`ready.json`）改为每段新建的 `evidenceSession`（`evidenceSession=<uuid>`，`reachability evidence session=<uuid>`）。
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
- **SwiftUI `Menu` 在真机 visionOS 上可能报 `isHittable == false`，却仍然接受语义 tap**。可观察的契约是"菜单可用 → 公共选项可用 → 设置标题变了"，`isHittable` 单独不足以否决这个系统控件。
- 系统 `Menu` 里只有 `Button` 行保留标识符、`Section` 会吞掉内部每一行的标识符——两条见 `docs/DESIGN_SYSTEM_CONSTRAINTS.md`。

## 时序容差的来由

- **`PlaybackSeekPresentation` 在时长的 2% 内接受渲染器位置**，而 `waitForState` 每 0.1 秒轮询一次，所以一个 Playing 快照可能比目标多走一次轮询。
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

## 状态复位的语义

App 侧测试通道的复位不是"删掉一切"：

- **TestMediaInbox 是 harness 拥有的暂存区，不是 app 状态**。在这里清掉它，等于强迫每个用例重新推一遍所有媒体文件。
- **内存中的媒体库必须最先清**：它在变更时与终止时都会把自己重新持久化，留着它就会把这次复位刚删掉的引用复活。
- **记住的服务器证书是 app 状态**，落在自己的前缀下，而产品没有"遗忘"入口；不清它，信任提示在第一次接受之后就再也不会出现。
- **已保存的远程来源是复位要删的状态**。`resetState` 经 `removeDataSource` 逐个移除 `savedDataSources`，凭据无共享时 Keychain 条目跟着删除；段结束时侧栏回到只有 Media Library。
- **复位必须报告它建立出来的状态**，只报删除数量会把下一个单元真正依赖的东西——库里现在有什么——藏起来。
- **视图模式偏好活过 relaunch**：`MediaLibraryUIState.viewMode` 落盘在 `enchron.mediaLibrary.uiPreferences` 里，relaunch 不清它。切过视图模式的场景必须在同一场景内把它切回 grid 并验证网格标识回到层级里；复位走 DEBUG 通道的 `setViewMode` 而不用合成 tap——该控件按落点半区选择模式，而 visionOS 对合成事件上报的落点不可靠，同一条 `coordinateTap` 在不同会话阶段会落到不同半区。`resetState` 删掉该 key 的同时把内存里的 viewMode 置回 grid。新建文件夹、打开文件夹、导航、多选链开头断言 grid 模式，不满足时以 `library-view-mode-not-grid` 失败，不得自适应到 list 行继续。
- **空间验收测试从隔离的播放状态开始，但同一个测试内部的进程重启必须保住它正在验证的格式**。新的 reset token 表示新测试，同一个 token 表示该测试内部的一次冷重启。

## worktree 审计

- **`git branch --merged` 对在另一个 worktree 里检出的分支加 "+" 前缀而不是 "*"**，解析它的输出会把每一个这样的分支静默报成未合并。`Scripts/verification/worktree_audit.py` 改为用 `git merge-base --is-ancestor` 直接问祖先关系。
- **`du` 报的是逻辑大小，而 APFS 上各 worktree 通过写时复制共享块**，删掉它们释放的空间少于各自大小之和。2026-08-15 实测：15 个 worktree 的 du 合计 7.80 GB，删除后 df 只多出 4 GB。`Scripts/verification/worktree_audit.py` 打印的可回收量是上界，实际以 df 为准。
