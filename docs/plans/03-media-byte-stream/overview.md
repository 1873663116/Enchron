# Media Byte Stream 与 Format Description

## Context

两条互不相交的重构。字节侧把三种远程来源收敛到一个入口，见 [ADR 0020](../../adr/0020-media-byte-stream-is-the-single-byte-entry.md)。格式侧把 `CMVideoFormatDescription` 的构造收敛到一个所有者。两者不共用代码，可并行。

字节侧的动因是每一项与"读"有关的能力都要写三遍：本地走 `file:`，SMB 与 WebDAV 各起一个回环服务器，Emby 由 FFmpeg 直连。格式侧的动因是同一个决定散在十余处，其中一处以文件后缀字符串推断容器类型。

## Scope

包含：字节来源协议与其四个实现；回环端点的所有权迁移与生命周期；SMB 连接池；统一证书信任策略；Container Index Cache；Artwork 存储迁移与产生方式变更；解封装读线程的预读与断线恢复；等待与失败的产品行为；Format Description 的构造收敛与事实来源。

排除：新增来源类型（NFS、直播、串流）的实现；离线下载；Emby 目录内容的本地持久化。

## 术语

以 [`docs/CONTEXT.md`](../../CONTEXT.md) 为准。本文使用 Media Byte Stream、Format Description、Media Format、Media Identity、Content Revision、Viewing State Authority。

## Constraints

- 模块依赖单向，见 [ADR 0018](../../adr/0018-one-way-target-dependencies-and-media-source-ownership.md)。PlaybackCore 是独立包，看不到 MediaSource 的类型，因此它继续只接收地址；类型上的闸设在 PlaybackFeature。
- 本地文件不经回环端点。
- Emby 的目录内容与观看进度不落盘；服务器是权威。Emby 图片按其 image tag 作键落盘。
- 回归判据是 PlaybackCore 单测基线逐条比对失败名。本分支当前基线 3 失败 4 issue：`appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`、`appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`、`controllerRejectsSecondOpenAndRecordsTheRejection`，三者由主工作树在途的 pause-after-seek 工作负责。`acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` 是已记录的负载 flake，以干净重跑裁决。

## 总表

### 字节侧

| | 事项 | 完成判据 |
|---|---|---|
| M1 | 在 MediaSource 定义字节来源协议：长度（可未知）、能否跳转、是否实时、建议缓冲深度、按区间读取 | 四种来源都实现它 |
| M2 | 回环 HTTP 端点从 MediaLibrary 迁入 MediaSource，改为整个 App 一个实例 | MediaLibrary 不再持有网络端点 |
| M3 | 端点支持长度未知：改用分块传输并声明不可跳转 | 服务器不报大小的文件可顺序播放 |
| M4 | SMB 适配器实现协议，播放复用浏览已建立的连接 | 播放不再新建第二条 SMB 连接 |
| M5 | WebDAV 适配器实现协议 | 适配器内无 HTTP 服务代码 |
| M6 | Emby 字节源，经系统网络库并携带令牌 | Emby 播放经回环端点 |
| M7 | 本地文件直通，返回文件地址 | 本地播放参数仍是文件路径 |
| M8 | PlaybackFeature 的播放入口只接受端点发出的句柄 | 传裸地址编译不过 |
| M9 | 去掉端点响应中的 `Connection: close` | 单次打开的连接数下降 |
| M10 | 删除 `open_media_source` 的 HTTP 特殊分支 | 桥接层不再区分本地与 HTTP |
| M11 | SMB 连接池：一台服务器一条，懒建立，不主动断，用前确认 | 换文件不重新认证 |
| M12 | 浏览所报大小仅用于显示与排序，取字节时以服务端当场回答为准 | 尾部不被静默截断 |

### 证书

| | 事项 | 完成判据 |
|---|---|---|
| S1 | 统一证书信任策略，所有网络请求共用一处 | WebDAV 与 Emby 走同一判断 |
| S2 | 无法验证时在连接阶段询问，展示地址、证书名、指纹、有效期 | 播放阶段永不询问 |
| S3 | 按服务器记住指纹，证书变更时重新询问 | 换证书被拦下 |

### 缓存与 Artwork

