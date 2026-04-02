# Enchron v3 — 代码实现完整性审计报告

> 生成时间: 2026-04-02 (v3 Round 6, T0.6)
> 审计方法: 4 个并行 Sonnet subagent 按模块分工读取代码，判定每个功能的入口可达性、逻辑完整性、数据流贯通性
> 审计范围: feature-inventory-v3.md 的 82 个功能点

---

## 审计总览

| 判定 | 数量 | 说明 |
|------|------|------|
| ✅ 完整贯通 | 52 | 入口可达 + 逻辑完整 + 数据流贯通 |
| ⚠️ 名义实现但断联 | 7 | 代码存在但调用链中断或从未触发 |
| ❌ 确认缺失 | 6 | 无代码实现 |
| ⚪ MVP 外（符合预期） | 2 | F2.3, F2.4 |
| 🔧 有 TODO/stub | 3 | 有明确 TODO 注释的未完成逻辑 |
| N/A 运行时验证 | 5 | F9.1-F9.5 需运行时测试 |

---

## 关键发现：名义实现但实际断联的功能

以下功能在 feature-inventory-v3.md 中标为 🟡（已实现未验证），但代码审计发现**调用链中断**：

### 1. 🚨 F3.2 沉浸场景模式 — VirtualScreenEntity 无视频纹理 (P0)

- **问题**: `PanoramaLayerBridge.attachVideoLayer()` 仅在 `.panorama` 模式下被调用（`PlayerControlsView.swift:447-452`），进入 `.immersive` 模式时不调用。导致 `VirtualScreenEntity` 的 `textureResource` 为 nil，虚拟影院屏幕**无视频画面**。
- **根因**: bridge 原为全景设计（名为 "PanoramaBridge"），后扩展为沉浸模式的纹理源，但 `switchPlaybackMode()` 中遗漏了 `.immersive` case 的 bridge 接入。
- **影响**: 沉浸影院模式核心体验完全不可用。
- **修复方向**: `switchPlaybackMode()` 中 `.immersive` case 也需调用 `panoramaBridge.attachVideoLayer(layer)`。

### 2. F3.9 捏合拖拽进度条 — 手势检测到但未接线 (P1)

- **问题**: `DisambiguateGestureUseCase` 正确检测 `.drag` 手势（距离 ≥ 8pt），但 `MainView.swift:136` 对 `.drag` case 执行 `break`（空操作）。
- **影响**: 空间内捏合拖拽进度条功能不可用。进度条拖拽仅通过 `PlayerControlsView` 的 Slider 控件实现。

### 3. F3.10 二级时间轴 — 计算模型无 View 消费 (P2)

- **问题**: `DetailedTimelineGeometry` 是一个完整的 zoom/tick/offset 计算模型（196 行），但**没有任何 SwiftUI View 使用它**。`DetailedTimelinePreviewSeekPolicy` 也未被调用。
- **影响**: 精细 scrubber 功能不可用。当前仅有 Slider 时间轴。

### 4. F4.1 网络缓冲指示器 — State 定义但从未触发 (P0)

- **问题**: `PlaybackState` 有 `.buffering` case，但 `MPVPlayerAdapter` 中**从未调用** `updateState(.buffering)`。`MainView` 有 `ProgressView` 但仅在初始 `.placeholder` 状态显示。
- **影响**: 网络卡顿时用户无任何反馈。

### 5. F5.2 HDR/SDR 实时切换按钮 — 后端完整但无 UI 入口 (P0)

- **问题**: `MPVPlayerAdapter.setHDREnabled(_:)` 有完整实现（切换 colorspace-hint/trc/prim + CAMetalLayer EDR），`WindowVideoViewModel` 也暴露了 `setHDREnabled` 方法，但**整个 PlayerUI 中没有任何 Toggle/Button 调用它**。
- **影响**: 用户无法手动切换 HDR/SDR 输出。

### 6. F6.2/F6.3 沉浸环境 — skyboxAssetName 是死代码 (P1)

- **问题**: `CinemaEnvironment.skyboxAssetName` 定义了 `"StarryNight"` 和 `"SunsetNature"`，但 `EnvironmentDomeEntity` **从未读取或加载这些资源**。所有环境仅渲染为纯色球体（dark=white(0.02), starry=darkBlue(0.01,0.01,0.06), sunset=brown(0.15,0.08,0.03)）。
- **影响**: "星空夜景"和"日落自然"环境没有视觉细节，仅为纯色。

### 7. F6.6 屏幕形状持久化 — 完全缺失 (P1)

- **问题**: `appModel.screenShape` 仅存在于内存。`ScreenPositionStoring` 协议和 `SwiftDataStore` 实现只持久化 distance/verticalOffset/viewAngle，**不含 screenShape**。`PreferencesStoring`/`UserDefaultsStore` 也无此字段。
- **影响**: 用户选择的曲面/平面屏幕偏好在重启后丢失。

