# Enchron 驱动与取证的产品事实

本文汇总与 lane 无关的驱动与取证事实。可能漂移的值在使用前重新核对；控制器与脚本的当前形态以各自的 `--help` 为准。

## 状态通道

**诊断串**是产品当前状态的快照。`PlayerUI-window-control-plane` 元素的 Accessibility value 是一条分号分隔的键值串，字段在 `Apps/Enchron/MainView.swift` 拼装，内容涵盖：呈现状态与切换、待执行的平台效果、沉浸空间驻留与生命周期修订、表面准备阶段、渲染器消费者、组件渲染状态、格式来源与投影，以及平台执行器最后一次操作的检查点与结论。排查呈现切换、表面附着与格式协商问题时，应当以诊断串为起点——它的判定早于层级与像素。完整串取自 `snapshot --identifier PlayerUI-window-control-plane` 返回的 `matchedElement.value`；直接导出层级文本时，同一行会被 XCTest 截断。

**探针**是事件时间线，记录诊断串这种快照无法表达的顺序信息：事件时序、沉浸空间开合的精确时刻、settle 判据的逐项布尔分解、手势投递与否。载体为容器内的 `Documents/surface-tap-probe.log`。该文件没有自动截断机制，且跨 App 重启持续追加，因此长批次测试前后应各归档一次并清空。

**PlaybackCore 实时记录**是媒体打开过程的分步流水。每个媒体会话在容器的 `tmp/playbackcore-live-debug/<mediaSessionID>/` 下生成 `events.jsonl` 与 `snapshot.json`，根部的 `current.json` 始终指向最新会话。常驻交互会话中默认开启；`VisionProDeviceAcceptanceUITests` 通过 `ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER=1` 将其关闭。当播放长时间停留在 Loading 时，若 `events.jsonl` 只有 `source.acquired` 与 `open.admitted` 两条记录，说明线程阻塞在 FFmpeg 的 reader open 阶段——既没有取得流信息、也没有报错，而诊断串此时只会显示 `lifecycle=Loading`。

**App 命令通道**直接驱动产品状态，不经过 hit testing。动词集合以 `Apps/Enchron/TestCommandChannel.swift` 为准；App 以 `ENCHRON_TEST_CHANNEL=1` 启动后，在自身 Documents 目录下以 500ms 周期轮询 `test-command.json`。它的用途是测试前置、清场与状态读回，驱动方式记为 `injected`；可达性仍须由 `real` 驱动证明。

### 通道的有效范围

沉浸呈现 settle 之后，主窗口仍然存在但内容为空：`PlayerUI-window-control-plane`、PlayerPanel、顶部动作与媒体库全部退出层级。因此诊断串只在 window、portal 及过渡的窗口阶段可读；panorama 与 docked 的 settle 判定改为轮询探针文件。

沉浸空间里的 SwiftUI attachment（如 `PlayerUI-immersive-playback-surface`）会出现在层级中并报告 isHittable，对它执行 `tap --identifier` 也会返回 Element tapped——但 App 的空间手势并没有收到投递，因为合成点击不携带注视加捏合语义。XCUIAutomation 对空间表面报告 `invalid activation point transform (nil)`。**在真机上，空间手势只有真人的捏合能够触发**；在模拟器 lane，Device Hub 画布的鼠标映射（悬停为 Gaze、点击为 Pinch）可以产生走真实输入管线的空间手势，见[模拟器 lane](simulator.md)。无论哪条通路，投递与否都以探针文件为准。

层级文本只打印主窗口一棵树。portal chrome 与系统 popover 承载的面板在这棵树之外，`snapshot --identifier` 对它们取不到 `matchedElement`——但这不代表不可达：`tap --identifier` 对这些元素仍能解析并命中。**可达性以 `tap` 自身的返回为准。**

## 矩阵与扫描

`Scripts/verification/playback_mode_matrix.py` 是播放模式矩阵 runner：一个 cell 等于 clip × path × rep，每个 cell 独立执行 ensure-session，verdict 落入 `results.jsonl`。覆盖矩阵以它执行。

**一次调查只允许一个常驻 runner。** 每 cell 独立 ensure-session 的前提是整轮矩阵独占目标设备。旧 runner 未停止时两者会争用目标：新 runner 停在 `Writing result bundle` 且从不开始自身测试，旧 runner 照常应答 preamble 与 tap，于是 cell 表现为打开成功随后挂起，并报出产品并未造成的 settle 超时。判别签名是：该 cell 的 `controller/runner.log` 不含任何 `t = …s` 行，而同 cell 的命令全部返回成功。

宽度优先的扫描（同一路径遍历多个片源）由 `Scripts/verification/playback_open_sweep.py` 执行：只建立一次会话且不重建，每个片源按 relaunch、resetState、push、importMedia、tap 的顺序驱动。判据优先读诊断串；当诊断串连续数次读取失败（这是沉浸落地的签名）后转取探针文件。容器拷贝要放在轮询末尾——放在开头会让单次迭代耗尽整个 settle 期限。

## 元素命中

侧栏源条目 `FileBrowsing-SourcesSidebar-source-<id>` 之下，删除按钮、图标与文本共享同一个 identifier，因此 `tap --identifier` 会命中删除按钮。选中某个来源时，应当按 label 或 `--index` 定位。

