---
date: 2026-04-06
topic: mpv-metadata-investigation
status: COMPLETE
---

# mpv 元数据调研报告 — ProjectionType & StereoLayout 检测

> 当前生产播放路线是 mpv-first。本文关于 AVFoundation 的内容用于 metadata/reference/future investigation，不表示当前已经存在或应默认实现 AVFoundation 生产播放路线。

## 1. mpv `video-params/stereo-in` 属性

### 1.1 数据来源

`video-params/stereo-in` 是 mpv 从 `mp_image_params.stereo3d` 字段读取后转为字符串的属性，通过 `mp_stereo3d_names[]` 表映射。

- **MKV/WebM**：mpv 自有 demux_mkv.c 直接读取 EBML `StereoMode` 元素并赋值给 `track->stereo_mode`，最终转入 `sh_v->stereo_mode`，再通过 `opaque_ref` 传递给解码帧的 `params.stereo3d`。
- **MP4/MOV**：FFmpeg (libavformat) 解析 `st3d` box → `AVStereo3DType` side data → mpv 的 `mp_image_from_av_frame()` 从 `src->opaque_ref` 中读取（**不是**从 `AV_FRAME_DATA_STEREO3D` side data）。

> **重要**：mpv 目前 **不读取** `AV_FRAME_DATA_STEREO3D` 帧 side data，`stereo3d` 来源是 decode 层通过 `opaque_ref` 传递的 codec 参数。

### 1.2 完整值表（来源：mpv/video/csputils.c `mp_stereo3d_names[]`）

| mpv 字符串 | 含义 | 对应 Matroska StereoMode 值 |
|-----------|------|--------------------------|
| `"no"` / `""` | 无效/单眼（mono） | N/A（内部 -1） |
| `"mono"` | 单眼 | 0 |
| `"sbs2l"` | Side-by-Side，左眼在左 | 1 |
| `"ab2r"` | Above-Below，右眼在上 | 2 |
| `"ab2l"` | Above-Below，左眼在上 | 3 |
| `"checkr"` | Checkerboard，右眼先 | 4（vf_stereo3d 不支持） |
| `"checkl"` | Checkerboard，左眼先 | 5（vf_stereo3d 不支持） |
| `"irr"` | Row Interleaved，右眼先 | 6 |
| `"irl"` | Row Interleaved，左眼先 | 7 |
| `"icr"` | Column Interleaved，右眼先 | 8（不支持） |
| `"icl"` | Column Interleaved，左眼先 | 9（不支持） |
| `"arcc"` | Anaglyph Cyan/Red | 10 |
| `"sbs2r"` | Side-by-Side，右眼在左 | 11 |
| `"agmc"` | Anaglyph Green/Magenta | 12 |
| `"al"` | Alternating frames，左眼先 | 13 |
| `"ar"` | Alternating frames，右眼先 | 14 |

### 1.3 与 StereoLayout 的映射关系

```
sideBySide: "sbs2l" | "sbs2r"
topBottom:  "ab2l"  | "ab2r"
mono:       "mono"  | "" | "no"（或属性不可用）
```

**当前代码（ProjectionDetection.swift）覆盖分析：**
- `stereo.contains("sbs")` → 命中 `sbs2l`、`sbs2r` ✓
- `stereo == "side_by_side_left"` → 永远不会命中（mpv 不输出该字符串）⚠️
- `stereo.hasPrefix("ab")` → 命中 `ab2l`、`ab2r` ✓
- `stereo.hasPrefix("ou")` → 永远不会命中（mpv 无 `ou` 前缀值）⚠️
- `stereo.contains("over_under")` → 永远不会命中 ⚠️
- `stereo.contains("top_bottom")` → 永远不会命中 ⚠️

**结论**：OBsolete 字符串匹配（`"side_by_side_left"`, `"over_under_*"`, `"top_bottom"`）永远不会被 mpv 触发，应清理。正确值是 `"ab2l"`, `"ab2r"`, `"sbs2l"`, `"sbs2r"`。

---

