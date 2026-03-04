# mpv/FFmpeg visionOS 交叉编译与 Apple 框架集成研究报告

本报告详细说明了在 Apple visionOS (xrOS) 平台上构建和集成 mpv 与 FFmpeg 的现状、挑战及实践方案。

## 1. 现有开源项目研究

### 1.1 MPVKit (核心参考)
*   **项目地址**: [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit)
*   **构建机制**: 
    *   该项目是目前最接近 visionOS 原生支持的 mpv 封装。
    *   其构建脚本集（包含 `ffmpeg-build` 和 `libluajit-build`）已更新，支持 `xros` 和 `xrsimulator` 平台。
    *   **优点**: 专门针对 iOS/tvOS/visionOS 优化，解决了大部分底层工具链的交叉编译配置。

### 1.2 FFmpegKit (社区分支)
*   **项目地址**: [kingslay/FFmpegKit](https://github.com/kingslay/FFmpegKit)
*   **背景**: 官方 `arthenica/ffmpeg-kit` 已停止维护，目前由社区分支提供 visionOS 支持。
*   **支持**: 
    *   提供了 `xros` 平台的编译预设。
    *   支持通过 Swift Package Manager (SPM) 直接集成。
    *   支持 VideoToolbox 硬件加速。

### 1.3 KSPlayer (生产级参考)
*   **项目地址**: [kingslay/KSPlayer](https://github.com/kingslay/KSPlayer)
*   **特点**: 这是一个完整的播放器框架，已在 visionOS 上实现。它展示了如何处理 Metal 渲染和 CVPixelBuffer 桥接。

### 1.4 IINA (macOS 参考)
*   **项目地址**: [iina/iina](https://github.com/iina/iina)
*   **机制**: 
    *   通过 `deps/` 文件夹下的脚本管理复杂的依赖链。
    *   使用 `libmpv` 动态库，并通过 Swift 桥接 C API。
    *   **可借鉴点**: 其 `MPVController.swift` 对 libmpv 事件循环的封装非常成熟，可作为 XrPlayer 封装 libmpv 的蓝本。

---

## 2. visionOS 交叉编译的关键挑战

### 2.1 SDK 与 API 差异
*   **OpenGL/GLES 缺失**: visionOS 完全不支持 OpenGL。mpv 传统的 `vo_gpu` 必须弃用，转向基于 **Metal** 的渲染。
*   **缺失 UIKit API**: `UIScreen`, `isLandscape`, `orientation` 等 API 在 visionOS 中不可用，需要重写相关的 UI 适配逻辑。
*   **架构识别**: 编译器目标需指定为 `arm64-apple-xros` 或 `arm64-apple-xros-simulator`。

### 2.2 VideoToolbox 限制
*   **硬件解码**: M2 芯片不支持 AV1 硬件解码。HEVC (8/10-bit) 和 H.264 受支持。
*   **空间视频 (MV-HEVC)**: 系统原生支持较好，但 FFmpeg 的支持仍处于早期阶段，通常需要通过系统 API 解码获取 `CVPixelBuffer`。

### 2.3 渲染模型
*   **RealityKit 集成**: visionOS 的沉浸式视频渲染通常需要将视频帧渲染到 `CVPixelBuffer`，然后通过 `VideoMaterial` 或 `LowLevelMesh` 显示。这要求 mpv 的视频输出钩子（Hooks）能够高效输出 `CVPixelBuffer`。

---

## 3. 依赖链与配置

### 3.1 FFmpeg 最小化组件
为减少体积和编译复杂度，建议仅启用以下核心组件：
*   **libavcodec**: 核心解码。
*   **libavformat**: 容器解析（MKV, MP4 等）。
*   **libavutil**: 通用工具。
*   **libswresample/libswscale**: 格式转换。
*   **配置标志**: `--enable-videotoolbox`, `--disable-opengl`, `--disable-x11`, `--enable-cross-compile`。

### 3.2 libmpv 依赖
*   **libplacebo (强烈推荐)**: 用于 Metal 渲染后端。需要使用 Meson 进行 visionOS 交叉编译（需自定义交叉配置文件）。
*   **libass**: 用于字幕渲染。在 visionOS 上由于缺少部分系统字体 API，可能需要捆绑字体包。
*   **Lua/LuaJIT**: 如果不需要 mpv 脚本功能，可以禁用以精简体积。

### 3.3 音频输出
*   **后端**: 推荐使用 `AudioToolbox` 或 `CoreAudio`。
*   **空间音频**: 需要将 mpv 输出的 PCM 喂给 `AVAudioEngine` 以利用系统级的空间音频处理。

### 3.4 许可考量
*   如果链接了 GPL 库（如 libx264, libx265），整个应用需遵循 GPL 协议。
*   建议尽可能使用 LGPL 标志构建 FFmpeg 以符合闭源应用要求（如果需要）。

---

## 4. IINA 方案的深度分析与复用

### 4.1 编译策略
IINA 不在工程中直接编译 mpv，而是将编译好的 `libmpv.dylib` 放入 Frameworks。对于 visionOS，应采用 **XCFramework** 形式。

### 4.2 Swift 接口层 (MPVController)
XrPlayer 可复用 IINA 的以下逻辑：
1.  **事件循环**: 使用 `mpv_wait_event` 在后台线程轮询，通过 NotificationCenter 或 Combine 将事件分发到 SwiftUI。
2.  **属性观察**: `mpv_observe_property` 监听 `time-pos`, `duration`, `pause` 等关键属性。
3.  **命令发送**: 封装 `mpv_command` 为 Swift 友好的异步函数。

### 4.3 渲染桥接
IINA 在 macOS 上使用 `CAOpenGLLayer` 或 `Metal`。在 visionOS 上，我们需要实现一个 `mpv_render_context` 的 Metal 回调，将结果绘制到纹理并转换为 `CVPixelBuffer` 供 RealityKit 使用。

---

## 相关资源链接
*   [FFmpegKit visionOS Fork](https://github.com/kingslay/FFmpegKit)
*   [MPVKit](https://github.com/mpvkit/MPVKit)
*   [libplacebo VisionOS Cross-file Info](https://github.com/haasn/libplacebo/issues)
*   [IINA Source](https://github.com/iina/iina)
