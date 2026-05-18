# V2 Overnight Execute — Code Review Report

**Date**: 2026-04-06  
**Reviewer**: ce-review Agent  
**Scope**: commit 12c1760..HEAD (8 Units)  
**Mode**: report-only

---

## 总览

**状态**: PARTIAL

8 个 Unit 的变更总体质量良好，架构方向正确，但存在 1 个 P1 功能性 bug（playerControls 窗口残留）和多个 P2/P3 问题需要跟进。REGRESSION.md 未更新是强制要求漏项。

---

## 发现项汇总

| 严重性 | 数量 |
|--------|------|
| P0 | 0 |
| P1 | 2 |
| P2 | 3 |
| P3 | 2 |

---

## P1 发现项

### P1-1: playerControls 窗口在沉浸退出路径（requestDismissImmersiveSpace）中不被 dismiss

**文件**: `XrPlayer/MainView.swift`

**问题**: `ToggleImmersiveSpaceButton` 和 `SceneSelectorView` 通过 `appModel.requestDismissImmersiveSpace()` 退出沉浸空间时，`playerControls` 窗口不会被关闭。

**根因分析**:
```
T1: requestDismissImmersiveSpace() → immersiveSpaceRequest = .dismiss
T2: onChange(immersiveSpaceRequest) → isTransitioningPlaybackMode = true
T3: await dismissImmersiveSpace()
T4: ImmersiveSpace.onDisappear → playbackMode = .window
     → onChange(playbackMode != .window) fires → guard !isTransitioningPlaybackMode → BLOCKED
T5: openWindow("main"); isTransitioningPlaybackMode = false
T6: playerControls 窗口永远不被 dismiss
```

直接走 `onChange(of: appModel.playbackMode)` 的退出路径（mode 先变、再 dismiss space）不受影响——那条路上两个 onChange 同时触发，flag 尚未设置，`dismissWindow("playerControls")` 可正常执行。但 `ToggleImmersiveSpaceButton` / `SceneSelectorView` 的 request 路径有此 race。

**修复方向**: 在 `.dismiss` case 处理末尾显式调用 `dismissWindow(id: "playerControls")`，不依赖 onChange 二次触发。

---

### P1-2: REGRESSION.md 未新增本轮 8 个 Unit 对应回归项

**文件**: `REGRESSION.md`

**问题**: 本轮修复了 8 个 bug（菜单闪烁、HDR 超时、元数据预读、沉浸入口统一、NLE 动效、画布缩放、骨架动画、增量刷新），CLAUDE.md 明确要求"修复 bug → 必须在 REGRESSION.md 新增对应回归项"，VerifyList 也列明 REGRESSION.md 文档同步为必做项。当前 REGRESSION.md 最高编号 REG-133，本轮无新增。

**修复方向**: 至少补充以下新回归项：
- REG-13x: 沉浸退出时 playerControls 窗口关闭（§5.9d，本条 P1-1 修复后同步）
- REG-13x: ornament 不挂宽域 .animation() — 菜单闪烁防御项（§5.4）
- REG-13x: HDR 元数据超时 3s fallback SDR profile（§5.5）
- REG-13x: MediaProfilePrefetchService 并发限制 + 取消传播（§5.6）
- REG-13x: 沉浸空间统一入口 requestImmersiveSpace（§5.9a）
- REG-13x: NLE 关闭动效向下滑入（§5.11）
- REG-13x: updateUIView 显式同步 nativeView.frame（§5.8）

---

## P2 发现项

### P2-1: MediaProfilePrefetchService 对 SMB 文件发起无效 AVFoundation 请求

**文件**: `XrPlayer/App/MediaProfilePrefetchService.swift`, `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift`

**问题**: `buildPrefetchRequests()` 使用 `file.url`（SMB 文件为 `smb://placeholder/...`）构建 PlaybackLaunchRequest 传给预读服务，但 AVFoundation `AVURLAsset` 无法加载 `smb://` scheme 的 URL，必然以错误返回，造成每次进入 SMB 文件夹时触发 N 个无效的网络/解析尝试。注释中写"AVFoundation will handle remote URLs (HTTP/WebDAV)"——WebDAV 是 HTTP(S) 所以可行；SMB 不可行，注释有误导性。

**影响**: SMB 场景下预读服务产生大量无效错误日志；不影响本地/WebDAV 场景；无 crash（已有 catch）。

**修复方向**: `buildPrefetchRequests()` 中过滤掉 `file.url.scheme == "smb"` 或更一般地只允许 `file://` 和 `http(s)://`。

---

### P2-2: MediaProfilePrefetchService Dolby Vision 检测使用非标准 key

**文件**: `XrPlayer/App/MediaProfilePrefetchService.swift` (line 197)

**问题**: 检测 Dolby Vision 使用字符串字面量 `"DolbyVisionConfiguration"` 而非 `kCMFormatDescriptionExtension_DolbyVisionConfiguration`（iOS 14+ 公开常量）。字符串可能拼写正确也可能不正确，编译器无法验证。AVFoundation 14+ 有公开常量，应使用它。

**影响**: Dolby Vision 检测可能静默失败，所有 DV 内容被误报为 HDR10 或 SDR。对于 `MediaProfilePrefetchService` 这个辅助预读路径来说影响可控（mpv 在实际播放时会纠正），但降低了预读的准确性。

**修复方向**: 改为 `kCMFormatDescriptionExtension_DolbyVisionConfiguration as String`。

---

### P2-3: `MediaProfilePrefetchService.init` 默认参数允许悄悄创建孤立 metadataService 实例