## 2. `video-params` 完整相关属性（来源：mpv master player/command.c）

以下属性均通过 `video-params/<name>` 访问：

| 属性名 | 类型 | 说明 |
|--------|------|------|
| `stereo-in` | String | 见上节 |
| `primaries` | String | 色域，见 §5 |
| `gamma` | String | 传输函数，见 §5 |
| `colormatrix` | String | 色彩矩阵，见 §5 |
| `colorlevels` | String | `"limited"` / `"full"` |
| `sig-peak` | Float | 信号峰值（已废弃，用 `max-luma / 203.0`） |
| `min-luma` | Float | HDR10 最小亮度（cd/m²），unavailable on SDR |
| `max-luma` | Float | HDR10 最大亮度（cd/m²），unavailable on SDR |
| `max-cll` | Float | 最大内容亮度，unavailable on SDR |
| `max-fall` | Float | 最大平均亮度，unavailable on SDR |
| `scene-max-r/g/b` | Float | HDR10+ 场景最大值，unavailable on non-HDR10+ |
| `scene-avg` | Float | HDR10+ 场景平均值 |
| `max-pq-y` | Float | PQ 峰值亮度（0-1） |
| `w`, `h` | Int | 原始分辨率 |
| `dw`, `dh` | Int | 显示分辨率（含 SAR） |
| `rotate` | Int | 旋转角度（顺时针度数） |
| `pixelformat` | String | 像素格式 |

> **⚠️ 关键发现**：`video-params/hdr-format` **不是** mpv 的标准属性，它不在 mpv 文档和源码的属性列表中。Enchron 现有代码中调用 `stringProperty("video-params/hdr-format")` 将始终返回 `nil`（空字符串），该调用无效。

---

## 3. `metadata/by-key/GSpherical:*` 属性

### 3.1 关键发现：GSpherical 元数据不通过 metadata/by-key 暴露

调查结论：**mpv 的 `metadata/by-key/GSpherical:Spherical` 等 GSpherical 键名在实践中大概率为空**。

原因链：

1. **MOV/MP4 文件中的 GSpherical V1**（UUID box 中的 XMP XML）：  
   FFmpeg `mov_parse_uuid_spherical()` 解析 XML，但将结果写入 `sc->spherical`（`AVSphericalMapping` side data），**不写入** `st->metadata` 字典。
   
2. **MOV/MP4 文件中的 sv3d/st3d（GSpherical V2）**：  
   FFmpeg `mov_read_st3d()` / `mov_read_sv3d()` 同样只写 side data（`AV_PKT_DATA_SPHERICAL`、`AV_PKT_DATA_STEREO3D`），不写 metadata dict。

3. **mpv demux_lavf.c**：不读取 `AV_PKT_DATA_SPHERICAL` side data，不将其转为 `metadata/by-key/` 键值对。

4. **WebM/MKV 中的 GSpherical**：WebM 使用 GSpherical V1 元数据（track header 中的 XML tags）。FFmpeg 的 matroska demuxer 通过 `mkv_parse_video_projection()` 解析投影，写入 side data，不写 metadata dict。

**例外情况**：如果 MOV/MP4 的 `moov.udta` 或 `moov.meta.ilst` 区段有用户自定义 GSpherical 元数据标签，mpv 可能通过 `mp_tags_move_from_av_dictionary` 将其暴露到 `metadata/by-key/`。但这不是标准路径，不可依赖。

### 3.2 正确检测路径

| 检测目标 | 正确路径 | 说明 |
|---------|---------|------|
| 球面投影类型 | `video-params/stereo-in` 判 mono/SBS/TB；mpv 目前无球面投影类型属性 | 见 §4 |
| SBS 立体 | `video-params/stereo-in` = `"sbs2l"` / `"sbs2r"` | ✓ 可靠 |
| TopBottom 立体 | `video-params/stereo-in` = `"ab2l"` / `"ab2r"` | ✓ 可靠 |
| 360 等距球面 | `video-params/stereo-in` 为空/mono + 宽高比约 2:1 → 猜测（不可靠） | 见 §4 |

