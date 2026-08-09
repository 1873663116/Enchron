# 播放控件的显示与隐藏

`showControls` 是唯一状态：窗口模式下驱动 chrome 与底部控件条的可见性；沉浸呈现下驱动独立控件窗口的开合（ImmersiveSpaceView 观察同步，捏合、无障碍、测试通道三条路径呈现一致）。

## Sub-features

- 窗口模式：点击播放表面切换 chrome，秒级自动隐藏，交互重置计时。
- panorama：注视加捏合命中不可见 SwiftUI 面（`PlayerUI-immersive-playback-surface`）召唤控件窗口。
- 自动隐藏与二级菜单钉住。

## How to get to it (user POV)

窗口：视线点视频区域捏合。panorama：任意注视方向捏合（前向 6×6 米命中面）。

## Driving it with the controller

窗口模式：`tap PlayerUI-window-playback-surface`（真实用户路径）。沉浸模式：真实捏合不可合成，验证用通道等价动作：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb toggleControls
```

## 证明的终态

探针出现 `toggle source=… showControls=…`（捏合路径）或 `testcmd toggleControls ok`（通道路径），且沉浸态下伴随 `controlsWindow open`/`dismiss` 行。窗口模式下 chrome 元素回到层级即视觉在场证明。

## Gotchas

- panorama 召唤后的控件窗口不进 accessibility 层级（对佩戴者可见性只能由佩戴者或截图确认），自动化对面板按钮不可达。
- 捏合→attachmentTap→toggle 的探针链是原始捏合缺陷的验收判据：佩戴者一次捏合，日志应出现 `attachmentTap` 紧跟 `toggle source=immersiveSwiftUI showControls=true`。
