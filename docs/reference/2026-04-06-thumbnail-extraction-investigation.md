# 缩略图提取技术调研

**日期**：2026-04-06  
**范围**：封面提取、帧提取作为缩略图、缓存策略、推荐方案  
**项目**：Enchron — visionOS 视频播放器

---

## 1. 内嵌封面提取

### 1.1 mpv/libmpv API 路径

**MKV Attached Picture / MP4 Cover Art**

mpv（通过 FFmpeg demuxer）将容器内嵌的封面图（Matroska `AttachedFile` element、MP4 `covr` atom、MP3 ID3 `APIC` frame）统一解析为**视频轨道**，而非独立的 metadata 字段。

关键属性路径：
- `track-list/N/type` — 返回 `"video"` （嵌入封面与真实视频轨一样被标记为 video）
- `track-list/N/image` — **boolean 属性**，当该视频轨是静态图像（embedded cover art、attached picture）时返回 `true`。这是区分"封面图"和"真实视频轨"的唯一正式 API。
- `track-list/N/title` — 封面图的轨道标题，如 `"Cover"` 或 `"Album Art"`
- `audio-display` 选项：当播放纯音频文件时，mpv 用第一个 `image=true` 的视频轨作为封面展示

**提取封面 bitmap 的方式**：

mpv 本身不提供"把 cover art 输出为文件"的 API。一旦识别到目标轨道号（`track-list/N/image == true`），可以：
1. 向 mpv 实例发送 `["set", "vid", "<track_id>"]` 切到封面轨
2. 立即发 `["screenshot-to-file", "<output_path>", "video"]` 截帧
3. 读回图片文件
4. 恢复 `vid` 到原视频轨

这个流程对当前播放实例有侵入性（会短暂切换视频轨），**正确做法是使用独立的 mpv 实例**（见第 2.2 节）。

**`metadata/by-key/` 路径**：无法访问封面 bitmap。它只用于容器级文字 metadata（如 `GSpherical:*`、`title`、`artist` 等），不包含二进制图像数据。项目代码中已有对该路径的使用（见 `MPVPlayerAdapter.swift:1238-1258`）。

### 1.2 AVFoundation 路径

`AVAsset.metadata` + `AVMetadataItem` 理论上可访问 MP4/M4V/MOV 的 `covr` atom：

```swift
let item = AVMetadataItem.metadataItems(
    from: asset.commonMetadata,
    withKey: AVMetadataKey.commonKeyArtwork,
    keySpace: .common
).first
let imageData = item?.dataValue // JPEG/PNG raw bytes
```

**限制**：
- **只支持 AVFoundation 原生容器**：MP4/MOV/M4V/MP3/AAC/ALAC。**MKV、WebM、AVI 不支持**（AVFoundation 不含 Matroska demuxer）。
- **远程 URL**：`AVURLAsset` 支持 HTTP/HTTPS URL，但 SMB/WebDAV URL（smb://、http:// 经由 AMSMB2 处理）不能直接用 AVFoundation 打开。WebDAV 可以通过 HTTP URL 访问，有一定可能性，但需要认证 header 注入，AVFoundation 无法传递 SMB NTLM 凭证。
- **格式兼容性差**：无法覆盖 Enchron 需要的全部格式（MKV/WebM 缺失）。

**结论**：AVFoundation 封面提取仅作为 MP4/MOV 本地文件的**补充路径**，不能作为主路径。

### 1.3 优先级

```
mpv track-list image track + screenshot-to-file（独立实例）
    > AVFoundation commonMetadata.artwork（MP4/MOV 本地文件限定）
    > 直接解析容器（过度工程，跳过）
```

---

## 2. 帧提取作为缩略图

### 2.1 mpv API 路径

**`screenshot-to-file` 命令**

项目已有实现：`MPVPlayerAdapter.captureScreenshot(to:flags:)` 调用 `["screenshot-to-file", path, flags]`。

- 输出文件格式：PNG 或 JPEG（由 `screenshot-format` 选项控制，默认 PNG）
- flags 可选值：`"video"`（仅视频帧，无 OSD）、`"subtitles"`、`"window"`
- **批量生成适合性**：**不直接适合**。该命令依赖当前 mpv 实例的解码状态（需要文件已加载且解码出帧）。批量场景下需为每个文件启一个独立实例，seek 到目标时间点后截帧。

**`mpv_render_context` offscreen rendering**

