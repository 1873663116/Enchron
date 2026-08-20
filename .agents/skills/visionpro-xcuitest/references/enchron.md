# Enchron Vision Pro 自更新运行手册

这是 `/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron` 的证据缓存。使用前重新核对检查成本低、可能漂移的值；除非新的设备证据推翻，保留这里已经验证的生命周期。

## 现有基础设施

- 常驻 XCTest runner：`Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift`
- Mac 实时控制 VP：`Scripts/verification/interactive_visionpro_ui.py`
- `.xcresult` 录屏恢复与联系表生成器：`Scripts/verification/extract_visionpro_ui_recording.py`
- Xcode：`/Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer`
- 2026-08-09 最后核对的物理设备：CoreDevice ID 为 `59E3D57A-0288-53DC-9A7D-B657B6939558`，Xcode destination ID 为 `00008142-001871A11491401C`

使用脚本前先读取其 `--help`。当前控制器在每条命令后返回界面层级、App 状态、匹配元素观察、session 身份，以及可选的本地 PNG。

实测耗时的滚动记录在 `controller_timings.json`，控制器每次成功往返自动更新（2026-08-09 基线：session 健康时一条 `snapshot --no-screenshot` 往返 2.3 到 2.5 秒）。据此在前台连续发命令。命令长时间不返回时控制器返回 `responseTimeout` 与现场观察清单，按 [故障分流](diagnostics.md) 对应行处理。

## 诊断状态通道

`PlayerUI-window-control-plane` 元素的 Accessibility value 是一条分号分隔的诊断串，字段在 `Apps/Enchron/MainView.swift` 里拼装，以那里为准。它同时给出呈现状态与切换、待执行平台效果、沉浸空间驻留与生命周期修订、表面准备阶段、渲染器消费者、组件渲染状态、格式来源与投影，以及平台执行器的最后一次操作、检查点和结论。排查呈现切换、表面附着和格式协商时先读它，它比层级和像素都先说话。

`snapshot --identifier PlayerUI-window-control-plane` 返回的 `matchedElement.value` 是完整串；层级文本里的同一行会被 XCTest 截断。

App 内探针写入 `Documents/surface-tap-probe.log`，取回：

```sh
xcrun devicectl device copy from --device <CoreDevice ID> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.XrPlayer \
  --source Documents/surface-tap-probe.log --destination <本地路径>
```

探针适合记录诊断串给不出的东西：事件时序、沉浸空间开合时刻、settle 判据的逐项布尔分解、手势是否被投递。诊断串是状态快照，探针是时间线，两者互补。

PlaybackCore 自己还写第三条通道，无需改代码就能取：每个媒体会话在 App 容器的
`tmp/playbackcore-live-debug/<mediaSessionID>/` 下留 `events.jsonl` 与 `snapshot.json`，
根部的 `current.json` 指向最新一个。除非环境变量
`ENCHRON_VERIFICATION_DISABLE_PLAYBACK_DEBUG_RECORDER=1`（只有
`VisionProDeviceAcceptanceUITests` 这么设），常驻交互会话里它是开的。

```sh
xcrun devicectl device copy from --device <CoreDevice ID> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.XrPlayer \
  --source tmp/playbackcore-live-debug/current.json --destination <本地路径>
```

它回答"卡在打开的哪一步"：一个停在 Loading 的会话如果 `events.jsonl` 只有
`source.acquired` 和 `open.admitted` 两条，说明线程还堵在 FFmpeg 的 reader open 里，
既没读到流信息也没失败。诊断串此时只显示 `lifecycle=Loading`，说不出停在哪。
`devicectl device info files` 的列表很长，按 `playbackcore` 过滤。

通道有效范围（2026-08-09 真机证实）：settled 的沉浸呈现里主窗口仍然开着但完全空掉，`PlayerUI-window-control-plane`、PlayerPanel、顶部动作、媒体库全部不在层级里。因此诊断串只在 window/portal 及过渡的窗口阶段可读；判定 panorama/docked 的 settle 一律轮询探针文件。沉浸空间的 SwiftUI attachment（如 `PlayerUI-immersive-playback-surface`）是例外：它出现在层级里且报告 isHittable，但对它 `tap --identifier` 会返回 Element tapped 而 App 的空间手势收不到任何投递——合成点击不携带注视加捏合语义，success 不等于送达，投递与否只有探针文件说了算。佩戴者的真实捏合仍是空间手势唯一的触发方式。

