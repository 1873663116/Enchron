# 串流输入

会话窗口捕获佩戴者的键盘与指针输入，转发给主机。输入的送达以主机的实际反应为准，不以客户端计数为准。

## Sub-features

- 会话窗口获得焦点后，键入的文字送到主机。
- 指针移动送达主机，主机的指针跟随。
- 按住不放的按键与按钮在会话结束时全部释放，不残留。
- Dock 控件释放所有按住的输入，原因为 `control-hit`。
- 键盘捕获控件对画面不可见：它覆盖在视频之上，但不得遮挡视频。

## How to get to it (user POV)

会话进行中直接使用键盘与指针。窗口在焦点状态时输入进入会话；离开焦点后输入回到系统。

## Driving it with computer use

Preconditions: 会话在 streaming 状态。

键入必须走真实按键。模拟器接受的合成键盘事件与真实键入走同一条产品管线：

```sh
# 先点一下会话窗口，确认它拿到焦点
python3 Scripts/verification/device_hub_canvas.py --device <UDID> pinch \
  --shot-x <x> --shot-y <y> --shot-width 3840 --shot-height 2160
osascript -e 'tell application "System Events" to keystroke "hello"'
```

送达判定读产品探针的输入计数与主机的反应：

```sh
D="$(xcrun simctl get_app_container <UDID> com.xiongzhipeng.Enchron data)/Documents"
grep "input release" "$D/stream-session-probe.log" | tail
./.scratch/stream-cmd.sh streamSnapshot '{}'   # input:keyboard=… input:mouse=…
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 键盘捕获控件在窗口内不绘制不透明背景 | 源码结构检查 |
| 物理 | 键入后控制面 `input:keyboard` 增长，主机侧读到对应文字 | 控制面读数 + 主机取证 |
| 物理 | 指针移动后控制面 `input:mouse` 增长 | 控制面读数 |
| 物理 | 会话结束后 `input release cause=user` 出现，按住的键全部释放 | 探针 |
| 感知 | 输入延迟 | **待做** |

## 证明的终态

输入的证明终点在主机一侧：主机收到了那段文字或那个指针位置。客户端计数增长只证明事件进了客户端的转发函数，不证明主机收到。

## Gotchas

- **合成键盘事件可能被系统吞掉。** 先点一下窗口让它拿到焦点，再发按键；没有焦点时事件不进会话，探针一动不动。
- **输入计数增长不等于主机收到。** 计数在转发入口就会增加。