---

## 4. mpv 对球面视频（Spherical Video）的支持现状

### 4.1 MKV/WebM

- **StereoMode 元素**：完全支持，直接映射到 `video-params/stereo-in`（见 §1）。
- **Projection 元素**（ProjectionType 0-3）：mpv 的 `demux_mkv.c` 读取 yaw/pitch/roll，但**不支持非零 yaw/pitch**（输出 warning）；ProjectionType 本身未暴露为 mpv 属性。

### 4.2 MP4/MOV（GSpherical V1 & sv3d V2）

- **st3d box**：FFmpeg 解析 → `AVStereo3DType` side data → 通过 codec opaque_ref → `video-params/stereo-in`（应该有效）。
- **sv3d box（equi/cbmp 子 box）**：FFmpeg 解析 → `AVSphericalMapping` side data → mpv 不读取，**不暴露为任何 mpv 属性**。
- **GSpherical V1 UUID box（XMP XML）**：同上，只到 side data，mpv 不读取。

**结论**：对于 MP4/MOV 球面视频，mpv 无法通过任何标准属性得知"这是 360 度等距球面"。仅 StereoLayout（SBS/TB）可以通过 `stereo-in` 获得。

### 4.3 Apple MV-HEVC（空间视频）

mpv 当前无法处理 MV-HEVC 空间视频：

- MV-HEVC 使用 VEXU box（View EXtension Unit）标识立体视图
- ffmpeg/mpv 目前不解析 VEXU，无法识别左右眼视图
- Apple MV-HEVC 空间视频需要通过 AVFoundation / AVKit 做 metadata、reference 或未来 Apple-native 生产路线研究；当前 mpv 生产路径不能声明支持

---

## 5. HDR 类型检测

### 5.1 mpv `video-params/primaries` 可能值（来源：libplacebo `pl_csp_prim_names[]`）

| 字符串值 | 色域标准 |
|---------|---------|
| `"bt.709"` | BT.709（HD 标准，SDR） |
| `"bt.2020"` | BT.2020（UHD，HDR 内容常用） |
| `"display-p3"` | Display P3（iOS/macOS 屏幕） |
| `"dci-p3"` | DCI P3（电影标准） |
| `"bt.601-525"` | NTSC SD |
| `"bt.601-625"` | PAL/SECAM SD |
| `"bt.470m"` | M 型 |
| `"adobe"` | Adobe RGB |
| `"prophoto"` | ProPhoto |
| `"cie1931"` | CIE 1931 |
| `"v-gamut"` | V-Gamut（Panasonic） |
| `"s-gamut"` | S-Gamut（Sony） |

### 5.2 mpv `video-params/gamma` 可能值（来源：libplacebo `pl_csp_trc_names[]`）

| 字符串值 | 传输函数 | HDR 类型 |
|---------|---------|---------|
| `"bt.1886"` | BT.1886（SD/HD 参考显示） | SDR |
| `"srgb"` | sRGB | SDR |
| `"linear"` | 线性 | SDR |
| `"gamma1.8"`~`"gamma2.8"` | 伽马曲线 | SDR |
| `"pq"` 或 `"smpte2084"` | PQ（感知量化器） | **HDR10 / HDR10+** |
| `"hlg"` 或 `"arib-std-b67"` | HLG（混合对数伽马） | **HLG** |
| `"v-log"` | V-Log（Panasonic） | 对数曲线 |
| `"s-log1"` / `"s-log2"` | S-Log（Sony） | 对数曲线 |
| `"prophoto"` | ProPhoto | SDR |
| `"st428"` | ST 428（DCDM） | |
| `"scrgb"` | scRGB | HDR-like |

### 5.3 HDR 类型推断决策树（修正版）

