# 画面解释的正确性

同一段字节被解释成什么样的画面：动态范围（SDR、HDR10、HLG、Dolby Vision 各 profile）、立体（左右或上下排布、MV-HEVC 双层）、投影（矩形、180°、360°、Apple Immersive）。这些事实由来源媒体声明，构成 Format Description；用户偏好只在 Media Format 里表达，不改变来源声明。

这是整份地图里唯一需要**感知验收**的特性族，因为"颜色对不对"的谓词本身是人的判断。感知验收只覆盖动态范围：立体与投影的画面由片源构造决定，构造正确画面必然正确，物理证据只需确认有正常显示。

## Sub-features

- HDR10 与 HLG 片源的色彩与亮度。
- Dolby Vision profile 5、7 双层、8 单层、10（AV1）、20 的处理。
- 立体片源的左右眼分离与深度。
- 180° 与 360° 全景按所选覆盖角包裹。
- Apple Immersive 投影。

## How to get to it (user POV)

用户不做任何设置就应该看到正确画面。需要改变解释方式时，播放中 More → Video Format。

## Driving it

结构侧不需要设备：`Scripts/verification/verify_source_parity_matrix.py` 扫语料并逐字段比对本地与远程两种取源方式；`Scripts/verification/check_dolby_vision_premises.py` 与 `inventory_dynamic_range_corpus.py` 分别验前提与清点语料。

物理侧用 `playback_mode_matrix.py` 按呈现格取像素。**判读任何截图前先看尺寸**：正常 1920×1080，1×1 表示捕获失败而不是画面全黑。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | `CMVideoFormatDescription` 构造入口唯一；重建的解码器配置只补空位不覆盖容器原文 | `verify_format_description_ownership.py`（构建阶段强制） |
| 结构 | Dolby Vision profile、cross-compatibility、增强层标志、立体增强层进入 `MediaSourceInformation` | PlaybackCore 单测 |
| 结构 | 本地与远程两种取源方式逐字段一致 | `verify_source_parity_matrix.py --mode parity` |
| 物理 | 出画且非纯色、非冻结 | `playback_mode_matrix.py` 的双帧亮度与 SSIM 闸 |
| 物理 | 动态范围片源的采集帧与验收参照物的差异在阈值内 | `verify_reference_frames.py`，参照物由验收场铸造，缺参照时以退出码 2 大声失败 |
| 感知 | 佩戴者确认动态范围各家族（HDR10、HLG、Dolby Vision 各 profile）色彩与亮度正常 | **待做**，每家族一次，确认帧即成参照物 |

## 证明的终态

结构侧：三个脚本零失效，且 parity 矩阵改动前后逐字段无差异。物理侧：立体与投影 `visual.verdict = content` 即为终态；动态范围还需与参照物比对在阈值内。感知侧：佩戴者对每个动态范围家族一次性确认，确认当时采集的帧成为参照物，此后由机器比对。

参照物由 `verify_reference_frames.py` 铸造与比对，本体存放在 `TestMedia/References/`，验收片单在其 `acceptance-clips.md`。Profile 5 全程偏色时全套自动化通过，正是因为结构证据没人验、物理证据没有参照、感知验收没做过，三条同时为空。

## Gotchas

- Profile 7 双层源的配置记录在增强层上，而解码只走基础层；读 profile 要从持有它的那条流读。
- Dolby Vision Profile 7 被 VideoToolbox 以 -12910 拒绝，产品做法是拆基础层按 HDR10 呈现，这是既定行为不是缺陷。
- `TestMedia` 中分辨率足够的 180° 片源部分是成人内容，需要目视确认时先与佩戴者确认用哪个片源。
