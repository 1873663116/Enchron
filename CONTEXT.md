# Enchron 术语

Enchron 是一个产品上下文；PlaybackCore 是其中可独立测试的播放模块，不形成第二个产品或文档上下文。

## 产品与播放

**Enchron**：面向用户的 visionOS 媒体产品及其唯一代码仓库。

**Entry App**：承载 Enchron 产品来源、策略、界面与平台呈现的应用入口；macOS 与 visionOS 入口共享同一播放应用控制。
_Avoid_：Verify App、Anchor App

**macOS 近产品开发宿主**：Enchron Entry App 在 macOS 上长期维护的第一等开发入口，复用生产业务、播放与可移植呈现实现，但不形成第二个产品，也不拥有 visionOS 空间语义的最终验收权。
_Avoid_：macOS 产品、visionOS 模拟器、平行前端

**macOS Scene Host**：macOS 近产品开发宿主中用于呈现 Environment 与 Docked 的场景入口；它不代表 ImmersiveSpace、Portal 或 Panorama。
_Avoid_：macOS 游戏场景、macOS ImmersiveSpace、macOS Portal、macOS Panorama

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

**Video Player Consumer**：Window、Docked 和 Panorama 统一使用的 RealityKit `VideoPlayerComponent` consumer；三个 Presentation 只改变 scene、transform 与 immersive mode。
_Avoid_：planar consumer、Window/Docked `VideoMaterial` 路径

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

**Playback Surface Anchor**：Reality Composer Pro Environment 对 Docked 视频基准位置与朝向的唯一场景定义；产品调整只表达相对该 anchor 的变换。
_Avoid_：world 原点绝对坐标、运行时自定屏幕位置、Docking Region

**Screen Size**：Docked Video Entity 相对一米基准高度的 uniform scale，以百分比向用户呈现；宽度由 RealityKit 根据视频宽高比生成。
_Avoid_：屏幕宽度、非等比缩放、Window 尺寸、Panorama 尺寸

**Docked**：Entry App 将当前 renderer 放入所选 Reality Composer Pro 场景的 Playback Presentation。

**Panorama**：Entry App 使用 `VideoPlayerComponent` immersive viewing behavior 呈现当前 renderer 的 Playback Presentation。

**Presentation Transition**：从一个稳定 Playback Presentation 到另一个稳定 Presentation 的暂态；成功提交，失败回滚。

## 验证

**L1 Core Contract**：不依赖产品 surface 的核心合同、container 与 sample 验证。

**L2 Enchron Integration**：macOS Entry App 以真实 renderer、RealityKit consumer 和产品 adapter 证明可播放与接入等价性的验证层。

**L3 Vision Pro Acceptance**：物理 Vision Pro 上的硬件解码、HDR/EDR、音频、空间呈现、性能与最终交互验收。

**Structural Presentation Success**：Playback Presentation 的 scene、surface、renderer binding、RealityKit actual mode 与 Media Session 连续性全部符合产品合同。
_Avoid_：视觉正确、模式切换成功

**Perceptual Presentation Success**：用户实际看到的视频位置、尺度、投影、左右眼方向、视场与空间舒适度符合产品定义；它独立于 Structural Presentation Success。
_Avoid_：结构成功、无报错、renderer ready

**Rendered Presentation Success**：在规定 camera pose 下，RealityKit 输出满足 Visual Oracle 的机器验收结论。
_Avoid_：Wearer Experience Success、结构成功

**Wearer Experience Success**：真实佩戴者对空间尺度、头部运动响应、舒适度、HDR/EDR 与沉浸感作出的最终设备验收结论。
_Avoid_：Rendered Presentation Success、AirPlay 画面正确

**Diagnostic Media**：通过真实产品播放路径进入 RealityKit、并以方向、几何、双眼与时间标记提供机器视觉 oracle 的专用验收媒体。
_Avoid_：普通电影画面、UI fixture、静态占位图

**Visual Oracle**：根据 Diagnostic Media 的语义标记、方向与几何关系判断渲染结果的机器合同；逐像素参考图只作为诊断附件。
_Avoid_：像素完全一致、无黑屏即正确、普通截图目测

**DesignPreview**：生产组件的代码化陈列入口，不拥有产品导航或业务状态。

**Product Runtime Observability**：由 OSLog、signpost、Xcode、LLDB、Console、Instruments 与测试产出的可关联运行事实。
