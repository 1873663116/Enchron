# Enchron

Enchron 是一款 visionOS 视频播放器：本地文件、SMB / WebDAV / Emby 媒体库，在沉浸空间中以环境场景（海面、室内）承载大尺寸播放屏幕。

## 技术栈

- **UI / 呈现**：SwiftUI + RealityKit。窗口与沉浸空间并存，播放表面由 `VideoPlayerComponent` 与自定义 RealityKit 实体承载，dock 位姿由运行时解算器按场景 authored rest pose 计算。
- **播放引擎**：`Packages/PlaybackCore`，自定义 sample-buffer 播放管线（`AVSampleBufferDisplayLayer` / `AVSampleBufferAudioRenderer` + 自有时间轴同步）。
- **解码 / 解封装**：vendored `PlaybackFFmpeg.xcframework`（FFmpeg 9.0.1，固定 SHA-256 源码 + 本地补丁，构建脚本见 `Packages/PlaybackCore/Scripts/build_ffmpeg.sh`）。
- **媒体来源**：SMB 走 AMSMB2（动态框架），WebDAV 与 Emby 为自研客户端，本地文件经安全作用域书签访问。
- **环境场景**：`Packages/OceanEnvironment` 等。海面为 Metal FFT 波浪模拟（OceanProbe），场景资产由 Reality Composer Pro 工程导出为 `.reality`。
- **存储**：媒体库索引与播放进度存于本地数据库，远程凭据存于 Keychain，诊断数据不离开设备。

## 仓库结构

代码所有权与依赖入口以 [`ARCHITECTURE.md`](ARCHITECTURE.md) 为准；模块级说明见各 `Packages/*/AGENTS.md`。回归契约与执行协议在 `Regression/`。

## 外部依赖

| 组件 | 用途 | 许可 |
|---|---|---|
| FFmpeg 9.0.1 | 解封装 / 解码 | LGPL 2.1+ |
| AMSMB2（含 libsmb2） | SMB 客户端 | LGPL 2.1 / LGPL 2.1+ |
| FreeType、HarfBuzz、libass 等 | 字幕渲染（经 PlaybackFFmpeg 带入） | 见设置内开源许可页 |

完整第三方许可清单见应用内 设置 → Open-source Licenses，以及 [`NOTICE`](NOTICE)。

## 贡献

本项目暂不接受外部贡献（Pull Request / Issue 均不开放）。仓库公开仅为源码可见性，CI 与签名供应链不对外提供服务。