当前项目的 software rendering 路径（`vo=libmpv`）已使用 `mpv_render_context_render` + `MPV_RENDER_PARAM_SW_*` 把帧写入 CVPixelBuffer（见 `MPVPlayerAdapter.swift:1005-1053`）。这条路径**技术可行**：可以在 loadPaused 状态下 seek 到目标时间点，触发一次 render，读回 CVPixelBuffer，无需写临时文件。

**性能**：offscreen render 比 screenshot-to-file 更低延迟（无磁盘 IO），但同样受制于 mpv 实例生命周期。

**`video-frame-info` 属性**：只返回帧的元信息（PTS、时间码、size），不返回像素数据，对缩略图提取无用。

### 2.2 独立 mpv 实例策略（推荐）

thumbfast 等成熟方案的架构：

1. **主播放实例**：正常播放，不受干扰
2. **缩略图专用 mpv 实例**：`vo=libmpv`（offscreen）、`pause=yes`、`frames=1`，加载同一 URL
3. seek 到目标时间点（`seek <t> absolute+exact`）→ 等待 `MPV_EVENT_VIDEO_RECONFIG` 或 render update → 截帧

对于 Enchron：
- 创建 `ThumbnailMPVAdapter`，复用 `MPVPlayerAdapter` 的 software rendering 路径（`MPV_RENDER_PARAM_SW_*`）
- 配置 `vo=libmpv`、`pause=yes`、`cache=no`、`demuxer-readahead-secs=0`
- 远程 URL（SMB/WebDAV）直接传入同一 URL 字符串，mpv 内部通过 FFmpeg 协议层处理（与主播放实例相同机制）

### 2.3 AVFoundation 路径

`AVAssetImageGenerator`:

```swift
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: 320, height: 180)
gen.generateCGImagesAsynchronously(forTimes: [targetTime]) { _, image, _, result, _ in
    // ...
}
```

**优势**：硬件加速（VideoToolbox），对 MP4/MOV 性能优秀  
**限制**：
- **不支持 MKV/WebM**：AVFoundation 无 Matroska demuxer，无法打开这些文件
- **SMB 不支持**：SMB URL（smb://）无法直接传入 AVURLAsset
- **WebDAV**：若服务器允许 HTTP 直接访问且无需额外认证，理论可用（HTTP URL）；实际场景中认证障碍大
- **格式覆盖不足**：对 Enchron 的核心格式（MKV/WebM）完全无效

**结论**：AVAssetImageGenerator 只能作为 MP4/MOV 本地文件的快速路径（可选优化，非主路径）。

### 2.4 ffmpeg / ffmpegkit 路径

MPVKit-GPL 内部已链接 FFmpeg（libavformat、libavcodec 等），但其 C API 没有通过 Swift wrapper 暴露。直接调用 `av_seek_frame` + `avcodec_receive_frame` 技术可行，但需要大量底层 C interop，维护成本高，且与 mpv 路径重复。**不推荐**：避免绕过 mpv 直接使用 FFmpeg C API。

---

## 3. 缓存策略

### 3.1 缓存位置

| 层 | 适用场景 | 实现 |
|---|---|---|
| `NSCache<NSString, UIImage>` | 当前会话内存缓存，LRU 自动淘汰 | 立即可用，无需 I/O |
| 磁盘缓存（`Library/Caches/thumbnails/`） | 跨会话复用，节省重复提取开销 | `FileManager` 写 JPEG |
| UserDefaults / SwiftData | **不适合**图像数据，过于重量 | — |

推荐采用两级缓存：`NSCache`（热路径）+ 磁盘 JPEG（冷路径）。

磁盘位置：`FileManager.urls(for: .cachesDirectory, in: .userDomainMask).first`  
子路径：`thumbnails/<cache_key>.jpg`

### 3.2 缓存 Key 设计

```
本地文件：  SHA256(file_path + last_modified_date) → hex string
远程文件：  SHA256(url_absolute_string + server_last_modified) → hex string
```

- 路径规范化：使用 `standardizedFileURL.path` 消除符号链接差异
- 修改时间来源：`FileBrowsingDomain.MediaFile.modifiedAt`（已在 `MediaFile` 实体中存在）
- 远程文件缺 `modifiedAt` 时：fallback 到 URL string only（接受缓存过期问题）

### 3.3 远程文件特殊考虑

- **SMB**：mpv 独立实例可直接使用 `smb://` URL，网络延迟会影响 seek 速度；对远程文件缩略图生成应降低并发度（建议 1-2 个并发）
- **WebDAV**：同上，HTTP URL 直接传入
- **缓存优先级更高**：远程文件生成缩略图代价大，磁盘缓存 TTL 可设长（如 30 天），本地文件依据 `modifiedAt` 失效

