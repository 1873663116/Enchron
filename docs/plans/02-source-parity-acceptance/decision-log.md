# 源行为一致性验收 决策记录

本文件是决策记录，按时间累积，不遵守 artifact 的“只描述当前状态”规则。

## 2026-08-15 23:50 起点快照

集成分支 `perf/presentation-switch-source-reopen` 在 `c2cf9ed6`，领先 `main` 21 个提交，落后 0 个。工作区有一处未提交改动 `Scripts/verification/controller_timings.json`（3 增 3 删），来源未查。

三个并行工作树全部从 `c2cf9ed6` 分出，此刻均无提交：

| 工作树 | 分支 | 状态 |
|---|---|---|
| `Enchron-wt-dolby-profile5-color` | `feat/dolby-profile5-color` | 正在改 `PlaybackFFmpegBridgeTests.swift`，未提交 |
| `Enchron-wt-dolby-profile7-native` | `feat/dolby-profile7-native` | 干净 |
| `Enchron-wt-http-reuse-hevcconf` | `feat/http-reuse-hevcconf` | 干净 |

任务目标由用户给定：等三个工作树的 agent 完成后，在集成分支合并并清理，验收其工作；达成本地源与远程源的播放行为一致性，验证全部投影与格式；本地全部视频与远程 Emby 中全部 DynamicRange 视频正常播放；终态是分支可合并到 `main`。

**决策**：本轮不开工，只记录基线，一小时后重新检查三个分支是否有提交。依据是用户明确告知 agent 尚未写入，且三个工作树的分支指针确实仍在 `c2cf9ed6`，此时读代码或起验证通道都会基于即将改变的树，产出会作废。

## 2026-08-16 00:59 三个分支已合并，工作树已回收

三个 agent 各交付一个提交，均已并入集成分支，工作树已删除。集成分支现在在 `290a9138`，领先 `main` 28 个提交。

| 提交 | 内容 | 生产代码改动 |
|---|---|---|
| `66b69c78` | Fix Dolby Vision Profile 5 sample descriptions | `PlaybackFFmpegBridge.c` 一行 + `VideoSampleProvider.swift` 删两行 |
| `95ec9bef` | Reuse HTTP connections during remote media open | `PlaybackFFmpegBridge.c` 28 行 |
| `8e0d0ef1` | Add Dolby Vision Profile 7 base-layer split | `PlaybackFFmpegBridge.c` 335 行 |

三个 agent 都把报告写到了仓库根的同一个路径 `REPORT.md`，属于并发写共享路径。合并过程已把三份报告改名分流到 `docs/research/`，根目录无残留 `REPORT.md`，此项无需返工。

### 通道二（PlaybackCore macOS `swift test`）复测

