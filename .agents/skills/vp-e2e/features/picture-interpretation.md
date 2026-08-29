# 画面解释的正确性

本特性族关注同一段字节应当被解释成什么样的画面，涵盖三个维度：动态范围（SDR、HDR10、HLG、Dolby Vision 各 profile）、立体（左右或上下排布、MV-HEVC 双层）、投影（矩形、180°、360°、Apple Immersive）。这些解释事实由来源媒体自身声明，构成 Format Description；用户偏好只在 Media Format 中表达，不会改变来源的声明。

这是整份地图里唯一需要**感知验收**的特性族，因为"颜色对不对"这一谓词本身依赖人的判断。感知验收只覆盖动态范围这一个维度：立体与投影的画面形态由片源的构造决定，只要构造正确，画面就必然正确，因此物理证据只需要确认画面有正常显示。

## Sub-features

- HDR10 与 HLG 片源的色彩与亮度解释正确。
- 对 Dolby Vision profile 5、7 双层、8 单层、10（AV1）、20 各形态的处理。
- 向后兼容的 Dolby Vision 单层片源可以在播放中切换为其声明所对应的 HDR10 或 HLG 解释；Profile 5 不提供这一偏好。
- 立体片源的左右眼画面正确分离并呈现深度。
- 180° 与 360° 全景片源按所选覆盖角包裹画面。
- 对 Apple Immersive 投影的支持。

## How to get to it (user POV)

用户在不做任何设置的情况下就应该看到正确的画面。需要改变解释方式时，可在播放中打开 More → Video Format 菜单。

## Driving it with the verifiers 与 playback_mode_matrix

Preconditions: 结构侧验证无需设备；物理侧的前置条件与 [clean-state-playback.md](clean-state-playback.md) 相同。

结构侧的验证不需要设备参与：`Scripts/rules/verify_format_description_identity.py` 逐文件比较 FFmpeg 归一化声明与 PlaybackCore 的构造结果；`verify_source_parity_matrix.py` 对本地与远程两种取源方式逐字段比对；`check_dolby_vision_premises.py` 与 `inventory_dynamic_range_corpus.py` 分别用于验证前提与清点语料。

物理侧使用 `playback_mode_matrix.py` 按呈现格采集像素。**判读任何截图之前先检查图像尺寸**：正常截图为 1920×1080；若尺寸为 1×1，说明捕获失败，而不是画面全黑。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | `CMVideoFormatDescription` 的构造入口唯一；重建的解码器配置只填补空位，不覆盖容器原文 | `verify_format_description_ownership.py`（构建阶段强制） |
| 结构 | 语料中每个视频的 codec、色彩、range、配置 atoms 与静态 HDR 元数据均等于 FFmpeg 归一化声明；遇到未知的 Dolby Vision 声明形状时显式失败 | `verify_format_description_identity.py` |
| 结构 | Dolby Vision profile、cross-compatibility、增强层标志、立体增强层均进入 `MediaSourceInformation` | PlaybackCore 单测 |
| 结构 | HDR 回退只移除渲染输入中的 Dolby Vision 配置，并按 cross-compatibility 解释为 HDR10 或 HLG；来源 Format Description 保持不变 | PlaybackCore 单测 |
| 结构 | 本地与远程两种取源方式的结果逐字段一致 | `verify_source_parity_matrix.py --mode parity` |
| 物理 | 画面已出且既非纯色、也非冻结 | `playback_mode_matrix.py` 的双帧亮度与 SSIM 闸 |
| 物理 | 动态范围片源的采集帧没有整体色偏，也没有未解释 PQ 造成的灰雾形态 | Agent 判读，取间隔至少 1 秒的 3 帧；每轮先用 furyroad-with-dv 与 stripped 阴阳样本完成自检 |
| 感知 | 佩戴者确认动态范围各家族（HDR10、HLG、Dolby Vision 各 profile）的色彩与亮度正常 | **待做**，每家族一次 |

## 证明的终态

结构侧的终态是：构造入口唯一性检查通过；构造恒等检查中 Dolby Vision 语料零失效，其他家族的既有差异被逐项报告；来源 parity 矩阵逐字段没有传输差异。物理侧：立体与投影达到 `visual.verdict = content` 即为终态；动态范围由 Agent 判读采集帧得出结论，若判读者未通过阴阳样本自检，则本轮结论作废。感知侧的终态是佩戴者对每个动态范围家族做一次性确认。

动态范围的物理判定由 Agent 阅读采集帧作出，具体判据与自检样本见 [判读模型](../../../../docs/archive/plans/04-regression-journeys/draft.md)；验收片单记录在 `TestMedia/References/acceptance-clips.md`。Profile 5 曾经出现全程偏色而全套自动化仍然通过的情况，原因是当时结构证据无人验证、物理层没有判读者、感知验收从未执行过，三条证据线同时为空。

## Gotchas

- Profile 7 双层片源的配置记录在增强层上，而解码只走基础层；因此读取 profile 时必须从持有该配置的那条流读取。
- Dolby Vision Profile 7 会被 VideoToolbox 以 -12910 拒绝，产品的做法是拆出基础层并按 HDR10 呈现；这是既定行为，不是缺陷。
- `TestMedia` 中分辨率足够的 180° 片源有一部分是成人内容，需要目视确认时应先与佩戴者确认使用哪个片源。
