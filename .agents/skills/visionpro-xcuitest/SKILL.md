---
name: visionpro-xcuitest
description: 通过 XCUITest 操作真实 Vision Pro。适用于根据运行时现场进行端到端调试、读取 App 公开的诊断状态与 Accessibility 层级、埋设备内探针、截图和录屏。
---

# Vision Pro XCUITest

开始前，先阅读 UI 测试目录内最近的指引，并检查当前 runner、控制器、录屏提取器及其 `--help` 输出。Bundle ID、命令、destination 和证据位置由项目内当前文件负责。

 [references/enchron.md] 中保存了已经验证的命令形态、证据基线、权限顺序和已证伪路径。
 [features/README.md] 是 Enchron 的特性地图：每个用户可见特性一个文件，说明它是什么、用户怎么到达、什么终态算证明。只验证了便捷入口而地图列有其它入口的证明是不完整的。
 [references/operation-units.md] 是回归集：产品的全部操作按操作单元分组，逐条给出驱动方式与判据。它由 `Scripts/verification/journey_units.py reference` 生成，不手工编辑。
 [references/journeys/index.md] 是回归轮次的组织层：13 条旅程（常备 10 条，J00/J05/J06 按需），由 `Scripts/verification/regression_journeys.py reference` 生成，不手工编辑。开轮先 `regression_journeys.py run open` 建台账，每条旅程读完判据即 `run verdict` 记录，收轮 `run close`；台账未收前，Stop hook 会拒绝结束回合，显式放弃用 `run abort --reason`。
 播放 PASS 必须有像素佐证。

## 注意事项

操控真实设备的基础是，Vision Pro 目前用纸巾遮住了传感器，系统误以为是佩戴状态，因此未锁定。这样它可以让 XCUITest 执行自动化操作和实时调试，不是官方实现，目前不太稳定。
优先复用同一个当前 session，如果启动从未发布可用 session，或者权限交互已经导致测试失败，就结束该 runner，并从现有构建产物重启，不能继续等待或叠加另一个 runner。
控制器命令在前台连续发送，把一次调查所需的多步写成一批；真正需要后台的是构建和常驻 runner，等待一律依赖进程退出事件而不是定时器。实测耗时的滚动记录在 `Scripts/verification/controller_timings.json`，控制器每次成功往返自动更新。

已知问题：
- Simulator 无法模拟 APP 的完整生命周期，因此必须操控真实设备，但 Apple 官方的 Device Hub 暂时无法操控 Vision Pro，也无法建立有效画面，因此不作为观察和操控通道。
- 卸载App会重置系统权限并引入首次启动流程，需要用户佩戴授权。

## 流程

所有产品状态模拟真实用户操作；非特殊情况默认不使用 hack 手段。

导入媒体、开始播放、切换呈现模式、读诊断状态与层级、取回探针、截图录屏，由控制器连续完成。

**现场驱动**指的就是这种方式：建立一个会话之后，在前台连续发控制器命令，每一步看完返回再决定下一步，不写脚本、不进后台、不等聚合结论。只有构建和常驻 runner 本身可以在后台。

四类事需要佩戴者，除此之外不必征询：XCTest 无法触达的系统权限 Scene；空间表面上的捏合与注视（XCUIAutomation 无法为其推导激活坐标，见 [故障分流](references/diagnostics.md)）；画面舒适度、眩晕、音质这类主观判断。需要佩戴者时，先把控制器能做的部分全部做完，再一次性说明要他做什么、你会据此读哪条证据。

1. 建立干净的自动化生命周期。确认物理设备已连接，用控制器的 `ensure-session` 一次完成停止残留、启动专用 UI 测试、等待会话就绪，返回 `stage: ready` 才继续。它是几十秒的单次调用，在前台等它返回。目标 App 由该 runner 自己启动，并在会话期间保持常驻；只需要停止时用 `halt`。

