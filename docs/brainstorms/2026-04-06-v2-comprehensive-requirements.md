---
date: 2026-04-06
topic: v2-comprehensive
supersedes:
  - 2026-04-05-uiux-redesign-requirements.md
  - 2026-04-05-known-issues-fix-requirements.md
  - 2026-04-05-playback-mode-hierarchy-requirements.md
---

# Enchron V2 综合需求文档

本文档是 Overnight Pipeline 的**唯一任务权威源**。Supervisor 每轮只需读取本文件即可恢复完整上下文。所有之前的 brainstorms 文档被本文件取代。

---

## 1. 目标总述

Enchron 是面向 visionOS 的沉浸式视频播放器。本轮迭代有四大目标：

1. **UI 严格对齐 HTML 设计稿** — 播放控件、首页、详情页逐像素对齐
2. **功能完善** — 缩略图加载、数据源切换加载态、HDR 开关
3. **视频格式自动识别 + 播放路由状态机** — 三轴正交模型，元数据驱动
4. **QA/E2E 验收** — 完整 Accessibility 体系 + 形式对齐验证

---

## 2. 三轴正交模型（核心架构变更）

当前 `ProjectionType` 混淆了投影几何和立体布局。必须拆分为三个正交轴。

### 2.1 三轴定义

| 轴 | 代码命名 | 枚举值 | 语义 |
|----|---------|--------|------|
| **播放模式** | `PlaybackMode` | `.window` / `.immersive` / `.panorama` | 视频呈现在哪里（空间位置） |
| **立体布局** | `StereoLayout` | `.mono` / `.sideBySide` / `.topBottom` | 怎么分左右眼（立体编排） |
| **投影类型** | `ProjectionType` | `.flat` / `.equirectangular180` / `.equirectangular360` / `.fisheye` | 内容的几何拓扑（平面 vs 球面） |

三轴正交组合，视频内容的原生属性决定天花板。

### 2.2 域模型变更

**当前状态（需要重构）：**
```swift
// ProjectionType 混合了投影 + 立体
enum ProjectionType { case flat, stereoscopicSBS, stereoscopicOU, panorama360, panorama180, fisheye }
// StereoMode 存在但未纳入 MediaProfile
enum StereoMode { case sideBySide, overUnder }
// MediaProfile 缺少 StereoLayout
struct MediaProfile { let projectionType: ProjectionType; let hdrType: HDRType; ... }
```

**目标状态：**
```swift
// ProjectionType — 纯几何投影
enum ProjectionType { case flat, equirectangular180, equirectangular360, fisheye }

// StereoLayout — 纯立体编排（取代当前 StereoMode 命名）
enum StereoLayout { case mono, sideBySide, topBottom }

// MediaProfile — 三轴都有
struct MediaProfile {
    let projectionType: ProjectionType
    let stereoLayout: StereoLayout
    let hdrType: HDRType
    let resolution: Resolution
    let frameRate: Double
    let videoCodec: String?
    let durationSeconds: Double?
    let hasCoverArt: Bool  // 新增：是否有内嵌封面
}
```

### 2.3 PlaybackMode 约束矩阵

**由 ProjectionType 决定可用的 PlaybackMode：**

| 内容的 ProjectionType | Window | Immersive | Panorama |
|----------------------|--------|-----------|----------|
| `.flat` | OK | OK | **禁用** |
| `.equirectangular180` | OK（降格预览） | OK | OK |
| `.equirectangular360` | OK（降格预览） | OK | OK |
| `.fisheye` | OK（降格预览） | OK | OK |

**核心规则：Panorama 模式仅对全景投影内容开放。Window 和 Immersive 对所有内容开放。**

### 2.4 StereoLayout 约束矩阵

**由内容原生 StereoLayout 决定 3D 开关可用性：**

| 内容的 StereoLayout | 3D 开关 |
|---------------------|---------|
| `.mono` | **禁用**（锁定 2D） |
| `.sideBySide` | 可开可关（关 = 降格为 mono 渲染） |
| `.topBottom` | 可开可关（关 = 降格为 mono 渲染） |

**核心规则：只能降格，不能越级。mono 内容永远不能开启 3D。**

### 2.5 自动路由逻辑

