# Enchron Overnight 任务队列 — 三种播放路径完整实现

> 生成时间: 2026-04-02 (v2)
> 模式: Test-First 驱动 + 对抗性审查 + 全功能 E2E 验证
> 核心目标: 完成三种播放路径（窗口/沉浸影院/全景）的完整实现，消灭所有占位/空壳代码
> 前置成果: v1 overnight 已完成窗口模式 UI 重构、Liquid Glass 迁移、视频详情界面、基础功能补齐
> 终止条件: 见底部（全部机器可验证，不接受主观判断）

---

## Phase 0: 困住自己（Test-First 陷阱设计）

**这是 overnight 的第一个动作。在写任何功能代码之前，必须先完成本阶段全部任务。**
**本阶段的产出是一套会全部失败的测试。这些红色测试就是你的枷锁——它们不变绿，你不能标 DONE。**

### T0.1 — 全文档审计与功能清单提取
- [x] 读取 workspace-agents/product_philosophy.md
- [x] 读取 workspace-agents/Requirements.md（逐节、逐行）
- [x] 读取 workspace-agents/design_docs/ 全部 6 个文件
- [x] 读取 workspace-agents/contracts/ 全部文件
- [x] 读取 ARCHITECTURE.md
- [x] 读取 REGRESSION.md
- [x] 输出：**完整功能清单**（每个功能一行，标注：已实现/部分实现/未实现/占位）
- [x] 特别关注：沉浸影院模式、全景视频、3D 立体视频、投影类型路由、屏幕位置控制、环境切换

### T0.2 — API 调研（使用 context7 MCP）
- [x] RealityKit: 虚拟屏幕渲染方案（VideoMaterial vs ShaderGraphMaterial vs UnlitMaterial）
- [x] RealityKit: ModelEntity 平面 mesh 与曲面 mesh 的创建和动态切换
- [x] RealityKit: ImmersiveSpace 多环境加载与切换 API
- [x] RealityKit: Entity 位置/旋转/缩放的持久化与恢复
- [x] Metal: Stereo 3D SBS 左右帧分离 shader 实现方案
- [x] Metal: Stereo 3D OU 上下帧分离 shader 实现方案
- [x] Metal: 180° 半球纹理坐标裁剪方案
- [x] Metal: 鱼眼投影重映射算法（equidistant fisheye → equirectangular）
- [x] 调研结果写入当轮 EP，包含代码示例和 API 签名

### T0.3 — 综合测试计划设计
- [x] 为 T0.1 功能清单中每个功能设计对应测试
- [x] **单元测试**：domain logic、value objects、state machines、projection detection、mode routing
- [x] **结构测试**：UI 组件存在性、View body 中的绑定验证、Protocol 实现完整性
- [x] **E2E 测试路径**：为 /qa 技能设计完整的功能验证路径，覆盖三种播放模式的每一条操作路径
- [x] 测试数量要求：新增 ≥ 40 个测试用例
- [x] 每个测试必须在当前代码上 FAIL（证明功能未实现）
- [x] 将 E2E 测试路径写入文档，供 /qa 使用

### T0.4 — 对抗性审查（三阶段裁决）
- [x] **阶段 1 — Codex 挑战**：将完整功能清单 + 测试计划发给 codex（adversarial-review 模式），要求：
  - 找出测试覆盖的漏洞（哪些功能没有测试？）
  - 找出断言过于宽松的测试（会假性通过的）
  - 找出文档中描述但测试未覆盖的边缘情况
  - 检查是否有"占位测试"（永远通过的空断言）
- [x] **阶段 2 — Counter-Agent 反驳**：另一个 Agent 评估 codex 的每条挑战，推翻不合理的部分：
  - visionOS Simulator 确实无法测试的功能（如真实手势）不算漏洞
  - 超出 MVP v1.0 范围的功能不强制要求
  - 但沉浸空间、全景视频、3D 立体相关挑战必须认真对待
