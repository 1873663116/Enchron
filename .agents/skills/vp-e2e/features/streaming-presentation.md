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

从主窗口的Moonlight 标签页选中一台已配对主机，应用网格里点一个应用卡片启动会话。会话窗口出现在佩戴者面前。

窗口顶栏左侧是复用的「返回」控件，右侧是 `PlayerUI-TopAction-dock`。点 Dock 打开环境菜单，选一个环境进入 docked；在沉浸呈现里用控件面板上的 exit 返回窗口。

关闭窗口走系统窗口关闭手势。窗口消失即会话结束，没有第二个确认步骤。

## Driving it with computer use

Preconditions: 模拟器已启动并装有带测试通道的 Enchron；主机为已配对状态。

呈现转场由真实指针动作触发。需要注视与捏合的动作走 Device Hub：用 computer use 在 Device Hub 画布上合成鼠标事件，坐标取自 `simctl io <UDID> screenshot` 的原图。需要这类动作的场景在目录里按跳过登记，不生成端到端单元。

```sh
# 每次指针动作前后各看一次画面
xcrun simctl io <UDID> screenshot /tmp/sim-before.png
# 用 computer use 在模拟器窗口里点一下
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
- **空间手势经 Device Hub 确认。** 一次点击能否到达空间表面，靠动作后的画面与产品探针判定；XCUITest 目录不覆盖这一段。

## 本轮补齐范围（2026-10-26 裁决）

范围、阶段与验收见 `docs/reviews/streaming-port-review/plan.md`。

纳入：

- 串流会话向系统申请显示模式：用协商到的帧率与 HDR 色彩空间构造显示判据，经文件播放同一条 `AVDisplayManager` 通道提交，结束时释放；播放器侧探针 `displayCriteria requestedHz=…`，会话侧探针 `display criteria frameRate=… hdr=…`。
- 失败态的呈现：分类标题、恢复建议、重试入口；启动失败弹窗，串流中失败走窗口内浮层。
- 串流相关文案进入本地化目录：138 条文案按中文原文为键，补齐七种语言；设置行、菜单项与动态失败文案都走目录查表。
- 会话统计浮层在画面左上角，identifier `Stream-Session-stats`。

不做：串流退出按钮与退出确认（结束串流仍只有关闭窗口一条路）、控制面板增加槽位、画面缩放模式。
