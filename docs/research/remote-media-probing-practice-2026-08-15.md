# 远程媒体信息的建立时机与 FFmpeg 一次性打开远程 MP4 的方法

日期：2026-08-15。结论取自一手来源：FFmpeg 源码（n8.0.1、n8.1、n9.0.1 与 master 提交 `5c395992f9`）、Jellyfin 与 Emby 3.5.2 的服务端源码、Kodi 与 mpv 与 VLC 源码、Firecore 官方支持文档、Apple Developer Documentation、RFC 9110。文中标注"实测"的数字来自本地可复现实验：用一个记录 Range 与连接生命周期的 HTTP 服务端提供 TestMedia 中的真实文件，再用 FFmpeg 自身的字节计数日志（`avformat_find_stream_info` 前后的 `bytes read`）读数。实验所用 ffprobe 为 FFmpeg master `N-125990-g5c395992f9`；PlaybackCore 当前 vendored 的是 FFmpeg 8.0.1（`libavformat 62.3.100`，见 `Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework/*/Headers/libavutil/ffversion.h`），二者在 HTTP 连接复用上的差异在下文单列。

---

## 一、媒体系统在什么时刻建立轨道表、编解码、时长与尺寸

### Jellyfin：入库扫描时探测并落库，播放请求只读数据库

`PlaybackInfo` 端点的实现链路是 `MediaInfoController.GetPlaybackInfo` → `MediaInfoHelper.GetPlaybackInfo` → `MediaSourceManager.GetPlaybackMediaSources(item, user, allowMediaProbe: true, enablePathSubstitution: true, ...)`。
来源：https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Helpers/MediaInfoHelper.cs（第 148 行）

`GetPlaybackMediaSources` 先调用 `GetStaticMediaSources`，只有在下述条件成立时才触发一次带远程探测的元数据刷新：

```csharp
if (allowMediaProbe && mediaSources[0].Type != MediaSourceType.Placeholder
    && (item.Path.EndsWith(".strm", StringComparison.OrdinalIgnoreCase)
        || (item.MediaType == MediaType.Video && mediaSources[0].MediaStreams.All(i => i.Type != MediaStreamType.Video))
        || (item.MediaType == MediaType.Audio && mediaSources[0].MediaStreams.All(i => i.Type != MediaStreamType.Audio))))
```

即：文件是 `.strm` 快捷方式，或库里存下来的流列表里根本没有主视频（音频）流。两者都不成立时，`PlaybackInfo` 全程不启动 ffprobe。
来源：https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Library/MediaSourceManager.cs（第 177 至 198 行）

`MediaSourceInfo` 的技术字段来自持久化数据。`BaseItem.GetVersionInfo` 用 `MediaStreams = MediaSourceManager.GetMediaStreams(item.Id)`、`RunTimeTicks = item.RunTimeTicks`、`Container = item.Container`、`Size = item.Size` 组装；`MediaSourceManager.GetMediaStreams` 的实现是 `var list = _mediaStreamRepository.GetMediaStreams(query);`，即一次数据库查询。
来源：https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.Controller/Entities/BaseItem.cs（第 1155 至 1177 行）、同上 MediaSourceManager.cs（第 102 至 104 行）

写入侧在扫描期。`ProbeProvider` 实现 `ICustomMetadataProvider<Movie>` 与 `IPreRefreshProvider`，其 `FetchVideoInfo` 调用 `FFProbeVideoInfo.ProbeVideo`，后者在 `_mediaStreamRepository.SaveMediaStreams(video.Id, mediaStreams, cancellationToken)` 处落库，并把 `RunTimeTicks` 写回 item。
来源：https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.Providers/MediaInfo/ProbeProvider.cs、https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.Providers/MediaInfo/FFProbeVideoInfo.cs（第 272 行）

探测本身是一次 ffprobe 进程，命令形如 `{probeSizeArgument} -i {input} -threads {n} -v warning -print_format json -show_streams -show_format`，本地文件的视频还追加 `-show_frames -only_first_vframe`。`-analyzeduration` 与 `-probesize` 只有在服务端配置里显式设过时才出现，默认不加。
来源：https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.MediaEncoding/Encoder/MediaEncoder.cs（`GetMediaInfoInternal` 与 `GetExtraArguments`）

**从未被扫描过的文件**由同一段判据兜底：库里没有视频流记录，`PlaybackInfo` 就同步做一次全量刷新再重新读库。代价落在这一次请求上。

**关键例外**：`ProbeProvider.FetchVideoInfo` 有一道门 `if (!options.EnableRemoteContentProbe && !item.IsFileProtocol) return _cachedTask;`。`EnableRemoteContentProbe` 只有 `GetPlaybackMediaSources` 在播放时刻会置真。因此非 file 协议的条目（`.strm` 指向的远程 URL）在常规扫描中根本不被探测，只在每次 `PlaybackInfo` 时探测一次，且结果不会消除下一次的探测——因为落库的流会让判据在下一次不再成立，这一点取决于刷新是否成功写入。

### Emby：4.9.5 闭源，但同一段代码在 3.5.2 的祖先版本中形状一致

