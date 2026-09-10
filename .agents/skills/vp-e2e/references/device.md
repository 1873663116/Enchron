# 物理 Vision Pro lane

## 目标身份

设备标识最后核对于 2026-08-09：CoreDevice ID 为 `59E3D57A-0288-53DC-9A7D-B657B6939558`，Xcode destination ID 为 `00008142-001871A11491401C`。设备更换后以 `xcrun devicectl list devices` 的输出为准。

## 唤醒隧道（设备不在 `list devices` 里就自己重连，不要当作阻塞）

Vision Pro 通过网络隧道（CoreDevice）连接。头显一段时间不活动后隧道会掉，此时 `xcrun devicectl list devices` 里看不到它——这不是设备离线，也不需要人去戴上或输密码（头显常插电、无密码）。直接按 CoreDevice 查询一次即可重新建立隧道：

```sh
xcrun devicectl device info details --device 59E3D57A-0288-53DC-9A7D-B657B6939558 --timeout 30
```

返回里出现 `Device State: connected`、`Boot State: booted`、`Developer Mode Status: Enabled` 即已连上；隧道地址形如 `Tunnel IP Address: fde0:...`。此后 `xcrun devicectl list devices` 会把 `00008142-001871A11491401C` 列为 `connected`。2026-09-03 实测这条命令把掉线的头显在数秒内拉回 `connected`。设备缺席时先跑这一条，连不上是重连没做，不是设备的问题。

## 建立会话

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device 00008142-001871A11491401C \
  --developer-dir "$(xcode-select -p)" \
  --execution-input <证据目录>/execution-input.json \
  --output-directory <证据目录> \
  ensure-session
```

`ensure-session` 内部依次完成：halt 清理、启动常驻 runner、等待新 `sessionID` 发布，最后以一次 `snapshot` 证明会话可用。只有返回 `stage: ready` 才算建立成功，全程在前台等待。实测耗时不稳定：`controller_timings.device.json` 的 27 个 `ensure-session` 样本（2026-08-26 至 09-03）落在 4 到 268 秒之间，单一数字不能代表这条命令的预算。

该命令走 `test-without-building` 模式并复用同一份 DerivedData，单步命令之间不会重复构建；源码有改动时，需要先自行执行 `build-for-testing`。

会话建立后 runner 常驻，在有意重启之前，后续命令保持同一个 session ID。停止会话用 `halt`，返回的 `remaining` 列表为空才算停净。

实测耗时的滚动记录在 `controller_timings.json` 中，控制器每次成功往返都会自动更新它。2026-08-09 的基线是：session 健康时，一条 `snapshot --no-screenshot` 的往返耗时 2.3 到 2.5 秒。

## 首次安装顺序

卸载 Enchron 会重置系统权限并重新引入首次启动流程。干净安装至少曾出现以下系统 Scene：

1. 初始启动时的「手部结构与动作」权限请求必须由佩戴者亲自允许。若此时 runner 已失败或从未发布可用快照，先停止它，再从现有构建重新启动交互测试。
2. 打开媒体管理流程后的「允许 Enchron 访问四周」。历史成功运行中，佩戴者允许之后即可继续工作，但继续发送命令前应先请求一次新快照。

只有当验收对象本身就是干净安装行为时才卸载 App；其余情况停止当前范围内的控制器与 runner 进程即可。

## 取回容器文件

```sh
xcrun devicectl device copy from --device <CoreDevice ID> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.Enchron \
  --source Documents/surface-tap-probe.log --destination <本地路径>
```

`tmp/playbackcore-live-debug/current.json` 用同样的方式取回。`devicectl device info files` 的文件列表很长，按 `playbackcore` 过滤。

注意一个陷阱：目标 App 未运行时，`appDataContainer` 拷贝会长时间挂起而不是报错，因此拷贝超时与 App 崩溃之间没有对应关系。App 是否存活以 `process launch --console` 判断；`device info processes` 列出的是可执行文件路径（`Enchron`），不是 bundle id。

## 截图退化

在当前 visionOS 设备构建上，`XCUIScreen.main.screenshot()` 会返回 1×1 图像（4232 字节，仅含 ICC 数据），此时 runner 照常写文件、控制器照常报成功，目视是一张黑图。runner 已改为：检测到屏幕图像退化时，自动回退到 application 元素捕获，该回退同样能捕获沉浸空间内容。**判读任何截图前先看尺寸**：正常截图为 1920×1080、0.5 到 2.8 MB；1×1 表示捕获失败，而不是画面全黑。

## 录屏

常驻会话默认只截图不录屏，因为常规执行输入指向的是以 `InteractiveDeviceSession` 测试计划构建的 xctestrun（`preferredScreenCaptureFormat: screenshots`），空闲 30 分钟后自行结束。`interactive_visionpro_ui.py` 不接受 `--test-plan` 参数：录屏与否完全由 `--execution-input`／`ENCHRON_EXECUTION_INPUT` 指向的 xctestrun 决定。需要判断过渡、闪现、短暂遮挡、焦点变化或动画时，先以 `Enchron` 测试计划（`preferredScreenCaptureFormat: screenRecording`）`build-for-testing` 出对应 xctestrun 并冻结出指向它的执行输入，再用这份执行输入启动会话，完成后立即 `halt` 促使 XCTest 落盘 `.xcresult`，再由 `Scripts/verification/extract_visionpro_ui_recording.py` 提取视频。录屏暂存写在头显本地存储，且只在测试结束时回收，因此录屏会话必须短小且有明确终点。

## 已证伪路径

以下做法均已实测行不通，不要再走：

- 经 `devicectl device process launch --terminate-existing` 启动目标 App，再由常驻 runner 接管：可以读取像素与层级，但输入没有有效的 App Scene 身份。
- 对系统权限卡或 Files 选择器控件发送 App 全局坐标：可能命中错误的 Scene。应当使用语义 identifier 或可见 label；XCTest 触达不到的系统权限交由佩戴者处理。
- 旧 runner 未干净停止时启动新 runner：session 身份、权限、结果包与目标 App 的所有权将变得含混。
- 以 `Wait for com.xiongzhipeng.Enchron to idle` 判定失败：历史成功运行的快照与点击之前同样会出现该行。
- 在异于 `xcodebuild` 的 PTY 中执行 `sudo -v`：无法覆盖 Xcode 随后启动的 `devicectl diagnose` 认证。

## 基础设施退化

设备侧的自动化基础设施会随会话高频循环渐进退化，具体签名与处置见[故障分流](diagnostics.md)。一条常态数据：执行 `devicectl device reboot` 之后，2026-08-10 实测 32 秒即重新就绪，且该次重启没有清除自动化授权。
