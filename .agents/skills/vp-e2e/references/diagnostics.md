# 故障分流

同时读取当前 Xcode 操作、目标可见状态、进程所有权与最新响应。实际观察到对应签名时方采用该分流。

本表拥有「观察到 X 之后做什么」，「该 lane 的常态是什么」归 [模拟器 lane](simulator.md) 与 [真机 lane](device.md)。lane 列标注签名可能出现的一侧。

| lane | 可观察签名 | 含义 | 下一步 |
| --- | --- | --- | --- |
| 真机 | Xcode 或设备工具明确报告 Vision Pro 已锁定 | 设备启动前检查被阻塞 | 请佩戴者解锁，继续同一个必要操作。 |
| 真机 | 测试初始化报告 `Timed out while enabling automation mode.`，或头显中可见密码、UI 测试授权界面 | XCTest 未在启动时限内取得佩戴者授权。此为 XCUITest 授权门槛，区别于 App 卡死、设备普通锁定与 Mac 终端认证；出现超时的 runner 已失去建立可用会话的机会 | `ensure-session` 识别该签名并收敛：结束死 runner、保留构建、自动重启一次，连续两次超时返回 `authorizationTimeout`。其余动作属于佩戴者：完成头显侧授权后重跑 `ensure-session`。授权节律见 [真机 lane](device.md)。 |
| 两条 | `ensure-session` 返回 `readyTimeout` 或长时间悬挂，而 runner.log 中**不含** `Timed out while enabling automation mode` | 尚未定性的会话建立失败：设备深度待机、连续 halt 与重启带来的系统疲劳、连接抖动均属可能 | 先 `grep` runner.log 查找上一行的字面签名；未命中则对照授权时间节律排除授权解释，halt 干净后重试一次。仍失败则升级调查（`devicectl device info lockState`、App 命令通道 ping、设备闲置时长、系统资源），已定性的一种见下一行，新签名补进本表。宣称需要佩戴者的前置条件是观察到字面授权签名，模式相似不构成依据。 |
| 真机 | App 命令通道应答正常（`app-command --verb ping` ok）、持久状态已清空，而连续多个全新 runner 均停在 `Wait for <bundle> to idle`，runner.log 无授权签名 | 设备侧自动化基础设施退化：与 App 状态、当前构建、Mac 侧进程均无关（三者逐一排除后仍复现），随会话高频循环渐进出现，可偶发单次恢复后再度恶化（2026-08-10 定性：一夜约 20 余次会话后出现） | 重启 Vision Pro（`devicectl device reboot`），重连后以一次 `ensure-session` 验证。矩阵 runner 连续 DRIVE_ERROR 熔断时自动执行判别器，并把 `diagnosis` 与剩余 cell 清单写入 results.jsonl，按其分流后以 remaining 清单续跑。 |
| 真机 | Shell 显示 `Password:` | Mac 正在等待认证；XCTest 失败后可能来自 Xcode 的 `devicectl diagnose` 调用 `/usr/bin/sudo -- /usr/bin/true` | 在该命令所在 PTY 中完成 Mac 认证。预期反复触发诊断认证时，在同一 PTY 中执行 `sudo -v && exec … xcodebuild …`；另一 PTY 中预热 sudo 无效。该签名与 Vision Pro 锁定无关。 |
| 真机 | 系统权限弹窗覆盖已启动 App | 首次启动的系统权限正在阻塞 App | interruption monitor 能触达该系统 Scene 时使用它，否则请佩戴者处理可见权限。随后以新快照与一次公开操作证明 session 健康；runner 从未可用或已失败时，自现有构建重新启动。 |
| 两条 | 控制台打印 `Wait for <bundle> to idle` | XCTest 到达正常同步点 | 继续观察是否返回新快照或 session 响应。排除直接观察到的锁定与权限门槛后仍无进展，方标记为停滞。 |
| 真机 | 可见系统权限 Scene，而经 App 发送的事件报 `Received invalid scene ID (nil) from Accessibility` | 事件指向 App Scene，而权限属于系统 Scene | 交由佩戴者处理可见权限。 |
| 两条 | 外部启动目标进程后普通 App 窗口可读，而所有合成事件均报 `Received invalid scene ID (nil) from Accessibility` | 目标 App 不属于当前 XCTest 自动化 Scene 关系 | 结束无效会话，经 `XCUIApplication.launch()` 建立 XCTest 所有的新会话。仅能截图的通道尚不构成可交互。 |
| 两条 | Window 控件可接受合成事件，而 RealityKit 或沉浸表面报 `invalid activation point transform (nil)` | Window 自动化关系正常，XCUIAutomation 无法为该空间表面推导激活坐标变换 | 单独记录空间输入边界。产品存在真正公开的空间 Accessibility target 时使用它，否则需要佩戴者操作与直接物理证据。 |
| 两条 | 元素存在但不可命中，且层级中另有大型 Window 或 Scene | 另一产品或系统 Scene 可能遮挡画面或持有焦点 | 对照可见像素、几何范围、Scene 声明、恢复与默认启动行为判定。此为产品 Scene 证据，区别于传输通道失败。 |
| 两条 | 控制器 UI 命令返回 `stage: responseTimeout`，附现场观察清单（Mac 侧 runner 进程、设备进程表、runner 日志尾部、沉浸计数，逐项注明来源） | 文件应答未在时限内到达；清单只陈述观察，归因由读者作出 | 按清单区分：runner 进程消失、设备上 App 消失、日志停在授权签名，各自指向不同原因。重建经 halt 后 ensure-session，保持单一 runner。 |
| 真机 | 反复进出沉浸后合成事件停止投递，或 runner 进程无声消失（2026-08-10 两次） | 进入沉浸将断开主窗口的 UIScene（探针实测：SwiftUI `onDisappear` 不触发、场景身份值不变，而 UIKit session 已断开，执行器正是靠 `mainWindowSceneIsDisconnected` 确认关闭），XCTest 绑定的正是被销毁的那个 UIScene。此为 visionOS 正常场景生命周期。控制器对沉浸进入计数，随响应（`immersiveFacts`）与超时观察清单返回 | 测试侧据此规划：跨沉浸转场的批次将每个 cell 视为可能失去输入所有权，命令返回 responseTimeout 即 halt 后重建会话，单个会话内的沉浸往返保持有限次数。 |
| 真机 | Device Hub 无法显示 Vision Pro，而 XCTest 截图可用 | 该观察界面不可用，XCUITest 证据通道仍然成立 | 遵循项目当前测试指引，使用 Xcode 与 XCTest 的截图和录屏。该失败的范围仅限 Device Hub。 |
| 两条 | 测试动作报告成功，而截图、层级或录屏未显示请求的产品结果 | 输入交付与产品结果发生分离 | 自实际观察到的状态继续调查。此时可报告的是动作已交付，功能是否通过尚待证据。 |
| 两条 | 系统控件有可见 label 而无稳定 identifier | 语义表面存在，identifier 查询能力不足 | 扩展通用控制器，按当前公开 label 与 index 选择。坐标可能落入错误 Scene，App 全局坐标不构成替代。 |
| 两条 | 播放器区域只剩 `PlayerUI-loadFailure-primary` 与 `-secondary`，工具栏与播放面板整体缺席 | 加载失败视图取代了播放控件 | 先点 `PlayerUI-loadFailure-primary`（Retry）恢复播放，再召唤控件。此为产品状态，区别于层级异常。 |
| 两条 | 探针文件增长到几十万行，每次取回耗时很长 | `Documents/surface-tap-probe.log` 持续追加 | 长批次前后各归档一次并清空（`devicectl device copy from` 取回存档，再 `copy to` 推一个空文件覆盖）。清空前确认无 runner 正依赖行号偏移读取。 |
| 模拟器 | 会话建立后的第一条命令吃满 60 秒应答超时，第二条正常返回 | 模拟器侧的启动抖动 | 重发即可，会话保持。 |
| 模拟器 | `tap --identifier` 报「无匹配元素」，而该元素本应在播放器 chrome 上 | 控件已自动隐藏并退出层级 | 以 App 命令通道的 `toggleControls` 召唤，其应答直接给出召唤后的可见状态。 |

## 干净停止

用控制器的 `halt` 子命令。它先发 `stop` 并唤醒 runner，最多等待 30 秒确认；随后给 `xcodebuild` 最多 180 秒退出，使 `.xcresult` 与录屏落盘；仍未退出的按仓库作用域解析控制器、`xcodebuild` 与 test-runner 进程，SIGTERM 5 秒后强杀，返回 `terminated` 与 `remaining` 两张清单。`remaining` 为空方算停净。各时限以 `interactive_visionpro_ui.py` 顶部常量为准。

作用域按进程工作目录判定，同一项目的另一 checkout 或 worktree 因此在范围之外。自行拼写的 `pkill` 会按名字匹配到范围外的构建。

干净停止是建立下一次实时闭环的组成部分，其目标是让 session 身份、设备权限、结果包与 App 所有权保持单一归属。