Emby 服务端自 3.5.3 起闭源，GitHub 上 `MediaBrowser/Emby` 的最后源码 tag 为 `3.5.2.0`，Jellyfin 即由此分叉。该版本的对应实现：

```csharp
public async Task<List<MediaSourceInfo>> GetPlayackMediaSources(BaseItem item, User user, bool allowMediaProbe, bool enablePathSubstitution, CancellationToken cancellationToken)
{
    var mediaSources = GetStaticMediaSources(item, enablePathSubstitution, user);

    if (allowMediaProbe && mediaSources[0].Type != MediaSourceType.Placeholder && !mediaSources[0].MediaStreams.Any(i => i.Type == MediaStreamType.Audio || i.Type == MediaStreamType.Video))
```

判据比 Jellyfin 更窄：库里既没有音频流也没有视频流才探测。`FFProbeProvider.FetchVideoInfo` 同样有 `if (!options.EnableRemoteContentProbe && !item.IsFileProtocol) return _cachedTask;`，`FFProbeVideoInfo` 同样在 `_itemRepo.SaveMediaStreams(video.Id, mediaStreams, cancellationToken)` 落库。
来源：https://github.com/MediaBrowser/Emby/blob/3.5.2.0/Emby.Server.Implementations/Library/MediaSourceManager.cs（第 124 至 138 行）、https://github.com/MediaBrowser/Emby/blob/3.5.2.0/MediaBrowser.Providers/MediaInfo/FFProbeProvider.cs（第 178 行）、同版本 FFProbeVideoInfo.cs（第 224 行）

Emby 4.x 的这段代码不可读。可核验的旁证是 Emby 自己的日志格式：社区帖子中的服务端日志显示扫描期执行 `ffprobe -threads 0 -v info -print_format json -show_streams -show_chapters -show_format`，与 3.5.2 的构造一致。
来源：https://emby.media/community/topic/117689-monitoring-library-scan/

**对"Emby 在扫描时探测、播放时不探测"这一假设的裁决**：在祖先代码层面成立，且成立的前提是条目走 file 协议并且扫描已经落库。当前部署满足这个前提，Emby 通过挂载把远程库看成本地路径，因此条目是 file 协议，扫描期就会被探测；Emby 对客户端提供 HTTP 只是分发通道，与它自己建立媒体信息的通道无关。4.9.5 的源码不可读，但其行为已用未落库条目的 `PlaybackInfo` 计时确认与 3.5.2 的判据一致，数字见第四节。

### 没有服务端索引的客户端播放器

**Kodi** 在入库扫描时探测并落库。`CVideoInfoScanner` 在 NFO 未提供 streamdetails 时调用 `CDVDFileInfo::GetFileStreamDetails(pItem)`，后者开一个 input stream 加一个 FFmpeg demuxer 抽取 `CStreamDetails` 存进 `myvideos.db`。但它对远程来源设了门：`CanExtract` 对 `NETWORK::IsInternetStream` 直接返回 false，并且"For HTTP/FTP we only allow extraction when on a LAN"——非局域网的 HTTP/FTP 路径不抽取。
来源：https://github.com/xbmc/xbmc/blob/master/xbmc/video/VideoInfoScanner.cpp（第 2167 至 2171 行）、https://github.com/xbmc/xbmc/blob/master/xbmc/cores/VideoPlayer/DVDFileInfo.cpp（`CanExtract` 第 358 至 392 行，`GetFileStreamDetails` 第 399 行起）

**VLC** 对加入播放队列的条目做 preparse，即一次不播放的 demuxer 打开，用来取时长与轨道。`auto-preparse` 默认 true，`preparse-timeout` 默认 5000 毫秒，`metadata-network-access` 默认 **false**。也就是说 VLC 确实对浏览到但未播放的条目提前解析，但给了 5 秒硬超时，并且默认不允许为元数据访问网络。
来源：https://github.com/videolan/vlc/blob/master/src/libvlc-module.c（第 2170 至 2182 行）

**mpv** 没有库，也不预解析未播放的条目。它只有 `--prefetch-playlist`（默认 no）："Prefetch next playlist entry while playback of the current entry is ending... This merely opens the URL of the next playlist entry as soon as the current URL is fully read."
来源：https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst

**Infuse** 闭源，但官方支持文档把这个取舍做成了每个共享的显式开关。"Pre-Cache Details"：开启时 "Infuse will work to fetch details for all videos so they are ready and waiting. This will require longer library indexing times."；关闭时 "Infuse will fetch these detail on-demand while browsing."。被缓存的正是 "runtime, codec info, and other file specs"。接 Plex/Emby/Jellyfin 的 Direct Mode 下 Infuse 直接显示服务端的元数据，不在本地预缓存。
来源：https://support.firecore.com/hc/en-us/articles/27862264977047-Library-Scanning-Indexing、https://support.firecore.com/hc/en-us/articles/360006462093-Streaming-from-Plex-Emby-and-Jellyfin

四者的共同形状：**要么由一个索引阶段承担探测代价并落盘，要么把探测限制在一次、加超时、并对网络来源额外设防**。没有任何一个在播放时刻对同一个远程文件做多次独立探测。

