---
name: vp-e2e
description: 适用于根据运行时现场进行端到端调试、读取 App 公开的诊断状态与 Accessibility 层级、埋设备内探针、截图和录屏。
---

# Vision Pro 端到端调试与回归

开始任何工作之前，先检查当前 runner、控制器、录屏提取器及其 `--help` 输出。Bundle ID、命令、destination 与证据位置以项目内的当前文件为准；本文中可能漂移的值，使用前重新核对。

- [references/product.md](references/product.md)：与 lane 无关的驱动与取证事实，包括四条状态通道、元素命中陷阱、identifier 在系统容器里的存活规则、矩阵与扫描的用法。两条 lane 都适用。
- [references/simulator.md](references/simulator.md) 与 [references/device.md](references/device.md)：两条 lane 各自的通道、代价与独有的坑。
- [references/diagnostics.md](references/diagnostics.md)：故障分流表，回答观察到某个签名之后应当做什么。
- [features/README.md](features/README.md)：Enchron 的特性地图，包含基线前置、驱动约定、证据契约与各特性分册的索引。
- `Regression/operations/`、`Regression/journeys/` 与 `Regression/rubrics/`：Catalog v2 的操作能力、执行组织和验收合同。回归只能执行编译计划中的 Operation Call；不得从旧操作清单或自由叙述临时拼接步骤。

## Launch

E2E 测试默认在 visionOS 模拟器 lane 执行。只有以下两类内容必须进真机 lane，原因是模拟器缺少对应硬件能力：

- Dolby Vision 与 AV1 编码格式的播放画面。模拟器没有这两种解码器。
- 双层 MV-HEVC 的第二视图。模拟器只解基础层，无法产生立体对。

两条 lane 共用同一个常驻 XCUITest runner 与同一套控制器：`--device` 参数收到模拟器 UDID 时，控制器自行切换底层传输，上层命令形态不变。回归 runner 的目标设备由 `ENCHRON_TARGET_DEVICE` 环境变量选定，把它设为模拟器 UDID 即可将整轮矩阵移到模拟器 lane（实现见 `Scripts/verification/enchron_target.py`）。大部分调试可以在模拟器上完成，真机作为额外的取证层或二次验收点。

建立会话（模拟器 UDID 取自 `xcrun simctl list devices` 中的 Apple Vision Pro 条目）：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device <UDID> --developer-dir "$(xcode-select -p)" \
  --derived-data-path .scratch/DerivedData-<主题> \
  --output-directory .scratch/<日期>-<主题>/evidence \
  ensure-session
```

只有返回 `stage: ready` 才算建立成功。模拟器约 24 秒，真机约 26 秒。该命令走 `test-without-building` 并复用 DerivedData；源码有改动时先自行 `build-for-testing`。

如果只需要做注入式前置或状态读取，可以跳过 runner，直接以测试通道冷启 App（约 2 秒，仅模拟器有此捷径）：

```sh
SIMCTL_CHILD_ENCHRON_TEST_CHANNEL=1 \
  xcrun simctl launch --terminate-running-process <UDID> com.xiongzhipeng.XrPlayer
