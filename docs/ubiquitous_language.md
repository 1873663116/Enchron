# Ubiquitous Language

Purpose: define the shared vocabulary used by Enchron code, docs, and agent tasks.
Status: Active vocabulary.
Owner/scope: stable domain terms and their intended meaning.
This file is not a strategy essay, API contract, implementation plan, or changelog.

## PlaybackEngine

后端执行引擎。它负责实际媒体加载、播放、解码、状态推进和能力报告。

当前规划中的 engine 名称：

- `mpv`
- `appleAV`

`PlaybackEngine` 不是播放模式，不等于窗口、沉浸场景或全景。

## PlaybackEngineRoute

一次播放 session 启动前产生的确定性路由结果。它说明本 session 由哪个 `PlaybackEngine` 执行，以及该决策的依据、所需能力、fallback 策略和错误状态。

一个 session 只能拥有一个 `PlaybackEngineRoute`。

## PlaybackEngineRouter

能力路由器。它根据 source、metadata、session capability requirements 和用户未来可能的合法 override，选择一个且仅一个 engine。

`PlaybackEngineRouter` 不启动播放，不拥有 UI 状态，不决定 `PlaybackMode`。

## AppleNativeMedia

原始 source、container、timing model、codec、track model、HDR/color metadata、spatial metadata 可被 Apple 媒体框架按本 session 所需能力原生解释的媒体。

典型例子包括 AV-compatible MP4/MOV/M4V、HLS、Photos assets、Spatial Video、MV-HEVC、Apple immersive media。

扩展名不是充分证据。

## OpenFormatMedia

开放、复杂、历史遗留、元数据不完整或输入行为不稳定的媒体来源族。

典型例子包括 MKV、WebM、AVI、TS、M2TS、FLV，以及 source ownership 或 remote I/O 不足以证明 Apple route 安全的输入。

## MediaProfile

跨 engine 的媒体事实层。它描述 projection、stereo layout、HDR type、resolution 等 UI 与 `SpatialScene` 需要理解的媒体属性。

任何 adapter 内部观察到的 engine-specific 信息，都必须先归一化为 `MediaProfile` 或共享 domain capability model，才能进入 `PlayerUI`、`SpatialScene` 或持久化层。

## PlaybackMode

当前视频的呈现方式：窗口模式、沉浸场景模式或全景模式。

`PlaybackMode` 是 presentation decision，不是 engine decision。

## ProjectionType

视频的空间投影方式，例如 flat、equirectangular360、equirectangular180 或 fisheye。

## HDRType

视频源的动态范围类型，例如 SDR、HDR10、HDR10+、Dolby Vision 或 HLG。

`HDRType` 描述源事实，不等于最终显示输出已经被验证。

## HDROutputMode

渲染器选择或验证到的 HDR/SDR 输出路径。它是输出能力与配置标签，不是源文件类型。

## AudioTrack

媒体中的一条音频流。一个文件可能包含多条不同语言、编码或声道布局的音轨。

## SubtitleTrack

媒体中的字幕轨或外挂字幕表示。字幕正确性包括格式、语言、默认/forced 状态、字体附件和渲染能力。

## PlaybackSession

从用户选择一个媒体文件开始播放，到播放结束、退出或切换媒体为止的完整生命周期。

一个 `PlaybackSession` 只能拥有一个 `PlaybackEngineRoute`。

## BrowsingMediaFile

文件浏览中的媒体条目，包含文件名、大小、修改时间和来源信息。

## PlaybackMediaFile

播放语义中的媒体文件，包含 URL、格式信息、音轨、字幕轨和播放所需事实。

## DataSource

文件来源，包括本地文件系统、Apple 相册、SMB、WebDAV 和未来来源。

## ConnectionInfo

远程数据源的连接参数，例如地址、端口和协议类型。
