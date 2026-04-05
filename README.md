# XrPlayer

[中文](./README.md) | [English](./README.en.md)

XrPlayer 是面向 visionOS 的沉浸式视频播放器。

## 产品定位

XrPlayer 不是一个把传统播放器简单搬到头显里的项目。它的目标是：

- 提供原生、低学习成本的 visionOS 观影体验
- 统一本地与远程媒体浏览和播放
- 为三种模式建立同一套播放内核与控件体系：
  - 窗口模式
  - 沉浸场景模式
  - 全景模式

当前阶段最重视的不是功能堆叠，而是：

- 首播体验与冷启动体感
- 二级时间轴与播放控件交互
- HDR 识别与输出可信度
- SMB / WebDAV 等远程数据源稳定性

## 当前状态

- README 与对外描述统一使用 `XrPlayer`
- `Enchron` 仍可能出现在当前工作目录、提交历史或内部整理文档中
- 当前实现覆盖本地播放、远程浏览/播放、播放控件、HDR 状态管理和部分持久化能力
- 核心测试可通过 `swift test` 验证

## 核心能力

- 本地文件浏览与播放
- 远程数据源接入：`SMB`、`WebDAV`
- 播放列表、音轨、字幕、倍速、快进快退
- 二级时间轴与精确定位交互
- HDR 内容识别与输出模式区分
- 播放进度、偏好与部分场景参数持久化

## 名称约定

- `XrPlayer`：产品名、对外名称、README 默认叫法
- `Enchron`：当前工作目录名 / 内部代号

如果你在仓库中看到这些内容，属于预期行为：

- `Enchron/` 工作目录
- `XrPlayer/` 目录
- `XrPlayer.xcodeproj`
- `XrPlayer` scheme

这不代表产品名未定，只是工程与工作区还保留了部分内部命名。

## 开发环境

- Xcode 16+
- Swift 6
- macOS 14+
- visionOS SDK

说明：

- SMB 依赖 `AMSMB2`
- 没有该依赖时，SMB 适配器会以降级桩实现通过编译，但无法建立真实 SMB 连接

## 快速开始

### 1. 克隆仓库

```bash
git clone <your-repo-url>
cd Enchron
```

### 2. 在 Xcode 中打开

```bash
open XrPlayer.xcodeproj
```

选择 `XrPlayer` scheme，在 visionOS Simulator 或 Apple Vision Pro 真机上运行。

### 构建入口说明

- 日常开发、运行、真机/模拟器构建：使用 `XrPlayer.xcodeproj`
- 顶层 `Package.swift`：仅用于 `swift build` / `swift test` 的辅助校验，不是应用主工程
- `XrPlayer/XrPlayer.xcodeproj.bak`：历史备份，不参与当前开发和构建

### 3. 运行测试

```bash
swift test
```

## 项目结构

```text
Enchron/
  XrPlayer/             # 主要应用代码
    FileBrowsing/       # 本地/远程数据源接入与浏览
    PlaybackCore/       # 播放内核与播放器适配
    PlayerUI/           # 控件与播放交互
    Persistence/        # 偏好、进度、凭证等持久化
  Tests/                # SwiftPM 测试
```

## 文档入口

- 产品哲学：`docs/product_philosophy.md`
- 功能需求：`docs/Requirements.md`
- 质量门禁：`docs/quality_gates.md`
- 架构设计：`docs/design_docs/`
