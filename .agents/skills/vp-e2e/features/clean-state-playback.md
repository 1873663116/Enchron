# 干净状态播放

从无任何持久化残留（无格式覆盖、无观看进度、空媒体库）的状态入库并播放一个视频。这是"任意视频可播"标准的原子验证单元。

## Sub-features

- 无信令片源（容器与样本均无投影元数据）按 window 呈现平面播放。
- 带信令片源（Apple APMP、MV-HEVC 等）按源分类进入相应呈现。
- 观看进度从 0 开始（resetState 已清 enchron.* 键）。

## How to get to it (user POV)

用户在媒体库网格点击视频卡片（`MediaLibrary-grid-video-<文件名>`），播放器打开并开始播放。

## Driving it with playback_mode_matrix

```sh
python3 Scripts/verification/playback_mode_matrix.py \
  --clean --paths clean-open --reps 1 \
  --clips "<Samples 下相对路径>" \
  --evidence-dir <evidence>/clean-open-<stamp>
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 解封装、时间线、轨道结构正确 | PlaybackCore 单测 |
| 结构 | 干净态无持久化残留 | 模拟器单测 |
| 物理 | 落地呈现正确，画面非黑非冻结 | `playback_mode_matrix.py` 的双帧亮度与 SSIM 闸 |
| 感知 | 不适用（本条只证明"能播"，画面解释的正确性见 [picture-interpretation.md](picture-interpretation.md)） | |

## 证明的终态

`results.jsonl` 该 cell `verdict: PASS`，`landed` 记录落地呈现（window 或 panorama）。window 落地要求控制串 `videoVisible=true` 且 lifecycle 稳态；panorama 落地要求探针 `settled=true`。此外 PASS 必须带 `visual.verdict = content`（双帧截图 + 亮度/SSIM 分析，黑屏或冻结即判负），截图路径在 cell 记录里供人工复审。40 秒未达任一稳态即失败，证据在 cell 目录的探针摘录与最后控制串。

## Gotchas

- 干净序必须 reset 后先重启再导入：内存中的库会在下一次变更时把旧引用重新持久化。
- landed=window 对无信令全景片源是当前的正确行为（分类无信息可用），不是失败；启发式分类是待产品裁决的开放项。