```
1. Dolby Vision：
   - video-params/colormatrix 包含 "dolby" 或 "dovi"，或
   - track-list/N/dolby-vision-profile 存在（> 0）
   → HDRType = .dolbyVision

2. HLG：
   - video-params/gamma = "hlg" 或 "arib-std-b67"
   → HDRType = .hlg

3. HDR10+：
   - video-params/scene-max-r 属性可用（has_hdr10plus 为 true）
   → HDRType = .hdr10Plus

4. HDR10：
   - video-params/gamma = "pq" 或 "smpte2084"，或
   - video-params/max-luma 属性可用（> 0）
   → HDRType = .hdr10

5. 峰值回退：
   - video-params/sig-peak > 1.05 且 video-params/primaries 包含 "bt.2020"
   → HDRType = .hdr10（不可靠，保守使用）

6. 其他 → HDRType = .sdr
```

> **修正**：`video-params/hdr-format` 不是有效的 mpv 属性，当前代码读取它永远得到空字符串。应移除该调用，改用 `video-params/gamma` 作为主要 HDR 传输函数检测依据。

---

## 6. 容器格式元数据字段映射

### 6.1 MKV/WebM

| 信息 | EBML 元素 | mpv 暴露方式 |
|------|----------|------------|
| 立体布局 | `StereoMode`（EBML ID: 0x53B8） | `video-params/stereo-in` |
| 投影类型 | `ProjectionType`（EBML ID: 0x7671）值：0=矩形,1=等距球面,2=立方体,3=网格 | **未暴露**（解析但不传递） |
| 投影朝向 | `ProjectionPoseYaw/Pitch/Roll`（±180°/±90°/±180°） | **未暴露**（记录 warning） |

### 6.2 MP4/MOV

| 信息 | box 路径 | mpv 暴露方式 |
|------|---------|------------|
| 立体布局（V2） | `st3d`（stereo_mode: 0=mono,1=TB,2=LR） | `video-params/stereo-in`（通过 FFmpeg side data → opaque_ref） |
| 球面投影（V2） | `sv3d > proj > equi/cbmp` | **未暴露** |
| 球面投影（V1） | UUID box（XMP XML）中的 GSpherical 字段 | **未暴露**（仅转 side data） |
| 立体布局（V1） | GSpherical:StereoMode XML 标签（mono/left-right/top-bottom） | **未暴露** |

**st3d 与 mpv stereo-in 的映射**（FFmpeg mov.c `mov_read_st3d()`）：

| st3d mode 值 | FFmpeg AVStereo3DType | mpv stereo-in |
|-------------|---------------------|--------------|
| 0 | AV_STEREO3D_2D | `"mono"` |
| 1 | AV_STEREO3D_TOPBOTTOM | `"ab2l"` 或 `"ab2r"` |
| 2 | AV_STEREO3D_SIDEBYSIDE | `"sbs2l"` 或 `"sbs2r"` |

### 6.3 Apple MV-HEVC

| 信息 | 检测方式 |
|------|---------|
| 是否空间视频 | `CMFormatDescription` 中 VEXU box 的 `eyes` 字段，或 AVAssetTrack 的 `formatDescriptions` 检查 `kCMFormatDescriptionExtension_StereoViewComponent` |
| 立体布局 | 固定为 MV-HEVC 编码（左眼 base view，右眼差分），通过 AVFoundation `AVVideoCompositionInstruction` 或 `AVSampleBufferDisplayLayer` 的立体配置读取 |
| 投影类型 | 固定为平面（`flat`）；Apple MV-HEVC 不是球面格式 |

**mpv 当前不支持 MV-HEVC**。生产支持应保持 unsupported，除非未来 Apple-native 路线经过显式架构决策。

---

## 7. 完整检测策略（正确版）

### 7.1 投影类型（ProjectionType）检测