播放启动时，`DecidePlaybackModeUseCase` 根据 MediaProfile 自动选择：
- 全景 + 3D 内容 → Panorama 模式 + 3D 开启
- 全景 + mono 内容 → Panorama 模式 + 2D
- 平面 + 3D 内容 → Immersive 模式 + 3D 开启（沉浸式大屏 3D）
- 平面 + mono 内容 → Window 模式 + 2D

用户可手动切换，但受约束矩阵限制。不合法的切换目标在 UI 上灰色禁用。

---

## 3. 视频格式自动识别（INVESTIGATE 阶段）

### 3.1 识别来源

**必须依赖容器元数据，不依赖文件名。** 需要调查以下路径：

| 容器格式 | 投影类型检测 | 立体布局检测 |
|---------|------------|------------|
| MKV/WebM | Matroska `Projection` element | `StereoMode` element |
| MP4/MOV | `sv3d` box (Spherical Video V2), `SA3D` (Spatial Audio) | `st3d` box |
| Apple MV-HEVC | 系统 AVFoundation API | Apple Spatial Video metadata |
| 通用 | mpv `video-params/stereo-in` 属性 | mpv `video-params` |

### 3.2 封面/缩略图检测

| 来源 | 方法 |
|------|------|
| 内嵌封面（MKV attached picture / MP4 cover art） | 优先使用 |
| 无封面 → 提取帧 | 取视频某时间点的帧作为缩略图 |

### 3.3 HDR 类型检测

mpv 属性：`video-params/primaries`、`video-params/gamma`、容器级 HDR metadata。
映射到 `HDRType`：`.sdr` / `.hdr10` / `.dolbyVision` / `.hlg`。
注意：`hdr10Plus` 已在枚举中，保留。

### 3.4 调查范围

Overnight INVESTIGATE 阶段需产出：
1. mpv 暴露哪些属性可用于 ProjectionType 和 StereoLayout 检测
2. 各容器格式的元数据字段映射
3. 封面提取的最佳实现路径（mpv API vs AVFoundation）
4. 全场景组合矩阵（确保不遗漏任何合法组合）

---

## 4. UI 严格对齐

### 4.1 设计稿权威

| 页面 | 设计稿 |
|------|--------|
| 首页（文件浏览器） | `docs/designs/variant-AB-combined.html` |
| 播放器（控件 + 时间轴） | `docs/designs/player.html` |

**对齐标准：** 布局结构、元素排列顺序、展开方向、面板相对位置必须与 HTML 一致。使用 visionOS 原生容器（Liquid Glass、系统材质）替代 HTML 的 CSS 容器，但形式结构不变。

### 4.2 播放控件 — player.html 对齐清单

#### 控制栏（胶囊形）
- 5 个核心按钮，从左到右：Menu → Rewind → Play/Pause → Forward → Settings
- 胶囊形玻璃容器（pill-shaped glass）

#### Menu 弹出面板（向上展开，面板居右对齐按钮位置）
```
┌────────────────────┐
│ [ON]  {HDR标签}     │  ← 动态：Dolby Vision / HDR10 / HLG / 不显示(SDR)
├────────────────────┤
│ ◀  Subtitles       │  ← 三级菜单向左展开
├────────────────────┤
│ ◀  Audio Track     │  ← 三级菜单向左展开
├────────────────────┤
│ ◀  Playback Speed  │  ← 三级菜单向左展开（可滚动列表）
└────────────────────┘
```

**HDR 标签动态规则：**
- 内容是 Dolby Vision → 显示 `Dolby Vision` + ON/OFF 状态
- 内容是 HDR10 → 显示 `HDR10` + ON/OFF
- 内容是 HLG → 显示 `HLG` + ON/OFF
- 内容是 SDR → **该项不显示**

#### Settings 弹出面板（向上展开，面板居左对齐按钮位置）
```
┌─────────────────────┐
│  Playback Mode   ▶  │  ← 三级菜单向右展开
├─────────────────────┤
│  Environment     ▶  │  ← 三级菜单向右展开（可滚动卡片列表）
└─────────────────────┘
```

**Playback Mode 三级菜单：**
- Window / Immersive / Panorama
- 当前激活项带 ✓ 标记
- 不可用项（受 ProjectionType 约束）灰色禁用 + 不可点击

**3D 开关：** 在 Settings 面板中新增一项（或在 Playback Mode 子菜单中）：
```
│  3D              ▶  │  ← 展开显示 Off / Side-by-Side / Top-Bottom
```
- 内容是 `.mono` → 整项灰色禁用
- 内容是 `.sideBySide` → 默认选中 Side-by-Side，可切换为 Off
- 内容是 `.topBottom` → 默认选中 Top-Bottom，可切换为 Off

