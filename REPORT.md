# Emby 媒体无法打开调查报告

调查日期为 2026-08-17。调查对象是 Emby 服务器 `http://192.168.5.2:8096` 在本次运行时返回的全部视频条目。全库共计 1081 个条目，每个条目各有一个媒体源。调查使用产品实际采用的 Emby 静态直放 URL 形状，并通过 `RemoteMediaProbe` 依次检查 HTTP Range、FFmpeg 会话打开、流信息和抽样解码。对于异常项，调查还使用服务端路径执行本地对照探测。

## 结论

| 归因 | 数量 | 占比 | 结论 |
| --- | ---: | ---: | --- |
| Mac 侧打开及抽样解码通过 | 1053 | 97.41% | HTTP Range、FFmpeg 打开及 0.5 秒抽样解码均通过。 |
| 能力边界 | 22 | 2.04% | 21 个 VC-1 和 1 个 MPEG-2 视频无法进入本产品的压缩样本渲染路径。媒体本身可访问，产品应当明确拒绝。 |
| 产品缺陷 | 6 | 0.56% | Emby 将文件长度报告为 0 且没有声明视频流，但远程和本地媒体均可打开并解码。产品原来把 0 当作权威长度，后续非零 Range 因此会被本地字节服务器拒绝。 |
| 服务端、存储或传输硬故障 | 0 | 0.00% | 没有 404、无效 Range、超时、存储路径缺失、FFmpeg 打开失败或流信息读取失败。 |

本次报告所称“通过”限定为 Mac 侧的打开和短时抽样解码，不等同于整片播放完毕，也不证明 Vision Pro 上的画面、音频或佩戴者所见错误提示。

## 全库矩阵

权威逐项结果位于：

- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/emby-open-20260817/full-matrix.json`
- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/emby-open-20260817/full-matrix.csv`
- `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/emby-open-20260817/full-matrix.jsonl`

JSON 和 CSV 是最终矩阵；JSONL 是可恢复的逐项运行记录。矩阵枚举到 996 个剧集、83 部电影和 2 个普通视频，容器分布为 771 个 MKV、309 个 MP4 和 1 个 MPEG-TS。Emby 声明的视频编码为 539 个 HEVC、514 个 H.264、21 个 VC-1 和 1 个 MPEG-2；另有 6 个媒体源没有声明视频流。库中没有 ISO 或 FLV，因此既有后缀过滤器的这两项能力承诺没有触发本次故障，不能据此对当前报告样本作归因。

全部 1081 个远程请求均返回 HTTP 206，并具有有效 `Content-Range`。调查期间 `~/Library/CloudStorage/EmbyMedia` 始终由 `localhost:/` 以 NFS 挂载；没有观察到 webdavfs，也没有出现整库 404 或开放区间补零特征。因此，本次结果没有把挂载故障误归为产品缺陷。

## 产品缺陷及修复

### 长度为零的可读媒体

6 个触发样本均来自《东京喰种》，Emby 报告的 `Size` 为 0 且视频流列表为空，但服务端实际返回 1.77 GB 至 2.52 GB 的权威总长度。远程探测和本地文件对照都成功建立会话并解码 HEVC 样本。代表证据如下：

| Item ID | 条目 | Emby 长度 | Range 响应总长度 | 远程/本地结果 |
| --- | --- | ---: | ---: | --- |
| 3588 | 东京喰种 第04集 | 0 | 1,970,228,043 | 均通过 |
| 3607 | 东京喰种 第05集 | 0 | 1,773,008,904 | 均通过 |
| 3608 | 东京喰种 第06集 | 0 | 2,228,099,551 | 均通过 |
| 3609 | 东京喰种 第08集 | 0 | 2,351,281,511 | 均通过 |
| 3587 | 东京喰种 第12集 | 0 | 2,516,382,377 | 均通过 |
| 3606 | 东京喰种 第12集 | 0 | 2,135,731,499 | 均通过 |

修复将 Emby 的非正数长度解释为未知长度。对于支持 seek 但长度未知的媒体源，本地字节服务器先发起有界 Range 读取，从响应中取得权威总长度并缓存，随后用该长度处理 HEAD、开放区间和后缀区间请求。该实现以“未知但可 seek 的字节源”为声明形状，不包含条目名称或 Emby 专用分支。

结构测试覆盖了零长度映射、首次 Range 恢复真实长度、第二次后缀 Range 复用已发现长度，以及未知且不可 seek 的顺序源仍使用 chunked transfer 的既有行为。

