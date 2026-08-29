# 播放控件的显示与隐藏

控件的显示与隐藏由 `showControls` 这一个状态唯一决定。在窗口模式下，它控制 chrome 与底部 ornament 的显隐。在 docked 与 panorama 呈现下，它控制同一个 RealityView attachment 的启用状态和透明度。这个 attachment 持续留在沉浸空间中，显隐过程不会开关 Window Scene。

## Sub-features

- 窗口模式：点击播放表面即可切换 chrome 的显隐；chrome 会在秒级时间后自动隐藏，任何交互都会重置这个计时。
- docked 与 panorama：用户注视并捏合各自呈现的产品交互外壳，即可召唤跟随头部姿态的空间内控件。
- 控件会自动隐藏，但打开二级菜单会把控件钉住。

## How to get to it (user POV)

在窗口呈现中，用户视线落在视频区域并捏合。在 docked 呈现中，用户视线落在视频表面并捏合。在 panorama 呈现中，180° 内容需要注视前半球，360° 内容可以注视任意方向；捏合动作由覆盖对应范围的 `EnchronPanoramaInput.*` 外壳接收。

## Driving it with the controller

Preconditions: 会话已经建立，且正处于播放中。要驱动沉浸态，先按 [mode-transitions.md](mode-transitions.md) 的路径进入目标呈现。

在窗口模式下，直接执行 `tap PlayerUI-window-playback-surface`。模拟器 lane 的沉浸模式使用 Device Hub 画布：鼠标悬停产生 Gaze，鼠标点击产生 Pinch，并走系统空间输入管线。执行前先完成 Device Hub 的目标绑定、窗口放大、Fit 画布和 Pointer 模式预检，见[模拟器 lane](../references/simulator.md)。真机 lane 只在调查产品状态时使用以下等价动作；该动作不证明真机物理输入。

```sh
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb toggleControls
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | `showControls` 是唯一的控制状态；沉浸态的显隐不开关 Window Scene | `verify_playback_surface_structure.py` |
| 物理 | 窗口态下 chrome 元素回到层级；沉浸态下探针出现 visible 翻转，且期间没有 Window Scene 操作 | 两条 lane 的产品证据 |
| 物理 | 隐藏之后残留的语义节点必须报告 `isHittable=false` | 两条 lane 的 Accessibility 取证 |
| 物理 | Docked 与 Panorama 下的 Device Hub Pinch 只由各自的 `EnchronDockedInput.surface` 或 `EnchronPanoramaInput.*` 外壳接受，并产生 `toggle source=spatialTap` | Simulator Device Hub 与产品探针 |
| 物理 | 每一条 `spatialVideoTopology reconciled writeID=<id>` 都有携带同一 ID 的 `ownershipVerified ... ancestorChainActive=true` 与之对应，并且不出现 `ancestorChainActive=false` | `measure_controls_flash.py` 的真机录屏轮次 |
| 感知 | 注视与控件跟随的主观感受 | 不进入 Agent 回归；人工测试者自行判断 |

## 证明的终态

在窗口模式下，终态是 chrome 元素重新出现在层级中。在沉浸模式下，每一次显示控件时，探针事件必须按以下顺序出现：同一 revision 先请求定位，接着由 `ImmersivePlaybackControlsAttachmentController.applyLockedTransform` 写入 transform 与 opacity，最后以 `entityEnablementWrite ... value=true` 打开实体；随后出现 `placementApplied` 与 `placementStopped ... reason=worldLocked`。这些运行时事实与结构守卫共同证明：控件在被启用之前已经完成落位。每次显示与隐藏应分别出现 `immersiveControlsAttachment visible=true` 与 `visible=false`，并且期间没有任何 Window Scene 操作。控件显示时，层级中应包含 `PlayerPanel-controls`，以及播放、快退、快进、进度、退出和设置等原有的 `PlayerPanel-*` 标识。visionOS 可能在控件隐藏之后仍保留语义节点，但这些节点必须报告 `isHittable=false`。

## Simulator 验收步骤

开始前，确认启动环境没有设置 `ENCHRON_HEAD_INPUT_PROBE=1` 或 `ENCHRON_DOCKED_HIT_TEST_PROBES=1`。清空 `surface-tap-probe.log`，把控件置为隐藏状态，并运行 Device Hub `enlarge` 预检。预检只有在返回当前 Simulator 的 `targetBinding`、宽度不少于 1200 点的 16:9 画布，以及 Pointer 模式位置时才完成。

### Docked

1. 通过 Device Hub 把鼠标移动到 Docked 视频画面的中央，然后点击一次。画面保持连续，控件出现。
2. 把鼠标移动到控件以外的视频区域，再点击一次。控件隐藏。
3. 核对两次 Pinch 各自产生一组连续的探针记录：
   - `spatialTap entity=EnchronDockedInput.surface accepted=true`
   - 随后的 `toggle source=spatialTap showControls=true` 或 `showControls=false`

### Panorama

1. 在控件隐藏时，把鼠标移动到 180° 内容的可见前半球或 360° 内容的任意可见方向，然后点击一次。控件出现，画面不闪黑。
2. 把鼠标移动到控件以外的全景区域，再点击一次。控件隐藏。
3. 核对两次 Pinch 各自产生一组连续的探针记录：
   - `spatialTap entity=EnchronPanoramaInput.<panel> accepted=true`
   - 随后的 `toggle source=spatialTap showControls=true` 或 `showControls=false`

每种呈现都必须同时得到一次 `true` 和一次 `false`，并与操作后的控件状态一致。以下任一结果均为失败：探针出现 `EnchronHeadInput.probe`、`EnchronDockedInput.probeFront` 或 `EnchronDockedInput.probeChildFront` 的 `accepted=true`；探针只出现 `accepted=false`；或者后续没有 `toggle source=spatialTap`。诊断三板只在单独调查问题时通过 `ENCHRON_DOCKED_HIT_TEST_PROBES=1` 启用。

## Gotchas

- 2026-08-12 的真机结果显示，attachment 中的完整 deck 会进入 Accessibility 层级，控件显示时这些元素报告 `isHittable=true`。对 `PlayerPanel-button-play` 执行 XCUIElement tap，会把其标签从 `Pause` 改为 `Play`；对 `PlayerPanel-button-exit-spatial` 执行 tap，会返回 Portal。控件隐藏后，相同的节点仍然可以被查询到，但报告 `isHittable=false`。那一轮验证没有对隐藏状态的节点发送激活动作。
- 捏合路径的判据是探针出现 `toggle source=spatialTap showControls=true`。XCUITest 点击不携带空间输入语义；Device Hub 的 Mac 鼠标映射会产生系统 Gaze 与 Pinch，可用于 Simulator lane 的物理输入证据。