- [x] **阶段 3 — Opus 裁决**：Supervisor 根据 Requirements.md + 调研结果做最终裁决
  - 裁决结果写入 EP 的 Decision Log
  - 采纳的挑战 → 补充测试
  - 驳回的挑战 → 记录理由

### T0.5 — 测试代码落地
- [x] 将裁决后的测试计划转为 Swift 测试代码
- [x] 放入 Tests/XrPlayerCoreTests/ 目录
- [x] `swift test` 执行，确认：
  - 新增测试 ≥ 40
  - 旧 205 个测试仍然全部 PASS
  - 新增测试全部 FAIL（证明功能未实现）
- [x] git commit 测试代码（此时功能代码尚未写）

---

## Phase 1: 功能实现（让红色测试逐个变绿）

**每完成一个子任务，运行 `swift test` 确认对应测试变绿。不变绿不 commit。**

### T1.1 — 沉浸影院模式：虚拟屏幕实体
- [ ] 创建 VirtualScreenEntity（ModelEntity 子类或组合）
- [ ] 平面屏幕 mesh（plane geometry，尺寸可配置）
- [ ] 曲面屏幕 mesh（curved geometry，曲率可配置）
- [ ] 平面/曲面切换逻辑（运行时切换 mesh，不重建 Entity）
- [ ] Settings 中新增屏幕形状选择（Flat / Curved）
- [ ] Metal 纹理桥接复用：CVPixelBuffer → TextureResource → Material（与全景管线共用）
- [ ] `swift test` 对应测试变绿

### T1.2 — 沉浸影院模式：屏幕位置控制
- [x] 远近距离调节（2m ~ 20m 连续，Slider）
- [x] 垂直高度调节（Slider）
- [x] X 轴旋转调节（±45°，Slider）
- [x] ScreenPositionStoring Protocol 实现（SwiftData/UserDefaults 持久化）
- [x] 每个环境独立的位置记忆（SavedScreenPosition + EnvironmentIdentifier 键）
- [x] 位置恢复：切换环境时自动加载该环境的记忆位置
- [x] `swift test` 对应测试变绿

### T1.3 — 3 个沉浸式环境
- [x] 环境 1: 暗黑影院（纯黑 Skybox + 虚拟屏幕，最简环境）
- [x] 环境 2: 星空夜景（星空 Skybox/程序化生成 + 虚拟屏幕）
- [x] 环境 3: 自然日落（暖色调 Skybox + 柔和环境光 + 虚拟屏幕）
- [x] SceneSelectorView 功能化：每个按钮对应一个真实环境，切换时实际加载
- [x] 播放中环境切换：不中断播放，平滑过渡
- [x] 环境切换后自动恢复该环境的屏幕位置记忆
- [ ] `swift test` + Simulator 可加载验证

### T1.4 — 全景视频完善
- [x] 180° 半球裁剪：纹理坐标限制前半球，背面不渲染
- [x] Stereo 3D SBS 渲染：Metal shader 将宽帧左右分离 → 双眼各投射一半
- [x] Stereo 3D OU 渲染：Metal shader 将高帧上下分离 → 双眼各投射一半
- [ ] 鱼眼投影重映射：equidistant fisheye → equirectangular 变换
- [x] 投影类型手动覆盖 UI：PlayerControlsView 中新增 Picker，允许用户覆盖自动检测结果
- [x] `swift test` 对应测试变绿

### T1.5 — 播放模式自动路由
- [x] MediaProfile 统一结构（HDR 类型 + 投影类型 + 立体格式）
- [x] PlaybackMode 决策矩阵：投影类型 × 沉浸状态 → 自动选择模式
  - flat + 非沉浸 → 窗口模式
  - flat + 沉浸 → 沉浸影院模式
  - panorama360/180/fisheye → 全景模式（自动进入沉浸空间）
  - stereoscopic + 非沉浸 → 窗口模式（SBS/OU 渲染）
  - stereoscopic + 沉浸 → 沉浸影院模式（SBS/OU 虚拟屏幕渲染）