### 不支持编码没有明确反馈

21 个 VC-1 条目集中在《Rick and Morty》前两季，代表样本为 Item ID 3721 `Pilot`；另一个 Item ID 612 `Coherence` 使用 MPEG-2。远程与本地探测都在相同的编码能力边界失败，HTTP 和存储读取正常。

修复在建立字节流和字幕会话之前检查 Emby 已声明的视频编码。H.264、HEVC、AV1 和 ProRes 进入既有打开流程；明确声明的其他编码返回带本地化说明的 `unsupportedVideoCodec` 错误。缺失或未知的服务端声明仍交由实际媒体探测判断，避免把服务端元数据缺失误当成不支持。现有 Emby 界面会显示该错误的 `localizedDescription`，因此用户不再只看到无反馈的打开失败。

结构测试断言了 VC-1 在播放开始前被拒绝，并断言面向用户的错误文本。真机上错误区域是否位于佩戴者可见范围仍需设备验证。

## 服务端与媒体处置建议

6 个零长度样本说明 Emby 元数据与实际文件不一致。产品已经能够容忍未知长度，但服务端仍应对这些条目执行元数据刷新或库扫描，并检查扫描日志、文件权限和 NFS 属性读取，直至 `Size` 与视频流信息恢复。产品修复解决的是健壮性问题，不会把服务端元数据异常改写成正常元数据。

22 个编码边界样本需要视频转码。仅重新封装容器不会改变 VC-1 或 MPEG-2 编码，因此不能解决问题。建议将视频转为 H.264、HEVC 或 AV1，并保留所需音轨和字幕；如果希望由 Emby 动态转码，则需要另行确认产品与服务端的转码播放协议，目前的静态直放路径不会自动完成该转换。

本次没有服务端或存储硬故障需要处置。若用户再次报告“整库无法打开”，应先检查 `mount | grep EmbyMedia` 和 Emby 静态流的 Range 响应，再运行本次可恢复矩阵；不要以产品兜底掩盖挂载丢失或错误的存储实现。

## 验证结果

| 门禁 | 结果 | 证据 |
| --- | --- | --- |
| 矩阵分类单元测试 | 6 项通过 | `inventory-harness-tests.log` |
| 产品结构测试 | visionOS 模拟器上 3 个 suite、29 项通过 | `targeted-visionos-simulator-tests.log` |
| PlaybackCore 包测试 | 213 项运行；仅命中 3 个既知失败名称，共 4 个 issue | `playbackcore-swift-test.log` |
| ProRes 偶发超时裁决 | gauntlet 首轮超时，单项重跑通过 | `verification-gauntlet-quick.log` |
| 快速 verification gauntlet | 通过；结构检查 7 项通过，PlaybackCore 既知失败集合匹配 | `verification-gauntlet-quick.log` |
| visionOS 整机构建 | `generic/platform=visionOS`、禁用签名，构建成功 | `visionos-build.log` |

PlaybackCore 的三个既知失败名称为：

- `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`
- `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`
- `controllerRejectsSecondOpenAndRecordsTheRejection`

目标结构测试使用 visionOS 模拟器。Xcode 测试目标仍带有主工作树的硬编码 package 名称，因此命令行将 `OTHER_SWIFT_FLAGS` 的 package 名称覆盖为本 worktree 的 `wt_emby_open`；该覆盖没有进入产品代码。

## 设备证据待办

Mac 侧已经能够给全部 1081 个媒体源分类，没有遗留必须依赖设备才能完成的条目归因。以下结论涉及佩戴者实际体验，必须由物理 Vision Pro 补证：

1. 分别打开一个 VC-1 和一个 MPEG-2 样本，确认明确错误文字可见，且界面不会长时间停留在加载或反复重试状态。
2. 打开一个长度为零的 HEVC 样本，确认修复后的 Range 路径能够在头显上持续出画，并验证 seek 行为。
3. 对代表性的 H.264 和 HEVC 通过项验证佩戴者实际看到的画面与物理音频，避免把 Mac VideoToolbox 的抽样结果当作头显渲染证据。

本任务时间窗内物理 Vision Pro 被另一任务独占，因此没有建立任何设备会话，也没有采集或声称设备证据。

## 提交

逻辑改动已经分别提交，未推送：

- `6dfde501 Reject unsupported Emby video codecs explicitly`
- `c4d102a1 Recover remote media length from range responses`
- `c3e63bb7 Add resumable Emby open inventory probe`
- `33907e18 Cache discovered remote media length`

