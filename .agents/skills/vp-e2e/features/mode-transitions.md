# 呈现切换

播放共有四种呈现：window、portal、docked、panorama，定义见 `PlaybackPresentation.swift`。转场关系是固定的：Window 呈现进入 Docked，Portal 呈现进入 Panorama；退出时，Docked 回到 Window，Panorama 回到 Portal。应用视频格式只会在主窗口这一列内切换呈现，也就是只在 Window 与 Portal 之间切换。Window 的窗口按有效逐眼画面比例锁定；Portal 则是一个可以自由缩放的视口，进入时会请求 1280×720 的尺寸。runtime 的附着权属于转场的目标呈现；当没有转场在进行时，附着权属于当前已确定的呈现。控件窗口的场景操作与转场按顺序序列化执行。

## Sub-features

- 打开媒体后的落地呈现：干净状态下按媒体来源的分类决定；当存在持久化的格式覆盖时，按覆盖决定。
- 从 window 切换到 portal：应用全景格式，并等待主窗口达到稳态。
- 从 portal 切换到 panorama：需要显式点击窗口菜单中的 `PlayerUI-TopAction-resumePanorama`，该入口的 accessibility label 是 Enter Panorama。
- 从 panorama 退回 portal：通过控件面板上的 exit 完成。
- window 与 docked 之间的双向切换：进入经过 TopAction-dock 与 DockMenu，退出通过控件面板上的 exit。
- 失败回滚：当 settle 等待超时后，转场必须干净地回滚，不允许悬挂在中间状态。

## How to get to it (user POV)

在 Window 呈现中，chrome 上提供 Dock 与 Video Format 两个入口。在 Portal 呈现中，chrome 上同时提供 Enter Panorama 与 Video Format。在 Panorama 呈现中，用户先用捏合召唤控件面板，再点击面板上的 Return to Portal。

## Driving it with playback_mode_matrix

Preconditions: 循环 fixture 已经通过 `zsh Scripts/fixtures/generate_loop_fixtures.sh` 生成；当前没有其他常驻 runner 在运行。

使用下面的命令运行三条干净状态的循环路径：

```sh
python3 Scripts/verification/playback_mode_matrix.py --clean --reps 1 \
  --paths clean-spatial-cycle clean-dock-cycle \
  --media-root .scratch/loop-fixtures \
  --clips "Spatial/Stereo180/180_3D_loop10.mp4" "Spatial/Stereo180/180_3D_TB_loop10.mp4" \
  --evidence-dir <evidence>/cycles-<stamp>
# 360 变体：--paths clean-360-cycle --clips "Spatial/Panorama/360_loop10.mp4"
```

这三条路径依赖以下机制：
- **循环 fixture**：当需要覆盖播放过程中的连续切换时，必须先运行 `zsh Scripts/fixtures/generate_loop_fixtures.sh`，由 TestMedia 中的原片生成 10 分钟的流拷贝（文件名形如 `*_loop10.mp4`），再用 `--media-root` 把媒体根目录指向 `.scratch/loop-fixtures`。这样做是因为原片大约一分钟就会播完，会让会话在循环中途结束。而 ended 转换的测试恰恰相反，它使用的正是会自然播放到结束的原片。
- **summon 原语**（`summon:<identifier>`）：位于自动隐藏 chrome 上的控件，必须在一个收敛循环里操作：先直接尝试点击，如果没有命中，就先 toggle 唤出 chrome，再经过 runner 内的 3 秒存在等待后重试。如果把可见性探测拆成独立的一步来做，它永远会输给自动隐藏计时器。
- **tapSequence**：窗口菜单的点击序列（例如格式编辑需要的五击）必须放在同一条 runner 命令内，以亚秒级间隔连续落点。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 保持格式不变的切换必须复用现有媒体会话，而不是重新打开来源 | PlaybackCore 单测（RendererGraphReplacementTests） |
| 结构 | 附着权属于转场的目标呈现；场景操作与转场按顺序序列化执行 | `verify_playback_surface_structure.py` |
| 物理 | 每一步都以 settle 或稳态收口；失败时干净回滚，不悬挂 | `playback_mode_matrix.py` 的循环路径 |
| 感知 | 切换过程是否突兀、有没有闪烁 | **待做** |

## 证明的终态

每一步转场都要有收口证据：目标是沉浸呈现时，以探针的 settle 收口；目标是窗口呈现时，以控制串达到稳态收口。全景格式的 Apply 必须先证明 Portal 已达到稳态、并采用了 1280×720 的自由缩放策略，然后再点击显式入口，并证明 Panorama 完成 settle。当目标是 Window 时，还必须证明窗口按有效逐眼比例锁定。当转换发生在 ended 状态时，目标呈现必须显示最终帧并提供 Replay，且 lifecycle 保持 ended。如果转场没有 settle，应当观察到呈现回滚到源呈现，并且没有遗留的 pending effect。

## Gotchas

- 当发生 teardown 型场景解散之后，如果主窗口元素仍能被命中、但输入事件不再投递到应用，而 App 命令通道的 ping 仍然正常应答，此时应当重建 XCUITest 会话。
- 当进入沉浸呈现的过程停滞时，先取探针输出中的 settlement 行与 `modeRequestRetry` 行，再做判断。
