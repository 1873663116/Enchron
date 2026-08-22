# 物理 Vision Pro lane

## 目标身份

2026-08-09 最后核对：CoreDevice ID `59E3D57A-0288-53DC-9A7D-B657B6939558`，Xcode destination ID `00008142-001871A11491401C`。设备更换后以 `xcrun devicectl list devices` 为准。

自动化成立的前提是该设备的传感器被纸巾遮挡，系统据此判定处于佩戴状态而不锁定。此方式非官方实现，本身不稳定。

## 建立会话

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device 00008142-001871A11491401C \
  --developer-dir "$(xcode-select -p)" \
  --output-directory <证据目录> \
  ensure-session
```

`ensure-session` 内部完成 halt、启动常驻 runner、等待新 `sessionID` 发布，并以一次 `snapshot` 证明会话可用，返回 `stage: ready` 方告成立。2026-08-09 实测 25.7 秒返回，在前台等待。

该命令走 `test-without-building` 并复用同一 DerivedData，单步命令之间不重复构建；源码改动后先自行 `build-for-testing`。

runner 随后常驻，在有意重启之前后续命令保持同一 session ID。停止用 `halt`，`remaining` 为空方算停净。

实测耗时的滚动记录在 `controller_timings.json`，控制器每次成功往返自动更新。2026-08-09 基线：session 健康时一条 `snapshot --no-screenshot` 往返 2.3 到 2.5 秒。

## 佩戴者授权

XCUITest 的自动化授权由佩戴者在头显内给出，按时间更新而非按会话次数消耗：实测约 8 到 12 小时一次（2026-08-10），并经受住一次设备重启。距上次授权不足该窗口时，授权失效不构成候选解释。

`ensure-session` 自行识别授权超时签名并收敛：自动重启一次，连续两次返回 `authorizationTimeout` 并说明佩戴者动作。`readyTimeout` 的返回自带观察清单，其它停滞按 [故障分流](diagnostics.md) 区分。

## 首次安装顺序

卸载 Enchron 将重置系统权限并引入首次启动流程。干净安装至少曾出现以下系统 Scene：

1. 初始启动时的「手部结构与动作」。向该权限卡发送 Enchron App 坐标曾报 `invalid scene ID (nil)`，需佩戴者允许。runner 已失败或从未发布可用快照时，先停止它，再自现有构建重新启动交互测试。
2. 打开媒体管理流程后的「允许 Enchron 访问四周」。历史成功运行中，佩戴者允许后同一健康 session 继续工作。继续发送命令前先请求新快照。

卸载 App 仅在验收对象本身为干净安装行为时执行；其余情况停止当前范围内的控制器与 runner 进程即可。

## 取回容器文件

```sh
xcrun devicectl device copy from --device <CoreDevice ID> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.XrPlayer \
  --source Documents/surface-tap-probe.log --destination <本地路径>
```

`tmp/playbackcore-live-debug/current.json` 同法取回。`devicectl device info files` 的列表很长，按 `playbackcore` 过滤。

`appDataContainer` 拷贝在目标 App 未运行时长时间挂起而非失败，故拷贝超时与 App 崩溃无对应关系。App 存活性以 `process launch --console` 判断；`device info processes` 列出的是可执行文件路径（`Enchron`）而非 bundle id。

## 截图退化

`XCUIScreen.main.screenshot()` 在当前 visionOS 设备构建上返回 1×1 图像（4232 字节，仅 ICC 数据），runner 照常写文件、控制器照常报成功，目视为一张黑图。runner 已改为屏幕图像退化时回退到 application 元素捕获，该回退亦可捕获沉浸空间内容。**判读任何截图前先看尺寸**：正常为 1920×1080、0.5 到 2.8 MB；1×1 表示捕获失败而非画面全黑。

Device Hub 的 `View Screen` 在当前环境产生不出可用画面，不作为观察通道；该限制的范围仅限于此，`XCUIScreen` 截图与 `.xcresult` 录屏不受影响。

## 录屏

常驻会话默认只截图不录屏（`InteractiveDeviceSession` 测试计划），空闲 30 分钟后自行结束。判断过渡、闪现、短暂遮挡、焦点变化或动画时，以 `--test-plan Enchron` 启动录屏会话，完成后立即 `halt` 使 XCTest 落盘 `.xcresult`，再由 `Scripts/verification/extract_visionpro_ui_recording.py` 提取。录屏暂存写在头显侧并仅在测试结束时回收，录屏会话因此必须短且有明确终点。

## 已证伪路径

- 经 `devicectl device process launch --terminate-existing` 启动目标 App，再由常驻 runner 控制：可读取像素与层级，而输入没有有效的 App Scene 身份。
- 对系统权限或 Files 选择器控件发送 App 全局坐标：可能命中错误 Scene。使用语义 identifier 或可见 label；XCTest 触达不到的系统权限交由佩戴者处理。
- 旧 runner 未干净停止时启动新 runner：session 身份、权限、结果包与目标 App 所有权将变得含混。
- 以 `Wait for com.xiongzhipeng.XrPlayer to idle` 判定失败：历史成功快照与点击前同样出现该行。
- 在异于 `xcodebuild` 的 PTY 中执行 `sudo -v`：无法覆盖 Xcode 随后启动的 `devicectl diagnose` 认证。

## 基础设施退化

设备侧自动化基础设施随会话高频循环渐进退化，签名与处置见 [故障分流](diagnostics.md)。一条常态：`devicectl device reboot` 之后 2026-08-10 实测 32 秒就绪，该次重启未清除自动化授权。
