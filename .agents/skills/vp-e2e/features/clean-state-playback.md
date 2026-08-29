# 干净状态播放

本特性验证从没有任何持久化残留的状态出发（没有格式覆盖、没有观看进度、媒体库为空），入库并播放一个视频。它是"任意视频可播"这一标准的原子验证单元。

## Sub-features

- 无信令片源（容器与样本均不含投影元数据）按 window 呈现为平面播放。
- 带信令片源（Apple APMP、MV-HEVC 等）按源分类进入相应的呈现方式。
- 观看进度从 0 开始，因为 resetState 已经清除了 enchron.* 键。

## How to get to it (user POV)

用户在媒体库网格中点击视频卡片（`MediaLibrary-grid-video-<文件名>`），播放器打开并开始播放。

## Driving it with playback_mode_matrix

Preconditions: TestMedia 片源已就位；没有其他常驻 runner 在运行，因为脚本会为每个 cell 自建会话，并以 `--clean` 重置状态。

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
| 结构 | 干净状态下没有持久化残留 | 模拟器单测 |
| 物理 | 落地呈现正确，画面既不是黑屏也没有冻结 | `playback_mode_matrix.py` 的双帧亮度与 SSIM 闸 |
| 感知 | 不适用（本条只证明"能播"，画面解释的正确性见 [picture-interpretation.md](picture-interpretation.md)） | |

## 证明的终态

`results.jsonl` 中该 cell 的 `verdict: PASS`，`landed` 字段记录实际落地的呈现方式（window 或 panorama）。window 落地要求控制串 `videoVisible=true` 且 lifecycle 处于稳态；panorama 落地要求探针报告 `settled=true`。此外，PASS 还必须带 `visual.verdict = content`，该判定来自双帧截图加亮度/SSIM 分析，黑屏或冻结都会判负；截图路径写在 cell 记录里，供人工复审。40 秒内未达到任一稳态即判失败，此时的证据是 cell 目录中的探针摘录与最后一条控制串。

## Gotchas

- 执行干净状态测试序列时，必须在 resetState 之后先重启 App、再导入媒体。原因是内存中仍持有的旧媒体库对象会在下一次状态变更时把已删除的引用重新写回磁盘。
- 对无信令的全景片源，landed=window 是当前的正确行为，不是失败，因为分类没有任何信息可用。启发式分类是待产品裁决的开放项。