#### 顶栏
- 左侧：返回按钮 + 视频标题 + 技术标签（4K HDR · HEVC · Spatial Audio）
- 返回按钮：圆角矩形玻璃按钮，点击返回文件浏览器

#### 进度条
- 位于控制栏上方
- 左侧：当前时间（如 1:01:22）
- 右侧：剩余时间（如 -1:26:52）
- 拖动滑块可跳转

#### NLE 二级时间轴
- 从底部滑出的面板（180pt 高）
- 玻璃背景（rgba(14,14,14,0.85) + blur 40px）
- 标尺（时间刻度）+ 轨道区域（缩略图条）+ 中央播放头

### 4.3 播放详情页 — 缺失功能

| 缺失项 | 描述 |
|--------|------|
| **返回按钮** | 详情页顶部的返回按钮 |
| **HDR 开关** | 与播放控件中的 HDR 开关同步，允许用户在进入播放前预设 |
| **沉浸模式选择** | 用户可在详情页选择以沉浸空间播放 |

### 4.4 首页 — variant-AB-combined.html 对齐

- 整体风格、卡片布局、导航结构必须与设计稿一致
- 视频卡片显示缩略图/封面（见第 5 节）

---

## 5. 功能需求

### 5.1 视频缩略图/封面加载

**现象：** 首页所有视频卡片和播放详情页均无缩略图。

**期望：**
- 优先加载视频文件内嵌封面（MKV attached picture / MP4 cover art）
- 无内嵌封面 → 提取视频某帧作为缩略图
- 缩略图应缓存，避免每次重新提取

### 5.2 数据源切换加载状态

**现象：** 切换到 WebDAV/SMB 时，页面停留在本地文件夹，无加载动画，直到远程数据加载完成才跳转。

**期望：**
- 立即切换到目标数据源页面
- 显示加载动画（skeleton shimmer 或 ProgressView）
- 加载完成后替换为实际内容

### 5.3 三种播放场景的切换

| 模式 | 窗口状态 | 视频呈现 | 控件 |
|------|---------|---------|------|
| **Window** | APP 窗口可见 | 窗口内 Metal 渲染 | 窗口底部 ornament |
| **Immersive** | APP 窗口消失 | 沉浸空间中虚拟大屏纹理 | 独立浮动窗口（可拖动） |
| **Panorama** | APP 窗口消失 | 球体内壁（180°/360°） | 独立浮动窗口（可拖动） |

- Immersive 和 Panorama 共享同一套播放控件 — 视觉和交互与 Window 模式完全一致
- 控件宿主是独立的 visionOS `.plain` window，可被用户自由拖动位置
- 双击视频纹理唤出/隐藏控件
- 2D 和 3D 视频都可以在 Immersive 模式中播放
- Panorama 模式仅全景投影内容可用

### 5.4 播放控件交互 Bug

**现象：** 播放中二级/三级菜单不可拖动、不可点击，且持续闪烁。暂停后恢复正常。

**这是 P0 bug，必须优先修复。**

可能的根因方向：
- 播放刷新帧率干扰了 SwiftUI 状态更新
- 菜单的 visibility 状态被播放循环中的某些逻辑反复 toggle
- ornament 的 hit testing 与视频渲染层冲突

### 5.5 HDR 视频详情页卡死（P0）

**现象：** 部分 HDR 视频在打开详情界面时无限加载，界面完全冻结，无法操作任何按钮/选项。

**可能的根因方向：**
- mpv profile 检测对特定 HDR 视频的元数据解析挂起，阻塞 UI 线程
- HDR 元数据解析超时未处理，导致等待永远不会返回的回调
- 需要对元数据检测增加超时机制和错误兜底

### 5.6 详情页首次加载元数据错误（P0）

**现象：** 打开视频详情页时，首次显示的信息（分辨率、编码、HDR 类型等）是错误的。关闭后重新打开才显示正确信息。

**根因：** 当前实现在打开详情页时才触发 mpv 检测管道，首次返回的是不完整/默认的 profile，第二次才拿到缓存的正确值。

