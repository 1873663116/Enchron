# Video Format 编辑

投影（Flat/180°/360°/Custom Angle）与立体布局（Mono/Side-by-Side/Top-Bottom）的用户编辑。编辑入口只存在于主窗口列，并走同一 `launcher.applyFormat`/`resetFormat` 下游。

## Sub-features

- 窗口菜单宿主：`PlayerUI-TopAction-videoFormat` 打开，`PlayerUI-VideoFormat-*` 标识。
- Portal 面板 Advanced Settings 宿主：`PlayerPanel-button-settings` 展开，`PlayerPanel-VideoFormat-*` 标识。
- Automatic 恢复（provenance 为 source 时禁用并显示对勾）。
- 应用后的呈现路由：全景投影 → portal，Flat → window。进入 Panorama 需要点击 `PlayerPanel-button-enter-panorama`。

## How to get to it (user POV)

Window：视线点击播放表面唤出 chrome，右上 Video Format。Portal：召唤面板，展开 Advanced Settings。Panorama 先 Return to Portal，再编辑格式。

## Driving it with the controller

窗口宿主（已全程无人化验证）：

```sh
# chrome 自动隐藏，序列必须以表面点击开头并紧凑连发
tap PlayerUI-window-playback-surface
tap PlayerUI-TopAction-videoFormat
tap "PlayerUI-VideoFormat-Projection-180°"        # 标识含度数符号
tap "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side"  # 标识含空格
tap PlayerUI-VideoFormat-apply
```

Portal 面板使用同一组 `PlayerPanel-VideoFormat-*` 标识。

## 证明的终态

应用全景格式后，控制串必须先满足 `presentation=portal`、`attached=portal`、`transition=none`、`pendingSpatialEffect=none`，且投影、立体布局和格式 revision 已更新。点击显式 Panorama 入口后，再用沉浸探针证明 RealityKit 采用所选投影。应用 Flat 后控制串满足 `presentation=window`。

## Gotchas

- ended 状态下应用格式与播放中应用格式都必须成立（两者均已真机验证；曾有"ended 转移必停滞"假说，已证伪）。
- 分段选择器的 accessibility 标识由标题与标签拼成，改 UI 文案会破坏自动化标识。