---

## 二、用 FFmpeg 一次打开并探测远程 HTTP 媒体文件

### 打开一个 moov 在尾部的远程 MP4，实际发生的请求序列

实测对象为 `TestMedia/Samples/Spatial/Stereo180/HNVR-158_H_4096p_8K_LR_180_clip.mp4`，105.2 MiB，HEVC 8192×4096，60 秒，`moov` 位于偏移 110201178，长 104716 字节。

当前 PlaybackCore 的形态（先 `http_source_length` 再带 `end_offset` 打开，见 `Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c` 的 `http_source_length` 与 `open_media_source`），**每个消费者 4 个 HTTP 请求、4 条 TCP 连接**：

| # | Range | 用途 |
| --- | --- | --- |
| 1 | `bytes=0-` | `avio_open2` 长度探测，读完 Content-Length 立刻关闭 |
| 2 | `bytes=0-110305893` | 真正打开，格式探测 |
| 3 | `bytes=110201178-110305893` | 回到尾部读 moov |
| 4 | `bytes=676-110305893` | 回到 mdat 起点供 `avformat_find_stream_info` 读包 |

`PBFFmpegAudioTrackCount`、每条音轨一次的 `PBFFmpegAudioTrackCopyInfo`、`PBFFmpegSubtitleTrackCount`、视频 reader 与音频 reader 各自都走这条路径，且都只拿到 `path` 字符串（见 `AudioSampleProvider.tracks(in:asset:)` 与 `SubtitleProvider.tracks(in:asset:)`），因此文件被独立打开四到五次，总请求数是 16 到 20。

### `avio_size` 不需要单独的 `avio_open2`

`avio_size` 的实现是 `size = s->seek(s->opaque, 0, AVSEEK_SIZE);`，HTTP 协议的 seek 回调对 `AVSEEK_SIZE` 直接返回已解析的 `s->filesize`，不发任何请求：

```c
if (whence == AVSEEK_SIZE)
    return s->filesize;
```

来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/aviobuf.c（`avio_size`，第 323 行起）、https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/http.c（`http_seek_internal`，第 1995 行）

`s->filesize` 在响应头解析时就已经填好，来源是 `Content-Length`，或在 206 响应中优先取 `Content-Range` 的总长（`filesize_from_content_range`）。因此**在一个已经打开的 AVIOContext 上取长度是零成本的**，第 1 个请求纯属多余。

难点只在顺序：`end_offset` 是协议打开时消费的选项，而长度只有打开之后才知道。可解，因为 `end_offset` 可以在连接已经建立之后改写。`AVIOContext` 的 AVClass `ff_avio_class` 的 `child_next` 返回其 `opaque`（即 `URLContext`），`url_context_class` 的 `child_next` 再返回协议 `priv_data`（即 `HTTPContext`），所以 `av_opt_set_int(pb, "end_offset", len, AV_OPT_SEARCH_CHILDREN)` 能命中 `HTTPContext.end_off`。
来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/avio.c（第 60 至 105 行）

Range 头在每次请求时按当时的 `s->off` 与 `s->end_off` 重新拼装，因此改写后的 `end_offset` 对**后续**每一次请求生效：

```c
if (!has_header(s->headers, "\r\nRange: ") && !post && (s->off > 0 || s->end_off || s->seekable != 0)) {
    av_bprintf(&request, "Range: bytes=%"PRIu64"-", s->off);
    if (s->end_off)
        av_bprintf(&request, "%"PRId64, s->end_off - 1);
    av_bprintf(&request, "\r\n");
}
```

来源：同上 http.c 第 1543 至 1549 行

`avformat_open_input` 在 `s->pb` 已被调用方设好时不会再打开 URL，只会置 `AVFMT_FLAG_CUSTOM_IO` 并在已有的 pb 上做格式探测：

```c
if (s->pb) {
    s->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (!s->iformat)
        return av_probe_input_buffer2(s->pb, &s->iformat, filename, s, 0, s->format_probesize);
    ...
}
```

来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/demux.c（`init_input`，第 158 至 174 行）

实测把这三点串起来（`avio_open2` → `avio_size` → `av_opt_set_int(end_offset)` → `ctx->pb = pb` → `avformat_open_input`），请求数从 4 降到 3，连接数从 4 降到 2，得到的流信息逐字段相同。唯一残留差异是第一个请求仍是开放式的 `bytes=0-`，因为设 `end_offset` 时它已经发出。

### 一个 AVFormatContext 足以枚举全部轨道

`AVFormatContext.streams[]` 在一次打开后就包含全部视频、音频与字幕流，`codecpar->codec_type` 区分类别。实测一次打开即得到完整轨道表，无需为音轨计数、音轨信息、字幕计数、视频 reader 分别打开。多个读取者需要独立读位置这件事不构成再开一次容器的理由：ffplay 的参考实现就是单个 `AVFormatContext` 加一个读线程，按 `pkt->stream_index` 分发到各流的包队列。
来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/fftools/ffplay.c（`read_thread`）