- [ ] 模式切换 UI：允许用户手动覆盖自动决策
- [ ] 模式间切换不需要退出重进（graceful transition）
- [x] `swift test` 决策矩阵全部测试变绿

### T1.6 — 占位代码清除
- [ ] 审计所有 UI 组件：每个按钮、每个 Picker、每个 Toggle 都必须有真实功能
- [ ] SceneSelectorView 的 4 个按钮 → 3 个真实环境 + 布局调整
- [ ] 消灭所有 `// TODO`、`// PLACEHOLDER`、`fatalError("Not implemented")` 
- [ ] 消灭所有 `.disabled(true)` 占位按钮

---

## Phase 2: 全面测试（最重要阶段，不可压缩）

### T2.1 — swift test 全绿
- [ ] `swift test` 全部通过
- [ ] 总测试数 ≥ 245（205 旧 + ≥ 40 新）
- [ ] 零 FAIL、零 SKIP

### T2.2 — /qa E2E 端到端测试
- [ ] 使用 /qa skill 在 Apple Vision Pro Simulator 上执行
- [ ] 三种播放模式全部验证：
  - 窗口模式：SDR/HDR10/DV 视频播放、控件交互、音轨字幕切换
  - 沉浸影院模式：虚拟屏幕渲染、平面/曲面切换、位置调节、3 个环境切换
  - 全景模式：360° 球体、180° 半球、投影类型切换
- [ ] 每个 UI 按钮功能验证（无空按钮/无占位）
- [ ] 播放模式自动路由验证（不同视频类型 → 正确模式）
- [ ] Health Score ≥ 90

### T2.3 — 回归测试
- [ ] REGRESSION.md 新增所有空间/全景回归项
- [ ] 现有回归项无退化
- [ ] 代码路径映射索引更新

### T2.4 — 对抗性结果审查
- [ ] codex 审查最终实现代码（adversarial-review）
- [ ] 对照 Requirements.md 2.3 节逐条核实三种播放模式
- [ ] 对照 MVP 范围速查表（4 节）逐条核实
- [ ] 发现的问题修复后重新验证

---

## 人类已确认的设计决策（不可推翻）

1. **虚拟屏幕形状**: 平面 + 曲面，运行时可切换。渲染管线保持一致（仅 mesh 不同）
2. **沉浸式环境数量**: 3 个（暗黑影院、星空夜景、自然日落），用于验证切换功能
3. **API 调研工具**: 使用 context7 MCP 调研 Apple 框架文档，不使用离线 DocSet
4. **测试优先级**: 计划和测试计划是重中之重 > 执行 > 测试验证（更重要）
5. **文档可修改**: 如果调研发现文档描述不合理，可以修改文档（记录在 Decision Log 中）

---

## 终止条件（必须 13/13 全部满足才可标 DONE）

- [ ] `swift test` 全部通过，总测试数 ≥ 245（其中 ≥ 40 为新增空间/全景测试）
- [ ] `swift build` 零 error
- [ ] /qa Health Score ≥ 90，覆盖窗口/沉浸影院/全景三种播放模式
- [ ] 虚拟屏幕实体可创建、可渲染（平面 + 曲面，Settings 中可切换）
- [ ] 3 个沉浸式环境可加载且可切换（SceneSelectorView 功能化，非占位）
- [ ] 屏幕位置调节可用（距离/高度/旋转），且每个环境有独立记忆
- [ ] 180° 半球裁剪正确（纹理坐标限制前半球）
- [ ] Stereo 3D SBS + OU 渲染管线实现（Metal shader 帧分离）
- [ ] 鱼眼投影重映射实现
- [ ] 投影类型手动覆盖 UI 可用（Picker 在 PlayerControlsView 中）
- [ ] 播放模式自动路由正确（投影类型 × 沉浸状态 → 模式决策矩阵全覆盖）
- [ ] 零占位按钮（每个 UI 交互元素都有真实功能对应）
- [ ] REGRESSION.md 已更新所有空间/全景回归项
