# Emby 海报墙 swipeUp 杀会话：定性结论

调查日期 2026-08-20，物理 Vision Pro（CoreDevice `59E3D57A-…`，destination `00008142-001871A11491401C`，visionOS 27.0 / 24M5348b）。

## 结论

这是自动化通道缺陷，不是产品缺陷，与 Emby 无关，也与任何动画无关。

杀死会话的不是"对 Emby 海报墙滑动"，而是**不带 `--identifier` 的 `swipeUp`**。控制器在缺少 identifier 时把滑动目标退化为 `XCUIApplication` 元素（`Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:233-234`）。visionOS 上 Application 元素不归属于任何单一 Scene，XCUIAutomation 合成事件时向 Accessibility 索要目标 Scene 得到 nil，三次重试全部失败后把失败记到测试方法上，常驻测试方法随即结束，Tear Down 终止它启动的目标 App。因此"设备进程表无 Enchron"是 XCTest 正常拆除的结果，不是崩溃。

三种可能性中确证为第三类的变体：**被测应用与 runner 进程都没有崩溃，是常驻测试方法自身被一次 XCTest 失败终结**。

历史记录把它归因于 Emby 滚动视图，是误归因。2026-08-16 两次死亡的 `.xcresult` 活动日志显示滑动目标是 `Target Application 'com.xiongzhipeng.XrPlayer'`，不是任何 Emby 元素；当时 Emby 只是恰好停在屏幕上。

产品负责人怀疑的"越过阈值触发的系统弹入动画"被证伪：`Modules/Emby/` 与 `Modules/DesignSystem/` 中不存在 `scrollTransition` 或 `visualEffect`；`EmbyScreens.swift` 的 `.animation` 只用于侧栏显隐（153-180 行）与季次交叉淡入（1101 行），`GridCard.swift` 的动画是骨架占位淡入（279 行）、选中态（363 行）与悬停过渡，都不是随滚动位置触发的入场动画。四次带 identifier 的合成滑动在 Emby 各页面正常滚动、卡片正常入场，会话全部存活。

## 证据

### 设备日志

失败签名，三次重试形状完全一致：

```
t = 32.05s Swipe up Target Application 'com.xiongzhipeng.XrPlayer'
t = 37.81s     Failed: Received invalid scene ID (nil) from Accessibility.
…（重试 #2、#3 同形）
InteractiveDeviceUITests.swift:244: error: … Failed to received invalid scene ID (nil) from Accessibility.
t = 51.80s Tear Down
```

| 证据 | 出处 | 说明 |
|---|---|---|
| 本次复现（Emby 详情页在屏） | posterwall-20260820 runner-death1.log:293-310，已删除 | 三次 `Synthesize event` 各约 5.5 秒后返回 nil scene ID |
| 本次对照（Files 页在屏，Emby 全程未打开） | 同一轮 runner-death2.log:42-67，已删除 | 同一签名，同一行号，证明与 Emby 无关 |
| 历史死亡一 | source-parity-20260816 Interactive-1786813813-1.xcresult，已删除 | 活动日志滑动目标为 Target Application |
| 历史死亡二 | 同一轮 Interactive-1786814348-1.xcresult，已删除 | 同上；失败落在当时源码 228 行，即 `case .swipeUp: surface.swipeUp()` |

App 存活的正面证据：每次合成失败之后，runner 仍成功取得目标 App 的 Accessibility 层级（`runner-death1.log:300,308`，pid 1061；历史运行同形，pid 3467）。设备崩溃报告域 `systemCrashLogs` 中 2026-08-20 无任何 Enchron 条目，最近一条为 `Enchron-2026-08-19-173430.ips`。

### 存活对照

同一会话、同一 runner，仅目标不同：

| 目标 | 页面 | 结果 |
|---|---|---|
| `Emby-library-list`（顶部起滑） | 电影库海报墙 | 成功，内容滚动，会话存活 |
| `Emby-library-list`（底部起滑） | 电影库海报墙 | 成功，会话存活 |
| `Emby-Home --index 2` | Emby 首页滚动视图 | 成功，内容滚动，会话存活 |
| `Emby-Detail-6303 --index 1` | 剧集详情页滚动视图 | 成功，会话存活 |
| `FileBrowsing-FilesScreen` | Files 页整窗元素（1536×864） | 成功，会话存活 |
| 无 identifier | Emby 详情页 | **会话死亡** |
| 无 identifier | Files 页 | **会话死亡** |

最后一行的整窗对照说明问题不在"元素太大"：与主窗口同尺寸的具名元素接受合成滑动，只有 Application 元素不接受。

### 代码位置

- `Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:231-250`：滑动分支。`command.identifier == nil` 时 `surface = app`，随后 `surface.swipeUp()` 直接调用，非抛出 API 的失败无法被 Swift 错误处理捕获。
- `Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:11`：`continueAfterFailure = true`。该设置未能保住会话——本次失败仍在记录后立即进入 Tear Down，说明 XCUIAutomation 的 Scene 路由失败以异常方式解开测试方法栈，不走可继续的失败记录路径。
- `Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:285-303`：`element(for:)` 按 `element(boundBy: index ?? 0)` 取匹配。Emby 首页有三个元素共享 `Emby-Home`（侧栏开关 Button、标题 StaticText、滚动视图 ScrollView，索引 0/1/2），要滑动滚动视图必须显式 `--index 2`。
- `Apps/Enchron/TestCommandChannel.swift:665-703`：`scrollEmby` 经 `NotificationCenter` 投递 `EmbyReachabilityScrollRequest`。
- `Modules/Emby/EmbyScreens.swift:433-447、581-595、723-733`：三处 `.scrollPosition($…)` 配 `.onReceive`，直接调用 `scrollTo(edge:)`。

