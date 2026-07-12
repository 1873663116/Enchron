# PlaybackCore 术语表

本术语表统一项目专有概念的名称；设计与行为以 `xr-fork/docs/core-spec.md` 为准。

---

## 核心架构

**播放核心**:
本仓库要建立并测试的主体。它由 provider-neutral Demux Contract、CoreMedia Sample Assembly 和 AVFoundation / RealityKit 呈现模块组成；对外暴露一个 `@Observable` 模型、一个视频实体和一个字幕实体，不依赖 SwiftUI。
_Avoid_: 播放器、player、完整 app

**混合架构**:
AVFoundation 负责呈现、系统解码和时间线；可替换的 demux adapter 负责容器、轨道、seek 和解封装。
_Avoid_: AVF 路线、新架构

**媒体会话**:
播放核心对一次打开媒体的稳定身份和状态容器。节点记录、运行时操作、事件和 Debug Snapshot 都必须归属到具体媒体会话。
_Avoid_: 文件、URL、播放任务

**打开操作 (Open Operation)**:
播放核心接受一次 `open(source:)` 后创建的父级执行记录。它把节点 2 到节点 9 的推进、失败、cleanup 和 Debug Snapshot 归属到同一个媒体会话；第一轮实现以它作为主执行骨架。
_Avoid_: 运行时操作、节点记录、公开 API

**数据主线**:
`demux adapter -> Demux Envelope -> CMSampleBuffer -> AVSampleBufferVideoRenderer / AVSampleBufferAudioRenderer -> AVSampleBufferRenderSynchronizer -> VideoPlayerComponent -> RealityView`。
_Avoid_: 数据流、pipeline

**三接口面**:
播放核心对外的三组运行接口：控制面接收 App 命令，状态面输出连续状态和离散事件，实体面交出视频实体与字幕实体。
_Avoid_: 三个 API、对外接口

---

## 解封装与样本

**轨道模型**:
播放核心对 demux provider 原始轨道事实的稳定解释。它为 video、audio、subtitle、attachment 和 unknown 项建立核心自己的身份、来源映射、格式提示、consumer、选择结果和未选择原因。
_Avoid_: demux track list、mpv 内部 track 对象、UI 轨道菜单

**Demux Envelope Stream**:
播放核心接收 demux provider 解封装事实的能力保真事件流。Envelope 同时携带归属事实和 provider facts，供后续 sample 组装消费。
_Avoid_: 最小 sample 输入、节点 6 专用字段、测试 sidecar event stream

**Track Format Snapshot**:
节点 5 为一条轨道记录的不可变格式事实。packet 通过 `formatRevision` 引用对应 snapshot；`streamEpoch` 独立区分 seek、reset、重新打开和 cleanup 前后的事件世代。
_Avoid_: 每包重复格式、可变全局格式、泛称 generation

**CoreMedia Sample Assembly**:
把 Demux Envelope 转换成 CoreMedia sample 的节点 6 领域概念。视频路径建立 compressed video `CMSampleBuffer`；音频路径在当前验收口径中统一输出 interleaved PCM `CMSampleBuffer`。
_Avoid_: 硬解节点、renderer 输入、任意音频转码器

**Audio Decode Adapter**:
节点 6 音频侧的解码适配层。它把 AAC、MP3 或 FLAC 的压缩音频 envelope 转换成可组装 PCM sample 的 decoded PCM frame group。
_Avoid_: AAC 转码器、音频 renderer、压缩音频直通

**注入点 B**:
将自造 `CMSampleBuffer` 直接 `enqueue` 给 AVFoundation renderer 的视频注入方式，绕过容器。
_Avoid_: 方案 B、enqueue 法

**硬件解码**:
视频轨统一交系统硬解。mpv 只解封装，不参与最终视频解码；系统硬件不能解码的编码即不支持播放。
_Avoid_: 解码边界、软硬解分界

---

## 投影、立体与空间格式

**APMP**:
Apple Projected Media Profile。播放核心需要把投影方式和视图打包写入视频帧的 `CMVideoFormatDescription` 扩展，让 Apple sample-buffer / RealityKit 路径按空间媒体语义呈现。
_Avoid_: 投影标签协议

**投影**:
描述画面几何的格式描述扩展键。当前核心语义包括 `rectilinear`、`halfEquirectangular`、`equirectangular`、`fisheye` 和 `unknown`。
_Avoid_: 投影类型