`Scripts/verification/playback_mode_matrix.py` 是按上述通道分工实现的播放模式矩阵 runner（cell = clip × path × rep，每 cell 独立 ensure-session，verdict 落 results.jsonl）；跑覆盖矩阵先用它，别重写轮询逻辑。

每 cell 一次 ensure-session 只在整轮矩阵独占设备时成立。新 runner 落地时旧 runner 仍常驻，两者争用设备：新 cell 的 runner 停在 `Writing result bundle`，从不开始自己的测试，而旧 runner 照常应答 preamble 和 tap，于是 cell 看起来打开成功随后挂起，报出产品并未造成的 settle 超时。判别签名是该 cell 的 `controller/runner.log` 没有任何 `t = …s` 行，而同一 cell 的命令全部返回成功。

因此**一次调查只能有一个常驻 runner**。宽度优先的扫描（同一路径跑很多片源）用 `Scripts/verification/playback_open_sweep.py`：它只建立一次会话且从不重建，每片源按 relaunch、resetState、push、importMedia、tap 顺序驱动，实测合计 13 秒。判据先读诊断串（约 2 秒往返），只有诊断串连续数次读不到（沉浸落地的签名）才去取探针文件；把容器拷贝放在每次轮询开头，会让单次迭代吃掉整个 settle 期限。

`devicectl` 的 `appDataContainer` 拷贝在目标 App 未运行时不会失败而是长时间挂起，因此拷贝超时不等于 App 崩溃；App 是否存活用 `process launch --console` 判断，`device info processes` 列的是可执行文件路径（`Enchron`），不是 bundle id。

## 控制器取证陷阱

`XCUIScreen.main.screenshot()` 在当前 visionOS 构建上返回 1×1 图像（4232 字节，仅 ICC 数据），runner 照常写文件、控制器照常报成功，肉眼看是一张黑图。runner 已改为屏幕图像退化时回退到 application 元素捕获。**判读任何截图前先看尺寸**：正常是 1920×1080、0.5 到 2.8 MB；1×1 表示捕获失败而不是画面全黑。该回退也能捕获沉浸空间内容。

`app-command` 当前支持的动词以 `Apps/Enchron/TestCommandChannel.swift` 为准。没有退出沉浸的动词，用 `relaunch` 回到干净状态。

侧栏源条目 `FileBrowsing-SourcesSidebar-source-<id>` 下挂着删除按钮、图标与文本三个元素共享同一 identifier，`tap --identifier` 命中的是删除按钮。选中源要按 label 或 `--index`。

播放中 chrome 自动隐藏快于两次控制器往返，`PlayerUI-InfoBar-button-back` 等按钮会报 exists 但 isHittable 为假。格式编辑器一次开合也活不过两次往返：用 `tapSequence` 把 `PlayerUI-TopAction-videoFormat`、投影项、`PlayerUI-VideoFormat-apply` 连发，或直接读 `tap` 自己返回的层级而不是再发一次 snapshot。

合成滑动一律带 `--identifier`。省略 identifier 时滑动目标退化为 Application 元素，而 visionOS 的 Application 元素不归属任何单一 Scene，合成事件取不到目标 Scene，三次重试全败后失败记到常驻测试方法上，方法结束并拆除 App——表现为 TEST EXECUTE FAILED、设备进程表无 Enchron，但两端进程都没有崩溃，那是正常拆除。与页面无关：Emby 从未打开时同样必死。带 identifier 的滑动在 Emby 各页与整窗具名元素上均正常。定性证据见 docs/plans/04-regression-journeys/emby-poster-wall-scroll.md。

Emby 播放入口：首页"接下来看"横条的 `Emby-StillCard-<id>` 打开单集详情，可视区内有 `Emby-Detail-Resume` 与 `Emby-Detail-PlayFromBeginning`。系列详情页按设计不提供播放按钮（`isPlayable` 对 series/season/boxSet 返回 false），播放入口是下方选集面板的 `Emby-Episode-<id>` 卡片，点击直接进入播放，不经三级详情页。折叠线以下的剧集条需先带 identifier 滚动。海报横条只有可视区内的卡可点，靠右的卡 tap 返回 False。

