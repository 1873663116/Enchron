# ExecPlan010 — T0.1 全文档审计与功能清单提取

> Round: 1
> Phase: PLANNING
> 日期: 2026-04-02
> 目标: 完成 TODOS.md T0.1 全部子任务，输出完整功能清单

## 审计范围

| 文档组 | 文件 | 审计 Agent |
|--------|------|-----------|
| 产品哲学 + 需求 | product_philosophy.md, Requirements.md | doc-audit-requirements |
| 设计文档 | design_docs/ (8 files + reference/) | doc-audit-design |
| 契约 + 回归 | contracts/, REGRESSION.md | doc-audit-contracts |
| 代码实现 | XrPlayer/ (5 modules) | code-audit |

审计结果：Requirements 提取 89 个功能点，design_docs 提取 14 个 protocol 签名 + 完整领域模型，REGRESSION.md 34 条活跃回归项，代码审计覆盖 SpatialScene/PlayerUI/PlaybackCore/Persistence/Settings 全模块。

---

## 完整功能清单（本轮 overnight 范围内）

聚焦三种播放路径相关功能。按实现状态标注：
- ✅ 已实现（代码审计确认功能完整可用）
- 🔶 部分实现（框架或 UI 存在，但核心逻辑缺失或未接入）
- ❌ 未实现（代码中无任何实现）
- 🔲 占位/空壳（UI 元素存在但 action 为空或仅更新本地 state）

---

### A. 沉浸影院模式（SpatialScene + PlayerUI + Persistence）

| # | 功能 | 状态 | 代码依据 | 来源 |
|---|------|------|---------|------|
| A1 | VirtualScreenEntity 创建与渲染 | ❌ | ImmersiveSpaceView.swift:22 注释 "Future" | Req 2.3, design phase2 |
| A2 | 平面屏幕 mesh（plane geometry） | ❌ | 无任何 plane mesh 代码 | Req 2.3, 人类锁定决策 |
| A3 | 曲面屏幕 mesh（curved geometry） | ❌ | 无任何 curved mesh 代码 | Req 2.3, 人类锁定决策 |
| A4 | 平面/曲面运行时切换（替换 MeshResource） | ❌ | 无切换逻辑 | 人类锁定决策 |
| A5 | Metal 纹理桥接：CVPixelBuffer → TextureResource → Material | 🔶 | CVPixelBuffer+MTLTexture 存在，PanoramaLayerBridge blit 存在，但未用于虚拟屏幕 | Req 2.3, design phase1 |
| A6 | Settings 屏幕形状选择（Flat/Curved） | ❌ | SettingsView 无此选项 | 人类锁定决策 |
| A7 | 屏幕距离调节 Slider（2m~20m） | 🔶 | ScreenPositionControlView UI 完整，AppModel 有字段，但无 3D Entity 消费 | Req 2.3 |
| A8 | 屏幕垂直高度调节 Slider | 🔶 | 同 A7 | Req 2.3 |
| A9 | 屏幕 X 轴旋转调节 | 🔶 | 同 A7 | Req 2.3 |
| A10 | ScreenPositionStoring 持久化 | ✅ | SwiftDataStore 实现 savePosition/loadPosition | design phase3 |
| A11 | 每环境独立位置记忆 | 🔶 | 接口支持 environmentID，但调用方硬编码 "virtual-screen" | Req 2.3, design phase2 |
| A12 | 环境 1: 暗黑影院（纯黑 Skybox） | ❌ | 无任何环境资产 | Req 2.3, 人类锁定决策 |
| A13 | 环境 2: 星空夜景 | ❌ | 无任何环境资产 | Req 2.3, 人类锁定决策 |
| A14 | 环境 3: 自然日落 | ❌ | 无任何环境资产 | Req 2.3, 人类锁定决策 |
| A15 | SceneSelectorView 功能化 | 🔲 | ForEach(0..<4) 占位，action 只更新 @State | Req 2.2 |
| A16 | 播放中环境切换（不中断播放） | ❌ | AppModel 无 currentEnvironmentID，ImmersiveSpaceView 无切换逻辑 | Req 2.3 |
| A17 | 环境切换后恢复屏幕位置记忆 | ❌ | 依赖 A11 + A16，均未完成 | Req 2.3 |

---

### B. 全景视频模式（SpatialScene + PlaybackCore）

| # | 功能 | 状态 | 代码依据 | 来源 |
|---|------|------|---------|------|
| B1 | 360° 全景球体渲染 | ✅ | PanoramaSphereEntity + PanoramaLayerBridge 完整 | Req 2.3, REG-070 |
| B2 | 180° 半球裁剪 | ❌ | PanoramaSphereEntity:41 注释 "future iteration" | Req 2.3, REG-071 |
| B3 | Stereo 3D SBS 帧分离 shader | ❌ | VideoShaders.metal 无左右裁剪 | Req 2.1/2.3 |
| B4 | Stereo 3D OU 帧分离 shader | ❌ | 同 B3 | Req 2.1/2.3 |
| B5 | 鱼眼投影重映射 shader | ❌ | 全项目无 fisheye shader | Req 2.1/2.3 |
| B6 | 投影类型自动检测 | ✅ | ProjectionDetection.swift 完整 | Req 2.1 |
| B7 | panorama180 检测（FOV 读取） | 🔶 | MPVPlayerAdapter:1193 TODO: horizontalFOVDegrees=nil | Req 2.3 |
| B8 | 投影类型手动覆盖 Picker | ❌ | PlayerControlsView 无此 Picker | Req 2.1/2.3 |

