---
date: 2026-04-05
topic: playback-mode-hierarchy
---

# 播放模式层级约束

## 问题框架

Enchron 有三种播放模式：窗口（window）、沉浸影院（immersive）、全景（panorama）。当前实现允许用户在播放任意视频时切换到任意模式，没有基于视频内容类型的约束。

这导致：
- 2D 视频切换到全景模式 → 平面画面被投射到球面上，严重变形
- 用户操作了一个几何上不兼容的选项，体验断裂

沉浸影院模式（虚拟屏幕 + 环境）对所有内容类型都合法 — 这是产品的核心差异化体验。约束的本质是**几何兼容性**：全景模式要求球面投影的内容，非全景内容在球面上会变形。

## 约束模型

| 内容类型 | ProjectionType 值 | 允许的播放模式 |
|---------|-------------------|--------------|
| 2D 平面视频 | `flat` | window, immersive |
| 3D 立体视频 | `stereoscopicSBS`, `stereoscopicOU` | window, immersive |
| 全景视频 | `panorama360`, `panorama180`, `fisheye` | window, immersive, panorama |

核心规则：**全景模式仅对全景内容开放。窗口和沉浸影院对所有内容开放。**

## 需求

**层级约束逻辑**

- R1. 系统根据当前视频的 `ProjectionType` 确定允许的播放模式集合：全景模式仅对 `isPanoramic` 内容开放，窗口和沉浸影院对所有内容开放
- R2. 手动模式切换必须受约束验证 — 不允许切换到当前视频不支持的模式
- R3. 自动路由（`DecidePlaybackModeUseCase`）的结果必须在允许模式集合内
- R3a. 约束执行点：`DecidePlaybackModeUseCase.decideMode()` 内部。手动覆盖在应用前必须经过 `allowedModes` 过滤，非法模式被 clamp 到允许集合中的最高模式

**UI 表现**

- R4. 播放控件的模式菜单只显示当前视频允许的模式选项（不显示不可用模式）
- R5. 当所有模式都可用时，菜单正常显示全部选项；当全景模式不可用时，只显示窗口和沉浸两个选项
- R6. 模式约束在视频切换时即时更新 — 切换到不同类型的视频后，可用模式立即反映新视频的能力

**降格行为**

- R7. 当用户从全景视频切换到非全景视频，且当前处于全景模式时，自动降格到沉浸模式（允许集合中的最高模式）
- R7a. 自动降格不得在 MediaProfile 检测进行中（`mediaProfile == nil`）时触发 — 系统保持当前模式，待检测完成后再应用约束
- R8. 降格应静默发生（自动切换），不需要用户手动操作。降格通过现有的 `AppModel.autoRoutePlaybackMode()` → `DecidePlaybackModeUseCase` 路径执行，不引入新的场景管理逻辑

**架构约束**

- R9. 层级约束逻辑放在 PlayerUI 层内（遵循 Architecture Invariant："PlayerUI 具备播放模式决策入口"）
- R10. 不改动 PlaybackCore 的检测逻辑、不改动 App 层的 scene 管理逻辑、不引入新的模块间依赖

## 成功标准

1. 播放 2D 或 3D 视频时，模式菜单显示"窗口"和"沉浸影院"（无"全景"）
2. 播放全景视频时，模式菜单显示全部三种模式
3. 播放 2D 视频时，可在窗口和沉浸影院之间自由切换
4. 从全景视频（当前在全景模式）切换到非全景视频 → 自动降格到沉浸模式
5. 在 profile 检测完成前，模式菜单保持当前状态不闪烁
6. REG-109（播放模式自动路由）保持通过
7. 已有控件功能不回归（时间轴、暂停/播放、音量等）

## 范围边界

- 不改动 PlaybackCore 的 ProjectionType 枚举或检测算法
- 不改动 AppModel 的 updatePlaybackMode() 接口签名
- 不改动 MainView 的 scene 切换协调逻辑
- 不涉及 SceneSelectorView 的环境选择（那是影院环境选择，不是播放模式）
- 不处理"检测错误"场景（如全景视频被误检测为 flat）— 那是 PlaybackCore 的责任

## 关键决策

- **隐藏 vs 禁用不可用模式**：选择隐藏（不显示）。理由：禁用按钮需要解释为什么不可用，增加 UI 复杂度；不显示更简洁，用户不会困惑"为什么这个按钮灰了"
- **约束归属**：逻辑放在 PlayerUI 的 `DecidePlaybackModeUseCase` 内。理由：这是业务规则（哪些模式允许），不是纯 UI 表现；且该 use case 已是模式决策的唯一入口
- **flat→immersive 保留**：沉浸影院（虚拟屏幕 + 环境）是产品核心体验，2D 视频在虚拟大屏上观看完全合法。约束只针对几何不兼容（flat→panorama），不限制空间增强（flat→immersive）
- **降格触发路径**：通过现有 `AppModel.autoRoutePlaybackMode()` → `DecidePlaybackModeUseCase` 路径，不新增场景管理逻辑。这满足 R10 的"不改动 App 层 scene 管理"约束

## 依赖 / 假设

- 假设 PlaybackCore 的 `ProjectionType` 检测准确 — 如果检测错误，约束也会错误，但那是上游问题
- 假设 `WindowVideoViewModel.displayMediaProfile` 在播放开始后可靠提供当前视频的 MediaProfile
- 假设 profile 检测期间（`mediaProfile == nil`），控件可见性由 `canPresentControls` gate 控制，因此正常首次播放不会出现无 profile 的模式菜单

## 待解问题

### 推迟到规划阶段

- [影响 R1][技术性] `allowedModes(for:)` 放在 `DecidePlaybackModeUseCase` 的扩展方法还是独立的 value object？

## 下一步

→ /ce:plan 进行结构化实施规划
