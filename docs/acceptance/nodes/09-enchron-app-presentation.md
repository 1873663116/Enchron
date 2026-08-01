# 节点 09：Enchron App Presentation

## 边界

节点 09 由 Enchron App 把节点 08 的 renderer-backed entity 放入目标 platform surface，完成 Presentation Binding，并观察 displayed frame、持续进度和音频输出。它不生产 sample，也不改变 Playback Lifecycle。

## 产品 Presentation

| Presentation | Surface | Consumer | 提交条件 |
|---|---|---|---|
| Window | playback window `RealityView` | `VideoPlayerComponent` | window、entity、binding 与当前 renderer 全部 active，component ready 且当前 renderer 已产生 displayed pixel |
| Docked | active environment 的 docking surface | `VideoPlayerComponent` | environment、目标 anchor、entity 与 binding 全部 active，component ready 且当前 renderer 已产生 displayed pixel |
| Panorama | playback `ImmersiveSpace` | `VideoPlayerComponent` | immersive space、actual viewing behavior、entity 与 binding 全部 settled |

Environment Context 与 Playback Presentation 独立。V1 只有一个正式 Environment identity，Day/Night 是同一场景与同一 anchor 语义的 Appearance。Window 可以在 Environment 打开时继续存在；Docked 继承当前 Environment，没有当前 Environment 时使用默认 Environment；Panorama 不使用 docking anchor。Docked 与 Panorama 不直接互转，必须先回到 Window。

## 稳定规则

- Presentation Binding 与 renderer binding 属于同一 Media Session。
- 任意稳定时刻只有一个 active final Presentation Binding。
- requested、candidate、presented 与 failed/rolledBack 分别记录；仅有 renderer attach 时只能记录 `surfaceAttached`，component 尚未 ready 或当前 renderer 没有 displayed pixel 时不能投影为 `videoVisible` 或 settled。
- 目标 surface 与 renderer binding 成功后才提交；失败恢复原 Presentation 与 Environment Context，不重开 Media Session。
- entity attached、首帧、displayed pixel、持续时间推进、颜色正确、audio progression 与可听同步是独立事实。
- close/reopen 后的 sample、pixel、time 和 session identity 必须来自新 session，不能复用旧观察。

## 完成条件

唯一完成条件：当前 entity 已加入目标 surface，Presentation Binding 可追溯到同一 Media Session，并产生当前 session 的 displayed-frame observation。持续播放、音频、颜色和设备观感由联合矩阵进一步验收。

## 验收

visionOS Simulator 使用 `Scripts/verification/verify-spatial-presentations-simulator.zsh` 驱动真实 PlaybackCore session，证明 Window surface 的 displayed frame、持续推进、音频、detach、same-process reopen，以及 Window → Docked → Window → Panorama → Window 事件序列、同一 Media Session、surface attach、两帧截图变化和 Panorama desired/actual mode 收敛。Vision Pro 独立验收硬件解码、HDR/EDR、可听同步、实际 immersive behavior、空间舒适度和性能。
