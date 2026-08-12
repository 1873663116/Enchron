# 播放控件的显示与隐藏

`showControls` 是唯一状态。窗口模式用它控制 chrome 与底部 ornament。docked 与 panorama 用它控制同一个 RealityView attachment 的启用状态和透明度。attachment 持续留在沉浸空间中，不开关 Window Scene。

## Sub-features

- 窗口模式：点击播放表面切换 chrome，秒级自动隐藏，交互重置计时。
- docked 与 panorama：注视加捏合播放表面或全景交互面，召唤跟随头部姿态的空间内控件。
- 自动隐藏与二级菜单钉住。

## How to get to it (user POV)

窗口：视线点视频区域捏合。docked：视线点视频表面捏合。panorama：任意注视方向捏合，前向 6×6 米交互面负责接收事件。

## Driving it with the controller

窗口模式：`tap PlayerUI-window-playback-surface`（真实用户路径）。沉浸模式：真实捏合不可合成，验证用通道等价动作：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb toggleControls
```

## 证明的终态

窗口模式下，chrome 元素回到层级。沉浸模式下，探针先出现 `immersiveControlsAttachment firstPoseApplied`。显示和隐藏分别出现 `immersiveControlsAttachment visible=true` 与 `visible=false`，期间没有 Window Scene 操作。显示时，层级包含 `PlayerPanel-controls`、播放、快退、快进、进度、退出和设置等原有 `PlayerPanel-*` 标识。visionOS 可能在隐藏后保留语义节点，但节点必须报告 `isHittable=false`。

## Gotchas

- 2026-08-12 真机结果显示，attachment 中的完整 deck 会进入 Accessibility 层级，显示时元素报告 `isHittable=true`。`PlayerPanel-button-play` 的 XCUIElement tap 把标签从 `Pause` 改为 `Play`。`PlayerPanel-button-exit-spatial` 的 tap 返回 Portal。隐藏后相同节点仍可查询，但报告 `isHittable=false`。本轮没有对隐藏节点发送激活动作。
- 捏合路径以 `toggle source=spatialTap showControls=true` 为判据。合成点击不带注视加捏合语义，不能代替这条物理输入证据。