### 探测边界的语义与默认值（libavformat 62 / FFmpeg 8.0.1）

| 选项 | 默认 | 约束的东西 |
| --- | --- | --- |
| `probesize` | 5000000 | `avformat_find_stream_info` 读包循环的累计字节上限，超过即 `break` 并打印 "Probe buffer size limit of N bytes reached" |
| `formatprobesize` | 1048576（`PROBE_BUF_MAX`） | 容器格式识别（`av_probe_input_buffer2`）读取的字节数，与上一项无关 |
| `analyzeduration` | 0，表示未设 | 未设时内部取：普通流 5 秒、字幕流 30 秒、mpeg/mpegts 7 秒、flv 90 秒 |
| `fpsprobesize` | -1，表示自动 | 为估计帧率而读的帧数，自动时为 20，时基粗糙（`av_q2d(time_base) > 0.0005`，如 mkv 的毫秒时基）翻倍为 40，`tb_unreliable` 为假时归零 |
| `max_probe_packets` | 2500 | 对**未知编解码**的流做码流探测所用的包数上限，MP4 的流在 stsd 里已声明编解码，这个上限不参与 |
| `max_ts_probe` | 50 | 为等到某条流的第一个时间戳而最多读的包数 |
| `duration_probesize` | 0 | 仅在 `estimate_timings_from_pts` 路径（mpeg/mpegts）生效 |

来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/options_table.h（第 39 至 108 行）、https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/demux.c（第 2556 至 2565 行、第 2648 至 2712 行、第 2812 至 2814 行）

三条对 MP4 的具体推论：

- `fpsprobesize` 对普通 MP4 无效。mov demuxer 在 stts 恒定时用 `av_reduce(&st->r_frame_rate...)` 填 `r_frame_rate`（`FF_API_R_FRAME_RATE` 在 lavf 62 中为 1），并在 `mov_read_trak` 末尾填 `avg_frame_rate`；两者都非零时探测循环里的帧数判据 `if (!(st->r_frame_rate.num && st->avg_frame_rate.num) && ...)` 整段跳过。实测 `-fpsprobesize 0` 对读取量没有改变。注意 `tb_unreliable` 对 H.264 与 HEVC 无条件返回 1，所以"HEVC 就要探 20 帧"的推断只在 demuxer 未填帧率的容器上成立。
  来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/mov.c（第 5234 至 5242 行、第 10705 至 10707 行）、同上 demux.c `tb_unreliable` 第 2281 行
- `analyzeduration` 未设时字幕流拿 30 秒预算。带内嵌字幕轨的影片，字幕包在时间轴上稀疏，探测循环会一直读到 `probesize` 上限才停。显式设 `analyzeduration` 会同时把字幕的 30 秒压到同一个值。
- `probesize` 是真正的止血点。实测：默认边界下 `avformat_find_stream_info` 读 3.67 MB、109 帧，以 "All info found" 退出；设 `-probesize 200000 -analyzeduration 0` 后读 0.49 MB、1 帧，以 "Probe buffer size limit" 退出，两次得到的 codec、分辨率、pix_fmt、声道数、采样率、时长完全一致。

### 对 MP4 可以完全不调用 `avformat_find_stream_info`

mpv 的 `format_hacks` 表对 `mp4` 与 `matroska` 标了 `skipinfo`，含义就是 "skip avformat_find_stream_info()"；`--demuxer-lavf-probe-info` 默认 `auto`，`auto` 即 `probeinfo = !priv->format_hack.skipinfo`。
来源：https://github.com/mpv-player/mpv/blob/master/demux/demux_lavf.c（第 139 行、第 181 至 182 行、第 1545 至 1552 行）

Apple 在 AVFoundation 侧给出同一判断。`AVURLAssetPreferPreciseDurationAndTimingKey` 默认 `false`，文档说明："Container formats like QuickTime and MPEG-4 provide sufficient timing information and don't require additional parsing to retrieve it. Other formats don't provide sufficient summary information, and the system can't accurately calculate the resource's duration and timing without examining the media content."
来源：https://developer.apple.com/documentation/avfoundation/avurlassetpreferprecisedurationandtimingkey

实测跳过 `avformat_find_stream_info` 后，同一个远程 MP4 只花 **2 个请求、2 条连接**，并且仍然拿到：流数与每条流的 `codec_type`、`codec_id`（hevc / aac）与 `codec_tag`（`hev1` / `mp4a`）、逐流时长（`st->duration * st->time_base`，60.043 与 60.016 秒）、language 与 title 元数据、视频宽高 8192×4096 与 2564 字节 hvcC extradata、音频 2 声道 48000 Hz 与 bit_rate 与 extradata、`avg_frame_rate` 与 `r_frame_rate`、disposition。

丢失的只有两项：容器级 `AVFormatContext.duration` 保持 `AV_NOPTS_VALUE`（`estimate_timings` 只在 `find_stream_info` 内被调用，但逐流时长可用），以及 `codecpar->format`（pix_fmt / sample_fmt 为 -1，这两个值本来就由解码器在首帧确定）。

### `multiple_requests` 与连接复用：一条明确的版本边界

