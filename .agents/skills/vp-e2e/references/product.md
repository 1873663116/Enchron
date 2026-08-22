# Enchron 驱动与取证的产品事实

可能漂移的值使用前重新核对。控制器与脚本的当前形态以各自的 `--help` 为准。

## 状态通道

**诊断串**是产品当前状态的快照。`PlayerUI-window-control-plane` 元素的 Accessibility value 为分号分隔串，字段在 `Apps/Enchron/MainView.swift` 拼装，内容涵盖呈现状态与切换、待执行平台效果、沉浸空间驻留与生命周期修订、表面准备阶段、渲染器消费者、组件渲染状态、格式来源与投影，以及平台执行器的最后一次操作、检查点与结论。呈现切换、表面附着与格式协商的排查以它为起点，其判定早于层级与像素。完整串取自 `snapshot --identifier PlayerUI-window-control-plane` 的 `matchedElement.value`；层级文本中的同一行受 XCTest 截断。

**探针**是事件时间线，记录诊断串无法表达的顺序信息：事件时序、沉浸空间开合时刻、settle 判据的逐项布尔分解、手势投递与否。载体为 `Documents/surface-tap-probe.log`，无自动截断且跨 App 重启持续追加，长批次前后各归档一次并清空。

**PlaybackCore 实时记录**是媒体打开过程的分步流水。每个媒体会话在容器的 `tmp/playbackcore-live-debug/<mediaSessionID>/` 下生成 `events.jsonl` 与 `snapshot.json`，根部 `current.json` 指向最新会话；常驻交互会话中默认开启，`VisionProDeviceAcceptanceUITests` 以 `ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER=1` 关闭。停留于 Loading 的会话若 `events.jsonl` 仅含 `source.acquired` 与 `open.admitted`，表示线程阻塞在 FFmpeg 的 reader open，既未取得流信息也未失败，而诊断串此时仅显示 `lifecycle=Loading`。

**App 命令通道**驱动产品状态而不经 hit testing。动词集合以 `Apps/Enchron/TestCommandChannel.swift` 为准；App 以 `ENCHRON_TEST_CHANNEL=1` 启动后，在自身 Documents 下以 500ms 周期轮询 `test-command.json`。其用途为前置、清场与读回，驱动方式记为 `injected`；可达性由 `real` 驱动证明。

### 通道的有效范围

沉浸呈现 settle 后主窗口仍存在但内容为空，`PlayerUI-window-control-plane`、PlayerPanel、顶部动作与媒体库均退出层级。诊断串因此仅在 window、portal 及过渡的窗口阶段可读，panorama 与 docked 的 settle 判定改为轮询探针文件。

沉浸空间的 SwiftUI attachment（如 `PlayerUI-immersive-playback-surface`）出现在层级中并报告 isHittable，对其 `tap --identifier` 返回 Element tapped，而 App 的空间手势未收到投递——合成点击不携带注视加捏合语义。XCUIAutomation 对空间表面报告 `invalid activation point transform (nil)`。**空间手势的唯一触发是真人的捏合**，投递与否以探针文件为准。

层级文本仅打印主窗口一棵树，portal chrome 与系统 popover 承载的面板在其之外，`snapshot --identifier` 对它们取不到 `matchedElement`。**可达性以 `tap` 自身的返回为准**：`tap --identifier` 对这些元素仍能解析并命中。

## 矩阵与扫描

`Scripts/verification/playback_mode_matrix.py` 是播放模式矩阵 runner，cell = clip × path × rep，每 cell 独立 ensure-session，verdict 落 `results.jsonl`。覆盖矩阵以它执行。

**一次调查只允许一个常驻 runner。** 每 cell 独立 ensure-session 的前提是整轮矩阵独占目标。旧 runner 未停止时两者争用目标：新 runner 停在 `Writing result bundle` 且从不开始自身测试，旧 runner 照常应答 preamble 与 tap，cell 表现为打开成功随后挂起，并报出产品未造成的 settle 超时。判别签名为该 cell 的 `controller/runner.log` 不含任何 `t = …s` 行，而同 cell 的命令全部返回成功。

宽度优先的扫描（同一路径遍历多个片源）以 `Scripts/verification/playback_open_sweep.py` 执行：仅建立一次会话且不重建，每片源按 relaunch、resetState、push、importMedia、tap 顺序驱动。判据优先读诊断串，诊断串连续数次读取失败（沉浸落地的签名）后转取探针文件；容器拷贝置于轮询末尾，置于开头将使单次迭代耗尽整个 settle 期限。

## 元素命中

侧栏源条目 `FileBrowsing-SourcesSidebar-source-<id>` 下的删除按钮、图标与文本共享同一 identifier，`tap --identifier` 命中删除按钮；选中源按 label 或 `--index`。

