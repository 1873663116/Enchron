# XrPlayer

[中文](./README.md) | [English](./README.en.md)

Enchron 是一个面向 VisionOS 平台的视频播放器项目，目标是提供本地与远程（SMB / WebDAV）统一浏览和播放体验，并持续推进空间场景下的播放交互能力。

## 当前状态

- 当前主线版本聚焦 v0.3：远程数据源链路已进入“可实际连接与浏览”的阶段
- `main` 已包含最近一轮远程连接/浏览修复（SMB + WebDAV）
- 核心逻辑可通过 `swift test` 进行基础验证

## 核心能力

- 本地文件浏览与播放
- 远程数据源接入：`WebDAV`、`SMB`
- 远程目录浏览（包含文件夹列表，不仅限视频文件）
- 数据源管理（新增、连接、删除）
- 连接错误提示与基础鉴权处理

## 远程连接规则（v0.3）

- 地址为必填，用户名可选
- 当服务端要求鉴权时再补充密码
- 仅在连接成功后才将数据源持久化，避免把失败连接写入主页列表
- 已输入凭证会保存到 Keychain（用于后续连接复用）

## 开发环境

- Xcode 16+
- Swift 6
- macOS 14+
- visionOS SDK（用于真机或模拟器构建）

> 说明：SMB 依赖 `AMSMB2`。在未引入该依赖的环境中，SMB 适配器会以降级桩实现编译通过，但无法实际连接 SMB。

## 快速开始

### 1) 克隆仓库

```bash
git clone <your-repo-url>
cd XrPlayer
```

### 2) Xcode 打开并运行

```bash
open XrPlayer.xcodeproj
```

在 Xcode 中选择 `XrPlayer` scheme，目标选择 visionOS Simulator 或 Apple Vision Pro 真机后运行。

### 3) 运行核心测试

```bash
swift test
```

## 项目结构

```text
XrPlayer/
  FileBrowsing/      # 本地/远程数据源接入与文件浏览
  PlaybackCore/      # 播放内核与播放器适配
  PlayerUI/          # 播放控制与交互
  Persistence/       # 持久化与 Keychain 凭证存储
docs/                # 需求、架构与路线图文档
Tests/               # SwiftPM 测试
```

## 路线图

- v0.3：远程数据源真实可用（进行中）
- 后续：播放稳定性、UI 打磨、更多协议与媒体能力扩展

详细计划见 `docs/phase4_implementation_roadmap.md`。

文档总览见 `docs/README.md`，测试资产说明见 `docs/test_inventory.md`。

## 贡献

欢迎提交 Issue / PR。建议在提交前完成：

```bash
swift test
```

并在 PR 描述中说明：

- 变更目标
- 复现与验证步骤
- 风险点与回滚方式（如有）
