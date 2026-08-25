# ADR 0018：明确 Target 的单向依赖和 Media Source 所有权

状态：Accepted

日期：2026-07-22

实现检查点：2026-07-23。五个核心 Target 已建立，并通过根 Package 与 Xcode 27 集成验证；MediaLibrary 对 PlaybackFeature 和 PlaybackCore 的反向依赖，以及目录级媒体信息预读取已经删除。PlaybackCore 接入代码需要 Xcode 27 提供的完整 Swift 接口，visionOS Scene 需要 App 生命周期，因此两者继续由 App Target 编译，但只能调用核心 Target 公开的接口。这些平台代码不能反过来成为产品规则的所有者。

## 背景

目录重建后，`Modules/MediaLibrary`、`PlaybackFeature`、`PlaybackPresentation` 与 `DesignSystem` 仍被 Enchron、EnchronMacOS 和 DesignPreview 的 App Target 共同编译。目录表达查找与所有权意图，但编译器不能阻止跨目录访问；同一源码被多个入口重复编译，新增文件还需要人工指定它属于哪些 Xcode Target。

直接把四个目录变成四个 Target 会暴露原有的循环依赖：Media Library 创建 Playback 类型并读取进度，Playback 又反过来依赖 Media Library 的来源访问与网络状态；Playback Runtime 使用 Presentation 类型，Presentation View 又直接操作 Runtime 与 AppModel；Playback 还依赖 App 内的 Settings。只改变目录对应的 Target，而不先重新分配状态和规则的所有权，会导致编译器拒绝循环依赖，或者迫使项目公开过多接口。

Persistent Viewing State 与 Media Format Preference 又必须共用唯一的 Media Identity 与 Content Revision。把身份算法分别留在 Media Library 和 Playback 会产生两套逐渐漂移的“同一媒体”定义。

## 决策

保留 `Packages/PlaybackCore` 为独立 Package，并在 Enchron 仓库内部建立一个产品 Package，包含以下五个 Target。它们的依赖保持单向，任何 Target 都不能直接或间接地依赖回自己：

```text
MediaSource
├── MediaLibrary ──> DesignSystem
└── PlaybackFeature ──> PlaybackCore
                         └── PlaybackPresentation ──> DesignSystem

Enchron / EnchronMacOS / DesignPreview
└── 只依赖上述产品，不再共同编译生产源码
```

- `MediaSource` 拥有 Media Identity、Content Revision、来源选择、解析结果和 source-access lifetime 合同。来源特定路径、服务器与 Photos 算法保持内部。
- `MediaLibrary` 拥有虚拟 Library、Source Directory 浏览和用户选择，只输出媒体选择与 Playback Collection 快照；不创建 Playback request，不读写观看策略。
- `PlaybackFeature` 拥有唯一 PlaybackCore adapter、Playback Queue、Persistent Viewing State、Media Format Preference、播放命令与只读 Playback Snapshot；不依赖 Presentation 或 App 类型。
- `PlaybackPresentation` 拥有 Window、Docked、Panorama、Environment、Appearance、placement、controls visibility 与 transition transaction；只消费 PlaybackFeature 的命令和 snapshot，不直接访问 PlaybackCore。
- `Apps` 只组合 owners、执行 SwiftUI scene/platform effects，并把结果交回 Presentation 提交或回滚；不拥有 feature 状态。
- `DesignSystem` 只拥有跨 feature 稳定复用的视觉原语，不依赖产品 feature。

访问控制默认使用 `internal`。每个 Target 只公开其他 Target 确实需要调用的入口 View、不可变状态值、操作命令、查询和值类型，以及 App 组装依赖时必须实现的少量协议。同一 Package 的验证代码需要访问、但 App 不需要访问的实现使用 `package`，不扩大为 `public`。SwiftUI 可以直接观察的模型，其初始化方法仍保持在 Target 内部，只能由该功能唯一的公开创建入口组装。持久化实现、具体数据源实现、地址解析实现、来源专用身份算法、PlaybackCore Session、页面内部 View 和测试数据不因测试需要而公开。

迁移先在原来的单一 App Target 中消除相互依赖，再按 `MediaSource / DesignSystem → PlaybackFeature / MediaLibrary → PlaybackPresentation → Apps` 的方向建立真实编译边界。迁移期间，目录名称不代表已经存在编译隔离；完成后，App 与验证入口不再通过 Xcode 的源文件归属设置重复编译 Package 已拥有的生产源码。

## 考虑过的替代方案

### 维持四个源码目录，不建立编译边界

改动最小，但继续依赖 Agent、自律和代码审查，无法达到“错误依赖由编译器拒绝”的目标。

### 把现有四个目录直接变成四个 Targets

表面简单，但 Media Library 与 Playback 的共享身份和当前反向依赖会形成循环；为绕过编译错误只能复制类型或引入模糊 Shared Target。

### 为 Viewing State、Format Preference、Queue 和每个 UI 区域分别建立 Targets

隔离更细，但公开 API、构建图和跨 Target 变更成本显著上升。它们是 PlaybackFeature 内聚策略，并不具有独立依赖方向。

### 把共享类型放入通用 Shared/Utils

能够暂时消除循环依赖，却会丢失媒体来源身份的明确所有者，最终让所有模块都可以随意依赖这个公共目录。

## 后果

- Target 依赖关系比最初四个目录多一个 `MediaSource` Target，因为媒体身份和内容版本是多个功能共同依赖的产品概念，并不是没有所有者的工具代码。
- 迁移必须先重塑来源 handoff、settings ownership、runtime snapshot 和 platform-effect transaction，不能先完成 UI 搬家。
- App、macOS 验证入口与 DesignPreview 依赖相同的 Package Product，避免同一源码在不同 Xcode Target 中逐渐采用不同的归属设置。
- 跨 Target 使用的类型需要谨慎决定是否声明为 `public`，初期迁移成本高于继续放在单一 App Target 中；完成后，错误依赖、App 对产品核心的反向依赖，以及测试实现逐渐替代生产实现等问题会被编译器或验证规则阻止。
- Scene resource delivery 仍需独立收敛：`RealityKitContent` 当前链接但未成为生产资源权威，不能用本 ADR 掩盖。
- App 组合层必须遵守 Runtime 的启动顺序合同：先在同一 Media Session 应用 Media Format，再挂载 RealityKit surface；默认速度作为 open 的初始 rate 传入，不能在 timeline 创建前补发 `setRate`。