`multiple_requests` 在请求头层面只做一件事：

```c
av_bprintf(&request, "Connection: %s\r\n", s->multiple_requests ? "keep-alive" : "close");
```

它**不减少请求数**。moov 在尾部的 MP4 必然产生"打开—跳到尾部—跳回头部"三次请求，这是 mov demuxer 的读取顺序决定的，与 keep-alive 无关。

它是否减少 TCP 连接数取决于 FFmpeg 版本：

- **8.0.1 及更早**：`http_seek_internal` 无条件 `s->hd = NULL` 再 `http_open_cnx`，随后 `ffurl_close(old_hd)`，每次 seek 都是新 socket。`multiple_requests` 只影响头部字段与 `http_buf_read` 里对 `willclose` 的 EOF 判定。
  来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/http.c（第 1986 至 2052 行）
- **8.1 起**：`http_seek_internal` 新增 soft-seek 分支，条件为 `s->hd && !s->willclose && s->range_end && short_seek > 0 && old_read_pos + short_seek >= s->range_end`，即当前响应体已基本读尽时，把剩余字节丢弃掉并在同一条连接上发下一个请求。`!s->willclose` 要求服务端没有回 `Connection: close`，因此这条路径**必须**配 `multiple_requests=1`。
  来源：https://github.com/FFmpeg/FFmpeg/blob/5c395992f99feb47860e4cc99a0cea2009457870/libavformat/http.c（第 2160 至 2200 行）；`range_end` 在 n8.0.3 中出现 0 次，在 n8.1 中出现 5 次

实测（master）：不加选项 3 请求 3 连接；`-multiple_requests 1` 3 请求 2 连接，读完 moov 之后跳回 mdat 的那次复用了同一条连接。ffprobe 自身的 trace 日志中 "Starting connection attempt" 出现次数由 3 降为 2，与服务端记录的连接生命周期一致。

8.1 同时引入了 `request_size` 与 `initial_request_size`，把每个请求切成有界窗口。这两项与 `end_offset` 正确复合：`target_off = FFMIN(s->off + req_size, s->end_off)`。有界窗口正是让 soft-seek 条件成立的前提，因为一个"读到文件末尾"的响应永远有大量未读剩余，无法软跳。8.0.1 没有这两个选项。

**文档与源码的分歧**：ffmpeg.org 的在线协议文档描述的是 master，写着 `multiple_requests` "Default is -1, which means auto (implies keep-alive when using -request_size or -initial_request_size)"。这个三态默认值在 n8.1、n8.1.2、n9.0、n9.0.1 中都还是 0，只在 master 上是 -1。按在线文档理解 8.0.1 的行为会出错。
来源：https://ffmpeg.org/ffmpeg-protocols.html

### `reconnect` 系列与 `rw_timeout`

默认值（n8.0.1 http.c 第 181 至 188 行）：`reconnect` 0、`reconnect_at_eof` 0、`reconnect_streamed` 0、`reconnect_on_network_error` 0、`reconnect_on_http_error` 空、`reconnect_delay_max` 120 秒、`reconnect_max_retries` -1（不限次）、`reconnect_delay_total_max` 256 秒。

语义（`http_read_stream` 第 1745 至 1806 行）：只在一次读失败之后才进入重连循环。`reconnect` 覆盖"未到 EOF 就断开"（`is_premature`，即 `s->off < s->filesize`）；`reconnect_at_eof` 把 EOF 本身当错误处理并重连，这是给直播与无尽流的，对一个有限长度的文件打开它会让文件末尾变成重连循环；`reconnect_streamed` 只对 `h->is_streamed` 为真的不可 seek 流有意义，range 可用的 HTTP 源不属于此类；`reconnect_on_network_error` 覆盖 connect 阶段的 TCP/TLS 失败。退避从 1 秒起翻倍，因此在默认的不限次数下，一个"连得上但读不出"的服务端最多能拖住 `reconnect_delay_total_max` 即 256 秒。要用就必须同时压 `reconnect_delay_max` 与 `reconnect_max_retries`。

`rw_timeout` 是 `URLContext` 级选项，单位微秒，默认 0。它在 `retry_transfer_wrapper` 中只对连续 `EAGAIN` 计时（前 5 次快速重试之后才开始计），超时返回 `AVERROR(EIO)`。TCP 协议另有自己的 `timeout` 选项（默认 -1），设置后同时充当 `open_timeout` 与该 URLContext 的 `rw_timeout`；未设时 `open_timeout` 为 5000000 微秒即 5 秒，而 `ff_network_wait_fd_timeout` 在 `timeout <= 0` 时只靠 `AVIOInterruptCB` 退出，会无限等待。
来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/avio.c（第 63 行、第 505 至 545 行）、https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/tcp.c（第 59 行、第 150 行、第 191 至 193 行）、https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/network.c（第 75 至 93 行）

对当前问题的判断：这四个 `reconnect` 选项与打开慢无关，它们只在链路已经出错之后改变行为。有意义的是超时——PlaybackCore 已经装了 interrupt callback，取消可用，但一个静默挂住的服务端不会自己失败。

