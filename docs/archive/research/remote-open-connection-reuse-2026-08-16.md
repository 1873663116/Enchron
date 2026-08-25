# 远程打开的连接复用与 HEVC 配置边数据

## HTTP 选项现状

`open_media_source` 在 `avio_open2` 之前只向 HTTP 传两个选项：

- `seekable=1`。认证源的第一个响应是 401 挑战，不带 `Content-Range`；不显式声明可寻址，FFmpeg 会在收到认证后的 206 之前就放弃可寻址状态，尾部头的定位随之退化成盲读。
- `multiple_requests=1`。允许一次打开所需的多个 range 共用一个 socket。

它们必须在 `avio_open2` 建立连接之前给出。像 `end_offset` 那样在 `AVIOContext` 建成后设置，对 FFmpeg 的 HTTP 打开状态已经太晚。

打开一个远程源当前产生两次成功媒体请求、两条 TCP 连接，首个 range 是开区间 `bytes=0-`。

## 为什么不用 `initial_request_size` 限定首个请求

限定首个请求可以把打开阶段的连接数从 2 降到 1，但 FFmpeg 9.0.1 会把这个窗口继续套用到**其后每一个**请求，而不只是首个。播放读到第一个窗口边界之外的字节时，wire 上不再出现新请求，读取无限期停住。

实测（2026-08-16，`Scripts/fixtures/range-http-server.py` 提供 keep-alive 的 range 服务）：600 Mbps 的 `a7s III 4K 60p 600Mbps 10 bit 422 Slog3 SGamut3 .MP4` 在设定 `initial_request_size=131072` 时，请求序列为 `bytes=0-131071`、尾部头、`bytes=131072-262143`，随后停止，需要第 262144 字节却不再发请求；不设该选项时同一文件的第三个请求是 `bytes=131072-637671341`，一次流完 637 MB 正常结束。

两条候选缓解都无效：去掉 `short_seek_size` 仍然停住；显式把 `request_size` 设为 1 GiB 也不能覆盖该窗口。

这条代价与收益不成比例——省一条 TCP 连接，换来高码率远程媒体永久卡死——因此不采用。命中条件是"顺序读跨过一个窗口边界"，与码率相关而与文件大小无关：低码率片源的解复用往往在跨界前就完成了打开，所以只测打开阶段的用例看不到它。

回归由 `httpPlaybackReadsTheWholeSourceWithoutStalling` 守住：它把 `RecordingRangeServer` 切到复用连接模式，开视频与音频两条 lane 读到流尾。测试服务器默认对每个响应回 `Connection: close`，那种形态下连接复用根本不发生，因此只测范围形状的用例无法暴露这类停顿。

## 为什么不采纳 `AV_PKT_DATA_HEVC_CONF`

FFmpeg 9.0.1 把 `AV_PKT_DATA_HEVC_CONF` 定义为从 ISOBMFF `hvcE` 盒或 Matroska 对应 `BlockAdditionMapping` 解析出的 `HEVCDecoderConfigurationRecord`，`dovi_split` 滤镜把它装成增强层的 extradata，拆分后即移除。

它描述的是增强层，而 bridge 建 `CMFormatDescription` 需要的每一种配置都来自基础层：基础视频层用 `AVCodecParameters.extradata`（通常即 `hvcC`）；MV-HEVC 元数据走既有的 `lhvC` 原子路径；基础层配置缺失时由基础层的参数集重建。把增强层配置当作 `hvcC` 使用会描述错误的解码器输入。只有将来真正拆分并解码增强层时它才有位置。
