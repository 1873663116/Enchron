# 呈现切换

四个呈现：window、portal、docked、panorama（`PlaybackPresentation.swift`）。Window 进入 Docked，Portal 进入 Panorama；Docked 退出到 Window，Panorama 退出到 Portal。应用格式只在主窗口列切换 Window 与 Portal。Window 按有效逐眼画面比例锁定；Portal 是自由缩放的视口，进入时请求 1280×720。runtime 附着权属于转场目标呈现（无转场时为已定呈现），控件窗口的场景操作与转场序列化执行。

## Sub-features

- 打开落地（干净态按源分类；带持久覆盖按覆盖）。
- window → portal（应用全景格式并等待主窗口稳态）。
- portal → panorama（显式点击窗口菜单的 `PlayerUI-TopAction-resumePanorama`，其 accessibility label 为 Enter Panorama）。
- panorama → portal（面板 exit）。
- window ⇄ docked（TopAction-dock + DockMenu；面板 exit）。
- 失败回滚：settle 超时后干净回滚，不悬挂。

## How to get to it (user POV)

Window chrome 提供 Dock 与 Video Format。Portal chrome 同时提供 Enter Panorama 与 Video Format。Panorama 内捏合召唤面板后点击 Return to Portal。

## Driving it with playback_mode_matrix

用以下命令运行三条干净态循环路径：

```sh
python3 Scripts/verification/playback_mode_matrix.py --clean --reps 1 \
  --paths clean-spatial-cycle clean-dock-cycle \
  --media-root /Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/fixtures \
  --clips "Spatial/Stereo180/180_3D_loop10.mp4" "Spatial/Stereo180/180_3D_TB_loop10.mp4" \
  --evidence-dir <evidence>/cycles-<stamp>
# 360 变体：--paths clean-360-cycle --clips "Spatial/Panorama/360_loop10.mp4"
```

三条路径依赖的机制：
- **循环 fixture**：需要覆盖播放中连续切换时，经 `--media-root` 选用 `TestEvidence/fixtures` 下的 10 分钟流拷贝（`*_loop10.mp4`）。ended 转换测试使用自然播放结束的 60 秒原片。
- **summon 原语**（`summon:<identifier>`）：自动隐藏 chrome 上的控件必须在一个收敛循环里"先试点、不中则 toggle 后经 runner 内 3 秒存在等待重试"；分离的可见性探测永远输给隐藏计时器。
- **tapSequence**：窗口菜单序列（格式编辑五击）必须在一条 runner 命令内以亚秒间隔落点。

## 证明的终态

每步以探针 settle（沉浸目标）或控制串稳态（窗口目标）收口；全景格式 Apply 必须先证明 Portal 稳态和 1280×720 自由缩放策略，再点击显式入口并证明 Panorama settle。Window 目标还必须证明窗口按有效逐眼比例锁定。ended 转换的目标必须显示最终帧和 Replay，且 lifecycle 保持 ended。未 settle 应观察到源呈现回滚且无 pending effect。

## Gotchas

- teardown 型解散后若主窗口元素命中但无输入投递，而通道 ping 仍应答，则重建会话。
- 沉浸入场停滞时，先取探针的 settlement 行与 `modeRequestRetry` 行。