```
数据来源优先级：

1. 容器格式判断（文件扩展名 / video-codec）：
   - codec = "hevc" 且为 Apple MV-HEVC → flat（AVFoundation metadata/reference 路径；当前生产播放 unsupported）
   
2. mpv 球面元数据（目前仅 WebM/MKV via st_metadata["stereo_mode"]）：
   - 当前 mpv 不暴露 MKV ProjectionType，无法可靠检测球面投影

3. GSpherical 元数据（仅 WebM/移动端 GSpherical 视频）：
   - metadata/by-key/GSpherical:Spherical = "true" → 有球面元数据
   - metadata/by-key/GSpherical:ProjectionType = "equirectangular" → 360 等距
   （注意：此路径仅在容器将 GSpherical 写入 metadata dict 时有效，非标准）

4. 宽高比启发式（最后兜底，低可信度）：
   - 宽高比 ≈ 2:1（equirectangular 360）
   - 宽高比 ≈ 1:1（equirectangular 180 或 fisheye）
   
→ 应在 ProjectionDetectionInput 中标记检测置信度
```

**结论**：对于 MP4/MOV 球面视频，mpv 目前**无法可靠检测球面投影类型**。这是架构上的空缺，需要：
- 方案 A：使用 AVFoundation 预扫描，在播放前读取 `AVSphericalMapping`
- 方案 B：通过 mpv `--input-ipc-server` 或 client API 在 demux 后读取 `ff_side_data`

### 7.2 立体布局（StereoLayout）检测（修正版）

```swift
static func detectStereoLayout(stereoIn: String) -> StereoLayout {
    let s = stereoIn.lowercased().trimmingCharacters(in: .whitespaces)
    
    // SBS（Side-by-Side）
    if s == "sbs2l" || s == "sbs2r" {
        return .sideBySide
    }
    
    // Top-Bottom（AB = Above-Below）
    if s == "ab2l" || s == "ab2r" {
        return .topBottom
    }
    
    // Mono（包括 "mono", "", "no", 属性不可用）
    return .mono
}
```

### 7.3 HDR 类型检测（修正版，移除 hdr-format）

主要依赖：
- `video-params/gamma`（传输函数）
- `track-list/N/dolby-vision-profile`
- `video-params/scene-max-r` 可用性（HDR10+ 标志）
- `video-params/sig-peak` 或 `max-luma / 203.0`
- `video-params/primaries`（BT.2020 辅助信号）

---

## 8. 关键 Bug 与遗漏

| 编号 | 问题 | 影响 | 修复方向 |
|------|------|------|---------|
| B1 | `stringProperty("video-params/hdr-format")` 永远返回 nil | HDR 检测逻辑中该字段始终为空字符串，fallthrough 到 gamma-based 检测 | 删除该调用，全依赖 gamma/primaries |
| B2 | `stereo.contains("top_bottom")` 等匹配永远不命中 | 无实际影响（ab2l/ab2r 已被 `hasPrefix("ab")` 命中） | 清理死代码，改用 `"ab2l" / "ab2r"` 精确匹配 |
| G1 | MP4/MOV 球面视频投影类型无法检测 | 360 等距 MP4 文件在 mpv 路径下无法被识别为球面 | 需要 AVFoundation 预扫描 |
| G2 | MKV Projection element 类型不暴露 | MKV 球面视频只能靠 StereoMode，不能知道是等距还是立方体 | 上游 mpv 功能缺口 |
| G3 | Apple MV-HEVC 当前不能走 mpv 生产路径 | 空间视频 mpv 无法处理 | 保持生产 unsupported；AVFoundation / AVKit 仅作 reference 或未来路线研究 |

---

## 9. 参考来源

- mpv 源码：`video/csputils.c`（mp_stereo3d_names）、`player/command.c`（属性定义）、`video/mp_image.c`（帧转换）、`demux/demux_mkv.c`（MKV demux）、`demux/demux_lavf.c`（FFmpeg 封装）
- FFmpeg 源码：`libavformat/mov.c`（MP4 st3d/sv3d 解析）、`libavformat/matroskadec.c`（MKV spherical 解析）、`libavutil/spherical.h`（AVSphericalProjection 枚举）
- Matroska 规范：StereoMode（0x53B8）、ProjectionType（0x7671）
- Google Spatial Media RFC V1/V2（GSpherical、sv3d、st3d）
- WWDC23 Session 10071（Apple MV-HEVC）