---

## 确认缺失的功能（与 inventory 🔴 一致）

| 功能 | 缺失确认 | 优先级 |
|------|---------|--------|
| F4.3 自动重连 | ❌ 无任何 retry/reconnect 逻辑 | P0 |
| F7.5 远程缓存清理 UI | ❌ 无缓存管理 UI 或清理按钮 | P1 |
| F8.4 VoiceOver 可访问性标签 | ❌ 仅发现 1 处 `.accessibilityHidden()`，无 `.accessibilityLabel` | P1 |
| F9.1-F9.3 性能监控 | ❌ 无 os_signpost / MetricKit / Instruments 配置 | P2 |

---

## Inventory 修正（审计与 inventory 判定不一致的项）

| 功能 | Inventory 判定 | 审计判定 | 说明 |
|------|---------------|---------|------|
| F4.7 文件列表进度 | 🔴 缺失 | ⚠️ 存在但形态不同 | 实为文字标记（橙色圆点 + "Watched HH:MM:SS"），非进度条 UI |
| F7.6 About 页面 | 🔴 缺失 | ⚠️ 存在但极简 | SettingsView 有 About Section（版本 "0.1" 硬编码 + Build 号），缺许可证/致谢 |
| F3.2 沉浸场景模式 | 🟡 已实现 | ⚠️ 断联 | VirtualScreenEntity 无纹理（bridge 未接入）— 升级为 P0 |

---

## 新发现的问题（inventory 未涵盖）

| 问题 | 严重度 | 位置 | 说明 |
|------|--------|------|------|
| 关闭按钮尺寸不合规 | P2 | MainView.swift:64 | PlayerControlSurfaceStyle(size: 48)，低于 60pt 最低要求 |
| 数据源删除按钮严重违规 | P1 | FileBrowserView.swift:92 | frame(width: 24, height: 24)，远低于 60pt |
| About 版本号硬编码 | P2 | SettingsView.swift:53 | "0.1" 应读取 CFBundleShortVersionString |
| ImmersionStyle 硬编码 .full | P2 | XrPlayerApp.swift:147 | `.constant(.full)` 无法动态切换 .mixed/.full |

---

## 有 TODO/Stub 的功能

| 功能 | 问题 | 位置 |
|------|------|------|
| F1.18/F1.21 FOV 180/360 消歧 | horizontalFOVDegrees hardcoded nil | MPVPlayerAdapter.swift:1195 (TODO 注释) |
| F1.15/F1.16 SBS/OU 3D | 仅左眼单目裁剪，非真正立体 | PanoramaLayerBridge.swift:240-254 (rightEyeUVRect 未使用) |

---

## 按模块详细审计结果

### PlaybackCore (F1.5-F1.22)

| 功能 | 入口 | 逻辑 | 数据流 | 备注 |
|------|------|------|--------|------|
| F1.5 MP4 | ✅ | ✅ | ✅ | libmpv 原生支持 |
| F1.6 MKV | ✅ | ✅ | ✅ | libmpv 原生支持 |
| F1.7 MOV | ✅ | ✅ | ✅ | libmpv 支持，缺测试素材（已在 T0.3 补齐） |
| F1.8 AVI | ✅ | ✅ | ✅ | libmpv 支持，缺测试素材（已在 T0.3 补齐） |
| F1.9 SDR | ✅ | ✅ | ✅ | inferHDRType 默认路径 |
| F1.10 HDR10 | ✅ | ✅ | ✅ | 检测→EDR映射→CAMetalLayer 完整 |
| F1.11 HDR10+ | ✅ | ✅ | ✅ | 先于 HDR10 检测，映射为 HDR10 兼容（Apple 无专用 API） |
| F1.12 DV | ✅ | ✅ | ✅ | WORKAROUND 标注映射为 HDR10 |
| F1.13 HLG | ✅ | ✅ | ✅ | arib-std-b67→CAEDRMetadata.hlg 完整 |
| F1.14 4K/8K | ✅ | ✅ | ✅ | VideoToolbox hwdec-codecs=all |
| F1.15 SBS | ✅ | ⚠️ | ⚠️ | 左眼单目裁剪，非立体 |
| F1.16 OU | ✅ | ⚠️ | ⚠️ | 同 F1.15 |
| F1.17 360° | ✅ | ✅ | ✅ | 全球体 + UV 映射完整 |
| F1.18 180° | ✅ | ⚠️ | ✅ | FOV hardcoded nil，自动检测永远返回 360° |
| F1.19 鱼眼 | ✅ | ✅ | ✅ | Metal compute shader 完整调用链 |
| F1.20 HDR 自动检测 | ✅ | ✅ | ✅ | FILE_LOADED + VIDEO_RECONFIG 触发 |
| F1.21 投影自动检测 | ✅ | ⚠️ | ✅ | 180/360 消歧失效（同 F1.18） |
| F1.22 投影手动覆盖 | ✅ | ✅ | ✅ | projectionMenu + autoRoutePlaybackMode |

