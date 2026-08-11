# 呈现切换

四个呈现：window、portal、docked、panorama（`PlaybackPresentation.swift`）。Window 进入 Docked，Portal 进入 Panorama；Docked 退出到 Window，Panorama 退出到 Portal。应用格式只在主窗口列切换 Window 与 Portal。runtime 附着权属于转场目标呈现（无转场时为已定呈现），控件窗口的场景操作与转场序列化执行。

## Sub-features

- 打开落地（干净态按源分类；带持久覆盖按覆盖）。
- window → portal（应用全景格式并等待主窗口稳态）。
- portal → panorama（显式点击 `PlayerPanel-button-enter-panorama`；`PlayerUI-TopAction-resumePanorama` 的动作含义和 accessibility label 也是 Enter Panorama）。
- panorama → portal（面板 exit）。
- window ⇄ docked（TopAction-dock + DockMenu；面板 exit）。
- 失败回滚：settle 超时后干净回滚，不悬挂。

## How to get to it (user POV)

窗口 chrome 的 Dock 与 Video Format；panorama 内捏合召唤面板后 Return to Portal；portal 面板点击 Enter Panorama。

## Driving it with playback_mode_matrix

三条干净态循环路径已无人化打通（含反复切）：

```sh
python3 Scripts/verification/playback_mode_matrix.py --clean --reps 1 \
  --paths clean-spatial-cycle clean-dock-cycle \
  --media-root /Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/fixtures \
  --clips "Spatial/Stereo180/180_3D_loop10.mp4" "Spatial/Stereo180/180_3D_TB_loop10.mp4" \
  --evidence-dir <evidence>/cycles-<stamp>
# 360 变体：--paths clean-360-cycle --clips "Spatial/Panorama/360_loop10.mp4"
```

三条路径依赖的机制：
- **循环 fixture**：60 秒原片会在多步路径中途播完并带走 chrome；`TestEvidence/fixtures` 下的 10 分钟流拷贝循环（`*_loop10.mp4`）经 `--media-root` 选用。
- **summon 原语**（`summon:<identifier>`）：自动隐藏 chrome 上的控件必须在一个收敛循环里"先试点、不中则 toggle 后经 runner 内 3 秒存在等待重试"；分离的可见性探测永远输给隐藏计时器。
- **tapSequence**：窗口菜单序列（格式编辑五击）必须在一条 runner 命令内以亚秒间隔落点。

## 证明的终态

每步以探针 settle（沉浸目标）或控制串稳态（窗口目标）收口；全景格式 Apply 必须先证明 Portal 稳态，再点击显式入口并证明 Panorama settle。未 settle 应观察到源呈现回滚且无 pending effect。

## Gotchas

- teardown 型解散（回滚、连播失败）后主窗口场景输入死亡：元素命中但零投递，通道 ping 仍应答即可确诊；恢复只有重建会话，产品级修复（解散时重新激活场景）在案未落。
- 沉浸入场仍有两个在案缺陷：multiview 立体的观看模式协商必现卡死（APMP-180）；SBS 偶发"五击落点但转场未启动"（复测中）。出现停滞先取探针的 settlement 行与 `modeRequestRetry` 行。
