# Enchron 术语

Enchron 是一个产品上下文；PlaybackCore 是其中可独立测试的播放模块，不形成第二个产品或文档上下文。

## 产品与播放

**Enchron**：面向用户的 visionOS 媒体产品及其唯一代码仓库。

**Entry App**：承载 Enchron 产品来源、策略、界面与平台呈现的应用入口；macOS 与 visionOS 入口共享同一播放应用控制。
_Avoid_：Verify App、Anchor App

**PlaybackCore**：Enchron 内负责媒体会话、sample、时间线、控制语义与 renderer graph 的独立模块。
_Avoid_：外部播放仓库、播放 App

**PlaybackRuntime**：Entry App 将产品请求交给 PlaybackCore、并把核心事实投影给界面的应用边界。
_Avoid_：第二播放核心、播放状态机

**Playback Lifecycle**：PlaybackCore 发布的媒体会话状态，包括 idle、loading、ready、playing、paused、ended 与 failed。
_Avoid_：播放模式

**Playback Presentation**：视频当前稳定的产品呈现位置，只包括 Window、Docked 和 Panorama。
_Avoid_：Playback Lifecycle、Playback Route、播放模式

**Playback Route**：Provider 与 sample 生产路线；产品固定使用 FFmpeg compressed 路线，其他路线只服务验证对照。
_Avoid_：播放模式、产品画质选项

**Media Session**：一次 accepted open 到 close 或 failed 的唯一核心身份范围。

**Current Media Slot**：PlaybackCore 同时允许占用的唯一 Media Session 位置。

**Renderer Graph**：同一 Media Session 的 video renderer、audio renderer 与共享 synchronizer。

**Renderer Consumer Binding**：Entry App 将当前 video renderer 交给唯一 RealityKit consumer 的可追溯绑定。

## 来源与产品策略

**Media Library**：Enchron 管理的虚拟媒体目录，只保存分类、媒体引用和播放相关状态。
_Avoid_：App 文件目录、本地文件系统

**Library Folder**：Media Library 中的用户分类容器，不对应系统文件夹。
_Avoid_：本地文件夹、Documents 文件夹

**Media Reference**：指向系统文件、Photos 资源或远程媒体的持久引用；删除引用不删除来源。
_Avoid_：导入文件、文件副本

**Add to Library**：创建 Media Reference，不复制、移动或修改媒体来源。
_Avoid_：导入

**Environment Context**：当前没有观影场景，或某个观影场景已经打开；它独立于 Playback Presentation。

**Docked**：Entry App 将当前 renderer 放入所选 Reality Composer Pro 场景的 Playback Presentation。

**Panorama**：Entry App 使用 `VideoPlayerComponent` immersive viewing behavior 呈现当前 renderer 的 Playback Presentation。

**Presentation Transition**：从一个稳定 Playback Presentation 到另一个稳定 Presentation 的暂态；成功提交，失败回滚。

## 验证

**L1 Core Contract**：不依赖产品 surface 的核心合同、container 与 sample 验证。

**L2 Enchron Integration**：macOS Entry App 以真实 renderer、RealityKit consumer 和产品 adapter 证明可播放与接入等价性的验证层。

**L3 Vision Pro Acceptance**：物理 Vision Pro 上的硬件解码、HDR/EDR、音频、空间呈现、性能与最终交互验收。

**DesignPreview**：生产组件的代码化陈列入口，不拥有产品导航或业务状态。

**Product Runtime Observability**：由 OSLog、signpost、Xcode、LLDB、Console、Instruments 与测试产出的可关联运行事实。
