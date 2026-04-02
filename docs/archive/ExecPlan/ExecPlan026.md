# ExecPlan026 — T0.3 测试素材清单与获取

**Round**: 3
**Pipeline State**: PLANNING
**目标**: 盘点现有测试视频，用 ffmpeg 转制/合成缺失的 7 种测试素材

## 现有素材盘点

| 文件 | 容器 | 编码 | 分辨率 | 色彩 | 时长 |
|------|------|------|--------|------|------|
| SDR-test.mkv | MKV | HEVC | 3840x2160 | BT.709 SDR | 23m |
| HDR10-test.MP4 | MP4 | HEVC | 3840x2160 | BT.2020/PQ HDR10 | 1.4m |
| dolby-vision-test.mp4 | MP4 | HEVC+DV | 3840x2160 | DV | 56s |
| 180-vr-test.mp4 | MP4 | HEVC | 3840x1920 | — | 60s |
| 360-test-nasa-wind-tunnel.webm | WebM | VP9 | 3840x1920 | — | 2.75m |

## 缺失素材 & 获取方案

| # | 素材 | 方案 | 源 |
|---|------|------|-----|
| 1 | MOV 容器 | remux SDR 前 15s | SDR-test.mkv |
| 2 | AVI 容器 | transcode H.264 前 15s | SDR-test.mkv |
| 3 | SBS 立体 3D | hstack 左右拼接 | SDR-test.mkv |
| 4 | OU 立体 3D | vstack 上下拼接 | SDR-test.mkv |
| 5 | 鱼眼投影 | v360 equirect→fisheye | 360-test |
| 6 | HLG | transcode HEVC + arib-std-b67 | SDR-test.mkv |
| 7 | HDR10+ | transcode HEVC + smpte2084 + sei | HDR10-test.MP4 |

## 验收标准

- 所有素材 ffprobe 输出正确的容器/编码/色彩元数据
- 所有素材放入 /Users/xiongzhipeng/Movies/
- 更新 TODOS.md T0.3 为 [x]
