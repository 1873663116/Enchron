# MPVKit & KSPlayer visionOS 集成调研报告

本报告详细说明了在 visionOS 平台上集成 `MPVKit` 的调研结果，并对备选方案 `KSPlayer` 进行了评估。

## 1. MPVKit (libmpv 绑定)

### 1.1 SPM 软件包详情
- **Package URL**: `https://github.com/mpvkit/MPVKit.git`
- **支持版本**: 最新版本为 `v0.41.0` (2025-12-23)，该版本明确支持 visionOS。
- **支持平台**: macOS 11.0+, iOS 14.0+, tvOS 14.0+, visionOS 1.0+。
- **公开产品**:
  - `MPVKit`: 默认版本，遵循 LGPL 协议。
  - `MPVKit-GPL`: 包含 GPL 限制功能的版本（如支持 samba 协议）。

### 1.2 API 接口
- **提供的模块**: `MPVKit` (Swift 封装层)。
- **C API 暴露**: MPVKit 主要通过 Swift 封装 `libmpv`。虽然它基于 C API (`client.h`, `render.h`)，但通常建议使用其提供的 Swift 类 `MPVPlayer` 进行交互。它不直接在公共头文件中暴露原始 C 指针，而是通过属性和方法进行包装。
- **关键操作**:
  - **创建实例**: `let player = MPVPlayer()`
  - **播放文件**: `player.load(url: videoURL)`
  - **属性控制**: `player.setProperty("hwdec", value: "auto")`
  - **获取视频帧**: 默认通过 `MPVVideoPlayer` (SwiftUI) 自动处理渲染。对于底层访问，需结合 Metal 渲染器使用（类似于本项目中的 `MetalVideoRenderer`）。

### 1.3 visionOS 兼容性
- **模拟器支持**: 完全支持 `xrsimulator` 架构。
- **已知问题**: 
  - visionOS 的 Metal 渲染路径在某些极端情况下可能需要针对 `gpu-next` 进行额外配置。
  - 空间音频支持不如原生 `AVPlayer` 完善。
- **最低部署目标**: visionOS 1.0。

### 1.4 集成示例
1. 在 Xcode 中选择 `File > Add Packages...`，输入 `https://github.com/mpvkit/MPVKit.git`。
2. 导入模块：`import MPVKit`
3. 最小代码示例：

```swift
import SwiftUI
import MPVKit

struct PlayerView: View {
    let url = URL(string: "https://example.com/video.mkv")!
    
    var body: some View {
        MPVVideoPlayer(url: url)
            .onMPVReady { player in
                // 推荐配置
                player.setProperty("vo", value: "gpu-next")
                player.setProperty("hwdec", value: "auto")
            }
            .glassBackgroundEffect()
    }
}
```

---

## 2. KSPlayer (备选/增强方案)

### 2.1 为什么考虑 KSPlayer？
`KSPlayer` 是一个比 `MPVKit` 更成熟的苹果生态播放器方案，特别是在 visionOS 适配方面。

- **SPM URL**: `https://github.com/kingslay/KSPlayer.git`
- **双引擎架构**: 
  - 对于系统原生支持的格式，使用 `AVPlayer`（功耗低、支持杜比视界、完美适配空间音频）。
  - 对于 MKV/FLV 等非原生格式，自动切换到 `FFmpeg` 引擎。
- **visionOS 特性支持**:
  - **原生空间音频**: 深度集成 visionOS 的音频系统。
  - **协议丰富**: 原生支持 SMB, WebDAV, FTP, DLNA 等，非常适合 XrPlayer 的文件浏览需求。
  - **SwiftUI 友好**: 提供了针对 visionOS 优化的 `KSVideoPlayer` 视图。

### 2.2 KSPlayer 集成示例
```swift
import SwiftUI
import KSPlayer

struct KSPlayerView: View {
    let url = URL(string: "https://example.com/video.mkv")!
    
    var body: some View {
        KSVideoPlayer(url: url)
            .setOptions { options in
                options.playerType = KSMEPlayer.self // 强制使用 FFmpeg 引擎播放 MKV
            }
    }
}
```

## 3. 结论建议
- 如果 **XrPlayer** 需要极高的自定义渲染能力（如自定义着色器），选择 **MPVKit**。
- 如果需要快速实现稳定、全能且深度适配 visionOS 原生特性的播放体验，强烈建议使用 **KSPlayer** 作为主引擎。
