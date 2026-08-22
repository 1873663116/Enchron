# 渲染器入口闸门改为帧预算的取证，2026-08-23

物理 Vision Pro `59E3D57A-0288-53DC-9A7D-B657B6939558`，片源 `180_3D.mp4`（HEVC 8192x4096
59.94 fps，yuv420p 8bit，`has_b_frames=2`，解码后一帧 50.3 MB）。同一装置、同一片源、同一
驱动方式，与 2026-08-21 与 2026-08-22 两轮读数可比。

## 结论

seek 的 `rendererFlushMilliseconds` 从 240.8 毫秒降到 0.8 毫秒，teardown 总时长从 259–285
毫秒降到 38–43 毫秒。闸门在该片源上放行 4 帧，等于码流重排深度 2 加两帧调度余量。

| 配置 | rendererFlush ms | 均值 | 闸门 |
| --- | --- | --- | --- |
| lead 0.75 s（2026-08-22） | 223.6 / 245.2 / 253.6 | 240.8 | 约 45 帧 |
| lead 1.0 s（2026-08-22） | 371.5 / 364.0 / 365.3 | 366.9 | 约 60 帧 |
| receiverBackpressure（2026-08-22） | 506.3 / 614.0 / 549.9 | 556.7 | 约 1.26 秒 |
| 帧预算（本轮） | 0.7 / 0.8 / 0.9 | 0.8 | 4 帧 |

原计划按 flush 正比于 frames^1.8 外推，预期 4 帧约 3 毫秒；实测优于该外推。

## 不饿死解码器

同一装置连续播放该片源，投递 3705 帧，`timeline.deliveryLagRecovery.started` 出现 0 次，
无渲染器失败。这是采用浅队列所换取的风险，也是本轮必须证伪的一项。

## 呈现路径

`playback_mode_matrix.py --clean` 在真机上的判决：

- `clean-open` PASS。
- `clean-spatial-cycle` PASS：window → portal（180 side-by-side）→ panorama → portal，往返两次。
- `clean-360-cycle` PASS：window → portal（360 mono）→ panorama → portal。
- `clean-dock-cycle` 前三步 PASS（window → docked → window），第四步 `enter-docked-2` 因
  `PlayerUI-TopAction-dock` 不可命中而中止。该现象在 `1a203ce` 上以相同步骤、相同信息复现，
  与本轮改动无关。

模拟器 lane 无法回答 panorama 与 docked：其上不存在 ARKit 会话，spatial probe 不产生记录，
`enter-panorama` 在 `1a203ce` 与本轮上同样停摆。

## 一处装置缺陷

首轮真机读数报告闸门放行 48 帧，即帧数上限而非字节上限。原因是解复用在合格的 MOV stream
table 上跳过 `avformat_find_stream_info`，重排深度与像素格式因此停在零值，预算把该片源读成
不花钱。`control.seek.teardownStages` 里携带的自证字段是发现它的唯一入口。

第二处：探针未指定 derived data，`ensure-session` 因而装回上一轮的 App，并把它的诊断当作本轮
读数。控制器现在接受 `ENCHRON_DERIVED_DATA`，任何 runner 都能指明所测的构建。

## 原始读数

`.scratch/seek-frames/` 下的 JSON 与 `.scratch/seek-flush-20260822/` 的历史读数均为可重建产物，
按保留期清除。上表数值与判决已写入正文，结论不依赖它们继续存在。
