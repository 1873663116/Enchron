---
title: mpv 视频元数据检测：stereo-in 值域、HDR 检测、球面投影与 MV-HEVC
date: 2026-04-06
category: docs/solutions/best-practices/
module: PlaybackCore
problem_type: best_practice
component: tooling
severity: high
applies_when:
  - 从 mpv 属性读取立体布局（StereoLayout）时
  - 检测 HDR 类型（HDR10 / HLG / DV）时
  - 检测球面/360 投影类型（ProjectionType）时
  - 处理 Apple Spatial Video（MV-HEVC）时
tags:
  - mpv
  - stereo-in
  - hdr-detection
  - spherical-video
  - mv-hevc
  - avfoundation
  - projection-type
  - metadata
---

# mpv 视频元数据检测：stereo-in 值域、HDR 检测、球面投影与 MV-HEVC

## 背景

在 Enchron 的 PlaybackCore 层，`ProjectionDetectionUseCase` 和 `HDRDetectionUseCase` 依赖 mpv 属性来判断视频的立体布局和 HDR 类型。调研（2026-04-06）发现代码中存在若干基于错误假设的死代码，以及 mpv 完全无法支持的检测路径。这些问题不会导致运行崩溃，但会让检测逻辑静默失效，且难以发现。

当前生产播放路线是 mpv-first。本文涉及的 AVFoundation 路径用于 metadata/reference/future investigation，不表示当前已经存在或应默认实现 AVFoundation 生产播放路线。

---

## 指导原则

### 1. `video-params/stereo-in` 只输出短名称

mpv 的 `video-params/stereo-in` 属性值来自 `mp_stereo3d_names[]` 数组（`video/csputils.c`），**只输出短缩写**，从不输出长名称。

**正确值对照表：**

| mpv 字符串 | 含义 |
|-----------|------|
| `"sbs2l"` | Side-by-Side，左眼在左（最常见） |
| `"sbs2r"` | Side-by-Side，右眼在左 |
| `"ab2l"` | Above-Below（Top-Bottom），左眼在上 |
| `"ab2r"` | Above-Below（Top-Bottom），右眼在上 |
| `"mono"` | 单眼（普通 2D） |
| `""` / `"no"` | 属性不可用或无效 |

**正确的 Swift 检测写法：**

```swift
static func detectStereoLayout(stereoIn: String) -> StereoLayout {
    let s = stereoIn.lowercased().trimmingCharacters(in: .whitespaces)
    if s == "sbs2l" || s == "sbs2r" { return .sideBySide }
    if s == "ab2l"  || s == "ab2r"  { return .topBottom  }
    return .mono
}
```

**永远不会被触发的死代码（应清理）：**

```swift
// ⛔ 以下匹配永远不会命中
stereo == "side_by_side_left"   // mpv 从不输出长名称
stereo.hasPrefix("ou")          // mpv 无 "ou" 前缀值
stereo.contains("over_under")   // mpv 无此字符串
stereo.contains("top_bottom")   // mpv 无此字符串
```

---

### 2. `video-params/hdr-format` 属性不存在

mpv 的标准属性列表（`player/command.c`）中**不存在** `video-params/hdr-format`。调用 `stringProperty("video-params/hdr-format")` 永远返回 `nil` / 空字符串，该调用无效，应删除。

**HDR 类型检测应完全依赖 `video-params/gamma`（传输函数）：**

| gamma 值 | HDR 类型 |
|---------|---------|
| `"pq"` / `"smpte2084"` | HDR10（可结合 max-cll/max-fall 确认） |
| `"hlg"` / `"arib-std-b67"` | HLG |
| `"bt.1886"` / `"srgb"` / `"linear"` | SDR |
| `"v-log"` / `"s-log1"` / `"s-log2"` | 对数曲线（LOG素材） |

**完整 HDR 决策树（优先级从高到低）：**

```
1. Dolby Vision：
   - video-params/colormatrix 包含 "dolby" / "dovi"，或
   - track-list/N/dolby-vision-profile 存在（> 0）
   → HDRType = .dolbyVision

2. HLG：
   - video-params/gamma = "hlg" 或 "arib-std-b67"
   → HDRType = .hlg

3. HDR10+：
   - video-params/scene-max-r 属性可用（有值）
   → HDRType = .hdr10Plus

4. HDR10：
   - video-params/gamma = "pq" 或 "smpte2084"，或
   - video-params/max-luma 属性可用（> 0）
   → HDRType = .hdr10

5. 峰值回退（低可信度）：
   - video-params/sig-peak > 1.05 且 primaries 包含 "bt.2020"
   → HDRType = .hdr10（保守使用，标注置信度低）

6. 其他 → HDRType = .sdr
```

---

### 3. mpv 不读取 FFmpeg `AV_PKT_DATA_SPHERICAL` side data

对于 MP4/MOV 球面视频，`metadata/by-key/GSpherical:*` 属性**始终为空**，即使文件包含 sv3d/st3d box 或 GSpherical V1 UUID box。

**原因链：**

1. FFmpeg 的 `mov.c` 解析 sv3d/st3d/UUID box → 写入 `AV_PKT_DATA_SPHERICAL` side data，**不写入** `st->metadata` 字典
2. mpv 的 `demux_lavf.c` **不读取** `AV_PKT_DATA_SPHERICAL` side data，不将其转为 `metadata/by-key/` 键值对
3. WebM/MKV 路径同理：FFmpeg 的 matroska demuxer 通过 `mkv_parse_video_projection()` 解析投影写入 side data，mpv 也不读取