```

## Doctor

遇到任何执行异常时，先做这组只读检查，再决定下一步：

1. `app-command --verb ping`：通道应答会携带当前 session id，证明命令能够到达 App。
2. `app-command --verb probeStatus`：证明探针文件可写且可读回。
3. 确认**独占 runner**：同一目标在同一时刻只允许一个常驻 runner。旧 runner 未停净时，新 runner 会停在 `Writing result bundle`，而旧 runner 照常应答，整体表现为假性挂起。判别签名与处置见[产品事实](references/product.md)与[故障分流](references/diagnostics.md)。
4. 模拟器会话建立后的第一条命令可能吃满 60 秒超时，这是启动抖动，重发即可，会话保持。

如果 ping 正常而 UI 命令超时，或出现其它报错签名，对照 [references/diagnostics.md](references/diagnostics.md) 分流。

## Drive

Bug 复现与回归测试应当模拟真实用户操作，默认走产品自己的 hit testing 与手势识别。导入媒体、开始播放、切换呈现模式、读取诊断状态与层级、取回探针、截图录屏，都由控制器的子命令连续完成（`snapshot`、`tap`、`tapSequence`、`typeText`、`swipe*`、`app-command` 等，完整列表见 `--help`）。元素定位规则、菜单时序与滑动约束见[产品事实](references/product.md)；每个特性的具体驱动序列见[特性地图](features/README.md)的对应分册。

**操作单元**是一次驱动中的完整动作块，通常不是单步。例如 `library.new-folder` 包含：打开管理菜单、点新建、输入名称、确认，再检查网格上出现该文件夹——共一次调用、一个判据、数秒完成。单元之间的先后顺序由各自声明的 `needs` 决定，而不是文件顺序。前置单元失败时，依赖它的单元无法产生有效结论，应当跳过并记为阻塞，不能当作通过。

每一步都要声明驱动方式：

- `real`：走产品自己的 hit testing 与手势识别，是唯一能证明「用户能操作到」的方式。
- `injected`：绕过了这条路径的一部分，必须写明绕过了什么、因此对哪一类缺陷失明。
- `setup` 与 `evidence`：自身不证明任何操作。
- 主观感知：不进入 Agent 回归计划。无法由 Agent 判断的项目不测试，也不得在运行中等待人类裁决。

同一控件在 window 与 panorama 下的验证互不覆盖，因为那是对两个渲染宿主的两次独立 hit test，一个通过不能替另一个作证。

### 不许中途收工

回归由编译计划和 Run Controller 管理，不依赖会话 Stop hook。Main Agent 负责调度，Sidekick 只执行分配给自己的 Scenario；每个节点必须写入 `passed`、`failed`、`blocked` 或 `indeterminate` 的机器终态及其证据绑定。存在未结节点的运行不是完整回归，不能据此生成成功收据。运行入口、冻结输入和恢复规则以 `Scripts/regression/runctl.py --help` 及 `Regression/execution-protocol.md` 为准。

### 佩戴者边界

以下内容 Agent 无法测试，除此之外的问题不必征询人类：

- 真机上的手部追踪与空间表面注视加捏合。XCUIAutomation 无法为空间表面推导激活坐标，合成点击也不携带注视加捏合语义（见[产品事实](references/product.md)的通道有效范围）。注意：在模拟器 lane，Device Hub 画布把鼠标悬停映射为 Gaze、点击映射为 Pinch，空间手势因此可以不经佩戴者完成，见[模拟器 lane](references/simulator.md)。
- 真机的物理输入本身，例如 Digital Crown 的旋转与按压。模拟器 lane 不继承这条限制：Device Hub 的工具栏可以用 Mac 合成鼠标事件点击 Home 等价按钮、视角控制和其他系统控件，画布内的系统 Scene 也可以用同一输入通路操作。
- HDR 亮度、画面舒适度、眩晕、音质等主观感受。

“XCTest 触达不到”不等于“Agent 无法测试”。权限对话框、Files／Photos 选择器、Home 主菜单、控制中心等系统 Scene 在模拟器 lane 可由 Device Hub 驱动。Device Hub 默认窗口很小，任何定位或点击之前必须先放大窗口并将画布切到 fit；完整操作边界见[模拟器 lane](references/simulator.md)。

投影与立体布局不在此列：mono、SBS、TB 在 2D 截图上各自不同，结合结构化字段就可以判断输出是否正确。

## Evidence

状态与取证走四条通道加截图，各通道的语义与有效范围见[产品事实](references/product.md)：

- **诊断串**：`snapshot --identifier PlayerUI-window-control-plane` 读取产品状态快照。它只在 window、portal 及过渡的窗口阶段可读。
- **探针**：`Documents/surface-tap-probe.log` 是事件时间线；panorama 与 docked 的 settle 判定依赖它。
- **PlaybackCore 实时记录**：容器内 `tmp/playbackcore-live-debug/current.json`，用于区分「打开卡住」与「正在拉流」。
- **截图与录屏**：判读任何截图之前先看尺寸——1×1 表示捕获失败，而不是画面全黑。播放判为 PASS 必须有像素佐证。

证据落在 `--output-directory` 指定的 `.scratch/<日期>-<主题>/` 目录内；真机证据的归档规则见仓库指引。测试动作返回成功不等于功能通过：功能是否通过，以应用侧证据为最终准绳。三类证据（结构、物理、感知）的分界与看守者登记在[特性地图](features/README.md)。

## Cleanup

结束测试、排查挂起会话或启动新一轮之前，执行控制器的 `halt` 子命令：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py --device <UDID> halt
```

返回的 `remaining` 列表为空才算停净。进程解析严格限定在本仓库作用域内，同项目的其它 checkout 不受波及；自行拼写的 `pkill` 会按进程名误伤范围之外的构建，不要使用。停止时序的细节见[故障分流](references/diagnostics.md)的干净停止一节。

长批次测试前后各归档一次探针文件并清空。清理只针对本轮拉起的进程与草稿状态；已捕获的证据文件必须保留在原路径。

## Helpers

另有两条回归通道，它们回答的问题与操作单元不同，三者不能互相替代：

- `Scripts/verification/reachability_matrix.py` 是物理可达性基线。操作单元问的是「产品做对了没有」，可达性基线问的是「操作送不送得到」。它与操作单元共用同一份源码派生清单作为轴。
- `Scripts/verification/playback_mode_matrix.py` 是播放模式矩阵，轴是片源 × 呈现路径，回答「某种媒体在某条路径上放不放得出来」。它与具体操作无关。

其余工装：`playback_open_sweep.py` 做宽度优先的多片源扫描；`extract_visionpro_ui_recording.py` 从 `.xcresult` 提取录屏；Catalog 由 `Config/regression/catalog-v2.json` 经 `Scripts/regression/materialize_catalog_v2.py` 生成。