`scrollEmby` 幸免的原因由此确定：它完全不合成 UI 事件，滚动由 SwiftUI 的 `ScrollPosition` 绑定在应用进程内完成，不经过 Scene 路由，因此不存在 Scene ID 查询。该动词由 `7d7da652`（2026-08-17，"Add device reachability delivery channels"）为可达性矩阵引入，晚于两次死亡，属于对该故障的绕行而非独立需求。

## 已确证与未能确证

已确证：

- 失败发生在事件合成阶段，错误为 Accessibility 返回 nil Scene ID。
- 目标 App 与 runner 均未崩溃；无当日崩溃报告；App 在每次失败后仍应答层级请求。
- 会话终止的直接原因是该失败终结了常驻测试方法。
- 触发条件是滑动目标为 Application 元素，与页面、与 Emby、与滚动距离、与卡片数量均无关。
- 2026-08-16 两次历史死亡与本次为同一机制。

未能确证：

- Accessibility 为何对 Application 元素返回 nil Scene ID 的系统内部原因。Enchron 主窗口之外同时存在装饰窗口（209×241.5）与两个 2130×1396 窗口，Application 元素跨越多个 Scene 是合理推测，但推测未经独立验证。
- `continueAfterFailure = true` 未能阻止方法终止的确切内部路径，只观察到结果。
- 其它合成手势（`swipeDown`/`swipeLeft`/`swipeRight`/`coordinateTap`）在缺 identifier 时是否同样致命。代码路径相同，预期一致，本次未逐个验证。

## 最小复现步骤

1. `ensure-session` 建立常驻会话（任意页面，Emby 无需打开）。
2. `python3 Scripts/verification/interactive_visionpro_ui.py --device <destination> swipeUp --no-screenshot`，不带 `--identifier`。

一次即死。控制器返回 `stage: responseTimeout`，runner 日志出现上述签名。`halt` 后 `ensure-session` 重建即恢复。

## 修复方向

问题在控制器与 runner，产品代码无需改动。

1. **runner 拒绝无目标的滑动。** `InteractiveDeviceUITests.swift:233-234` 的 `surface = app` 退化是故障源头。改为在缺 identifier 时返回结构化失败（"合成滑动必须指定目标元素"），与该文件其余分支处理"元素不存在""元素不可点击"的方式一致，会话得以保留。
2. **或退化到主窗口而非 Application。** 若需要保留无参形态，把默认目标改为 `app.windows.element(boundBy:)` 中与主窗口对应的那一个。整窗具名元素接受合成滑动已由本次 `FileBrowsing-FilesScreen` 对照证实。
3. **控制器侧前置校验。** `interactive_visionpro_ui.py` 在参数解析阶段就要求滑动动作携带 `--identifier`，把失败挡在会话之外，代价为零。
4. **修正运行手册。** `.agents/skills/visionpro-xcuitest/references/enchron.md` 现记"对 Emby 滚动视图发 swipeUp 导致 runner 死亡……Emby 界面一律不发合成滑动"。该禁令方向错误：Emby 界面带 identifier 的合成滑动正常工作，真正的禁令是"合成滑动一律带 identifier"。同一处记录的 `docs/plans/02-source-parity-acceptance/decision-log.md:165` 与 `decisions.tsv:26` 亦为误归因。
5. **可达性矩阵可去绕行。** `Scripts/verification/reachability_matrix.py:2284` 用 `scrollEmby` 替代 Emby 滚动，是本故障的历史绕行。`scrollEmby` 仍有价值（`#if DEBUG` 内的确定性滚动到边界），但 Emby 滚动的真实可达性现在可以由带 identifier 的合成滑动证明，两者应分别成条。

## 调查过程的操作记录

未改动任何产品代码。当时的构建产物与证据写在已废弃的外部产物根下，现已删除；重跑落 `.scratch/` 与 `TestEvidence/`。

工作树留有一处修改：`Scripts/verification/controller_timings.json`，为控制器每次成功往返自动写入的滚动耗时样本，属该脚本的设计行为，非手工改动；未回滚，以免丢弃本次真实测量。

证据清洗：对 204 个文件扫描 Emby 凭据值、URL 用户信息、鉴权头（`X-Emby-Token`／`X-MediaBrowser-Token`／`Authorization`）与 `api_key`。Emby 地址、主机名、鉴权头、URL 用户信息、api_key 全部零命中。凭据的 username 与 password 字段各有命中，经逐条核对均为子串巧合——username 与卷名 `Cortisol` 相同，命中的是文件路径；password 是代码签名身份中邮箱地址的子串，命中的是 Xcode 构建日志的签名行。二者都不是凭据泄露。后续扫描应使用带边界的匹配，否则这两个短字段会持续产生假阳性。
