# Video Format 编辑

这项功能是用户对投影（Flat/180°/360°/Custom Angle）与立体布局（Mono/Side-by-Side/Top-Bottom）的编辑。Window 与 Portal 两种呈现都从主窗口菜单进入编辑，并且走同一条 `launcher.applyFormat`/`resetFormat` 下游路径。

## Sub-features

- Window 与 Portal 的编辑界面都由窗口菜单承载：菜单由 `PlayerUI-TopAction-videoFormat` 打开，编辑项使用 `PlayerUI-VideoFormat-*` 系列标识。
- 在 Portal 呈现中，菜单会同时显示 `PlayerUI-TopAction-resumePanorama` 与 `PlayerUI-TopAction-videoFormat`。
- Automatic 恢复选项：当格式的 provenance 为 source 时，该选项被禁用并显示对勾。
- 应用格式之后的呈现路由：应用全景投影会路由到 portal，应用 Flat 会路由到 window。要进一步进入 Panorama，需要点击 `PlayerUI-TopAction-resumePanorama`。

## How to get to it (user POV)

在 Window 或 Portal 呈现中，用户用视线点击播放表面唤出 chrome，再点击右上角的 Video Format。在 Panorama 呈现中，用户需要先 Return to Portal 回到 Portal，然后才能编辑格式。

## Driving it with the controller

Preconditions: 会话已经建立；应用正处于 window 或 portal 呈现的播放中。

Window 与 Portal 使用同一组窗口菜单标识：

```sh
# chrome 自动隐藏，序列必须以表面点击开头并紧凑连发
tap PlayerUI-window-playback-surface
tap PlayerUI-TopAction-videoFormat
tap "PlayerUI-VideoFormat-Projection-180°"        # 标识含度数符号
tap "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side"  # 标识含空格
tap PlayerUI-VideoFormat-apply
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 用户偏好只修改 Media Format，不会改动来源声明的 Format Description | `verify_format_description_ownership.py` |
| 结构 | Automatic 恢复与 provenance 的判定正确 | 模拟器单测 |
| 物理 | 应用格式后，控制串中的投影、立体布局与 revision 都已更新，并且落地呈现正确 | 真机，使用本文的控制器序列 |
| 感知 | 不适用：投影与立体布局由片源的构造决定，只要构造正确，画面就必然正确，因此物理行的"落地呈现正确"即为终局 | |

## 证明的终态

应用全景格式之后，控制串必须先同时满足 `presentation=portal`、`attached=portal`、`transition=none`、`pendingSpatialEffect=none`，并且投影、立体布局和格式 revision 都已更新。此时 Portal 窗口使用自由缩放策略，并在进入时请求 `WindowPlaybackLayout.fallback.defaultSize`（1280×720）。在点击显式的 Panorama 入口之后，再用沉浸探针证明 RealityKit 采用了所选的投影。应用 Flat 之后，控制串必须满足 `presentation=window`，且窗口重新按有效逐眼画面比例锁定。

## Gotchas

- 在 ended 状态下应用格式时，目标呈现会显示最终帧，transport 保持 ended，主操作为 Replay。
- 分段选择器的 accessibility 标识由标题与标签拼接而成，因此修改 UI 文案会连带破坏自动化所依赖的标识。
