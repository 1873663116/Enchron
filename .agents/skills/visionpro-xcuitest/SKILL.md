---
name: visionpro-xcuitest
description: 通过 XCUITest 操作真实 Vision Pro。适用于根据运行时现场进行端到端调试、读取 App 公开的诊断状态与 Accessibility 层级、埋设备内探针、截图和录屏。
---

# Vision Pro XCUITest

开始前，先阅读 UI 测试目录内最近的指引，并检查当前 runner、控制器、录屏提取器及其 `--help` 输出。Bundle ID、命令、destination 和证据位置由项目内当前文件负责。

 [references/enchron.md](references/enchron.md) 中保存了已经验证的命令形态、证据基线、权限顺序和已证伪路径。[features/README.md](features/README.md) 是 Enchron 的特性地图：每个用户可见特性一个文件，说明它是什么、用户怎么到达、什么终态算证明。只验证了便捷入口而地图列有其它入口的证明是不完整的。回归运行用 `Scripts/verification/playback_mode_matrix.py`，单点排查用现场驱动；播放 PASS 必须有像素佐证。

## 注意事项

操控真实设备的基础是，Vision Pro 目前用纸巾遮住了传感器，系统误以为是佩戴状态，因此未锁定。这样它可以让 XCUITest 执行自动化操作和实时调试，不是官方实现，目前不太稳定。
优先复用同一个当前 session，如果启动从未发布可用 session，或者权限交互已经导致测试失败，就结束该 runner，并从现有构建产物重启，不能继续等待或叠加另一个 runner。
控制器命令在前台连续发送，把一次调查所需的多步写成一批；真正需要后台的是构建和常驻 runner，等待一律依赖进程退出事件而不是定时器。实测耗时的滚动记录在 `Scripts/verification/controller_timings.json`，控制器每次成功往返自动更新。

已知问题：
- 测试初始化报告 `Timed out while enabling automation mode.` 是 XCUITest 授权门槛的签名，表示 Vision Pro 没有及时完成头显侧的自动化授权或密码确认。`ensure-session` 识别它并自动收敛（结束死 runner、保留构建、重启一次），连续两次超时返回 `authorizationTimeout` 并说明佩戴者要做的事。它不是 App 卡死，也不是 Xcode 终端中的 Mac `Password:`；
- 其他真机状态停滞通常来自 Vision Pro 锁定或 XCUITest 锁定，需要立刻提醒用户佩戴处理，而 Xcode 终端中的 `Password:` 是 Mac 端认证提示，与 Vision Pro 无关；
- Simulator 无法模拟 APP 的完整生命周期，因此必须操控真实设备，但 Apple 官方的 Device Hub 暂时无法操控 Vision Pro，也无法建立有效画面，因此不作为观察和操控通道。
- 卸载App会重置系统权限并引入首次启动流程，需要用户佩戴授权。

## 流程

所有产品状态模拟真实用户操作；非特殊情况默认不使用 hack 手段。

控制器自己驱动全程。导入媒体、开始播放、切换呈现模式、读诊断状态与层级、取回探针、截图录屏，这些都由控制器连续完成，一次调查在同一轮里走到底。

**现场驱动**指的就是这种方式：建立一个会话之后，在前台连续发控制器命令，每一步看完返回再决定下一步，不写脚本、不进后台、不等聚合结论。只有构建和常驻 runner 本身可以在后台。**单点排查**与**回归运行**的分界：追一个未定位的失败是单点排查，用现场驱动；验证一批已完成的修复有没有相互破坏（修了 A 坏了 B）是回归运行，用覆盖矩阵。矩阵的用途与成本在它的启动输出中自述。

四类事需要佩戴者，除此之外不必征询：头显侧的 XCUITest 授权与密码确认；XCTest 触达不到的系统权限 Scene；空间表面上的捏合与注视（XCUIAutomation 无法为其推导激活坐标，见 [故障分流](references/diagnostics.md)）；画面舒适度、眩晕、音质这类主观判断。需要佩戴者时，先把控制器能做的部分全部做完，再一次性说明要他做什么、你会据此读哪条证据。

1. 建立干净的自动化生命周期。确认物理设备已连接且已解锁，用控制器的 `ensure-session` 一次完成停止残留、启动专用 UI 测试、等待会话就绪，返回 `stage: ready` 才继续。它是几十秒的单次调用，在前台等它返回。目标 App 由该 runner 自己启动，并在会话期间保持常驻；只需要停止时用 `halt`。

2. 按信息量取证，顺序是产品自身公开的诊断状态、Accessibility 层级与元素属性、`XCUIScreen` 截图、录屏。诊断状态回答“为什么”，像素回答“看起来如何”；调查内部状态时默认带 `--no-screenshot`。产品把内部状态公开成某个元素的 Accessibility value 时，读它比读像素更早也更准。

3. 产品没有公开某项内部事实时，在 App 内写一条诊断探针，落到容器里的一个文件，用 `devicectl device copy from --domain-type appDataContainer` 取回。探针适合记录时序、状态机检查点和判据的逐项分解，这些正是层级和像素都表达不出的东西。当前 XcodeBuildMCP 配置只启用 simulator 工作流，LLDB 断点通道不可用，探针文件是它的替代。

4. 优先使用稳定的 Accessibility identifier。

5. 流程会保留 XCTest 录屏。截图根据需要服务于当前决策，录屏保存两条命令之间的变化。需要判断过渡、闪现、短暂遮挡、焦点变化或动画时，结束会话后提取原始录屏，合成事件和命名检查点前后的帧达到“看视频”的能力；因此能够综合判断具体情况。呈现模式切换、沉浸空间开合都属于过渡，它们在两次快照之间完成，只有录屏能还原佩戴者实际看到的顺序。