### `end_offset` 的语义与相互作用

请求形态是 `bytes=<off>-<end_off - 1>`，即 `end_offset` 是**开区间上界**，传文件总长得到的最后一个字节号是 `len - 1`，正确。

按 RFC 9110 §14.1.2，`bytes=N-` 与 `bytes=N-<len-1>` 对服务端是等价的："If the last-pos value is absent, or if the value is greater than or equal to the current length of the representation data, the byte range is interpreted as the remainder of the representation (i.e., the server replaces the value of last-pos with a value that is one less than the current length of the selected representation)."
来源：https://www.rfc-editor.org/rfc/rfc9110.html#section-14.1.2

因此 `end_offset` 不是协议要求，而是对不合规服务端的规避；在合规服务端上它既不省字节也不多花字节，实测两种形态的请求数、连接数与读取量一致（3.41 MB 对 3.34 MB，差值来自响应头长度）。

三处需要注意的相互作用：

1. `http_seek_internal` 与 `http_buf_read` 都把 `end_off` 当作文件末尾使用：`end_pos = s->end_off ? s->end_off : s->filesize;`，seek 到 `>= end_pos` 直接返回成功而不发请求，读到 `>= target_end` 直接返回 EOF。所以 `end_offset` 若小于真实长度，尾部会被静默截断——`http_source_length` 坚持用服务端自己的 Content-Length 而不是调用方记录的尺寸，正是这个原因，注释里已经写明。
2. 与 8.1+ 的 soft-seek 冲突：设成文件总长意味着每个请求都声明"从这里一直到文件末尾"，剩余量永远远大于 `short_seek`，soft-seek 条件不成立。要同时拿到连接复用，必须配 `request_size` 把单个请求切窄；`end_offset` 只作为 `FFMIN` 的上界参与。
3. 与 `seekable` 探测的关系：`end_off` 非零会让 FFmpeg 即便在偏移 0 也发 Range 头（判据是 `s->off > 0 || s->end_off || s->seekable != 0`），这对判断服务端是否支持 range 有帮助，无害。

### 打开一个长片 MP4 的字节代价由什么主导

`moov` 必须完整读入才能出第一个包。mov demuxer 的 `mov_read_stsz` 等函数把每张表整表读进内存，`AVFMT_FLAG_IGNIDX`（`fflags +ignidx`）只作用于分片 MP4 的 sidx/索引路径，对 stbl 无效，没有任何选项能让 stbl 部分读取或延迟读取。
来源：https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavformat/mov.c（`mov_read_stsz` 第 3416 行、`mov_options` 第 11445 行起、`AVFMT_FLAG_IGNIDX` 仅出现在第 9551 与 9553 行）

`moov` 的体积由采样表决定，与时长线性相关。实测本地样本的 moov 中采样表占比：

| 文件 | 文件大小 | moov | moov 占比 | 采样表占 moov | 主要表 |
| --- | --- | --- | --- | --- | --- |
| HNVR-158 8K 60s | 105.2 MiB | 104716 B | 0.095% | 99.3% | ctts 26888、stsz 26880、stco 23588、stsc 19748 |
| insta360 | 209.2 MiB | 50968 B | 0.023% | 98.5% | stsz 19912、stco 14928、stsc 14876 |
| FEL_test_for_AVS | 153.9 MiB | 44559 B | 0.028% | 98.4% | stsz 23056、ctts 15272、stco 3872 |
| ARRI ProRes（每 chunk 单样本） | 162.4 MiB | 438140 B | 0.257% | 0.5% | 其余为 stsd 与色彩/时间码元数据 |

折算下来这三个普通 MP4 的采样表约为每个媒体样本 8 到 18 字节。一部两小时影片，24 fps 视频约 172800 个样本，一条 48 kHz AAC 约 337500 个样本，合计约 5×10⁵ 个样本，对应 **数 MB 量级的 moov**，且这几 MB 无法分批读。若还带多条音轨，按轨数近似线性叠加。

第二项代价是 `avformat_find_stream_info` 的读包循环，上限由 `probesize` 与 `analyzeduration` 给出，默认 5 MB。实测 60 秒 8K 片源在默认边界下这一项就是 3.67 MB，是同一次打开中 moov（0.1 MB）的三十多倍。

第三项是布局。`moov` 在文件头部（faststart）时，实测整个打开加探测只需 **1 个请求 1 条连接**；`moov` 在尾部时是 3 个。分片 MP4 最糟：`P81_GlassBlowing2_..._fmp4.mp4` 实测 **89 个请求 88 条连接**，因为索引要靠遍历 moof 建立。

---

## 三、对开头陈述的更正