---

### C. 播放模式自动路由（PlayerUI + App）

| # | 功能 | 状态 | 代码依据 | 来源 |
|---|------|------|---------|------|
| C1 | MediaProfile 统一结构 | ✅ | MediaProfile.swift 含 projectionType + hdrType | design phase2 |
| C2 | ProjectionType 枚举（6 值） | ✅ | ProjectionType.swift: flat/SBS/OU/360/180/fisheye | design phase2 |
| C3 | PlaybackMode 决策矩阵 | 🔶 | AppCoordinator.decidePlaybackMode 存在但未接入主流程 | Req 2.3, design phase3 |
| C4 | 模式切换 UI（Menu） | ✅ | PlayerControlsView:383-452 playbackModeMenu + switchPlaybackMode | Req 2.3 |
| C5 | 模式间 graceful transition | 🔶 | switchPlaybackMode 有 immersive open/dismiss 逻辑，但虚拟屏幕不存在 | Req 2.3 |
| C6 | PlaybackModeManaging protocol | ❌ | design phase3 定义了但代码中未实现 | design phase3 |
| C7 | DecidePlaybackModeUseCase | ❌ | 未实现 | design phase3 |

---

### D. 窗口模式（已基本完成，需补测试覆盖）

| # | 功能 | 状态 | 代码依据 | 来源 |
|---|------|------|---------|------|
| D1 | 本地视频播放（窗口模式） | ✅ | MTKView 渲染管线完整 | REG-001 |
| D2 | 播放/暂停/seek/skip | ✅ | PlayerControlsView 完整 | REG-012/015/016 |
| D3 | 统一时间轴 + 精确时间标签 | ✅ | REG-080 验证通过 | Philosophy §3 |
| D4 | 逐帧步进 | ✅ | REG-081 验证通过 | Philosophy §3 |
| D5 | 音轨/字幕切换 | ✅ | REG-018 | Req 2.3 |
| D6 | HDR10/HLG/DV 识别与渲染 | ✅ | REG-060/061/062/063 | Req 2.5 |
| D7 | 倍速播放 | ✅ | 已实现 | Req 2.3 |
| D8 | 选集功能 | ✅ | REG-019 | Req 2.3 |
| D9 | 播放记忆弹窗 | ✅ | REG-088 | Req 2.4 |
| D10 | 视频详情页 | ✅ | REG-082/083 | v1 overnight 产出 |

---

### E. 占位代码清除（全局）

| # | 功能 | 状态 | 代码依据 |
|---|------|------|---------|
| E1 | SceneSelectorView 4 按钮 → 3 环境 | 🔲 | ForEach(0..<4) 全占位 |
| E2 | TODO: FOV computation (MPVPlayerAdapter:1193) | 🔶 | horizontalFOVDegrees: nil |
| E3 | WORKAROUND: DoVI → hdr10 fallback | ✅ | 合法 workaround，Apple 无公开 API |
| E4 | VideoToolboxBridge.makePixelBuffer placeholder | 🔲 | 主体实现仅 placeholder |

---

## 实现差距统计

| 状态 | A 沉浸 | B 全景 | C 路由 | D 窗口 | E 占位 | 合计 |
|------|--------|--------|--------|--------|--------|------|
| ✅ 已实现 | 1 | 2 | 2 | 10 | 1 | **16** |
| 🔶 部分 | 5 | 1 | 2 | 0 | 1 | **9** |
| ❌ 未实现 | 8 | 5 | 2 | 0 | 0 | **15** |
| 🔲 占位 | 1 | 0 | 0 | 0 | 1 | **2** |

**核心差距**：
1. **沉浸影院模式几乎全部缺失**（17 项中仅 1 项完全实现）— 虚拟屏幕实体、环境系统、位置驱动全未做
2. **全景视频只有 360° 可用**（8 项中 2 项完成）— 180°/SBS/OU/鱼眼均未实现
3. **播放模式路由断裂**（7 项中 2 项完成）— 决策矩阵存在但未接入，UseCase 未实现
4. **窗口模式已完整**（10/10）— 仅需补测试覆盖

---

## 回归风险矩阵（本轮改动影响）

| 改动区域 | 触发回归项 | 风险 |
|---------|-----------|------|
| SpatialScene Entity 创建 | REG-070, REG-071, REG-050 | 极高 |
| ImmersiveSpaceView 环境切换 | REG-084 | 高 |
| Metal shader 新增 | REG-060/061（HDR 管线共用） | 高 |
| PlayerUI 模式路由 | REG-040, REG-012 | 高 |
| AppModel 环境状态字段 | REG-031, REG-085 | 中 |
| PanoramaSphereEntity 修改 | REG-070, REG-071 | 极高 |

---

## Decision Log

- [AUTO] T0.1 审计方式 | 4 个 Sonnet subagent 并行 | P3+P6 | 文档量大，并行最高效
- [AUTO] 功能清单范围 | 聚焦三种播放路径 + 占位清除，FileBrowsing/Settings 通用功能不列入 | P3 | 本轮 overnight 范围在 TODOS.md 已界定
