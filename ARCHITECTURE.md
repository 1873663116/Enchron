# Enchron 代码结构导航

## 仓库组成

Enchron 最低运行于 visionOS27

```text
Apps/Enchron/                    产品 App 组合与 visionOS Scene
Apps/DesignPreview/              生产 UI 组件的预览宿主
Modules/MediaSource/             本地与远程来源能力
Modules/MediaLibrary/            媒体库领域与可由 Package 编译的界面部分
Modules/PlaybackFeature/         播放产品状态与策略
Modules/PlaybackPresentation/    呈现领域，以及由 App 编译的平台界面代码
Modules/DesignSystem/            跨 feature 的视觉原语和生产组件
Packages/PlaybackCore/           独立播放核心 Package
Packages/RealityKitContent/      Xcode 工程当前链接的本地 RealityKit 内容 Package
Tests/                           Package、App 与 UI 测试
Scripts/verification/            可重复的结构与证据辅助检查
```

## 编译所有权

根 [`Package.swift`](Package.swift) 当前定义五个 library target。它也是这些 target 依赖关系的直接事实来源：

```mermaid
flowchart LR
    MediaSource["MediaSource"]
    DesignSystem["DesignSystem"]
    MediaLibrary["MediaLibrary"]
    PlaybackFeature["PlaybackFeature"]
    PlaybackPresentation["PlaybackPresentation"]

    MediaLibrary --> MediaSource
    MediaLibrary --> DesignSystem
    PlaybackFeature --> MediaSource
    PlaybackPresentation --> PlaybackFeature
```

## 产品代码职责

[`Modules/MediaSource`](Modules/MediaSource) 表达来源身份、授权与本地或远程访问。

[`Modules/MediaLibrary`](Modules/MediaLibrary) 表达虚拟媒体库、来源浏览和媒体引用。由根 Package 编译的领域代码与由 App 编译的平台界面代码通过 manifest 的 exclude 列表区分。

[`Modules/PlaybackFeature`](Modules/PlaybackFeature) 表达面向产品的播放状态和策略。`PlaybackRuntime` 是 App 当前连接 PlaybackCore 的适配层。

[`Modules/PlaybackPresentation`](Modules/PlaybackPresentation) 表达 Window、Portal、Docked、Panorama 和 Environment 相关的产品状态。平台 Scene、RealityKit 和 SwiftUI 呈现代码由 Enchron App 编译。

UI 生产表面属于承载其产品行为的 feature，跨 feature 的视觉原语和组件属于 [`Modules/DesignSystem`](Modules/DesignSystem)。[`Apps/DesignPreview`](Apps/DesignPreview) 展示这些生产实现，不拥有平行的产品页面或状态。

[`Apps/Enchron`](Apps/Enchron) 组合来源、媒体库、播放 feature、平台呈现和系统 Scene，并承担产品运行入口。

## 查证入口

产品结果从对应生产代码和运行结果查证。测试入口、断言和场景以 [`Tests`](Tests) 与当前 `.xctestplan` 文件为准。

结构检查脚本位于 [`Scripts/verification`](Scripts/verification)