**期望的优雅方案 — 预读+缓存：**
- **文件夹打开时预读**：进入某个目录时，后台批量预读所有视频文件的元数据（MediaProfile）
- **结果缓存到磁盘**：预读结果持久化（SwiftData 或文件缓存），下次直接从缓存加载
- **详情页零检测**：打开详情页时直接从缓存读取已有 profile，不再重新跑检测管道
- **缓存失效策略**：文件修改时间变化时重新检测
- **目标**：彻底消除详情页的加载延迟和首次数据错误

### 5.7 文件浏览系统性能与交互问题（P1）

#### 5.7a 文件浏览性能差

**现象：** 文件列表渲染/滚动卡顿。

**可能的根因方向：**
- 缩略图加载阻塞主线程
- LazyVGrid 未正确延迟加载
- 大量文件时列表未做虚拟化

#### 5.7b 远端数据源加载动画不正确（强化 §5.2）

**现象：** 切换到远端来源（WebDAV/SMB）时，确实有了加载页面，但加载动画没有正确播放（如 ProgressView 未旋转/shimmer 未动）。

**验收标准：** 加载动画必须是可见的、持续播放的视觉反馈，直到数据加载完成。

#### 5.7c 下拉刷新跳变

**现象：** 在文件页面下拉刷新时，页面内容突然跳变（可能是整个列表重建），且无明确的刷新成功/失败反馈。

**期望：**
- 下拉刷新时保持当前列表稳定，仅增量更新变化的内容
- 刷新完成后有明确的成功/失败反馈

### 5.8 视频画布不跟随窗口缩放（P2）

**现象：** 通过注视窗口边缘拖动调整窗口大小时，视频画布尺寸不更新，画布保持原始大小。这是一个长期存在的问题。

**调查方向：**
- UIViewRepresentable 在 visionOS 窗口 resize 时的生命周期
- 可能需要 GeometryReader 包裹 WindowVideoView，将 size 传入触发 updateUIView
- mpv 的 `vo-configured` 事件和 `video-out-params` 属性——mpv 可能缓存了输出分辨率
- MPVNativeMetalLayerView.layoutSubviews() 中的 MoltenVK workaround 是否过滤了合法 resize

### 5.9 沉浸空间行为问题（P0）

#### 5.9a 沉浸空间入口不统一

**现象：** 从详情页进入沉浸空间的路径和在播放状态下进入沉浸空间的路径不一致（代码路径不同）。

**期望：** 所有进入沉浸空间的路径统一经过 PlaybackLaunchCoordinator，确保行为一致。

#### 5.9b 进入沉浸空间后窗口未消失

**现象：** 无论从详情页还是播放状态进入沉浸空间，都只打开了沉浸空间，但原有的 APP 窗口仍然可见。

**期望：** 进入 Immersive/Panorama 模式后，APP 主窗口必须自动隐藏。这在 §5.3 的模式定义表中已明确，但当前未实现。

#### 5.9c 沉浸空间应为独占模式

**现象：** 进入沉浸空间后，其他应用仍然可见。

**期望：** 沉浸空间使用 `.full` immersion style（visionOS `ImmersiveSpaceSession` 设为 `.full`），屏蔽其他所有应用，只保留 Enchron。

#### 5.9d 沉浸空间中无法召唤播放控件

**现象：** 进入沉浸空间后，没有任何方式可以唤出播放控件，用户完全失去对播放的控制。

**期望：** 点击沉浸空间中的虚拟屏幕（视频纹理），toggle 播放控件的显示/隐藏。控件宿主是独立的 `.plain` window（见 §5.3），通过点击视频纹理触发。

### 5.10 播放控件严格对齐 player.html（P0）

**本条强化 §4.2，明确执行标准。**

播放控件必须与 `docs/designs/player.html` 逐元素严格对齐，不允许自由发挥布局：

| 对齐维度 | 要求 |
|---------|------|
| **间距** | padding/margin 与 HTML 一致 |
| **按钮** | 尺寸、图标、排列顺序一致 |
| **菜单** | 展开方向、层级结构、容器内按钮排布一致 |
| **容器** | 形状（胶囊/圆角矩形）、相对位置一致 |
| **弹出面板** | Menu 面板居右对齐、Settings 面板居左对齐 |

用 visionOS 原生容器（Liquid Glass、系统材质）替代 CSS 容器，但**布局结构、元素数量、排列逻辑必须一比一复刻**。

### 5.11 NLE 二级时间轴关闭动效突变（P1）

