# 故障分流

使用本表前，先同时读取四类现场信息：当前 Xcode 操作、目标的可见状态、进程所有权与最新响应。只有实际观察到对应签名时，才采用该行的分流；模式相似不构成依据。

本表回答「观察到 X 之后做什么」；「该 lane 的常态是什么」归[模拟器 lane](simulator.md) 与[真机 lane](device.md)。lane 列标注该签名可能出现的一侧。

| lane | 可观察签名 | 含义 | 下一步 |
| --- | --- | --- | --- |
| 两条 | `ensure-session` 返回 `readyTimeout` 或长时间悬挂 | 尚未定性的会话建立失败。设备深度待机、连续 halt 与重启带来的系统疲劳、连接抖动都有可能 | halt 干净后重试一次。仍然失败则升级调查（`devicectl device info lockState`、App 命令通道 ping、设备闲置时长、系统资源）。已定性的一种情况见下一行；发现新签名时补进本表。 |
| 真机 | App 命令通道应答正常（`app-command --verb ping` 返回 ok）、持久状态已清空，而连续多个全新 runner 都停在 `Wait for <bundle> to idle` | 设备侧自动化基础设施退化。它与 App 状态、当前构建、Mac 侧进程均无关（三者已逐一排除后仍复现），随会话高频循环渐进出现，可能偶发单次恢复后再度恶化（2026-08-10 定性：一夜约 20 余次会话后出现） | 重启 Vision Pro（`devicectl device reboot`），重连后以一次 `ensure-session` 验证恢复。矩阵 runner 在连续 DRIVE_ERROR 熔断时会自动执行判别器，把 `diagnosis` 与剩余 cell 清单写入 results.jsonl；按其分流后，以 remaining 清单续跑。 |
| 真机 | Shell 显示 `Password:` | Mac 正在等待管理员认证。XCTest 失败后，它可能来自 Xcode 调用 `devicectl diagnose` 触发的 `/usr/bin/sudo -- /usr/bin/true` | 在该命令所在的 PTY 中完成 Mac 认证。预期会反复触发时，在同一 PTY 中执行 `sudo -v && exec … xcodebuild …`；在另一个 PTY 中预热 sudo 无效。该签名与 Vision Pro 锁定无关。 |
| 真机 | 系统权限弹窗覆盖已启动的 App | 首次启动的系统权限请求正在阻塞 App | interruption monitor 能触达该系统 Scene 时使用它，否则请佩戴者处理可见权限。随后以一次新快照加一次公开操作证明 session 仍然健康；若 runner 从未可用或已失败，从现有构建重新启动。 |
| 两条 | 控制台打印 `Wait for <bundle> to idle` | XCTest 到达了正常的同步点 | 继续观察是否返回新快照或 session 响应。只有在排除了直接观察到的锁定与权限门槛之后仍无进展，才标记为停滞。 |
| 真机 | 可见系统权限 Scene，而经 App 发送的事件报 `Received invalid scene ID (nil) from Accessibility` | 事件指向的是 App Scene，而权限弹窗属于系统 Scene | 交由佩戴者处理可见权限。 |
| 两条 | 外部启动目标进程后，普通 App 窗口可读，而所有合成事件均报 `Received invalid scene ID (nil) from Accessibility` | 目标 App 不属于当前 XCTest 的自动化 Scene 关系 | 结束无效会话，经 `XCUIApplication.launch()` 建立由 XCTest 拥有的新会话。只能截图的通道不构成可交互。 |
| 两条 | Window 控件可以接受合成事件，而 RealityKit 或沉浸表面报 `invalid activation point transform (nil)` | Window 侧的自动化关系正常；XCUIAutomation 无法为该空间表面推导激活坐标变换 | 单独记录这条空间输入边界。产品存在真正公开的空间 Accessibility target 时使用它；模拟器 lane 可用 Device Hub 鼠标映射（见[模拟器 lane](simulator.md)）；真机上需要佩戴者操作与直接物理证据。 |
| 两条 | 元素存在但不可命中，且层级中另有大型 Window 或 Scene | 另一个产品或系统 Scene 可能遮挡了画面或持有焦点 | 对照可见像素、几何范围、Scene 声明、恢复与默认启动行为判定。这属于产品 Scene 证据，区别于传输通道失败。 |
| 两条 | 控制器 UI 命令返回 `stage: responseTimeout`，附带现场观察清单（Mac 侧 runner 进程、设备进程表、runner 日志尾部、沉浸计数，逐项注明来源） | 文件应答未在时限内到达。清单只陈述观察，归因由读者作出 | 按清单区分：runner 进程消失、设备上 App 消失，各自指向不同原因。经 halt 后 ensure-session 重建，保持单一 runner。 |
| 真机 | 反复进出沉浸后合成事件停止投递，或 runner 进程无声消失（2026-08-10 出现两次） | 进入沉浸会断开主窗口的 UIScene（探针实测：SwiftUI 的 `onDisappear` 不触发、场景身份值不变，而 UIKit session 已断开，执行器正是靠 `mainWindowSceneIsDisconnected` 确认关闭），而 XCTest 绑定的正是被销毁的那个 UIScene。这是 visionOS 正常的场景生命周期。控制器会对沉浸进入计数，随响应（`immersiveFacts`）与超时观察清单一起返回 | 测试侧据此规划：跨沉浸转场的批次把每个 cell 都视为可能失去输入所有权；命令返回 responseTimeout 即 halt 后重建会话；单个会话内的沉浸往返保持有限次数。 |
| 真机 | Device Hub 无法显示 Vision Pro 画面，而 XCTest 截图可用 | 该观察界面在真机上不可用；XCUITest 证据通道仍然成立 | 使用 Xcode 与 XCTest 的截图和录屏。该失败的范围仅限真机的 Device Hub。 |
| 两条 | 测试动作报告成功，而截图、层级或录屏未显示请求的产品结果 | 输入交付与产品结果发生了分离 | 从实际观察到的状态继续调查。此时可以报告的是「动作已交付」；功能是否通过尚待证据。 |
| 两条 | 系统控件有可见 label 而无稳定 identifier | 语义表面存在，identifier 查询能力不足 | 扩展通用控制器，按当前公开的 label 与 index 选择。坐标可能落入错误 Scene，App 全局坐标不构成替代。 |
| 两条 | 播放器区域只剩 `PlayerUI-loadFailure-primary` 与 `-secondary`，工具栏与播放面板整体缺席 | 加载失败视图取代了播放控件 | 先点 `PlayerUI-loadFailure-primary`（Retry）恢复播放，再召唤控件。这是产品状态，区别于层级异常。 |
| 两条 | 探针文件增长到几十万行，每次取回耗时很长 | `Documents/surface-tap-probe.log` 持续追加、没有自动截断 | 长批次前后各归档一次并清空（`devicectl device copy from` 取回存档，再 `copy to` 推一个空文件覆盖）。清空前确认没有 runner 正依赖行号偏移读取。 |
| 模拟器 | 会话建立后的第一条命令吃满 60 秒应答超时，第二条正常返回 | 模拟器侧的启动抖动 | 重发该命令即可，会话保持。 |
| 模拟器 | Device Hub 画布上的点击既不产生探针行，也不产生任何界面反应，但视角或窗口几何发生了变化 | 画布输入模式停在「移动相机」一档，点击被相机操作吞掉 | 切到画布底部工具栏第二组的第一个按钮（指针）。`device_hub_canvas.py` 的 `gaze`/`pinch`/`enlarge` 每次都会先按它，无需手工处理。 |
| 模拟器 | Device Hub 画布上的 cliclick 全部返回成功，而应用侧探针一行不增 | Device Hub 不在前台，合成事件落到了别的应用，没有任何报错 | 用 `Scripts/verification/device_hub_canvas.py` 驱动，它在每次指针动作前断言前台应用并拒绝空发。手工发命令时，任何 `osascript activate` 或人手点终端都会夺焦，必须重新前置。 |
| 两条 | `pgrep -x smbd` 无结果，而 `sharing -l` 显示共享点配置正确 | 无信息。macOS 的 smbd 由 launchd 按连接拉起，无客户端连接时本就不存在，与文件共享是否开启无关 | 改用 `Scripts/verification/journey_preflight.py smb`：它探 445 端口并真正挂载一次，读到片源才算就绪。不要据进程表判断 SMB 可用性。 |
| 两条 | 内容条件被判为「全库找不到某类样片」 | 多半是扫描范围或判据不对，而不是样片不存在 | 用 `Scripts/verification/journey_preflight.py audio-fixtures` 这类确定性检查复核后再落判决。2026-08-26 的 J08 就是漏扫了 `TestMedia/TestVectors/` 而误记 voided，纯音频与带封面样片一直都在。 |
| 模拟器 | `tap --identifier` 报「无匹配元素」，而该元素本应在播放器 chrome 上 | 控件已自动隐藏并退出层级 | 以 App 命令通道的 `toggleControls` 召唤，其应答直接给出召唤后的可见状态。 |
| 画布宽高比自检报出远大于 1.78 的值，或画布明显小于窗格 | Device Hub 工具栏缩放停在 1:1，画布不随窗口长大 | 切到 fit 挡位；画布从 850 点变为 1729 点，指点容错同步放大 |
| 空间点击落到窗口表面碰撞体而非顶栏按钮 | 先怀疑画布过小导致的瞄偏，而不是排除带与命中范围不符 | 在 fit 画布上复测；命中按钮时 `spatialTap` 计数不增，这一条就是判据 |

## 干净停止

停止会话用控制器的 `halt` 子命令。它先发送 `stop` 并唤醒 runner，最多等待 30 秒确认退出；随后给 `xcodebuild` 最多 180 秒的退出窗口，使 `.xcresult` 与录屏落盘；仍未退出的进程按仓库作用域解析（控制器、`xcodebuild` 与 test-runner），先 SIGTERM、5 秒后强杀，最终返回 `terminated` 与 `remaining` 两张清单。`remaining` 为空才算停净。各时限以 `interactive_visionpro_ui.py` 顶部的常量为准。

作用域按进程的工作目录判定，因此同一项目的另一个 checkout 或 worktree 不在清理范围内。自行拼写的 `pkill` 会按进程名匹配到范围之外的构建，不要使用。

干净停止是建立下一次实时闭环的组成部分：它的目标是让 session 身份、设备权限、结果包与 App 所有权始终保持单一归属。