播放中 chrome 的自动隐藏快于两次控制器往返：`PlayerUI-InfoBar-button-back` 等按钮会报告 exists 而 isHittable 为假；格式编辑器的一次开合同样短于两次往返。应对方式有二：用 `tapSequence` 在一条命令内连发 `PlayerUI-TopAction-videoFormat`、投影项与 `PlayerUI-VideoFormat-apply`；或者直接读取 `tap` 自身返回的层级。控件召唤用 App 命令通道的 `toggleControls` 执行，它的应答直接给出召唤后的可见状态。

**合成滑动一律携带 `--identifier`。** 省略时，滑动目标退化为 Application 元素，而 visionOS 的 Application 元素不归属任何单一 Scene，合成事件因此取不到目标 Scene；三次重试全败后，失败被记入常驻测试方法，方法结束并拆除 App——表现为 TEST EXECUTE FAILED 且目标进程表中没有 Enchron，但两端进程均未崩溃。这个失败与页面无关，Emby 从未打开时同样必现；携带 identifier 的滑动在 Emby 各页与整窗具名元素上均正常。定性证据见 `docs/archive/plans/04-regression-journeys/emby-poster-wall-scroll.md`。

播放控制面板的前缀是 `PlayerPanel-`，与 `PlayerUI-` 顶栏不同族。跳转用 `PlayerPanel-button-forward`；进度条拖动是真人专属操作（它是一个要求 200ms 稳定按住的状态机）。More 菜单中，Subtitles 具备 identifier（`PlayerUI-menu-subtitles`），Audio Track 及音轨条目只能按 label 命中；菜单存续短于两次往返，须读取 tap 自身返回的层级；同名条目（如两条 `und · aac · 2ch` 音轨）以 `--label` 加 `--index` 区分。DockMenu 条目按 label 命中（`Dark Mode`、`Light Mode`）；菜单打开后 `PlayerUI-TopAction-dock` 自身会退出层级，因此该按钮无匹配通常表示菜单已经打开。

Emby 的播放入口：首页「接下来看」横条的 `Emby-StillCard-<id>` 打开单集详情，可视区内提供 `Emby-Detail-Resume` 与 `Emby-Detail-PlayFromBeginning`。系列详情页按设计不提供播放按钮（`isPlayable` 对 series、season、boxSet 返回 false），播放入口是下方选集面板的 `Emby-Episode-<id>` 卡片，点击直接进入播放。折叠线以下的剧集条需要先携带 identifier 滚动到可视区。海报横条只有可视区内的卡片可点，靠右超出视野的卡片 tap 返回 False。

label 为 `Play button on a TV, filled` 的图标是导航栏的 Emby 页签（identifier `Emby-Navigation-Tab`，与 `Navigation-Ornament-tab-files`、`-settings` 同族但不同项），它不出现在系列详情页；已在 Emby 页签上时重复点击它没有可观察效果，这属于正确行为。

## identifier 在系统容器中的存活规则

SwiftUI 只在系统容器把内容提升为一等 action 时保留 `.accessibilityIdentifier`。以下结论于 2026-08-21 在同一构建上逐项实测：

| 位置 | 构造 | identifier |
|---|---|---|
| `.alert` | `Button` | 保留 |
| `.alert` | `TextField` | 丢弃（仅剩 `placeholderValue`） |
| `Menu` | `Button` | 保留 |
| `Menu` | inline `Picker` 的 `Text` 行 | 丢弃 |
| `Menu` | `Toggle` 行 | 丢弃 |
| `Menu` 中的 `Section` | 其中任何行 | 丢弃 |

自定义 `View` 包装（如 `MenuSelectionRow`）与自定义菜单宿主（如 `GlassCircleIconMenu`）都不影响保留与否，同一菜单内的三种变体对照已确认这一点。结论是：菜单行一律写为 `Button`，分组以 `Divider()` 实现，代价是对勾落于标题之前并把标题右推。`Modules/DesignSystem/Components/MenuSelectionRow.swift` 是唯一正确写法，新菜单直接复用它。

alert 中的 TextField 按 label 或 placeholder 命中。控制器的 `element(for:)` 支持 `--label`；`textInputElement` 依次尝试 identifier、label、placeholderValue。

## 文本输入

`typeText` 优先携带 `--identifier`，runner 解析到目标元素后会先 tap 聚焦再输入。系统容器丢弃 identifier 的字段改带 `--label`，取值为 placeholder 文本（如 `--label "Folder name"`）；两者均缺席时返回「无匹配元素」，字段保持为空。

SMB 连接表单可全程合成驱动，字段前缀为 `FileBrowsing-SourceConnection-smb-`；WebDAV 前缀为 `FileBrowsing-SourceConnection-webDAV-`。字段与按钮的完整集合以[远程来源特性](../features/remote-source-connection.md)为准。首次凭据连接后系统会弹出「保存密码?」对话框，`tap --label '以后'` 可以合成关闭。从播放器退出后，浏览位置回到 Media Library 根目录，重进远程目录需要从侧栏重走。

## 测试媒体

`TestMedia` 中分辨率足够的 180° 片源部分为成人内容。层级与诊断状态足以回答绝大多数问题；只有当结论确实取决于像素时才截图，需要目视确认时先与佩戴者确认片源。
