# Enchron Vision Pro 自更新运行手册

这是 `/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron` 的证据缓存。使用前重新核对检查成本低、可能漂移的值；除非新的设备证据推翻，保留这里已经验证的生命周期。

## 现有基础设施

- 常驻 XCTest runner：`Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift`
- Mac 实时控制 VP：`Scripts/verification/interactive_visionpro_ui.py`
- `.xcresult` 录屏恢复与联系表生成器：`Scripts/verification/extract_visionpro_ui_recording.py`
- Xcode：`/Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer`
- 2026-08-09 最后核对的物理设备：CoreDevice ID 为 `59E3D57A-0288-53DC-9A7D-B657B6939558`，Xcode destination ID 为 `00008142-001871A11491401C`

使用脚本前先读取其 `--help`。当前控制器在每条命令后返回界面层级、App 状态、匹配元素观察、session 身份，以及可选的本地 PNG。

## 已验证的启动形态

当前源码只构建一次。只重启常驻测试时，复用同一 DerivedData 并执行 `test-without-building`，不能在单步命令之间重复构建 Enchron。曾通过真实 Files 选择器完成导入、且没有产品状态注入的成功会话使用了以下形态：

```sh
sudo -v && exec env \
  DEVELOPER_DIR=/Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer \
  /Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer/usr/bin/xcodebuild \
  test-without-building \
  -project Enchron.xcodeproj \
  -scheme Enchron \
  -testPlan Enchron \
  -configuration Debug \
  -destination 'platform=visionOS,id=00008142-001871A11491401C' \
  -derivedDataPath <包含当前构建的 DerivedData> \
  -clonedSourcePackagesDirPath /Volumes/Cortisol/DevSpace/Xcode/Enchron/SourcePackages/VisionProCoreRegression \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:EnchronAppUITests/InteractiveDeviceUITests/testInteractiveDeviceSession \
  -resultBundlePath <新的证据目录>/Interactive.xcresult
```

开头的 `sudo -v` 只服务于 Mac 侧 Xcode 诊断认证，并且必须与 `xcodebuild` 共用一个 PTY。它与 Vision Pro 解锁或头显侧 UI 测试密码无关。

启动后，先通过控制器执行 `snapshot`。只有它返回 `success: true`、`runningForeground`、新的 `sessionID` 和当前层级时，才开始操作。runner 继续常驻；在有意重启之前，后续命令应保持同一个 session ID。

## 首次安装顺序

卸载 Enchron 会重置系统权限。干净安装至少曾出现以下系统 Scene：

1. 初始启动时出现“手部结构与动作”。向这个权限卡发送 Enchron App 坐标曾报 `invalid scene ID (nil)`，需要佩戴者允许。如果 runner 已失败或从未发布可用快照，停止它，只从现有构建重新启动交互测试。
2. 打开媒体管理流程后出现“允许 Enchron 访问四周”。历史成功运行中，佩戴者允许后，同一个健康 session 继续工作。继续发送命令前始终先请求新快照。

常规清理不卸载 App。只有请求的验收对象本身是干净安装行为时才卸载；其他情况只停止当前范围内的控制器与 runner 进程。

## 证据基线与边界

- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/true-user-panorama-repro-20260808-191108/true-user-session-after-permission.xcresult` 证明：没有产品状态注入的常驻 session 可以点击 Enchron 导入菜单，并通过真实 Files 选择器依次进入 iCloud Drive、Desktop、TestMedia、Samples、Spatial、Panorama 和 `insta360.mp4`。
- 同目录的 `true-user-session-imported.xcresult` 证明 Window 链路可以完成媒体选择、播放表面、Video Format、360° 和 Apply。它随后在沉浸空间 `Playback surface` 上报 `invalid activation point transform (nil)`，因此不能证明 XCUIAutomation 可以捏合任意 RealityKit 全景表面。
- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/interactive-panorama-repro-20260808/InteractivePanoramaRepro.xcresult` 是交互和切换成功基线，但其启动使用了回归状态控制，因此不是干净的普通用户启动基线。
- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/spatial-cutover-clean-20260809-rDPQwJ`、`spatial-cutover-system-ui-20260809-ezINUY` 和 `spatial-cutover-live-20260809-9Zue7Q` 证明截图或层级可以工作，而输入所有权仍然无效。不能复用这些会话采用的外部启动路径。

这台 Vision Pro 支持通过 XCUITest/Xcode 截图。当前环境中的 Device Hub `View Screen` 没有产生可用画面；这个限制不适用于 `XCUIScreen` 截图或 `.xcresult` 录屏。

## 已证伪路径

- 通过 `devicectl device process launch --terminate-existing` 启动目标 App，再尝试由常驻 runner 控制：可以读取像素和层级，但输入没有有效的 App Scene 身份。
- 对系统权限或 Files 选择器控件重复发送 App 全局坐标：可能命中错误 Scene。使用语义 identifier 或可见 label；XCTest 无法触达系统权限时，由佩戴者处理。
- 旧 runner 未干净停止时启动新 runner：会让 session 身份、权限、结果包和目标 App 所有权变得含混。
- 看到 `Wait for com.xiongzhipeng.XrPlayer to idle` 就判定失败：历史成功快照和点击前也出现过同一行。
- 在不同于 `xcodebuild` 的 PTY 中执行 `sudo -v`：不能覆盖 Xcode 随后启动的 `devicectl diagnose` 认证。

