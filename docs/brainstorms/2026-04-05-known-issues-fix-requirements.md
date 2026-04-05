---
date: 2026-04-05
topic: known-issues-fix
---

# Known Issues Fix — 需求文档

## 问题框架

Enchron UI/UX 重构（QA Round 2）暴露了 6 个未解决的 UI 问题，涵盖三个层级：一级浏览页、二级详情页、三级播放页。核心问题是 Agent 实现偏离了 HTML 设计稿的布局规范，同时部分 visionOS 平台 API 行为与预期不符。本次修复以 HTML 设计稿为唯一视觉权威，技术调查已完成，目标是逐一对齐。

## 需求

**布局对齐（P0）**

- R1. 播放页控件栏严格按 `player.html` 的 footer 布局实现：药丸形 glass 容器（`border-radius: 9999px`），内部按钮从左到右为 Menu → 后退10s → 播放/暂停 → 前进10s → Settings → NLE切换 → PiP，间距、尺寸与设计稿一致
- R2. Menu 按钮的弹出菜单向左展开（`bottom-full`），包含字幕、音轨、播放倍速三个子菜单（点击展开，非 hover）
- R3. Settings 按钮的弹出菜单向右展开，包含播放模式、环境两个子菜单
- R4. 一级浏览页和二级详情页的布局与 `variant-AB-combined.html` 对齐（导航、卡片网格、详情面板）
- R5. Seek bar 位于控制栏上方，含时间标签（左当前/右剩余），进度条样式与设计稿一致

**Hover 形状修复（P1）**

- R6. 所有控件按钮的 hover effect 形状必须匹配按钮本身的视觉形状：圆形按钮显示圆形 hover，圆角矩形按钮显示圆角矩形 hover
- R7. 技术方案：将 `.hoverEffect(.highlight)` 替换为 `.hoverEffect(.lift)`，后者在 visionOS 上正确遵守 `contentShape` 定义

**控件显隐动画（P1）**

- R8. 播放控件的出现/消失必须是纯 opacity 渐显/渐隐（0.4s ease-in-out），不允许任何位移、缩放动画
- R9. 如果 `.ornament()` 的内置 transition 导致位移，需在 ornament 层级禁用默认动画或调整 animation context
- R10. 所有修改 `showControls` 的 call site 必须用 `withAnimation(.easeInOut(duration: 0.4))` 包裹

**播放模式层级约束（P1）**

- R11. 播放模式基于视频内容类型实施层级约束：2D → 仅窗口；3D → 窗口+沉浸；全景 → 窗口+沉浸+全景。不允许从低层级升级到高层级
- R12. `PlayerControlsView` 的模式菜单仅显示当前视频允许的模式，禁用/隐藏不可用模式
- R13. `DecidePlaybackModeUseCase` 的手动覆盖必须验证目标模式是否在允许范围内，不允许无验证直通
- R14. 模式约束逻辑位于 PlayerUI 内（遵守 Architecture Invariants），事实来源于 PlaybackCore 的 `ProjectionType`

**视频画布缩放（P2）**

- R15. 拖拽 visionOS 窗口边缘缩放时，视频画布尺寸必须同步更新
- R16. 技术方案：用 GeometryReader 包裹 WindowVideoView，将 geometry.size 传入以触发 `updateUIView`
- R17. 保留 MoltenVK 1×1 workaround（它不是根因），确保合法 resize 不被过滤

**按钮可交互性（P0 补充）**

- R21. 三级页面（播放页）所有控件按钮必须可交互：可点击、可聚焦、触发正确动作。如果当前"不可选"是因为 hit testing、状态绑定或视图层级遮挡，需在 PLANNING 阶段诊断根因
- R22. 二级页面（详情页）相关按钮的可交互性需逐一验证，不可选按钮需明确原因（功能未实现 vs bug）

**NLE 时间轴（P2）**

- R18. NLE 时间轴面板需要 glass 背景（参考 `player.html` 的 `.timeline-panel`：`rgba(14,14,14,0.85)` + blur 40px）
- R19. 按钮不应溢出面板边界，内容需在容器内正确裁剪
- R20. 拖动逻辑按设计稿行为：ruler 区域可拖动，track area 可拖动，固定 playhead 在中心

## 成功标准

- 播放页控件栏的按钮排列、弹出菜单方向、尺寸间距与 player.html 视觉一致
- 三级页面所有控件按钮可交互，二级页面按钮可交互性已诊断
- 所有按钮的 hover effect 形状匹配其视觉形状
- 控件显隐为纯 opacity fade，无位移
- 2D 视频不能切换到沉浸/全景模式
- 窗口缩放时视频画布跟随
- NLE 时间轴面板有 glass 背景，无溢出

## 范围边界

- 不重构架构，仅在现有模块内修复
- 不新增 Domain 层实体
- 不修改 PlaybackCore 内部逻辑
- 不涉及沉浸场景渲染改动
- P0 的一级/二级页面布局对齐如果改动范围过大（>10 文件），应拆分为独立 PR
- NLE 时间轴的缩放手势（pinch to zoom）如实现复杂度过高，推迟到后续迭代

## 关键决策

- **Hover effect 使用 `.lift` 而非 `.highlight`**：因为 `.highlight` 在 visionOS 上忽略自定义 `contentShape`，强制圆形高亮
- **GeometryReader 方案用于画布缩放**：因为 `updateUIView` 不会自动因窗口几何变化触发
- **模式约束逻辑放在 PlayerUI**：遵守 ARCHITECTURE.md「PlayerUI 具备播放模式决策入口」的 Invariant
- **HTML 设计稿是视觉权威**：Agent 不可自由调整布局，必须严格对齐设计稿

## 依赖 / 假设

- HTML 设计稿（`docs/designs/file-browser-redesign-2026-04-05/`）准确反映产品期望
- PlaybackCore 的 `ProjectionType` 已正确检测视频投影类型
- `AppModel.playbackMode` 作为播放模式的单一事实源不变

## 待解问题

### 推迟到规划阶段

- [影响 R9][需要调研] ornament 默认 transition 的精确行为需在模拟器中验证；如果当前代码已生效，R9 可跳过
- [影响 R16][技术性] GeometryReader 包裹 WindowVideoView 后，mpv 的 `vo-configured` 事件是否需要额外处理
- [影响 R4][需要调研] 一级/二级页面的具体偏差需对比截图与 HTML 设计稿逐项列出

## 下一步

→ /ce:plan 进行结构化实施规划
