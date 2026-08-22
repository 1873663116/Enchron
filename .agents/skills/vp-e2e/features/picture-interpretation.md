# 画面解释的正确性

同一段字节被解释成什么样的画面：动态范围（SDR、HDR10、HLG、Dolby Vision 各 profile）、立体（左右或上下排布、MV-HEVC 双层）、投影（矩形、180°、360°、Apple Immersive）。这些事实由来源媒体声明，构成 Format Description；用户偏好只在 Media Format 里表达，不改变来源声明。

这是整份地图里唯一需要**感知验收**的特性族，因为"颜色对不对"的谓词本身是人的判断。感知验收只覆盖动态范围：立体与投影的画面由片源构造决定，构造正确画面必然正确，物理证据只需确认有正常显示。

## Sub-features

- HDR10 与 HLG 片源的色彩与亮度。
- Dolby Vision profile 5、7 双层、8 单层、10（AV1）、20 的处理。
- 向后兼容的 Dolby Vision 单层片源可在播放中切换到声明对应的 HDR10 或 HLG 解释；Profile 5 不提供该偏好。
- 立体片源的左右眼分离与深度。
- 180° 与 360° 全景按所选覆盖角包裹。
- Apple Immersive 投影。

## How to get to it (user POV)

用户不做任何设置就应该看到正确画面。需要改变解释方式时，播放中 More → Video Format。

## Driving it

结构侧不需要设备：`Scripts/verification/verify_format_description_identity.py` 逐文件比较 FFmpeg 归一化声明与 PlaybackCore 构造结果；`verify_source_parity_matrix.py` 逐字段比对本地与远程两种取源方式；`check_dolby_vision_premises.py` 与 `inventory_dynamic_range_corpus.py` 分别验前提与清点语料。

物理侧用 `playback_mode_matrix.py` 按呈现格取像素。**判读任何截图前先看尺寸**：正常 1920×1080，1×1 表示捕获失败而不是画面全黑。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | `CMVideoFormatDescription` 构造入口唯一；重建的解码器配置只补空位不覆盖容器原文 | `verify_format_description_ownership.py`（构建阶段强制） |
| 结构 | 语料中每个视频的 codec、色彩、range、配置 atoms 与静态 HDR 元数据等于 FFmpeg 归一化声明；Dolby Vision 未知声明形状显式失败 | `verify_format_description_identity.py` |
| 结构 | Dolby Vision profile、cross-compatibility、增强层标志、立体增强层进入 `MediaSourceInformation` | PlaybackCore 单测 |
| 结构 | HDR 回退只移除渲染输入的 Dolby Vision 配置，并按 cross-compatibility 解释为 HDR10 或 HLG；来源 Format Description 保持不变 | PlaybackCore 单测 |
| 结构 | 本地与远程两种取源方式逐字段一致 | `verify_source_parity_matrix.py --mode parity` |
| 物理 | 出画且非纯色、非冻结 | `playback_mode_matrix.py` 的双帧亮度与 SSIM 闸 |
| 物理 | 动态范围片源的采集帧无整体色偏、无未解释 PQ 的灰雾形态 | Agent 判读，间隔至少 1 秒的 3 帧；每轮先判 furyroad-with-dv 与 stripped 阴阳样本自检 |
| 感知 | 佩戴者确认动态范围各家族（HDR10、HLG、Dolby Vision 各 profile）色彩与亮度正常 | **待做**，每家族一次 |

## 证明的终态

结构侧：构造入口唯一性通过；构造恒等检查中的 Dolby Vision 语料零失效，其他家族的既有差异逐项报告；来源 parity 矩阵逐字段无传输差异。物理侧：立体与投影 `visual.verdict = content` 即为终态；动态范围由 Agent 判读采集帧，判读者未通过阴阳样本自检时本轮结论作废。感知侧：佩戴者对每个动态范围家族一次性确认。

动态范围的物理判定由 Agent 读采集帧作出，判据与自检样本见 [判读模型](../../../../docs/plans/04-regression-journeys/draft.md)。验收片单在 `TestMedia/References/acceptance-clips.md`。Profile 5 曾经全程偏色而全套自动化通过，因为当时结构证据没人验、物理层没有判读者、感知验收没做过，三条同时为空。

## Gotchas

- Profile 7 双层源的配置记录在增强层上，而解码只走基础层；读 profile 要从持有它的那条流读。
- Dolby Vision Profile 7 被 VideoToolbox 以 -12910 拒绝，产品做法是拆基础层按 HDR10 呈现，这是既定行为不是缺陷。
- `TestMedia` 中分辨率足够的 180° 片源部分是成人内容，需要目视确认时先与佩戴者确认用哪个片源。