**文件**: `XrPlayer/App/MediaProfilePrefetchService.swift` (line 29)

**问题**: `public init(metadataService: PlaybackMediaMetadataService = PlaybackMediaMetadataService())` 的默认参数允许调用方省略注入，此时 prefetch 服务会写入一个独立的 store 实例，缓存对 `PlaybackLaunchCoordinator` 完全不可见。`XrPlayerApp` 已正确注入共享实例，但这个 API 设计容易在测试或未来功能中被误用。

**修复方向**: 移除默认值，或将构造器改为 `internal`/`package` 可见性，强制调用方传入共享 service。

---

## P3 发现项

### P3-1: Spatial Audio 启发式关键词匹配过于宽泛

**文件**: `XrPlayer/PlayerUI/Views/PlayerInfoBarView.swift`

**问题**: `spatialKeywords` 包含 `"360"` 和 `"surround"`，这两个词出现在非 Spatial Audio 场景的 track 名称中的概率较高（如 "360p audio"、"surround sound SDR"）。可能产生误报。VerifyList §5.10 要求技术标签对齐 player.html，player.html 仅在确认有空间音频时显示标签。

**修复方向**: 去掉 `"360"` 和 `"surround"`，或加更精确的模式（如 `"dolby atmos"` 而非仅 `"atmos"`）。

---

### P3-2: ARCHITECTURE.md 未更新沉浸空间入口统一路径说明

**文件**: `ARCHITECTURE.md`

**问题**: VerifyList 文档同步项明确指出 ARCHITECTURE.md 可能需要更新以反映"沉浸空间入口统一路径"变更（§5.9a 新增 `immersiveSpaceRequest` + MainView 统一处理器）。当前 ARCHITECTURE.md 未提及此约束，未来的代码贡献者可能不知道这个不变量而绕过它。

**修复方向**: 在 `## Architecture Invariants → App` 章节补充："系统中不存在绕开 `appModel.immersiveSpaceRequest` + MainView 处理器直接调用 `openImmersiveSpace` / `dismissImmersiveSpace` 的合法路径（`SceneSelectorView`、`ToggleImmersiveSpaceButton` 已迁移为 request 路由）。"

---

## VerifyList 覆盖情况

对照 `docs/plans/active/VerifyList.md`（共 34 条功能需求 + 边界 + 文档同步）：

| VerifyList 条目 | 代码覆盖状态 |
|---------------|-------------|
| §5.4 菜单闪烁修复（6条） | ✅ 代码已实现（移除 ornament .animation，注释充分） |
| §5.5 HDR 超时（4条） | ✅ 代码已实现（3s timeout, fallback SDR profile, Task.isCancelled） |
| §5.6 元数据预读（5条） | ✅ 代码已实现（MediaProfilePrefetchService, sessionCache, Task.isCancelled） |
| §5.9 沉浸空间（8条） | ✅ 代码已实现（requestImmersiveSpace, dismissWindow("main"), .full, SpatialTapGesture） |
| §5.10 控件对齐（12条，UI/UX部分） | ✅ 代码已实现（图标对调, px-12 padding, mx-2 spacing, Spatial Audio label） |
| §5.7 文件浏览性能（5条） | ✅ 代码已实现（.id(isLoading), mergeFiles/mergeFolders, static formatter） |
| §5.11 NLE 动效（2条） | ✅ 代码已实现（.move(edge: .bottom)） |
| §5.8 画布缩放（3条） | ✅ 代码已实现（nativeView.frame + layoutIfNeeded） |
| 边界/错误处理（5条）| ✅ fallback SDR profile, 超时跳过, 失败保留列表 |
| 文档同步 - ARCHITECTURE.md | ⚠️ 未更新（P3-2，沉浸入口统一约束未写入） |
| 文档同步 - REGRESSION.md | ❌ 未更新（P1-2，必须补充） |
| 文档同步 - CLAUDE.md | N/A |

**覆盖**: 32/34（已覆盖），2/34 未完成（ARCHITECTURE.md 和 REGRESSION.md 文档同步）

---

## Architecture Invariants 检查

| Invariant | 状态 |
|-----------|------|
| `PlaybackLaunchCoordinator` 是唯一合法播放启动路径 | ✅ |
| `openImmersiveSpace` / `dismissImmersiveSpace` 统一经过 MainView | ✅ SceneSelectorView 和 ToggleImmersiveSpaceButton 已迁移为 request 路由 |
| `PlaybackCore` 不依赖 SwiftUI/RealityKit | ✅ |
| `SpatialScene` 不承接非空间播放控制逻辑 | ✅ |
| `Persistence` 不触发播放行为 | ✅ |
| `App` 负责组装，不承载业务规则 | ⚠️ `MediaProfilePrefetchService` 在 `App/` 目录，其中包含 AVFoundation 媒体检测逻辑——归属略有争议（PlaybackCore 也适合），但当前位置在 App 层属于可接受边界，未违反 Invariant |

---

## 升级项

无法在 report-only 模式下自动修复的问题：

1. **P1-1**: `MainView.swift` dismiss 路径补 `dismissWindow(id: "playerControls")` — 需人工修复并添加回归项
2. **P1-2**: `REGRESSION.md` 补充 7+ 条新回归项 — 需人工编写
3. **P2-1**: `FileBrowsingViewModel.buildPrefetchRequests()` 过滤 SMB URL — 需人工修复
4. **P2-2**: Dolby Vision key 改用公开常量 — 需人工修复