### PlayerUI (F3.1-F3.21, F4.x, F5.x)

| 功能 | 入口 | 逻辑 | 数据流 | 备注 |
|------|------|------|--------|------|
| F3.1 窗口模式 | ✅ | ✅ | ✅ | WindowVideoView + MetalVideoRenderer |
| F3.4 自动切换 | ✅ | ✅ | ✅ | DecidePlaybackModeUseCase + onChange |
| F3.5 200ms 消歧 | ✅ | ✅ | ✅ | DragGesture(minimumDistance:0) 已接线 |
| F3.6 单捏→菜单 | ✅ | ✅ | ✅ | toggle showControls |
| F3.7 双捏→播放/暂停 | ✅ | ✅ | ✅ | 400ms 窗口内检测 |
| F3.8 长按→2x | ✅ | ✅ | ✅ | 200ms 阈值 |
| F3.9 拖拽→进度条 | ⚠️ | ✅ | ⚠️ | **断联**: `.drag` case 执行 break |
| F3.10 二级时间轴 | ⚠️ | ✅ | ⚠️ | **断联**: 无 View 消费模型 |
| F3.11 视频列表 | ✅ | ✅ | ✅ | playlistMenu + PlaylistView |
| F3.12 播放/暂停 | ✅ | ✅ | ✅ | 状态感知图标 |
| F3.13 ±10s | ✅ | ✅ | ✅ | skip(by:) |
| F3.14 可变速度 | ✅ | ✅ | ✅ | 0.25x-5.0x 10 档 |
| F3.15 音轨 | ✅ | ✅ | ✅ | PlaybackMenuView |
| F3.16 字幕 | ✅ | ✅ | ✅ | Noto Sans SC + blend-subtitles |
| F3.17 视角旋转 | ✅ | ✅ | ✅ | -45° to +45° slider |
| F3.18 屏幕距离 | ✅ | ✅ | ✅ | 2-20m + 3 预设 |
| F3.19 屏幕高度 | ✅ | ✅ | ✅ | -2 to +2m |
| F3.20 环境位置记忆 | ✅ | ✅ | ✅ | per-environment 持久化 |
| F3.21 逐帧步进 | ✅ | ✅ | ✅ | mpv frame-step/frame-back-step |
| F4.1 缓冲指示器 | ⚠️ | ⚠️ | ⚠️ | **断联**: .buffering 从未触发 |
| F4.2 错误提示 | ✅ | ✅ | ✅ | Alert 弹窗（无重试按钮） |
| F4.3 自动重连 | ❌ | ❌ | ❌ | 确认完全缺失 |
| F4.4 进度记忆 | ✅ | ✅ | ✅ | SwiftDataStore |
| F4.5 恢复弹窗 | ✅ | ✅ | ✅ | 3 种 ResumePolicy |
| F4.6 记住选择 | ✅ | ✅ | ✅ | UserDefaultsStore |
| F4.7 列表进度 | ✅ | ✅ | ✅ | 文字标记非进度条 |
| F4.8 缓存清理 | ✅ | ✅ | ✅ | Photo 临时文件 5 天清理 |
| F4.9 结束行为 | ✅ | ✅ | ✅ | stop/repeat/playNext |
| F4.10 自动下一集 | ✅ | ✅ | ✅ | nextFileProvider |
| F5.1 HDR 标签 | ✅ | ✅ | ✅ | 3 处文本显示（info/debug/detail） |
| F5.2 HDR/SDR 切换 | ❌ | ✅ | ⚠️ | **断联**: 后端完整，无 UI 入口 |
| F5.3 DV 硬件解码 | ✅ | ✅ | ✅ | VideoToolbox hwdec-codecs=all |
| F5.4 字幕 GPU 合成 | ✅ | ✅ | ✅ | blend-subtitles=yes |

### FileBrowsing + App (F1.1-F1.4, F2.x)