播放中 chrome 的自动隐藏快于两次控制器往返，`PlayerUI-InfoBar-button-back` 等按钮报告 exists 而 isHittable 为假；格式编辑器的一次开合同样短于两次往返。应对方式为 `tapSequence` 连发 `PlayerUI-TopAction-videoFormat`、投影项与 `PlayerUI-VideoFormat-apply`，或读取 `tap` 自身返回的层级。控件召唤以 App 命令通道的 `toggleControls` 执行，其应答直接给出召唤后的可见状态。

**合成滑动一律携带 `--identifier`。** 省略时滑动目标退化为 Application 元素，而 visionOS 的 Application 元素不归属任何单一 Scene，合成事件取不到目标 Scene；三次重试全败后失败记入常驻测试方法，方法结束并拆除 App，表现为 TEST EXECUTE FAILED 且目标进程表无 Enchron，两端进程均未崩溃。该失败与页面无关，Emby 从未打开时同样必现。携带 identifier 的滑动在 Emby 各页与整窗具名元素上均正常。定性证据见 `docs/plans/04-regression-journeys/emby-poster-wall-scroll.md`。

播放控制面板前缀为 `PlayerPanel-`，与 `PlayerUI-` 顶栏不同族；跳转用 `PlayerPanel-button-forward`，进度条拖动为真人专属（200ms 稳定按住的状态机）。More 菜单中 Subtitles 具备 identifier（`PlayerUI-menu-subtitles`），Audio Track 及音轨条目按 label 命中，菜单存续短于两次往返，读取 tap 自身返回的层级；同名条目（如两条 `und · aac · 2ch` 音轨）以 `--label` 加 `--index` 区分。DockMenu 条目按 label 命中（`Dark Mode`、`Light Mode`），菜单打开后 `PlayerUI-TopAction-dock` 自身退出层级，该按钮无匹配通常表示菜单已经打开。

Emby 播放入口：首页「接下来看」横条的 `Emby-StillCard-<id>` 打开单集详情，可视区内提供 `Emby-Detail-Resume` 与 `Emby-Detail-PlayFromBeginning`。系列详情页按设计不提供播放按钮（`isPlayable` 对 series、season、boxSet 返回 false），播放入口为下方选集面板的 `Emby-Episode-<id>` 卡片，点击直接进入播放。折叠线以下的剧集条需先携带 identifier 滚动。海报横条仅可视区内的卡片可点，靠右的卡片 tap 返回 False。

label 为 `Play button on a TV, filled` 的图标是导航栏 Emby 页签（identifier `Emby-Navigation-Tab`，与 `Navigation-Ornament-tab-files`、`-settings` 不同族），不出现在系列详情页；在 Emby 页签上重复点击无可观察效果属正确行为。

## identifier 在系统容器中的存活规则

SwiftUI 仅在系统容器将内容提升为一等 action 时保留 `.accessibilityIdentifier`。2026-08-21 于同一构建逐项实测：

| 位置 | 构造 | identifier |
|---|---|---|
| `.alert` | `Button` | 保留 |
| `.alert` | `TextField` | 丢弃（仅剩 `placeholderValue`） |
| `Menu` | `Button` | 保留 |
| `Menu` | inline `Picker` 的 `Text` 行 | 丢弃 |
| `Menu` | `Toggle` 行 | 丢弃 |
| `Menu` 中的 `Section` | 其中任何行 | 丢弃 |

自定义 `View` 包装（如 `MenuSelectionRow`）与自定义菜单宿主（如 `GlassCircleIconMenu`）均不影响保留，同一菜单内三变体对照确认。菜单行写为 `Button`，分组以 `Divider()` 实现，代价是对勾落于标题之前并将标题右推。`Modules/DesignSystem/Components/MenuSelectionRow.swift` 是唯一正确写法，新菜单直接复用。

alert 中的 TextField 按 label 或 placeholder 命中。控制器的 `element(for:)` 支持 `--label`，`textInputElement` 依次尝试 identifier、label、placeholderValue。

## 文本输入

`typeText` 优先携带 `--identifier`，runner 解析目标元素后先 tap 再输入。系统容器丢弃 identifier 的字段改带 `--label`，取值为 placeholder（如 `--label "Folder name"`）；两者均缺席时返回「无匹配元素」，字段保持为空。

SMB 连接表单可全程合成驱动，前缀 `FileBrowsing-SourceConnection-smb-`；WebDAV 前缀 `FileBrowsing-SourceConnection-webDAV-`。字段与按钮的完整集合以 [远程来源特性](../features/remote-source-connection.md) 为准。首次凭据连接后系统弹出「保存密码?」对话框，`tap --label '以后'` 可合成关闭。自播放器退出后浏览位置回到 Media Library 根，重进远程目录需自侧栏重走。

## 测试媒体

`TestMedia` 中分辨率足够的 180° 片源部分为成人内容。层级与诊断状态足以回答绝大多数问题；结论确实取决于像素时才截图，需要目视确认时先与佩戴者确认片源。
