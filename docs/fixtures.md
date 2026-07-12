# macOS PlaybackCore 测试素材

当前只登记用于两条 video-only 路线的 contract fixture。

Apple Sample Reference Path 与 PlaybackCore Target Path 必须使用同一个 fixture。素材必须短小、许可清楚、适合进入仓库和自动化，container 为 MP4 或 MOV，只有一条 H.264 Baseline 或 Main video track，不含 audio、subtitle、DRM 或其他当前未实现能力。

每个 fixture 记录稳定 `fixtureID`、repo-relative path、file hash、来源、生成方式、container、codec、profile、coded dimensions、timebase、预期 sample 数量和时间序列是否稳定、验证命令与最近验证结果。

第一份 fixture 应能被 `ffprobe`、FFmpeg demux adapter 和 `AVAssetReader` 稳定读取。它不得依赖网络、用户目录或机器专属绝对路径。

fixture 进入自动化前必须确认：文件与登记 hash 一致；两种 sample 来源都能读到完整 video stream；没有持续解码错误；预期 sample facts 足以定位缺包、顺序、timing、format description 和 sync 标记问题。

规范化对照可以比较 codec、coded dimensions、format description、PTS、DTS、duration、sync state、data readiness，以及 registry 明确声明为稳定的 sample 数量和顺序。不得把 CoreMedia 对象 identity、内存布局或 encoded payload 逐字节相同写成通用要求。