| | 事项 | 完成判据 |
|---|---|---|
| C1 | Container Index Cache：只存容器索引，落硬盘，键含 Content Revision | 第二次打开同一文件不从网络取索引 |
| C2 | 设置页增加一行，沿用缩略图那套语义（无上限、显示用量、手动清除） | 与现有那一行形态一致 |
| C3 | 仅对远程来源生效 | 本地播放不写缓存 |
| A1 | 删除主动抽帧生成 Artwork 的代码路径 | 浏览不产生网络读取 |
| A2 | 退出播放时保存当前显示画面为 Artwork，覆盖旧的 | 额外读取为零 |
| A3 | Artwork 存储从 MediaLibrary 迁入 MediaSource | 三个模块经同一处存取 |
| A4 | 内存中的 Artwork 必为硬盘中已有；写盘不可丢弃 | 内存淘汰不丢失工作 |
| A5 | Emby 封面继续走服务器图片接口，按 image tag 作键 | 不经回环端点 |

### 预读与断线

| | 事项 | 完成判据 |
|---|---|---|
| P1 | 解封装读线程从"有消费者阻塞才读"改为"填至水位线" | 无人等待时仍继续填包 |
| P2 | 读线程区分可恢复的读失败与真正的流结束，失败后可恢复 | 一次读失败不再被当作播完 |
| P3 | 断线后有限次退避重连，不主动断连 | 抖动可自愈 |
| P4 | 加载指示由播放饥饿触发，不由网络事件触发 | 缓冲充足时重连全程无提示 |
| P5 | 重连判据改为来源类型，不看地址前缀 | 回环地址不再被误判为网络源 |
| P6 | 水位线与 SMB 并发取值由测量给出 | 有实测依据，不预设常量 |

### 等待与失败

| | 事项 | 完成判据 |
|---|---|---|
| E1 | 加载指示显示当前阶段，不显示读取速率 | 用户能看出卡在哪一步 |
| E2 | 连接来源失败分四类：凭据、证书、找不到服务器、地址格式 | 每类给出明确的下一步 |
| E3 | 播放中失败分四类：连接中断、文件不存在、拒绝访问、数据损坏 | 同上，且保住播放位置 |
| E4 | 播放中证书变更单列，停止播放且不在此刻接受 | 身份变更不会被顺手确认 |

### 格式侧

| | 事项 | 完成判据 |
|---|---|---|
| F1 | 编码标识归一化收敛为一处调用 | 调用点计数为 1 |
| F2 | `CMVideoFormatDescription` 的五种构造收敛到一个所有者，特例为其分支 | 构造入口计数为 1 |
| F3 | `MediaSourceInformation` 补齐 Dolby Vision 档次与立体增强层标志 | 事实集中在一个结构 |
| F4 | 是否咨询 AVFoundation 的判断改用上述事实 | 判断输入不含文件后缀匹配 |
| F5 | 冲突规则落到一处执行：以 AVFoundation 解析为底，桥接层的解码器配置合并其上 | 重建的配置不覆盖容器原文 |

### 防御

| | 事项 | 完成判据 |
|---|---|---|
| G1 | 结构检查：`CMVideoFormatDescription` 构造入口恰好一处，归一化调用恰好一处，格式判断不含后缀匹配 | 违反时构建失败 |
| G2 | 结构检查在无法运行时大声失败，不静默通过 | 通道失效可被发现 |
| G3 | 新增一种来源需触及的位置降至三处以内 | 以"假设新增 NFS"清点文件数验证 |

## Verification

| | 事项 |
|---|---|
| V1 | 格式侧合并前后 `Scripts/verification/verify_source_parity_matrix.py` 逐字段一致 |
| V2 | 真机四种来源各播一次，出画出声，跳转与切轨正常 |
| V3 | PlaybackCore 单测基线不退（8 失败 13 issue，逐条比对失败名） |
| V4 | 断线自愈：缓冲充足时断开连接，播放不中断且无提示 |
| V5 | 索引缓存：同一远程文件第二次打开，网络读取量不含索引 |

## Phases

1. 格式侧收敛（F1 至 F5、G1、G2），落在 PlaybackCore 与其桥接层，行为不变，由 V1 证明。
2. 字节侧基础（M1 至 M12、S1 至 S3、C1 至 C3、A1 至 A5），落在 MediaSource、MediaLibrary、Emby、PlaybackFeature。
3. 预读与断线（P1 至 P6、E1 至 E4），落在桥接层读线程与播放状态，依赖阶段二就位后才能测得水位线。

阶段一与阶段二文件不相交，可并行。阶段三与阶段一同处 `PlaybackFFmpegBridge.c`，在阶段一合入后进行。
