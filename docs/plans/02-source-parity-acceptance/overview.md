# 源行为一致性验收

## Context

集成分支 `perf/presentation-switch-source-reopen` 汇入了三个并行 agent 的工作，全部落在 `PlaybackFFmpegBridge.c` 与其 Swift 消费者上：Dolby Vision Profile 5 的 sample description 修正、Profile 7 双层源的基础层拆分、远程打开时的 HTTP 连接复用。三者共同改变的是"同一段媒体经本地文件与经远程 HTTP 进入解码器"这条路径，因此验收的对象是这条路径的行为一致性，而不是三个提交各自的实现细节。

## Scope

包含：三个提交的代码裁决；本地与远程两种取源方式在打开、解码、时长与轨道结构上的一致性；本地媒体库与 Emby 库中每一类 dynamic range 与投影的实际播放；分支达到可合并 `main` 的状态。

排除：Emby 服务端配置与 WebDAV 挂载本身的治理（`webdavfs` 的越界读补零是已知的外部缺陷，见 [[emby-truncates-open-ended-ranges]] 记录的判别方法）；SDR 全库 1020 条的逐条播放（dynamic range 维度由 HDR10、DolbyVision 各 profile 覆盖，SDR 取代表样本）。

## 语料

Emby 库 1081 条，非 SDR 54 条。Emby 的 `Dv*` 字段全为空，profile 由 `Scripts/verification/inventory_dynamic_range_corpus.py` 对文件 ffprobe 得到：

| PlaybackCore 分支 | Emby 条数 | 本地 fixture |
|---|---:|---|
| DolbyVision profile 7 双层拆分 | 8 | `Profile7.6/FEL_test_for_AVS.mkv`（bl=1 el=1 cc=6） |
| DolbyVision profile 8 单层 | 5 | `Profile8.1/OfficialDolby/P81_GlassBlowing2…mp4` |
| DolbyVision profile 5 单层 | 1 | `HD|UHD/Patterns_Of_Nature_DoVi_24_P5_*` |
| HDR10 | 40 | `HDR10/HDR10.MP4` |

Profile 7 双层占 Emby Dolby Vision 条目的八分之五，是本次新增拆分路径的真实负载。本地另有 Profile 10（AV1）、Profile 20、HLG P8.4 与全部投影样本（Stereo180、Panorama、MVHEVC），Emby 侧无对应条目。

## Constraints

- 验证走真机与 PlaybackCore 的 macOS `swift test`，不跑 visionOS 模拟器套件；构建产物一律落 `/Volumes/Cortisol`。
- 回归判据是 2026-08-15 的通道二基线 200 测试 8 失败 13 issue（本分支已从九失败降为八，见决策记录），逐条比对失败名，不比对数量。
- 过渡与首帧类结论需录屏逐帧取证，端点快照不足以判定过程。
- 远程语料是真实影片（单条数十 GB），一致性以有界前缀解码衡量，不整片解码。

## Verification

一致性预言：同一段媒体经本地路径与经 HTTP 路径送入 `PlaybackCoreRemoteMediaProbe`，其 `video_samples`、`audio_samples`、`delivered_seconds` 与轨道结构必须逐字段相等；`playback_bytes` 允许不等，因为 HTTP 的 range 边界与本地读取粒度不同。

播放预言：语料中每一条在真机上出画，且 dynamic range 与投影分类与 ffprobe 所述一致。

## Phases

1. [phase-1-parity-harness.md](phase-1-parity-harness.md)
2. [phase-2-corpus-decode.md](phase-2-corpus-decode.md)
3. [phase-3-device-projection-matrix.md](phase-3-device-projection-matrix.md)

阶段 1 建立有界一致性度量并对已知阴阳样本自校验；阶段 2 用它扫本地与远程全语料；阶段 3 在真机上取投影与出画的像素证据。