**视图打包**:
描述左右眼如何打包进单帧的格式描述扩展键。当前核心语义包括 mono、SideBySide 和 OverUnder。
_Avoid_: 分眼方式、打包方式

**Apple 空间视频（排除）**:
指 MV-HEVC 空间视频、Apple Immersive Video 等双目空间视频格式。本项目明确不处理它们，`desiredSpatialVideoMode` 不进入 API。
_Avoid_: 空间视频（若未注明已排除）

**PanoramaScannerLab**:
未来视觉识别实验档案，用于研究缺少明确 metadata 时是否能用画面特征推断投影与立体布局；当前仅作为研究资料，不进入播放核心验收前置条件。
_Avoid_: 当前播放核心规格、当前验收系统

---

## 呈现与场景

**呈现三件套**:
`AVSampleBufferVideoRenderer`、`AVSampleBufferAudioRenderer` 和 `AVSampleBufferRenderSynchronizer`。三者共同承担视频、音频和共享时间线。
_Avoid_: 三大组件

**Renderer Input Coordination**:
把 CoreMedia sample 送入呈现三件套的节点 7 领域概念。它负责 renderer graph、sample 路由、backpressure、flush、seek、format changed、cleanup 和 renderer error。
_Avoid_: renderer 绑定、画面呈现、sample 组装

**RealityKit renderer 绑定**:
把 active `AVSampleBufferVideoRenderer` 写入 `VideoPlayerComponent(videoRenderer:)`，并挂到 renderer-backed video entity 的节点 8 领域概念。
_Avoid_: RealityView 呈现、产品播放形态、真机可见性

**RealityView 呈现桥**:
App Adapter 把播放核心交出的实体放入 SwiftUI scene 和 `RealityView` 的节点 9 领域概念。它记录承载面和产品播放形态；真机硬解、APMP 真实显示、HDR / EDR、性能和体感属于 L3。
_Avoid_: renderer 输入、VideoPlayerComponent 绑定、真机验收

**产品播放形态**:
用户看到的视频呈现结果。当前形态包括 Window、Docked Immersive、Panorama 和 Portal，由投影、立体布局、scene container、`RealityView` binding 和 immersive viewing request 共同解释。
_Avoid_: 三种播放模式、三种场景、`VideoPlayerComponent` 的 Window/Immersive 模式

**内容观看方式**:
RealityKit `VideoPlayerComponent.desiredViewingMode` 请求 mono 或 stereo。它由 `effectiveStereoLayout` 派生，不表达产品播放形态。
_Avoid_: 泛称 viewing mode

**沉浸媒体观看方式**:
RealityKit `VideoPlayerComponent.desiredImmersiveViewingMode` 请求 full、progressive 或 portal。它只用于全景投影的 immersive media 展示路径。
_Avoid_: 泛称 viewing mode、沉浸模式

**字幕实体**:
实体面交出的第二个 RealityKit 实体。字幕由核心按时间线产出可呈现图片或纹理，前端负责摆放。
_Avoid_: 字幕层、sub overlay、纯文本 UI 通道

---

## 验收

**验收三层**:
播放核心的分层验收标准。L1 核心事实层验证核心自己产生的事实；L2 承载集成层验证公开接口和实体输出能否被 visionOS Simulator 验证 App 接住；L3 真机事实层只验证 host 和模拟器无法证明的设备事实。
_Avoid_: 测试分级

**Debug Snapshot**:
由媒体会话中的结构化事实、播放核心当前状态和 App Adapter 回填事实派生的稳定诊断 JSON。它服务于测试、验证 App、日志和证据记录。
_Avoid_: 事实数据库、产品 UI 状态、节点直接写入目标

**验证 App**:
一次性测试 UI 套件，服务于 L2 自动化和 L3 人工验收，归验证工具范围，不随核心复制进 `XrPlayer`。
_Avoid_: 测试 UI、产品 UI

**测试素材**:
播放核心测试用的媒体样本。Contract fixtures 用于常规自动化；seed fixtures 用于探索、L2 冒烟和 L3 真机观察；restricted fixtures 只在本地人工使用。
_Avoid_: 测试视频（若未说明分类）

---

## 仓库关系

**XrPlayer**:
播放核心的下游 visionOS app。它消费播放核心 Swift Package，并提供正式 SwiftUI 前端。
_Avoid_: 播放核心、验证 App