**现象：** NLE 二级时间轴的打开动效非常丝滑（从底部滑出），但关闭时没有反向的滑入动效，而是突然消失（突变）。

**期望：** 关闭动效必须是打开动效的反向播放——从底部滑入收起，与打开时的滑出对称。需要在关闭路径上加入 `.transition(.move(edge: .bottom))` 并用 `withAnimation` 包裹。

---

## 6. QA/E2E 验收

### 6.1 Accessibility 体系

- 所有可交互元素必须有 `accessibilityIdentifier`
- 按钮、开关、菜单项都必须有 `accessibilityLabel`
- 遵循 Apple HIG 无障碍规范

### 6.2 执行要求

- 执行 `/qa`（Standard 档位）和 `/e2e`
- **不使用 Simulator 截图测试**
- 严格验证 UI 形式对齐（控件数量、排列顺序、展开方向、禁用状态）
- 验证状态机约束（所有 ProjectionType × StereoLayout 组合的 PlaybackMode 可用性）

---

## 7. 执行顺序建议

| 阶段 | 动作 | 内容 |
|------|------|------|
| **Phase 1** | `investigate` | 视频元数据检测方法调研（ProjectionType、StereoLayout、封面提取） |
| **Phase 2** | `plan` | 综合 ExecPlan — 域模型重构 + UI 对齐 + 功能实现 |
| **Phase 3** | `execute` | Bug 修复（5.4）→ 域模型重构（三轴）→ UI 对齐 → 功能实现 |
| **Phase 4** | `review` | 代码审查 + 对抗审查 |
| **Phase 5** | `test` | QA + E2E + 全面扫描 |
| **Phase 6** | `fix` | 修复测试发现的问题 |

---

## 8. 架构约束（不可违反）

- 依赖方向向内：Adapters → UseCases → Domain
- PlaybackMode 决策权在 PlayerUI，不在 PlaybackCore
- PlaybackCore 只负责"能不能播、当前帧是什么、媒体属性是什么"
- 所有播放入口必须经过 PlaybackLaunchCoordinator
- 三轴模型的 ProjectionType 和 StereoLayout 属于 PlaybackCore Domain
- PlaybackMode 属于 PlayerUI（或 App 层级的导航状态）
- StereoLayout 的 3D 开关属于 PlayerUI 的用户偏好覆盖

---

## 9. 当前代码状态摘要

**需要重构的文件：**
- `ProjectionType.swift` — 拆分，移除 `stereoscopicSBS`/`stereoscopicOU`，新增 `equirectangular180`/`equirectangular360`
- `StereoMode.swift` → 重命名为 `StereoLayout.swift`，新增 `.mono`
- `MediaProfile.swift` — 新增 `stereoLayout` 字段和 `hasCoverArt` 字段
- `ProjectionDetection.swift` — 适配新的三轴检测逻辑
- `DecidePlaybackModeUseCase` 相关 — 适配新约束矩阵

**需要对齐的 UI 文件：**
- `PlayerControlsView.swift` — 按 player.html 重写菜单结构
- `VideoDetailView.swift` — 补返回按钮 + HDR 开关
- `ContentGridView.swift` / `VideoCardView.swift` — 缩略图加载
- `FileBrowsingViewModel.swift` — 数据源切换加载状态

**已知 Bug：**
- 播放时二级/三级菜单闪烁 + 不可交互（P0）— §5.4
- HDR 视频详情页无限加载卡死（P0）— §5.5
- 详情页首次加载元数据错误（P0）— §5.6
- 文件浏览性能差 + 远端加载动画不正确 + 下拉刷新跳变（P1）— §5.7
- 视频画布不跟随窗口缩放（P2）— §5.8
- 沉浸空间：入口不统一 + 窗口未消失 + 非独占 + 无法召唤控件（P0）— §5.9
- 播放控件未严格对齐 player.html（P0）— §5.10
- NLE 二级时间轴关闭动效突变（P1）— §5.11

---

## 更新日志

| 日期 | 变更 |
|------|------|
| 2026-04-06 | 初始版本。取代三份旧 brainstorms 文档。三轴正交模型确立。 |
| 2026-04-06 | 新增 §5.5-§5.11：HDR 详情页卡死、元数据预读缓存、文件浏览性能、窗口缩放、沉浸空间四项子问题、播放控件严格对齐、NLE 关闭动效。 |
