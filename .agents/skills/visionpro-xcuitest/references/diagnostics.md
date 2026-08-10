# Vision Pro XCUITest 故障分流

同时读取当前 Xcode 操作、设备可见状态、进程所有权和最新响应。只有实际观察到对应签名时，才采用该分流。

| 可观察签名 | 含义 | 下一步 |
| --- | --- | --- |
| Xcode 或设备工具明确报告 Vision Pro 已锁定 | 设备启动前检查被阻塞 | 请佩戴者解锁，然后继续同一个必要操作。 |
| 测试初始化报告 `Timed out while enabling automation mode.`，或头显中可见密码、UI 测试授权界面 | XCTest 没有在启动时限内得到 Vision Pro 佩戴者授权；这是 XCUITest 授权门槛，不是 App 卡死、设备普通锁定或 Mac 终端认证。出现超时的 runner 已失去建立可用会话的机会 | `ensure-session` 识别该签名并收敛：结束死 runner、保留构建、自动重启一次，连续两次超时返回 `authorizationTimeout`。剩下的动作属于佩戴者：完成头显侧授权后重跑 `ensure-session`。授权按时间更新（佩戴者实测约 8–12 小时一次，2026-08-10），不按会话次数消耗，也经受住了一次设备重启（2026-08-10）；距上次授权不足此窗口时，授权失效不是候选解释。 |
| `ensure-session` 返回 `readyTimeout` 或长时间悬挂，而 runner.log 里 **没有** `Timed out while enabling automation mode` 字样 | 未定性的会话建立失败：设备深度待机、连续 halt/重启带来的系统疲劳、连接抖动都可能，唯独不能未经验证就归因授权 | 先 `grep` runner.log 找上一行的字面签名；没有就对照授权时间节律排除授权解释，然后 halt 干净后重试一次。仍失败才升级调查（锁定状态 `devicectl device info lockState`、App 命令通道 ping、设备是否闲置过久、系统资源），已定性的一种见下一行；把新签名补进本表。宣称需要佩戴者的前置条件是观察到字面授权签名，模式相似不算数。 |
| App 的文件命令通道应答（`app-command --verb ping` ok）、持久状态已清空，而连续多个全新 runner 都停在 `Wait for <bundle> to idle`，runner.log 无授权签名 | 设备侧自动化基础设施退化：与 App 状态、当前构建、Mac 侧进程都无关（三者逐一排除后仍复现），随会话高频循环渐进出现，可偶发单次恢复再恶化（2026-08-10 定性：一夜约 20+ 次会话后出现） | 重启 Vision Pro（`devicectl device reboot`），等待重连后用一次 `ensure-session` 验证（2026-08-10 实测：重启后 32 秒就绪，且该次重启没有清除自动化授权）。矩阵 runner 连续 DRIVE_ERROR 熔断会自动跑判别器并把 `diagnosis` 与剩余 cell 清单写进 results.jsonl，按它分流后用 remaining 清单续跑。 |
| Shell 显示 `Password:` | Mac 正在等待认证；XCTest 失败后，可能来自 Xcode 的 `devicectl diagnose` 调用 `/usr/bin/sudo -- /usr/bin/true` | 在该命令所在 PTY 中完成 Mac 认证。预期会反复触发诊断认证时，在同一 PTY 中执行 `sudo -v && exec … xcodebuild …`；另一个 PTY 中预热 sudo 无效。不能把它描述成 Vision Pro 锁定。 |
| 系统权限弹窗覆盖已启动 App | 首次启动的系统权限正在阻塞 App | interruption monitor 能触达该系统 Scene 时使用它，否则请佩戴者处理可见权限。随后用新快照和一次公开操作证明 session 健康；runner 从未可用或已经失败时，从现有构建重新启动。 |
| 控制台打印 `Wait for <bundle> to idle` | XCTest 到达正常同步点 | 继续观察是否返回新快照或 session 响应。只有排除直接观察到的锁定与权限门槛后仍无进展，才标记为停滞。 |
| 可见系统权限 Scene，而通过 App 发送的事件报 `Received invalid scene ID (nil) from Accessibility` | 事件指向 App Scene，而权限属于系统 Scene | 由佩戴者处理可见权限，不再重复向系统 Scene 发送 App 坐标。 |
| 外部启动目标进程后，普通 App 窗口可读，但所有合成事件都报 `Received invalid scene ID (nil) from Accessibility` | 目标 App 不属于当前 XCTest 自动化 Scene 关系 | 结束无效会话，通过正常的 `XCUIApplication.launch()` 建立 XCTest 所有的新会话；只能截图的通道不能称为可交互。 |
| Window 控件能够接受合成事件，但 RealityKit 或沉浸表面报 `invalid activation point transform (nil)` | Window 自动化关系正常，但 XCUIAutomation 无法为该空间表面推导激活坐标变换 | 单独记录空间输入边界。产品存在真正公开的空间 Accessibility target 时使用它，否则需要佩戴者操作和直接物理证据。 |
| 元素存在但不可命中，并且层级中还有额外的大型 Window 或 Scene | 另一个产品或系统 Scene 可能遮挡画面或持有焦点 | 对照可见像素、几何范围、Scene 声明、恢复和默认启动行为；这是产品 Scene 证据，不是传输通道失败。 |
| 控制器 UI 命令返回 `stage: responseTimeout`，附现场观察清单（Mac 侧 runner 进程、设备进程表、runner 日志尾部、沉浸计数，逐项注明来源） | 文件应答没有在时限内到达；清单只陈述观察，归因是读者的判断 | 按清单区分：runner 进程消失、设备上 App 消失、日志停在授权签名，各自指向不同原因。重建用 halt 后 ensure-session，不叠加 runner。 |
| 反复进出沉浸后合成事件不再投递，或 runner 进程无声消失（2026-08-10 两次） | 进入沉浸会断开主窗口的 UIScene（探针实测：SwiftUI `onDisappear` 不触发、场景身份值不变，但 UIKit session 已断开，执行器正是靠 `mainWindowSceneIsDisconnected` 确认关闭）。XCTest 绑定的是那个被销毁的 UIScene。控制器对沉浸进入计数，随响应（`immersiveFacts`）和超时观察清单返回 | 这是 visionOS 的正常场景生命周期，不是产品缺陷，不要试图在 App 侧"保住"窗口。测试侧按此规划：跨沉浸转场的批次把每个 cell 当作可能失去输入所有权来设计，命令返回 responseTimeout 即 halt 后重建会话；不要在一个会话里无限累积沉浸往返。 |
| Device Hub 无法显示 Vision Pro，但 XCTest 截图可用 | 该观察界面不可用，XCUITest 证据通道仍然成立 | 遵循项目当前测试指引，使用 Xcode/XCTest 截图和录屏；不能把一次 Device Hub 失败泛化成设备不支持截图。 |
| 测试动作报告成功，但截图、层级或录屏没有显示请求的产品结果 | 输入交付与产品结果发生分离 | 从实际观察到的状态继续调查。只报告动作已交付，不能报告功能已通过。 |
| 系统控件有可见 label，但没有稳定 identifier | 语义表面存在，只是 identifier 查询能力不足 | 扩展通用控制器，使其按当前公开 label 和 index 选择；不能用 App 全局坐标替代，因为坐标可能落入错误 Scene。 |
| 播放器区域只剩 `PlayerUI-loadFailure-primary` / `-secondary`，工具栏与播放面板整个不存在 | 加载失败视图取代了播放控件，不是控件消失 | 先点 `PlayerUI-loadFailure-primary`（Retry）恢复播放，再召唤控件。把它当成产品状态读，不要当成层级异常。 |
| 探针文件增长到几十万行，每次取回都要等很久 | `Documents/surface-tap-probe.log` 从不自动截断，跨 App 重启持续追加 | 长批次前后各归档一次再清空（`devicectl device copy from` 取回存档，再 `copy to` 推一个空文件覆盖）。清空前先确认没有正在依赖行号偏移读取的 runner。 |

## 干净停止

用控制器的 `halt` 子命令。它先发 `stop` 让 XCTest 保存结果包，5 秒内没有确认就按仓库作用域解析控制器、`xcodebuild` 与 test-runner 进程并终止，返回 `terminated` 与 `remaining` 两张清单。`remaining` 为空才算停干净。

作用域按进程工作目录判定，因此同一项目的另一个 checkout 或 worktree 不在范围内。自行拼 `pkill` 会按名字匹配到范围外的构建。

旧 runner 尚未停止时启动新 runner，会让 session 身份、设备权限、结果包和 App 所有权变得含混。因此，干净停止是建立下一次实时闭环的一部分，不是广泛清理整台机器。
