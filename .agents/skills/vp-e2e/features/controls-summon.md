# 播放控件的显示与隐藏

`showControls` 是唯一状态。窗口模式用它控制 chrome 与底部 ornament。docked 与 panorama 用它控制同一个 RealityView attachment 的启用状态和透明度。attachment 持续留在沉浸空间中，不开关 Window Scene。

## Sub-features

- 窗口模式：点击播放表面切换 chrome，秒级自动隐藏，交互重置计时。
- docked 与 panorama：注视加捏合各自的产品交互外壳，召唤跟随头部姿态的空间内控件。
- 自动隐藏与二级菜单钉住。

## How to get to it (user POV)

窗口：视线点视频区域捏合。docked：视线点视频表面捏合。panorama：180° 内容注视前半球、360° 内容可注视任意方向捏合，由对应覆盖范围的 `EnchronPanoramaInput.*` 外壳接收。

## Driving it with the controller

窗口模式：`tap PlayerUI-window-playback-surface`（真实用户路径）。沉浸模式：真实捏合不可合成，验证用通道等价动作：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb toggleControls
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | `showControls` 是唯一状态；沉浸态不开关 Window Scene | `verify_playback_surface_structure.py` |
| 物理 | 窗口态 chrome 回到层级；沉浸态探针出现 visible 翻转且无 Window Scene 操作 | 真机 |
| 物理 | 隐藏后残留语义节点报告 `isHittable=false` | 真机 |
| 物理 | Docked 与 Panorama 的真人捏合只由各自的 `EnchronDockedInput.surface` / `EnchronPanoramaInput.*` 外壳接受并产生 `toggle source=spatialTap` | 真机佩戴者，按下列清单 |
| 物理 | 每条 `spatialVideoTopology reconciled writeID=<id>` 都有同一 ID 的 `ownershipVerified ... ancestorChainActive=true`，且没有 `ancestorChainActive=false` | `measure_controls_flash.py` 真机录屏轮次 |
| 感知 | 注视加捏合召唤是否跟手 | **待做**，合成输入不带该语义，只有佩戴者能验 |

## 证明的终态

窗口模式下，chrome 元素回到层级。沉浸模式每次显示时，同一 revision 先请求定位，再由 `ImmersivePlaybackControlsAttachmentController.applyLockedTransform` 写入 transform 与 opacity，最后以 `entityEnablementWrite ... value=true` 打开实体；随后出现 `placementApplied` 与 `placementStopped ... reason=worldLocked`。这些运行时事实与结构守卫共同证明控件在启用前已经落位。显示和隐藏分别出现 `immersiveControlsAttachment visible=true` 与 `visible=false`，期间没有 Window Scene 操作。显示时，层级包含 `PlayerPanel-controls`、播放、快退、快进、进度、退出和设置等原有 `PlayerPanel-*` 标识。visionOS 可能在隐藏后保留语义节点，但节点必须报告 `isHittable=false`。

## 佩戴者验收清单

操作员先安装待验构建，确认启动环境中没有 `ENCHRON_HEAD_INPUT_PROBE=1` 或 `ENCHRON_DOCKED_HIT_TEST_PROBES=1`，清空 `surface-tap-probe.log`，并把控件置为隐藏。佩戴者只执行以下捏合，不需要判断日志。

### Docked

1. 注视 Docked 视频画面中央，捏合一次。画面应连续，控件应出现。
2. 避开已经出现的控件，继续注视视频画面，捏合一次。控件应隐藏。
3. 操作员核对两次捏合各自产生一组连续探针：
   - `spatialTap entity=EnchronDockedInput.surface accepted=true`
   - 随后的 `toggle source=spatialTap showControls=true` 或 `showControls=false`

### Panorama

1. 控件隐藏后，180° 内容注视可见全景画面内的方向；360° 内容可注视任意方向。捏合一次，控件应出现且画面不闪黑。
2. 避开控件本身，再注视全景画面捏合一次。控件应隐藏。
3. 操作员核对两次捏合各自产生一组连续探针：
   - `spatialTap entity=EnchronPanoramaInput.<panel> accepted=true`
   - 随后的 `toggle source=spatialTap showControls=true` 或 `showControls=false`

每种呈现都必须同时得到一次 `true` 和一次 `false`，并与佩戴者看到的出现、隐藏一致。出现 `EnchronHeadInput.probe`、`EnchronDockedInput.probeFront` 或 `EnchronDockedInput.probeChildFront` 的 `accepted=true`，或者只有 `accepted=false`、没有后续 `toggle source=spatialTap`，均为失败。诊断三板只在单独调查时通过 `ENCHRON_DOCKED_HIT_TEST_PROBES=1` 启用，不参与产品验收。

## Gotchas

- 2026-08-12 真机结果显示，attachment 中的完整 deck 会进入 Accessibility 层级，显示时元素报告 `isHittable=true`。`PlayerPanel-button-play` 的 XCUIElement tap 把标签从 `Pause` 改为 `Play`。`PlayerPanel-button-exit-spatial` 的 tap 返回 Portal。隐藏后相同节点仍可查询，但报告 `isHittable=false`。本轮没有对隐藏节点发送激活动作。
- 捏合路径以 `toggle source=spatialTap showControls=true` 为判据。合成点击不带注视加捏合语义，不能代替这条物理输入证据。