label 为 "Play button on a TV, filled" 的图标是导航栏 Emby 页签（identifier `Emby-Navigation-Tab`，命名与 `Navigation-Ornament-tab-files`/`-settings` 不同族），不在系列详情页；已在 Emby 页签上再点它无可观察效果是正确行为。

播放控制面板前缀是 `PlayerPanel-`（play、forward 等），与 `PlayerUI-` 顶栏不同族。跳转用 `PlayerPanel-button-forward`；进度条拖动是佩戴者专属（200ms 稳定按住的状态机）。More 菜单里 Subtitles 有 identifier（`PlayerUI-menu-subtitles`），Audio Track 及音轨条目无 identifier，按 label 命中，且菜单活不过两次往返，读 tap 自身返回的层级。同名条目（如两条 `und · aac · 2ch` 音轨）用 `--label` 加 `--index` 组合。

SwiftUI 只在系统容器把内容提升为一等 action 时保留 `.accessibilityIdentifier`，否则丢弃。2026-08-21 真机双向确认：`.alert` 里的 Button 保留 identifier（`MediaLibrary-NewFolder-create` 在层级中），同一 alert 里的 TextField 丢弃（源码声明了 `MediaLibrary-NewFolder-name`，层级里只剩 `placeholderValue`）；`Menu` 里的 Button 保留（Settings 五个菜单宿主），`Menu` 里 inline `Picker` 的 `Text` 行丢弃（给排序菜单五行逐个加 identifier 后重建，层级完全不变）。因此这两类元素只能按 label 或 placeholder 命中，给它们加 identifier 是无效改动。控制器的 `element(for:)` 早已支持 `--label`，`textInputElement` 现在也依次尝试 identifier、label、placeholderValue。排序菜单按 `--label "Date Modified"` 命中并真实改变选中项。

面包屑 `MediaLibrary-Breadcrumb-current` 打开的层级菜单，其行同样只有 label（"Media Library"、"Media Library / Unit Folder"）。

`typeText` 优先带 `--identifier`：runner 解析目标元素后自己先 tap 再输入。系统容器丢弃 identifier 的字段改带 `--label`（值取 placeholder，如 `--label "Folder name"`）；两者都不带时返回"无匹配元素"，字段保持为空且没有别的失败信号。SMB 连接表单可全程合成驱动，使用 `FileBrowsing-SourceConnection-smb-` 前缀；WebDAV 使用 `FileBrowsing-SourceConnection-webDAV-` 前缀。字段与按钮的完整集合以 [远程来源特性](../features/remote-source-connection.md) 为准。首次凭据连接后系统弹"保存密码?"对话框，`tap --label '以后'` 可以合成关掉，不属于必须佩戴者的权限 Scene。从播放器退出后浏览位置回到 Media Library 根，重进远程目录要从侧栏重走。

## 测试媒体

`TestMedia` 中分辨率足够的 180° 片源部分是成人内容。层级与诊断状态足以回答绝大多数问题，只有当结论确实取决于像素时才截图。需要目视确认时，先与佩戴者确认使用哪个片源。

## 建立会话

用控制器的 `ensure-session`。它内部完成 halt、启动常驻 runner、等待新 `sessionID` 发布、并用一次 `snapshot` 证明会话可用，返回 `stage: ready` 才算成立。已验证的启动形态由脚本的默认参数承载，以 `--help` 为准；2026-08-09 实测 25.7 秒返回。

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device 00008142-001871A11491401C \
  --developer-dir /Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer \
  --output-directory <证据目录> \
  ensure-session
```

当前源码只构建一次。`ensure-session` 走的是 `test-without-building`，复用同一 DerivedData，不在单步命令之间重复构建 Enchron；源码改动后先自行 `build-for-testing`。

授权超时签名由 `ensure-session` 自行识别并收敛（自动重启一次，连续两次返回 `authorizationTimeout` 并说明佩戴者动作）；`readyTimeout` 的返回自带观察清单（签名检索结果与日志尾部），按 [故障分流](diagnostics.md) 区分其它停滞，不叠加第二个 runner。

Mac 侧 Xcode 诊断认证可能打印 `Password:`；它与 Vision Pro 解锁和头显侧 UI 测试密码无关，认证失败也不影响 runner 常驻。

runner 继续常驻；在有意重启之前，后续命令应保持同一个 session ID。

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