完整日志 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/playbackcore-postmerge-20260816.log`。结果 200 测试 13 issue 8 失败，对照 2026-08-15 基线的 193 测试 14 issue 9 失败：

失败集合逐条比对，8 个全部是基线既有失败（两个 Apple-Streaming-Examples fixture 漂移、四个 seek 超时、一个字幕 rapid-seek、一个 `controllerRejectsSecondOpenAndRecordsTheRejection`）。基线第九个失败 `dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals`（hvcC 原子比较）**现在通过**，正是 Profile 5 修复的靶心。

**裁决**：通道二无回归，且消掉一个基线失败。测试总数 193→200 是三个 agent 新增的 7 个测试。

**仪器教训**：首次运行用 `swift test ... | tail -80`，日志只留下最后 80 行，导致四个基线失败名在日志里查无此项，一度误判为"未运行"。管道接 `tail` 既吃掉退出码也吃掉日志，取证运行一律全量重定向到文件后再检索。

### 三个提交的代码裁决

**Profile 5（`66b69c78`）通过。** C 侧把 `create_dolby_vision_format` 的 flavor 由 `NULL` 改为 `kCMImageDescriptionFlavor_ISOFamily`，Swift 侧随即删掉"从 bridge format 取 hvcC 覆盖回去"的两行补丁。这是先修根因再删代偿，方向正确；`bridgeFormat` 在同文件其余七处仍在用，删除未留下悬空变量。基线失败 `dvh1WithoutDolbyVisionConfigurationUsesHEVCAndKeepsMultiviewSignals` 转通过，与该修复的靶心一致。

**HTTP 复用（`95ec9bef`）通过。** 在 `avio_open2` 之前把 `seekable=1`、`multiple_requests=1`、`initial_request_size` 与 `short_seek_size` 放进 `ioOptions`，退出路径补了 `av_dict_free`。开打开阶段媒体请求数不变而 TCP 连接由 2 降为 1。128 KiB 这个值取自单一 fixture 的尾部头大小（104,716 字节，向上取到四个 32 KiB 单位），对尾部头更大的文件会退化为多几次 range 请求，属性能特征不属正确性问题。

该改动与一条已知外部缺陷相接：改动前首个请求是开区间 `bytes=0-`，而 [[emby-truncates-open-ended-ranges]] 记录 `webdavfs` 正是对开区间请求越界补零。改动后首个请求变为 `bytes=0-131071`，有界。这可能顺带缓解远程打开的既有故障，需在真实 Emby 上验证，不能凭推理计入收益。

**Profile 7（`8e0d0ef1`）通过，带一处越界改动需回归。** 逐项检查：`detect_dolby_vision` 在 `configure_dolby_vision_base_layer_split` 之前执行，`dolbyVisionProfile` 已就绪；`prepare_profile7_base_layer_sample_bytes` 的两个 malloc 容量分别为 `pending+packet` 与 `packet`，与最坏写入量相等，NAL 长度前缀的边界检查不会下溢，尾字节不足时报错而非静默截断；pending 缓冲区的所有权移交与释放无泄漏无双重释放；`preparedBytes` 在错误与正常两条出口都被释放。

跨 seek 的陈旧状态是这类有状态 filter 的典型缺陷，此处不成立：每次 seek 后 `VideoSampleProvider.prepare` 都经 `operations.allocate()` 新建 reader，`dolbyVisionSplitFilter`、`pendingHEVCParameterSets`、`inputEnded`、`filterDrained` 随之全新，不存在残留。

越界改动：`copy_compressed_sample` 的失败分支由"任何负返回都当作流结束"改为"仅 `AVERROR_EOF` 当结束，其余返回 `PBFFmpegReadResultError`"。这对所有源生效，不限 Profile 7。语义上更诚实，但它改变了远程源在瞬时读失败下的可见行为：此前静默截断播放，此后报错。这一条正好落在本次要验收的本地／远程一致性上，列入运行时回归项。

### 语料裁决

Emby 库 1081 条中非 SDR 54 条，全部 ffprobe 成功。其中 Dolby Vision 14 条按 profile 分解为 profile 7 双层 8 条、profile 8 单层 5 条、profile 5 单层 1 条，HDR10 40 条。

**这改变了 Profile 7 工作的份量判断**：它不是为假想负载写的代码，而是覆盖用户库里八部实际影片（教父三部曲、Furiosa、Source Code、Upgrade、十二只猴子、Project Hail Mary）。本地 fixture `Profile7.6/FEL_test_for_AVS.mkv` 经 ffprobe 确认 bl=1 el=1 cc=6，是可用的阳性样本。

Emby 的 `Dv*` 字段全空，profile 只能由文件本身得到，这条事实固化进 `Scripts/verification/inventory_dynamic_range_corpus.py`。

## 2026-08-16 01:30 度量工具的两次自校验

`PlaybackCoreRemoteMediaProbe` 原有 `playback` 阶段要求音频流存在，Profile 7 fixture 无音轨直接报错。这是仪器缺陷不是产品缺陷：video-only 是合法媒体，`TestVectors` 里也有。已改为先由 demux 信息判断有无音轨，无音轨则只跑视频通道并在输出里带 `has_audio`。

**第一次度量不合格。** `playback` 阶段对 Profile 7 fixture 在合并前后给出完全相同的 120 个视频样本，无法区分拆分是否生效。原因是该阶段只统计解复用产出，而 bridge 只有 `PBFFmpegModeCompressed` 一种模式，VideoToolbox 根本不在这条路径上——而 Profile 7 的全部主张恰恰是关于 VideoToolbox 是否接受该格式的。

因此给探针加了 `decode` 阶段：取 `PBFFmpegReaderCopyCompressedFormatDescription` 建 `VTDecompressionSession`，逐样本送解，统计 `decoded_frames`、提交失败、回调失败与样本总字节。

**第二次度量合格，机制被确认。** 同一份仪器分别装在合并前 `c2cf9ed6` 与合并后的产品代码上（探针属仪器，两侧使用同一份 `main.swift`，只有 `PlaybackFFmpegBridge.c` 不同）：

| fixture | 合并前 sample_bytes | 合并后 sample_bytes | 判读 |
|---|---:|---:|---|
| `FEL_test_for_AVS.mkv`（P7 双层） | 7,506,347 | 5,499,605 | 降 26.7%，即被剥离的增强层 |
| `Patterns_Of_Nature_DoVi_24_P5_HD`（P5） | 1,446,213 | 1,446,213 | 逐字节相同 |
| `P81_GlassBlowing2`（P8.1） | 5,550,903 | 5,550,903 | 逐字节相同 |

预先指定的判别字段是样本总字节：若拆分生效，P7 应显著下降而单层应纹丝不动。三项都如预言翻转或不翻转，拆分只对 P7 双层生效，负对照成立。

附带事实：macOS VideoToolbox 在合并前后都能把 P7 fixture 的 121 帧全部解出。也就是说 macOS 侧本就容忍交错的增强层 NAL，拆分在 macOS 上的收益是少送 27% 数据而非从不可解变可解。visionOS 是否同样容忍属设备问题，不能由这条 macOS 结果推断。

另记一处与本次合并无关的既有现象：`P81_GlassBlowing2` 的压缩格式子类型是 `hvc1` 而非 `dvh1`，说明 `has_usable_dovi_configuration` 对它返回假。合并前后一致，非本次回归，留作独立问题。

## 2026-08-16 02:00 本地全语料扫描抓到 HTTP 回归，已回退

全语料一致性扫描跑到第四个文件 `Samples/CameraOriginals/Sony-A7SIII/a7s III 4K 60p 600Mbps…MP4`（600 Mbps，0.64 GB）时挂住，探针进程 0% CPU 睡眠，服务端 20 秒零新请求。

分流顺序是先怀疑仪器再怀疑产品：本地路径 `decode` 与 `playback` 两个阶段都在 5 秒内正常读完（301 样本 / 364 MB），排除解码阶段；HTTP 路径在不经 VideoToolbox 的 `playback` 阶段同样挂住，排除新加的 `decode` 阶段。定位到 HTTP 传输本身。

**合并前后对照确认为本次合并引入的回归**：同一文件、同一服务端、同一仪器，`c2cf9ed6` 的构建 rc=0 正常读完 300 样本 362 MB，合并后的构建 rc=124 超时。

wire 上的判别证据：

| | 合并前 | 合并后 |
|---|---|---|
| 第三个请求 | `bytes=131072-637671341`（一次流完 637 MB） | `bytes=131072-262143`（再次限到 128 KB） |
| 结果 | 正常结束 | 需要第 262144 字节，wire 上不再出现请求，永久停住 |

即 `initial_request_size` 在 FFmpeg 9.0.1 里并不只作用于首个请求，而是把窗口套到其后每一个请求。命中条件是"顺序读跨过一个窗口边界"，与码率相关而与文件大小无关。

两条缓解均无效：去掉 `short_seek_size` 仍挂；显式 `request_size=1GiB` 仍挂（wire 上仍是 128 KB 窗口）。

**裁决：回退请求限定部分，保留安全部分。** 保留 `seekable=1`（认证源 401 先行时确实需要，有该 agent 的证据支撑）与 `multiple_requests=1`（不限定请求，无害），以及新增 `ioOptions` 的 `av_dict_free`；回退 `initial_request_size` 与 `short_seek_size`，并把随之改写的两处测试断言恢复为开区间形态。代价是打开阶段回到两条 TCP 连接。理由是这笔交易本身不成立：省一条连接换高码率远程媒体永久卡死，而连接数不在验收目标里，"正常播放"在。

**为什么原 agent 的单元测试不可能发现它**：`RecordingRangeServer` 对每个响应回 `Connection: close`，连接复用在该测试服务器里从不发生，而这次停顿恰恰依赖"复用一条其有界响应已耗尽的连接"。测试服务器与产品所处的真实服务端在这一点上形态不同，是这个缺陷穿过全部单元测试的结构性原因。

因此给 `RecordingRangeServer` 加了可选的 `reusingConnections`（默认关，既有用例不受影响），并加回归测试 `httpPlaybackReadsTheWholeSourceWithoutStalling`：复用连接下开视频与音频两条 lane 读到流尾。该测试经两侧验证——回退后的代码 0.018 秒通过，合并态代码 30 秒后失败并给出停在第几个样本。

测试写法上有一处必须留意：读取阻塞在 FFmpeg 的 socket 读里，Swift Testing 的 `.timeLimit` 依赖协作式取消，无法打断它（实测挂满 220 秒外层超时才被杀）。因此读循环放到后台队列，用信号量硬等 30 秒，超时判失败。**判据教训**：给可能死锁的路径写回归测试时，超时机制本身必须不依赖被测线程的配合。

通道二复测：201 测试 13 issue，失败集合仍是那 8 个基线既有失败，无新增。