2. 按信息量取证，顺序是产品自身公开的诊断状态、Accessibility 层级与元素属性、`XCUIScreen` 截图、录屏。诊断状态回答“为什么”，像素回答“看起来如何”；调查内部状态时默认带 `--no-screenshot`。

3. 产品没有公开某项内部事实时，在 App 内写一条诊断探针。探针同时进系统统一日志和容器里的文件，用 `devicectl device copy from --domain-type appDataContainer` 取回文件那一份。探针适合记录时序、状态机检查点和判据的逐项分解，这些正是层级和像素都表达不出的东西。常驻会话的 App 由 runner 启动，Xcode 没有这次启动的会话记录，统一日志和调试器都够不到它，文件是唯一能取回的一份。

4. 优先使用稳定的 Accessibility identifier，提醒尚未 Accessibility 化的动作。

5. 常驻会话默认只截图不录屏（`InteractiveDeviceSession` 测试计划），空闲 30 分钟后自行结束。需要判断过渡、闪现、短暂遮挡、焦点变化或动画时，用 `--test-plan Enchron` 启动录屏会话，完成后立即 `halt` 让 XCTest 落盘 `.xcresult`，再提取原始录屏，合成事件和命名检查点前后数帧达到“看视频”的能力。呈现模式切换、沉浸空间开合都属于过渡，它们在两次快照之间完成，只有录屏能还原佩戴者实际看到的顺序。录屏暂存写在头显侧并只在测试结束时回收，因此录屏会话必须短且有明确终点。

## 回归测试

回归测试同样是现场驱动的，区别只在于粒度和顺序由操作单元决定，而不是由当下的疑问决定。

**操作单元**是一次驱动中最小的、以判据收尾的整块动作。它通常不是单步：`library.new-folder` 打开管理菜单、点新建、输入名称、确认，再检查网格上出现该文件夹，共一次调用、一个判据、数秒完成。这个粒度是回归测试可以现场驱动的前提——单个动词让你花十个往返却学不到东西，整套脚本让你等一小时只学到一个比特。读完一个单元的判据再选下一个，遇到失败就地转入单点排查，查清后回到单元序列。

单元之间的先后由各自的 `needs` 决定，不是文件顺序。前置单元失败时，依赖它的单元不产生信息，跳过并记为阻塞，不要当作通过。

每步声明驱动方式，这决定该步的通过值多少钱：
- `real` 走产品自己的 hit testing 与手势识别，是唯一能证明"用户能操作到"的方式。
- `injected` 绕过了这条路径的一部分，必须写明绕过了什么、因此对哪一类缺陷失明。它旁边的 `real` 步骤才是可达性证据。
- `setup` 与 `evidence` 自身不证明任何操作。到达某个界面和把它读回来都不是操作本身。
- `wearer` 需要佩戴者在头显里。

覆盖不靠声明，靠构造：一个步骤点了某个 identifier，它就覆盖了该 identifier 在当前呈现下的操作格；`Scripts/verification/journey_units.py` 从源码派生的可达性清单取轴，产品新增一个可交互控件的当时就会缺覆盖并失败，不必等谁想起来去改表。因此上设备之前先在本地跑它，绿了再开会话。剩下的声明只用于 identifier 字符串表达不了的东西：菜单展开、滚动、环境音量往返、断言某物不存在。

同一控件在 window 与 panorama 是两个格，因为那是对两个宿主的两次 hit test，一个通过不能替另一个作证。

另外两条回归通道回答别的问题，轴不同，不能互相替代：
- `Scripts/verification/reachability_matrix.py` 是物理可达性基线。单元问产品做对了没有，基线问操作送不送得到。它与操作单元共用同一份源码派生清单作为轴。
- `Scripts/verification/playback_mode_matrix.py` 是播放模式矩阵，轴是片源 × 呈现路径，回答某种媒体在某条路径上放不放得出来。它与操作无关。