### 3.4 并发策略

| 场景 | 并发数 |
|---|---|
| 本地文件批量浏览（文件网格） | 3-4 个并发 mpv 实例 |
| 远程文件（SMB/WebDAV） | 1-2 个并发（网络瓶颈） |
| 播放详情页封面 | 1 个（高优先级，单独队列） |

使用 Swift `AsyncStream` 或 `TaskGroup` 管理并发，利用 `actor` 保护缓存状态（与现有 `PlaybackMediaMetadataStore: actor` 模式一致）。

---

## 4. 推荐方案

### 总体架构

```
ThumbnailService (actor)
  ├── ThumbnailCache (NSCache + disk)
  ├── ThumbnailMPVAdapter (专用 vo=libmpv 实例，offscreen render)
  └── CoverArtExtractor (mpv track-list/N/image → screenshot-to-file)
```

### 实现优先级

**Phase A — 帧缩略图（文件浏览网格）**
1. `ThumbnailService`：接收 `MediaFile`，返回 `CGImage`
2. 缓存先查（NSCache → 磁盘），命中则直接返回
3. 未命中：启动 `ThumbnailMPVAdapter`（`vo=libmpv`、`pause=yes`、`cache=no`）
4. loadfile URL → seek 到 10% 时间点（避开片头黑帧）→ offscreen render → 写磁盘 → 更新 NSCache
5. `VideoCardView` 使用 `AsyncImage`-like task 异步加载，placeholder 保持现有设计

**Phase B — 内嵌封面优先**
1. 文件加载后：读 `track-list/N/image` 找封面轨
2. 若存在：切封面轨 → screenshot-to-file → 读回 → 写缓存
3. 优先级高于帧提取

**Phase C — AVFoundation 快速路径（可选优化）**
- 仅对 `.mp4 / .mov / .m4v` 本地文件：先尝试 `AVAssetImageGenerator`
- 失败或格式不匹配：回退到 mpv 路径

### 格式兼容性矩阵

| 格式 | 封面提取（mpv） | 帧提取（mpv） | 帧提取（AVFoundation） |
|------|----------------|--------------|----------------------|
| MKV  | ✓              | ✓            | ✗                    |
| WebM | ✓（若有封面）   | ✓            | ✗                    |
| MP4  | ✓              | ✓            | ✓（快速路径）         |
| MOV  | ✓              | ✓            | ✓（快速路径）         |
| AVI  | ✓              | ✓            | ✗                    |

### 架构边界约束

- `ThumbnailService` 属于 **FileBrowsing 上下文**（消费 `MediaFile`）
- 使用 mpv 独立实例，**不共享**主播放器的 `MPVPlayerAdapter`（避免干扰播放状态）
- `ThumbnailMPVAdapter` 复用 `MPVPlayerAdapter` 的 offscreen render 代码路径，但配置为 `useNativeGPUOutput=false`（`vo=libmpv`），不需要 `CAMetalLayer`
- 缓存目录使用 `Library/Caches`（非 `Documents`），系统低存储时可自动清理

---

## 5. 关键未解问题

1. **MPVKit-GPL 在 visionOS sandbox 下能否创建多个 `mpv_create` 实例**：MPVKit-GPL 已成功在设备上运行，但同时存在多个 mpv 上下文的内存/线程开销需要实测评估（不太可能被系统限制，但需验证）。
2. **缩略图实例的 seek 精度 vs 速度权衡**：`absolute+exact` seek 对长视频 I 帧稀疏时较慢，可改用 `absolute`（keyframe seek）接受误差换速度。
3. **SMB 的 mpv seek 延迟**：远程 MKV 文件 seek 时 mpv 可能需要预读大量数据；需要实测在 100Mbps 局域网下的延迟表现。

---

## 参考资料

- mpv 官方手册：https://mpv.io/manual/master/ — `track-list/N/image`、`screenshot-to-file`、`metadata/by-key/`
- thumbfast（成熟的 mpv 缩略图方案）：https://github.com/po5/thumbfast
- AVAssetImageGenerator Apple 文档：https://developer.apple.com/documentation/avfoundation/avassetimagegenerator
- mpv cover art 讨论（#8561）：https://github.com/mpv-player/mpv/issues/8561
- MPVKit Swift Package：https://github.com/mpvkit/MPVKit