- "`multiple_requests` / keep-alive 能降低 moov 在尾部的 MP4 的代价"——在 FFmpeg 8.0.1 上不成立，8.0.1 的每次 seek 都新建连接，该选项只改一个请求头字段。在 8.1 及以后成立，且只省连接不省请求。PlaybackCore 当前 vendored 的正是 8.0.1。
- "`fpsprobesize` 是可调的探测边界之一"——对普通 MP4 无效，因为 mov demuxer 已填好 `r_frame_rate` 与 `avg_frame_rate`，帧数判据被整段跳过。
- "`max_probe_packets` 约束探测代价"——它只约束编解码未知的流的码流探测，MP4 的流在 stsd 中已声明编解码，该上限不参与。
- "Emby 在扫描时探测、播放时不探测"——在可读的 3.5.2 祖先代码中成立，但成立的前提是条目走 file 协议且扫描已落库；对 `.strm` 这类非 file 协议条目，Jellyfin 与 Emby 都是每次 `PlaybackInfo` 探测一次。当前部署因为 Emby 通过 WebDAV 挂载把库看成本地路径而落在成立的一侧，但这是部署事实而非 Emby 的普遍行为。
- "`avio_open2` 的长度探测是必需的"——不必需。`avio_size` 在已打开的 AVIOContext 上零成本返回，`end_offset` 可以在连接建立之后用 `av_opt_set_int(..., AV_OPT_SEARCH_CHILDREN)` 改写并对后续请求生效。

---

## 四、对 192.168.5.2 的直接实测

数字取自绕开 App 直接对服务器的实验。探针是 `Scripts/verification/probe_remote_media_reads.py`（片源结构、吞吐、开放式范围、`PlaybackInfo` 计时、记录 Range 与连接的回环代理）与 `Scripts/verification/remote_open_accounting_probe.c`。后者链接 `Packages/PlaybackCore/Vendor/FFmpeg/PlaybackFFmpeg.xcframework/macos-arm64`，即产品自身 vendored 的 FFmpeg 8.0.1，并照抄 `open_media_source` 与 `PBFFmpegReaderOpen` 的调用顺序、选项与字节发布点。

### 片源结构

alist WebDAV 上的 `Blade Runner 2049 (2017).mp4` 长 18416527997 字节，顶层 box 只有三个，`ftyp` 28 字节、`mdat` 18409166983 字节、`moov` 7360986 字节。没有 `moof`，不是分片 MP4。流表只有两条，HEVC 3840×2160 与 AC3 六声道，既没有第二条音轨也没有字幕轨。

### 那 14 MB 不是 `avformat_find_stream_info` 的读取量

在 8.0.1 上按 `open_media_source` 的形态打开同一 URL，`avformat_open_input` 返回时 `pb->bytes_read` 为 7368761，`avformat_find_stream_info` 的增量为 7774 字节。经 Emby 直连为 7368081 与 7094 字节。经回环代理时两项为 7393754 与 65536 字节，差值来自缓冲粒度。在 HTTP 请求层面 `find_stream_info` 只发一个请求 `bytes=44-18416527996`，FFmpeg 中止它之前服务端送出 393216 到 589824 字节。

一次打开的 7.4 MB 由 `moov` 主导，而 `moov` 由 `avformat_open_input` 内的 `mov_read_header` 读入，`probesize` 不约束它。`probesize` 只约束 `avformat_find_stream_info` 的读包循环。"14 MB 超过 probesize 的 5 MB"比较的是两个互不管辖的量。

三个候选中，分片 MP4 被顶层 box 排除，字幕流的 30 秒 `analyzeduration` 被"没有字幕流"排除，剩下的是字节归属。按每次打开 7.4 MB 折算，设备记录的 37.4 MB 约合五次容器打开，13.9 MB 约合两次。

`PBFFmpegSourceReadMonitor` 是整个会话共用的一个计数器，`publish_source_bytes` 从 `pb->bytes_read` 取值，既在 interrupt callback 里随 I/O 发布，也在每个步骤边界发布，因此本机采样序列在 `avformat_open_input` 期间是连续上升而非平台期。

### 1 到 2 MB/s 是打开序列的空转，不是服务端上限

同一文件、同一字节范围、单条连接、写全上界：

| 范围 | alist WebDAV 5244 | Emby 直连 8096 |
| --- | --- | --- |
| `moov` 7360986 字节，偏移 18409167011 | 0.83 秒，8.86 MB/s | 17.60 秒，0.42 MB/s |
| 32 MiB，偏移 0 | 2.53 秒，13.3 MB/s | 0.57 秒，58.4 MB/s（挂载已落地） |
| 32 MiB，偏移 5000000000 | 2.14 秒，15.7 MB/s | 79.52 秒，0.42 MB/s |

同一文件在 alist 上切成 40 个 256 KiB 请求、每个请求新建连接，总计 13.89 秒 0.72 MB/s，每请求 347 毫秒。设备侧 `TestEvidence/mode-switch-graph-reuse-20260815/session/snapshot.json` 在 `lifecycle` 为 `playing` 时记录 `bytesPerSecond` 8342433。

因此 alist 稳定给出 8.9 到 15.7 MB/s，设备在播放阶段从同一台服务器拿到 8.3 MB/s，而打开阶段的 1.1 到 2.2 MB/s 是打开序列自身的空转。每个请求 330 到 520 毫秒用于连接建立与首字节，每次打开四个请求，一次准备打开四到五次。压请求数直接压打开时间，压带宽不会。

