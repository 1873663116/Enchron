# Video Format 编辑

投影（Flat/180°/360°/Custom Angle）与立体布局（Mono/Side-by-Side/Top-Bottom）的用户编辑。两个宿主渲染同一个编辑器组件、走同一 `launcher.applyFormat`/`resetFormat` 下游：语义等价由结构保证。

## Sub-features

- 窗口菜单宿主：`PlayerUI-TopAction-videoFormat` 打开，`PlayerUI-VideoFormat-*` 标识。
- 面板 Advanced Settings 宿主（panorama/portal）：`PlayerPanel-button-settings` 展开，`PlayerPanel-VideoFormat-*` 标识；docked 的 settings 是摆位滑杆，不是格式编辑器。
- Automatic 恢复（provenance 为 source 时禁用并显示对勾）。
- 应用后的呈现路由：全景投影 → panorama，Flat → window。

## How to get to it (user POV)

窗口模式：视线点击播放表面唤出 chrome，右上 Video Format。panorama/portal：捏合召唤面板，展开 Advanced Settings。

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

面板宿主在 panorama 的召唤依赖真实捏合（不可合成），属佩戴者验收面。

## 证明的终态

应用全景格式后探针出现新 settle 序列（`gotImmersive=progressive`、`gotViewing=stereo`、rkContentType 与所选投影一致）；应用 Flat 后控制串 `presentation=window`。窗口宿主完整往返今晚已在真机走通（window→panorama 1 秒 settle）。

## Gotchas

- ended 状态下应用格式与播放中应用格式都必须成立（两者均已真机验证；曾有"ended 转移必停滞"假说，已证伪）。
- 分段选择器的 accessibility 标识由标题与标签拼成，改 UI 文案会破坏自动化标识。
