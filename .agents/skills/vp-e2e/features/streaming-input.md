# 串流输入

会话窗口捕获佩戴者的键盘与指针输入，转发给主机。输入的送达以主机的实际反应为准，不以客户端计数为准。

## Sub-features

- 会话窗口获得焦点后，键入的文字送到主机。
- 指针移动送达主机，主机的指针跟随。
- 按住不放的按键与按钮在会话结束时全部释放，不残留。
- Dock 控件释放所有按住的输入，原因为 `control-hit`。
- 键盘捕获控件对画面不可见：它覆盖在视频之上，但不得遮挡视频。
- 外接手柄的按键、扳机与摇杆按 Moonlight 的报文字段转发；A/B/X/Y 各占一个位，方向键、肩键、摇杆按键、菜单键同样有位。
- 「交换 ABXY」打开时会话把 A 报成 `0x2000`、B 报成 `0x1000`，X 与 Y 同理；这个交换只发生在客户端。
- 手柄连接与断开各发一次到达/离开报文；会话结束时手柄状态归零。
- 「蓝牙鼠标」默认打开；打开时会话直接转发外接鼠标的相对移动、左/右/中键与滚轮，同一时间窗口的注视与捏合指针路径被抑制，避免一次点击到达两次；关闭后交互回到注视与捏合。

## How to get to it (user POV)

会话进行中直接使用键盘与指针。窗口在焦点状态时输入进入会话；离开焦点后输入回到系统。

## Driving it with computer use

用 computer use 在模拟器窗口的对应位置点一下；坐标取自 `simctl io <UDID> screenshot` 的原图。

Preconditions: 会话在 streaming 状态。

键入必须走真实按键。模拟器接受的合成键盘事件与真实键入走同一条产品管线：

```sh
# 先点一下会话窗口，确认它拿到焦点
  --shot-x <x> --shot-y <y> --shot-width 3840 --shot-height 2160
osascript -e 'tell application "System Events" to keystroke "hello"'
```

送达判定读产品探针的输入计数与主机的反应：

```sh
D="$(xcrun simctl get_app_container <UDID> com.xiongzhipeng.Enchron data)/Documents"
grep "input release" "$D/stream-session-probe.log" | tail
./.scratch/stream-cmd.sh streamSnapshot '{}'   # input:keyboard=… input:mouse=… input:gamepad=…
```

手柄不依赖系统合成输入，直接走命令通道注入报文，回报同一条映射算出的位：

```sh
./.scratch/stream-cmd.sh streamSendController '{"buttons":"a"}'
./.scratch/stream-cmd.sh streamSendController '{"buttons":"a,leftShoulder","lt":"200","lx":"-32767"}'
./.scratch/stream-cmd.sh streamSendController '{"buttons":""}'   # 全零报文
```

鼠标走同一条会话入口，相对位移、按键与滚轮一次一条：

```sh
./.scratch/stream-cmd.sh streamSendMouse '{"dx":"6","dy":"-4"}'
./.scratch/stream-cmd.sh streamSendMouse '{"button":"1","down":"1"}'
./.scratch/stream-cmd.sh streamSendMouse '{"scroll":"1"}'
```

控制面 `input:mouse` 是转发入口计数；`input:hardwareMouse` 表示会话当前是否接管了外接鼠标。模拟器没有 GCMouse，真机才有。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 键盘捕获控件在窗口内不绘制不透明背景 | 源码结构检查 |
| 物理 | 键入后控制面 `input:keyboard` 增长，主机侧读到对应文字 | 控制面读数 + 主机取证 |
| 物理 | 指针移动后控制面 `input:mouse` 增长 | 控制面读数 |
| 物理 | 会话结束后 `input release cause=user` 出现，按住的键全部释放 | 探针 |
| 结构 | 手柄位映射逐键等于 Moonlight 字段：A `0x1000`、B `0x2000`、X `0x4000`、Y `0x8000`、方向键 `0x1…0x8`、肩键 `0x100/0x200` | `StreamGamepadMappingTests` 单测 + 命令通道 |
| 物理 | 交换 ABXY 关闭时报 A 为 `0x1000`，打开时为 `0x2000` | 命令通道 + 探针 `controller flags=` |
| 物理 | 松开全部按键后报文 flags 回到 `0` | 命令通道 |
| 物理 | 滚轮按累计整格转发，半格输入不产生报文 | `StreamScrollAccumulatorTests` 单测；真机滚轮**待做** |
| 物理 | 外接鼠标的相对移动与按键计入 `input:mouse`，滚轮计入 `input:scroll` | 命令通道 + 控制面读数 |
| 物理 | 外接鼠标接管时会话探针出现 `mouse attached`，断开出现 `mouse detached` | 探针 |
| 感知 | 真实蓝牙鼠标在真机上驱动主机指针、左键单击不重复 | **待做**（当前环境无 GCMouse 硬件） |
| 感知 | 输入延迟、手柄震动的到达 | **待做** |

## 证明的终态

输入的证明终点在主机一侧：主机收到了那段文字或那个指针位置。客户端计数增长只证明事件进了客户端的转发函数，不证明主机收到。

## Gotchas

- **合成键盘事件可能被系统吞掉。** 先点一下窗口让它拿到焦点，再发按键；没有焦点时事件不进会话，探针一动不动。
- **输入计数增长不等于主机收到。** 计数在转发入口就会增加。
- **手柄的交换设置属于会话快照。** 会话进行中改设置不会改这一次的映射，要等下一次启动。
- **外接鼠标接管后不要再用注视点击。** 会话抑制了手势指针路径，注视不会移动主机指针；这是为了避免鼠标点击与手势点击重复。
- **系统指针在 visionOS 上仍然可见。** 会话只转发事件，不隐藏系统指针。
- **滚轮的轴值没有固定量纲。** 转发按累计截断成整格，半格输入留着与后续输入合并。
