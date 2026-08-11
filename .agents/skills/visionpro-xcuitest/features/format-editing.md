# Video Format 编辑

投影（Flat/180°/360°/Custom Angle）与立体布局（Mono/Side-by-Side/Top-Bottom）的用户编辑。Window 与 Portal 都从主窗口菜单进入，并走同一 `launcher.applyFormat`/`resetFormat` 下游。

## Sub-features

- Window 与 Portal 的窗口菜单宿主：`PlayerUI-TopAction-videoFormat` 打开，`PlayerUI-VideoFormat-*` 标识。
- Portal 的菜单同时显示 `PlayerUI-TopAction-resumePanorama` 与 `PlayerUI-TopAction-videoFormat`。
- Automatic 恢复（provenance 为 source 时禁用并显示对勾）。
- 应用后的呈现路由：全景投影 → portal，Flat → window。进入 Panorama 需要点击 `PlayerUI-TopAction-resumePanorama`。

## How to get to it (user POV)

Window 或 Portal：视线点击播放表面唤出 chrome，点击右上 Video Format。Panorama 先 Return to Portal，再编辑格式。

## Driving it with the controller

Window 与 Portal 使用同一组窗口菜单标识：

```sh
# chrome 自动隐藏，序列必须以表面点击开头并紧凑连发
tap PlayerUI-window-playback-surface
tap PlayerUI-TopAction-videoFormat
tap "PlayerUI-VideoFormat-Projection-180°"        # 标识含度数符号
tap "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side"  # 标识含空格
tap PlayerUI-VideoFormat-apply
```

## 证明的终态

应用全景格式后，控制串必须先满足 `presentation=portal`、`attached=portal`、`transition=none`、`pendingSpatialEffect=none`，且投影、立体布局和格式 revision 已更新。Portal 窗口使用自由缩放策略，并在进入时请求 `WindowPlaybackLayout.fallback.defaultSize`（1280×720）。点击显式 Panorama 入口后，再用沉浸探针证明 RealityKit 采用所选投影。应用 Flat 后控制串满足 `presentation=window`，窗口重新按有效逐眼画面比例锁定。

## Gotchas

- ended 状态下应用格式时，目标呈现显示最终帧，transport 保持 ended，主操作为 Replay。
- 分段选择器的 accessibility 标识由标题与标签拼成，改 UI 文案会破坏自动化标识。
