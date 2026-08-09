---
name: visionpro-xcuitest
description: 通过 XCUITest 操作真实 Vision Pro。适用于根据运行时现场进行端到端调试、读取 Accessibility 层级、截图和录屏。
---

# Vision Pro XCUITest

开始前，先阅读 UI 测试目录内最近的指引，并检查当前 runner、控制器、录屏提取器及其 `--help` 输出。Bundle ID、命令、destination 和证据位置由项目内当前文件负责。

 [references/enchron.md](references/enchron.md) 中保存了已经验证的命令形态、证据基线、权限顺序和已证伪路径。

## 注意事项

操控真实设备的基础是，Vision Pro 目前用纸巾遮住了传感器，系统误以为是佩戴状态，因此未锁定。这样它可以让 XCUITest 执行自动化操作和实时调试，不是官方实现，目前不太稳定。
优先复用同一个当前 session，如果启动从未发布可用 session，或者权限交互已经导致测试失败，就结束该 runner，并从现有构建产物重启，不能继续等待或叠加另一个 runner。
Wait for <bundle> to idle` 是 XCTest 的正常同步日志。只有在设备锁定与可见权限均已排除、而且之后仍没有任何新现场返回时，才进入 App 无法收敛到空闲状态的调查；不能只凭这一行判断锁定或卡死。

已知问题：
- 测试初始化报告 `Timed out while enabling automation mode.` 是 XCUITest 授权最显著的失败信号。它表示 Vision Pro 没有及时完成头显侧的自动化授权或密码确认；按 [故障分流](references/diagnostics.md) 结束已超时的 runner，保留当前构建，在佩戴者处理授权后只启动一个新 runner。它不是 App 卡死，也不是 Xcode 终端中的 Mac `Password:`；
- 其他真机状态停滞通常来自 Vision Pro 锁定或 XCUITest 锁定，需要立刻提醒用户佩戴处理，而 Xcode 终端中的 `Password:` 是 Mac 端认证提示，与 Vision Pro 无关；
- Simulator 无法模拟 APP 的完整生命周期，因此必须操控真实设备，但 Apple 官方的 Device Hub 暂时无法操控 Vision Pro，也无法建立有效画面，因此不作为观察和操控通道。
- 卸载App会重置系统权限并引入首次启动流程，需要用户佩戴授权。

## 流程

所有产品状态模拟真实用户操作；非特殊情况默认不使用 hack 手段。

1. 建立干净的自动化生命周期。确认物理设备已连接且已解锁，按精确进程身份停止本项目残留的控制器和测试 runner，再通过 XCTest 启动一个专用 UI 测试。目标 App 必须由该 runner 自己启动，并在会话期间保持常驻。

2. 取得当前 Accessibility 层级、元素属性、App 状态和 `XCUIScreen` 截图，模拟端到端操作、调试。

3. 优先使用稳定的 Accessibility identifier。

4. 流程会保留 XCTest 录屏。截图根据需要服务于当前决策，录屏保存两条命令之间的变化。需要判断过渡、闪现、短暂遮挡、焦点变化或动画时，结束会话后提取原始录屏，合成事件和命名检查点前后的帧达到“看视频”的能力；因此能够综合判断具体情况。