Emby 直连另有一条独立且低得多的上限。它的库路径是 `/Users/xiongzhipeng/Library/CloudStorage/EmbyMedia/...`，对该挂载尚未落地的区域只有 0.42 MB/s，比 alist 慢 20 到 37 倍，同一文件落地之后升到 58 MB/s。来源选择对打开时间的影响大于任何 FFmpeg 选项。

### 起点为 0 的开放式 `bytes=0-` 不触发该缺陷

每个开放式请求都配一个同窗口、写全上界的对照：

- alist WebDAV 全部逐字节相同，包括文件尾部 4 KiB 与 64 KiB 的短读，`Content-Range` 与 `Content-Length` 始终正确。
- Emby 直连在挂载尚未落地的文件上，尾部开放式请求答错。`十二只猴子`（88449522419 字节）与 `Joint Security Area`（76777433365 字节）对 `bytes=<len-4096>-` 都回 HTTP 500 PartialContent，`Blade Runner 2049` 对 `bytes=<len-1048576>-` 声明 1048576 字节只送出 999424。同窗口写全上界的对照每次都是 206 且完整。
- Emby 直连对 `bytes=0-`，在上述三个未读过的大文件上都回 206、`Content-Range` 为 `bytes 0-<len-1>/<len>`、`Content-Length` 等于文件长度，前 1 MiB 与对照逐字节相同。一个未读过的 64096442 字节文件用 `bytes=0-` 一直读到 EOF 也完整，与对照相同。
- 文件在挂载上完全落地之后，所有形态都正确。

判别变量不是是否写了上界，而是开放式请求的起点是否落在挂载尚未落地的区域，起点为 0 不属于此类。因此把 `end_offset` 改成打开之后设置是安全的，那次前置长度探测可以删掉。

`end_offset` 本身仍不能删，同一次运行里就能看到两种起点的分野。在 8.0.1 上不设 `end_offset` 经 Emby 打开同一文件只发两个请求，第一个 `bytes=0-` 正常送出 786432 字节后被 FFmpeg 中止，第二个 `bytes=18409167011-` 只送出 7290880 字节，比 `moov` 的 7360986 字节少 70106。日志随之是 `Stream ends prematurely at 18416457891, should be 18416527997`、`reached eof, corrupted STCO atom`、`error reading header`，`avformat_open_input` 返回 End of file。

### 打开后设 `end_offset` 的实测

`avio_open2` → `avio_size` → `av_opt_set_int(pb, "end_offset", len, AV_OPT_SEARCH_CHILDREN)` → `ctx->pb = pb` → `avformat_open_input`，在 8.0.1 上经回环代理对两台服务器计数：

| 形态 | 请求 | 连接 | `bytes_read` | 结果 |
| --- | --- | --- | --- | --- |
| 现状，WebDAV | 4 | 4 | 7459290 | 成功 |
| 打开后设，WebDAV | 3 | 3 | 7459290 | 成功 |
| 现状，Emby | 4 | 4 | 7459290 | 成功 |
| 打开后设，Emby | 3 | 3 | 7459290 | 成功 |
| 不设 `end_offset`，Emby | 2 | 2 | 7324000 | 失败 |

现状的请求序列是 `bytes=0-`（长度探测，65536 字节后中止）、`bytes=0-18416527996`（格式探测，786432 字节后中止）、`bytes=18409167011-18416527996`（`moov`，7360986 字节）、`bytes=44-18416527996`（读包，中止）。打开后设的序列去掉第一个，唯一的开放式请求是起点为 0 的那个，`moov` 请求已带上界。两种形态的流表与 `bytes_read` 完全一致。直连不经代理时总量为 WebDAV 7376535、Emby 7375175。

### Emby 4.9.5 在 `PlaybackInfo` 时刻确实探测

库里有九个条目的 `MediaSources[0]` 既无 `MediaStreams` 也无 `RunTimeTicks` 且 `Size` 为 0，正是 3.5.2 判据成立的条件。条目 9978 首次 `PlaybackInfo` 用 2.800 秒返回并带回 5 条流、`RunTimeTicks` 35012800000 与 `Size` 13233412518，第二次 0.019 秒。条目 3586 首次 2.902 秒返回 4 条流，第二次 0.029 秒。已落库的对照条目 9482 为 0.083 秒与 0.019 秒。条目 612 每次都要 60 到 64 秒且始终返回 0 条流，它的探测不成功，什么也没落库，于是每次 `PlaybackInfo` 重来一遍。

4.9.5 的行为与 3.5.2 的判据一致，库里没有音视频流就在 `PlaybackInfo` 时刻同步探测一次并落库，有就只读库。当前部署对已扫描条目落在播放时不探测的一侧。

### 仍未决

- 设备那 13.9 MB 的窗口跨了哪两步。`open_read_volume.py` 的原始序列没有落盘，重建需要重新上设备取一次。
- Emby 4.9.5 为什么对起点为 0 的开放式请求答对而对尾部答错。4.9.5 闭源，只有行为可用。
- 上表的速率都取自 Mac。设备在 WiFi 上的每请求延迟更高，要把请求数折算成设备上的打开时间需要在设备上复测。
