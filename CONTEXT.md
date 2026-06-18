# Enchron

面向 visionOS 的沉浸式视频播放器。本文件是项目**领域语言**术语源：跨模块的领域事实先进入这里，再进入代码与文档。DesignPreview 的**组件语言**（视觉角色 / 屏幕 / tab / 面板分类的名字）在 `DesignPreview/CONTEXT.md`；某个词进哪一层的裁决判据见根目录 `CONTEXT-MAP.md`。模块归属与不变量见 `ARCHITECTURE.md`。

## Language

### 播放引擎与路由

**PlaybackEngine**:
后端执行引擎，负责媒体加载、解码、播放、状态推进与能力报告。当前生产 engine 只有 `mpv`；`appleAV` 仅作未来研究/诊断语境的保留标签。
_Avoid_: PlaybackMode、播放模式（engine 不是呈现方式）

**PlaybackEngineRoute**:
一次播放 session 启动前产生的确定性执行结果：本 session 是否由生产 `PlaybackEngine` 执行、决策依据、所需能力、fallback 策略与错误状态。一个 session 只有一个 Route。
_Avoid_: presentation、呈现路由（那是 PlaybackMode 的领地）

**PlaybackEngineRouter**:
能力路由器：根据 source、metadata 与 session capability requirements 决定进入 mpv 生产播放路径或返回 unsupported/error。不启动播放、不拥有 UI 状态、不决定 `PlaybackMode`。
_Avoid_: 双引擎生产选择器

**AppleReferencePlayback**:
用 Apple AV / AVFoundation / AVKit 建立的参考、诊断或视觉对照播放路径。不拥有 production session，不作默认 fallback，不进入 UI 产品级分支。

### 帧管线

**FrameExit（帧出口）**:
mpv 渲染结果离开 mpv 的通道，两个值：`swapchain`（mpv 直接呈现进 App 提供的 CAMetalLayer）与 `residentTexture`（mpv 写入常驻纹理环）。生产侧概念，描述帧从哪里出来。
_Avoid_: 输出模式、渲染模式、PlaybackMode

**ResidentTextureRing（常驻纹理环）**:
Swift 分配的双 IOSurface 写/读环：mpv 交替写入并原子发布 front，消费端只读 front。`FrameExit = residentTexture` 的载体。
_Avoid_: 共享纹理（不精确）、DrawableQueue

**PresentationSurface（呈现表面）**:
消费帧的载体，三个值：`windowPlane`（窗口平面）、`virtualScreen`（虚拟屏幕）、`panoramaSphere`（全景球面）。`PlaybackMode` 是决策，`PresentationSurface` 是该决策选中的载体。
_Avoid_: 场景（与 SpatialScene 的虚拟场景概念混淆）、屏幕

**FrameOutput**:
`PlaybackCore` 对外的帧输出协议边界（见 ARCHITECTURE.md 关键边界）。`FrameExit` 描述 mpv 侧通道，`FrameOutput` 描述模块边界，分属两层。

### 媒体事实

**MediaProfile**:
跨 adapter、diagnostic evidence 和研究路径的媒体事实层：projection、stereo layout、HDR type、resolution 等 UI 与 `SpatialScene` 需要理解的属性。任何 adapter 内部观察先归一化为 `MediaProfile` 或共享 domain capability model，才能进入 UI、场景或持久化层。

**AppleNativeMedia**:
原始 source、container、timing model、codec、track model、HDR/color metadata、spatial metadata 可被 Apple 媒体框架解释的媒体。扩展名不是充分证据；当前仅用于 reference、diagnostics、metadata research 与未来能力评估。

**OpenFormatMedia**:
开放、复杂、历史遗留、元数据不完整或输入行为不稳定的媒体来源族（MKV、WebM、AVI、TS、M2TS、FLV 等），需要 mpv 兼容性能力的来源。

**ProjectionType**:
视频的空间投影方式：flat、equirectangular360、equirectangular180、fisheye。

**HDRType**:
视频源的动态范围类型：SDR、HDR10、HDR10+、Dolby Vision、HLG。描述源事实。
_Avoid_: 把它当作显示输出已验证的证据

**HDROutputMode**:
渲染器选择或验证到的 HDR/SDR 输出路径。输出能力与配置标签。
_Avoid_: 源文件类型

**AudioTrack**:
媒体中的一条音频流。一个文件可能包含多条不同语言、编码或声道布局的音轨。

**SubtitleTrack**:
媒体中的字幕轨或外挂字幕表示。字幕正确性包括格式、语言、默认/forced 状态、字体附件和渲染能力。

### 播放会话与呈现

**PlaybackSession**:
从用户选择媒体开始播放，到播放结束、退出或切换媒体为止的完整生命周期。一个 session 只有一个 `PlaybackEngineRoute`、一个生产播放核心。

**PlaybackMode**:
当前视频的呈现方式：窗口、沉浸场景或全景。presentation decision。
_Avoid_: engine decision、FrameExit

### 空间环境

**Environment（环境）**:
用户在环境卡片轮播（`EnvironmentCardCarousel`）中选择的沉浸观影环境（如 Snow Village），由美术仓 `xrplay_scene` 的 RCP3 场景提供，视频在其中播放。领域概念；2026-06-17 由旧名「Scene」改名以避开 SwiftUI `Scene` 协议（见 `docs/adr/0005`）。用例表前缀 `ENV`（2026-06-18 由 `SCEN` 改名，推翻 ADR-0005 的「沿用 SCEN」，见 `docs/adr/0006`）。
_Avoid_: SwiftUI `Scene`（窗口/空间容器协议）、`SpatialScene`（渲染模块）、`PresentationSurface`（帧载体）、裸词「场景」

### 文件与来源

**BrowsingMediaFile**:
文件浏览中的媒体条目，包含文件名、大小、修改时间和来源信息。

**PlaybackMediaFile**:
播放语义中的媒体文件，包含 URL、格式信息、音轨、字幕轨和播放所需事实。

**DataSource**:
文件来源：本地文件系统、Apple 相册、SMB、WebDAV 与未来来源。

**ConnectionInfo**:
远程数据源的连接参数，例如地址、端口和协议类型。

### 协作机制

**宪法**:
`CLAUDE.md` 顶部七条，人类-agent 协作的最高裁决规则；修宪走 ADR（首例 `docs/adr/0001`）。

**真相时态**:
每份文档的归属类别：活法律（现在为真）/ 时间戳记录（当时为真）/ 工作态（本轮为真）/ 人类投影（非规范）。决定文档会不会腐烂、怎么维护。

**作战地图**:
`docs/plans/active/` 下的轮级工作态文件：目标、工作假设、issue 索引、证据与堵点登记、执棒者。一轮一张。
_Avoid_: ExecPlan（旧时代命名）

**驾驶舱**:
`docs/cockpit/index.html`，人类投影层：全景、决策队列、概念地图。agent 只写不读。

**用例表（Use Case Ledger）**:
`docs/use_cases.md`，App 用户可观察行为的唯一规范清单。蓝图模式：记应然行为（含未实现），代码与之冲突时默认表为准。ID `UC-<前缀>-<序号>` 永不复用，前缀名单封闭。
_Avoid_: 需求文档、PRD、测试计划（它只管「是什么行为」，不管为什么、不管怎么测）

**验证状态**:
用例表条目的证据等级：`已验证`（有链接证据）/ `未验证`（凭记忆，待核）/ `未实现`。描述行为是否被证据确认，与代码是否存在无关。
_Avoid_: 实现状态、完成度

**执棒者**:
当前唯一有权写仓库的会话（mac 或云端），记录在作战地图头部；接棒先改字段。
