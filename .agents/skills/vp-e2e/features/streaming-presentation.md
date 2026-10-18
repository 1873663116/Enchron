# 串流呈现

串流会话的呈现完全复用播放窗口：同一个 `Window`、同一套 window／docked／panorama 状态机、同一个 Dock 入口。窗口上只保留复用的返回控件与 Dock 控件，其余播放控制逻辑不参与串流。关闭窗口即结束会话，与文件播放同一种收口方式。

串流与文件播放的区别只在特殊化：解码、计时与输入留在串流会话自己手里，`PlaybackRuntime` 只负责渲染器与呈现。

## Sub-features

- 启动会话后窗口内出现视频，画面的呈现方式与文件播放一致。
- Dock 入口来自播放窗口自己的 `PlayerUI-TopAction-dock`，串流不另开窗口、不另造控件。
- 从 window 进入 docked：经 Dock 菜单选择观影环境，窗口收敛为沉浸呈现。
- 从 docked 返回 window：沉浸呈现退出，窗口恢复并继续呈现同一会话。
- 关闭窗口结束会话：会话进入 ended，输入释放，音频停止。
- 会话在窗口内进行时，主窗口的浏览列照常可操作。

## How to get to it (user POV)

从主窗口的串流标签页选中一台已配对主机，应用网格里点一个应用卡片启动会话。会话窗口出现在佩戴者面前。

窗口顶栏左侧是复用的「返回」控件，右侧是 `PlayerUI-TopAction-dock`。点 Dock 打开环境菜单，选一个环境进入 docked；在沉浸呈现里用控件面板上的 exit 返回窗口。

关闭窗口走系统窗口关闭手势。窗口消失即会话结束，没有第二个确认步骤。

## Driving it with computer use

Preconditions: 模拟器已启动并装有带测试通道的 Enchron；Device Hub 已打开且目标 Simulator 画布可见；画布缩放挡位在 fit，输入模式在指针挡；Device Hub 是前台应用。主机为已配对状态。

驱动这条特性的操作全部是真实指针动作，经 Device Hub 画布映射成系统的注视加捏合输入。截屏坐标取自 `simctl io … screenshot` 的原图，`--shot-width`／`--shot-height` 必须填该原图的尺寸，不是预览图尺寸。

```sh
# 每次指针动作之前先看一次屏幕，确认当前画面
screencapture -x /tmp/before.png
xcrun simctl io <UDID> screenshot /tmp/sim-before.png

# 悬停即 Gaze，点击即 Pinch
python3 Scripts/verification/device_hub_canvas.py --device <UDID> gaze  --shot-x <x> --shot-y <y> --shot-width 3840 --shot-height 2160
python3 Scripts/verification/device_hub_canvas.py --device <UDID> pinch --shot-x <x> --shot-y <y> --shot-width 3840 --shot-height 2160

# 动作后取证
xcrun simctl io <UDID> screenshot /tmp/sim-after.png
```

每个单元的收口读产品自己的探针，不读截图：

```sh
D="$(xcrun simctl get_app_container <UDID> com.xiongzhipeng.Enchron data)/Documents"
tail -20 "$D/stream-session-probe.log"
```

状态与协商值走命令通道，只作为 `evidence`，不作为操作：

```sh
./.scratch/stream-cmd.sh streamSnapshot '{}'
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 串流会话把渲染器交给 `PlaybackRuntime` 的外部会话入口，自己保留解码、计时与输入 | `PlaybackRuntime` 的外部会话单测 |
| 结构 | 窗口上只有复用的返回控件与 `PlayerUI-TopAction-dock`，不存在串流专属的 Dock 控件 | `verify_playback_runtime_ownership.py`、可达性清单 |
| 物理 | 会话进入 streaming 后，窗口呈现区域内的像素来自主机画面，不是均匀色块 | Agent 读截图 + 探针的 `video surface bind` |
| 物理 | 进入 docked 后沉浸呈现出现画面；返回 window 后窗口再次出现画面 | Agent 读截图 + 探针的 `video surface bind revision=` |
| 物理 | 关闭窗口后探针出现 `input release cause=user`、`session end reason=user`、`audio stop` | 探针 |
| 感知 | 转场是否突兀、灰闪 | **待做** |

## 证明的终态

一条完整链路要按顺序收口：窗口有画面 → 点 Dock 进入 docked → 沉浸呈现有画面 → 返回 → 窗口再次有画面 → 关闭窗口 → 探针三行齐备且会话进入 ended。

窗口呈现与 docked 呈现属于两个渲染宿主，各自需要独立的画面证据，一条通过不能替另一条作证。

## Gotchas

- **灰屏是间歇的。** 同一个二进制、同一台主机，窗口有时显示视频、有时只显示均匀灰面板。此时探针仍报 `presentationState=videoVisible`、`componentBound=true`、`displayedPixel=true`，布局参数也正常。一次出现不能当作缺陷证明，一次不出现更不能当作修复证明，必须在同一条件下重复取证。
- **`simctl io screenshot` 的原图是 3840×2160。** 传 2730×1536 之类的预览尺寸会让点击落到错误的物理位置，表现为「点击没有反应」，而命令本身全部返回成功。
- **命令通道会卡死。** 通道无响应时命令文件堆积在 `Documents/test-commands/`、`Documents/test-responses/` 没有新增。此时先清空这两个目录再重启 App，携带 `SIMCTL_CHILD_ENCHRON_TEST_CHANNEL=1` 启动。
- **启动失败不写探针。** 会话建立前的失败只把原因放进内存并渲染成窗口内的一行红字（identifier `Stream-HostDetail-error`，详情在 accessibilityValue 的 `upstreamDetail`），探针一行不增。遇到「点了没反应、探针没动静」时先区分这两种情况：事件没送达，还是送达但启动失败。
- **应用网格可能显示模拟后端的条目。** `SimulatedStreamingBackend` 提供 `Enchron Probe` 这类名称，真实 Sunshine 不提供。点中这类卡片会启动失败，与呈现缺陷无关。
- **Device Hub 必须前台。** 前台被抢走时 cliclick 的事件落到别处且不报错，画布一条探针都不增，读起来与「产品没收下点击」完全一致。
- **画布缩放挡位必须在 fit。** 停在 1:1 时画布不随窗口放大，`device_hub_canvas.py` 会以宽高比不符拒绝执行。