| 功能 | 入口 | 逻辑 | 数据流 | 备注 |
|------|------|------|--------|------|
| F1.1 本地文件 | ✅ | ✅ | ✅ | 完整链路 |
| F1.2 Photos | ✅ | ✅ | ✅ | PHAsset 导出链完整 |
| F1.3 SMB | ✅ | ✅ | ✅ | 条件编译下完整 |
| F1.4 WebDAV | ✅ | ✅ | ✅ | PROPFIND 完整 |
| F2.1 启动 UI | ✅ | ✅ | ✅ | WindowGroup → MainView |
| F2.2 场景选择 | ✅ | ✅ | ✅ | SceneSelectorView 3 环境 |
| F2.3 面板最小化 | ❌ | ❌ | ❌ | ⚪ MVP 外 |
| F2.4 默认场景 | ❌ | ❌ | ❌ | ⚪ MVP 外 |
| F2.5 添加网络存储 | ✅ | ✅ | ✅ | DataSourceConfigView |
| F2.6 排序 | ✅ | ✅ | ✅ | Name/Date/Size 升降序 |
| F2.7 列表进度 | ✅ | ✅ | ✅ | 文字标记 |
| F2.8 自动模式 | ✅ | ✅ | ✅ | DecidePlaybackModeUseCase |
| F2.9 导航栏 | ✅ | ✅ | ✅ | TabView sidebarAdaptable |

### SpatialScene (F3.2-F3.3, F6.x)

| 功能 | 入口 | 逻辑 | 数据流 | 备注 |
|------|------|------|--------|------|
| F3.2 沉浸场景 | ✅ | ✅ | ⚠️ | **P0 断联**: bridge 未接入 |
| F3.3 全景模式 | ✅ | ✅ | ✅ | 完整链路 |
| F6.1 暗黑影院 | ✅ | ✅ | ✅ | 纯色 white(0.02)，设计意图 |
| F6.2 星空夜景 | ✅ | ⚠️ | ✅ | skyboxAssetName 死代码 |
| F6.3 日落自然 | ✅ | ⚠️ | ✅ | skyboxAssetName 死代码 |
| F6.4 环境切换 | ✅ | ✅ | ✅ | 原地替换 material |
| F6.5 平面/曲面 | ✅ | ✅ | ✅ | switchGeometry 完整 |
| F6.6 形状持久化 | ⚠️ | ❌ | ❌ | 完全缺失 |
| F6.7 过渡动画 | ✅ | ⚠️ | ✅ | 仅系统默认过渡 |

### Settings + Persistence (F7.x, F8.x)

| 功能 | 入口 | 逻辑 | 数据流 | 备注 |
|------|------|------|--------|------|
| F7.1 恢复策略 | ✅ | ✅ | ✅ | |
| F7.2 结束行为 | ✅ | ✅ | ✅ | |
| F7.3 默认速度 | ✅ | ✅ | ✅ | |
| F7.4 服务器管理 | ✅ | ✅ | ✅ | 双入口删除 |
| F7.5 缓存清理 | ❌ | ❌ | ❌ | 确认缺失 |
| F7.6 About | ✅ | ⚠️ | ✅ | 版本号硬编码 |
| F8.1 60pt 目标 | N/A | ⚠️ | N/A | 2 处违规 |
| F8.2 注视+捏合 | ✅ | ✅ | ✅ | |
| F8.3 世界空间 | ✅ | ✅ | ✅ | |
| F8.4 VoiceOver | ❌ | ❌ | ❌ | 确认缺失 |
| F8.5 Ornament | ✅ | ✅ | ✅ | .scene(.bottom) 合规 |

---

## Phase 2 修复项优先级排序（合并 inventory 🔴 + 审计新发现）

### P0 — 核心功能缺失/断联
1. **F3.2** 沉浸场景 bridge 断联 → 接入 `.immersive` 模式的 bridge（~5 行修复）
2. **F4.1** 网络缓冲指示器 → 在 mpv pause-for-cache 事件中触发 `.buffering` 状态
3. **F4.3** 自动重连 → mpv error 后 retry 逻辑
4. **F5.2** HDR/SDR 切换 → 在 PlaybackMenuView 添加 Toggle

### P1 — 体验完整性
5. **F6.6** 屏幕形状持久化 → ScreenPositionStoring 增加 screenShape 字段
6. **F6.2/F6.3** 环境纹理 → 加载 skybox 或移除 skyboxAssetName 死代码
7. **F3.9** 捏合拖拽进度条 → 接线 `.drag` case 到进度条操作
8. **F7.5** 远程缓存清理 UI → Settings 添加清理按钮
9. **F8.1** 交互目标违规 → 关闭按钮 48→60pt，删除按钮 24→60pt
10. **F8.4** VoiceOver 标签 → 主要 View 添加 accessibilityLabel

### P2 — 质量提升
11. **F1.18/F1.21** FOV 180/360 消歧 → 实现 GSpherical CroppedArea/FullPanoWidth 解析
12. **F3.10** 二级时间轴 → 创建 DetailedTimelineView 消费现有模型
13. **F7.6** About 版本号 → 读取 CFBundleShortVersionString
14. **F1.15/F1.16** SBS/OU → 真正立体渲染（需 visionOS stereo rendering API 调研）