**结论：** 对于 MP4/MOV 球面视频，mpv 目前**无法通过任何标准属性**得知"这是 360 度等距球面"。

**各格式 mpv 可检测内容：**

| 检测目标 | 格式 | mpv 是否支持 | 正确路径 |
|---------|------|------------|---------|
| SBS/TB 立体布局 | MKV、MP4 | ✅ 支持 | `video-params/stereo-in` |
| 360 等距球面投影 | MP4/MOV | ❌ 不支持 | 需要 AVFoundation 预扫描 |
| 360 等距球面投影 | MKV | ❌ 不支持 | ProjectionType 解析了但不暴露 |
| GSpherical 元数据 | MP4/MOV | ❌ 不支持 | 仅转 side data，不进 metadata dict |

**检测 MP4/MOV 球面投影的正确方案：**

- **方案 A（推荐）**：AVFoundation 预扫描，播放前通过 `AVAssetTrack` 读取 `AVSphericalMapping`
- **方案 B**：通过 mpv client API 在 demux 后直接读取 `ff_side_data`（侵入性较高）

---

### 4. Apple MV-HEVC 需要 Apple 平台能力研究，mpv 当前无法处理

Apple Spatial Video（MV-HEVC 格式）使用 VEXU box 标识立体视图，FFmpeg 和 mpv 目前均不解析 VEXU，无法识别左右眼视图。

**检测 / reference 研究应通过 AVFoundation：**

```swift
// 检测是否为 Apple Spatial Video
let formatDescriptions = track.formatDescriptions as! [CMFormatDescription]
for desc in formatDescriptions {
    if let stereoView = CMFormatDescriptionGetExtension(
        desc,
        extensionKey: kCMFormatDescriptionExtension_StereoViewComponent
    ) {
        // 这是 MV-HEVC 空间视频
    }
}
```

**Apple MV-HEVC 特性：**
- 投影类型固定为 flat（不是球面格式）
- 立体布局通过 AVFoundation `AVVideoCompositionInstruction` 或 `AVSampleBufferDisplayLayer` 的立体配置读取
- 当前 mpv 生产路径不能声明 MV-HEVC / Spatial Video 支持。未来如需 Apple AV 生产播放路径，必须先经过显式架构决策、能力边界、测试依据和文档更新。

---

## 为何重要

这些错误假设会导致静默的检测失效：
- 死代码的匹配条件永远不触发，但不会报错，容易被忽视
- `hdr-format` 属性返回空字符串会触发 fallthrough 到 gamma-based 检测（碰巧不总是错的，但逻辑是错的）
- GSpherical metadata 始终为空会导致 MP4/MOV 360 视频永远被识别为普通视频
- 走 mpv 路径尝试声明 MV-HEVC / Spatial Video 支持会导致播放失败或无法识别空间视频

---

## 适用场景

- 实现或修改 `ProjectionDetectionUseCase`、`StereoLayoutDetectionUseCase`、`HDRDetectionUseCase` 时
- 添加新的视频格式支持（360°、空间视频、HDR 格式）时
- 调试"为何球面视频/HDR 视频没有被正确识别"时
- 评估 mpv 能力边界或未来 AVFoundation / AVKit 平台能力时

---

## 示例

**错误写法（来自原始代码，已识别为死代码）：**

```swift
// ⛔ 死代码：mpv 不输出长名称
if stereo == "side_by_side_left" { return .sideBySide }
if stereo.contains("over_under") { return .topBottom }

// ⛔ 无效属性：永远返回 nil
let hdrFormat = stringProperty("video-params/hdr-format")

// ⛔ 永远为空：mpv 不读取 AV_PKT_DATA_SPHERICAL
let isSpherical = metadata["GSpherical:Spherical"] == "true"
```

**正确写法：**

```swift
// ✅ 使用精确短名称匹配 stereo-in
if s == "sbs2l" || s == "sbs2r" { return .sideBySide }
if s == "ab2l"  || s == "ab2r"  { return .topBottom  }

// ✅ 使用 gamma 属性检测 HDR 传输函数
let gamma = stringProperty("video-params/gamma") ?? ""
if gamma == "pq" || gamma == "smpte2084" { hdrType = .hdr10 }
if gamma == "hlg" || gamma == "arib-std-b67" { hdrType = .hlg }

// ✅ MP4/MOV 球面视频 → AVFoundation 预扫描路径
// mpv 路径无法检测 MP4/MOV 球面投影

// ✅ MV-HEVC → 当前 mpv 生产路径 unsupported；使用 AVFoundation 做检测 / reference 研究
// 例如 CMFormatDescription + kCMFormatDescriptionExtension_StereoViewComponent
```

---

## 相关

- 调研报告：`docs/archive/investigations/2026-04-06-mpv-metadata-investigation.md`
- mpv 属性文档：`video/csputils.c`（mp_stereo3d_names）、`player/command.c`
- FFmpeg：`libavformat/mov.c`（st3d/sv3d 解析）、`libavutil/spherical.h`
- Apple WWDC23 Session 10071（MV-HEVC / Apple Spatial Video）
- Matroska 规范：StereoMode（EBML 0x53B8）、ProjectionType（EBML 0x7671）
