# Enchron Overnight 任务队列 — 全覆盖 QA 驱动迭代 (v3)

> 生成时间: 2026-04-02 (v3)
> 模式: QA-Plan-First + 对抗性验证 + HelloWorld 参考审计
> 核心目标: 设计并执行覆盖所有用户可感知场景的 E2E QA 计划，然后修复发现的缺陷
> 前置成果: v2 overnight 完成了三种播放路径的代码实现（248 tests, QA 97.75），但 QA 覆盖面不足
> 关键缺陷: 上两轮 QA 是"代码通过测试"而非"用户觉得好用"，大量人类重要场景被跳过
> 终止条件: 见底部（全部机器可验证）

---

## Phase 0: 全覆盖 QA 计划设计（最重要阶段）

**这是 overnight 的第一个动作。在修复任何代码之前，必须先完成本阶段。**
**本阶段产出一份覆盖每一个用户可感知功能的 QA 测试计划。**

### T0.1 — 功能全清单提取（从用户视角）
- [ ] 逐行读取 Requirements.md 2.1-2.5 每一节
- [ ] 读取 product_philosophy.md 的体验愿景
- [ ] 读取 workspace-agents/design_docs/ 全部文件
- [ ] 提取每一个**用户可感知的功能**（不是代码路径，而是"用户能看到/触摸到/感受到的东西"）
- [ ] 分类标注：
  - 🟢 已实现且已验证
  - 🟡 已实现但未在设备/模拟器上验证
  - 🔴 未实现或缺测试素材
  - ⚪ MVP 外推迟
- [ ] 特别关注 Requirements.md 中以下被忽略的领域：
  - 2.3 空间手势（单次捏合/双击/长按/拖拽）的 200ms 消歧机制
  - 2.3 播放模式自动切换的用户体验（不只是代码逻辑）
  - 2.4 网络异常的用户可见行为（转圈/错误框/后台重连）
  - 2.4 播放记忆恢复弹窗的实际交互
  - 2.4 播放结束行为（停留最后帧/重播图标/自动下一集）
  - 2.4 缓存清理策略的用户可见效果
  - 2.1 所有宣称支持的视频格式是否有测试素材

### T0.2 — HelloWorld 参考审计
- [x] 读取 /Users/xiongzhipeng/Movies/HelloWorld 的关键文件：
  - WorldApp.swift（Scene 定义、ImmersiveSpace 设置）
  - ViewModel.swift（Observable 状态管理）
  - Modules/（NavigationStack、Card UI、Detail View 布局）
  - Globe/GlobeControls.swift（Glass 控制面板）
  - Settings/SliderGridRow.swift（Settings UI 模式）
  - Modifiers/（手势 Modifier、动画）
  - Solar System/SolarSystemControls.swift（控制面板 + 翻页）
- [x] 对照 Enchron 当前实现，逐项对比以下 UX 模式：
  - NavigationStack 路径路由 vs Enchron 的导航方式
  - Glass Background Effect 使用方式
  - Detail View 分栏布局（文字左 + 交互预览右）
  - Control Panel ornament 锚定到场景边缘
  - Slider Grid 布局（标签 + 滑条 + 数值显示）
  - 手势 Modifier 的 spring 动画
  - ImmersiveSpace 开关的 Toggle + environment 变量模式
- [x] 输出：Enchron 应采纳的 UX 改进清单（标注优先级和具体改动位置）

### T0.3 — 测试素材清单与获取
- [ ] 盘点现有测试视频：/Users/xiongzhipeng/Movies/
- [ ] 标注缺失并获取（下载公开测试素材或 ffmpeg 转制）：
  - SBS 立体 3D 视频（必须获取）
  - OU 立体 3D 视频（必须获取）
  - 鱼眼投影视频（必须获取）
  - MOV 容器格式样本（必须获取）
  - AVI 容器格式样本（必须获取）
  - HLG 色彩空间样本（应获取）
  - HDR10+ 样本（应获取）
- [ ] 每个素材用 ffprobe 验证元数据正确
- [ ] 所有素材放入 /Users/xiongzhipeng/Movies/

### T0.4 — E2E QA 测试路径设计
- [ ] 为 T0.1 清单中每个 🟡/🔴 项设计端到端测试路径
- [ ] 路径模拟**真实用户操作序列**（不是代码调用）：
  - 启动 App → 浏览文件 → 选择视频 → 查看详情 → 播放 → 控件交互 → 返回
- [ ] 路径覆盖要求（至少）：
  - 窗口模式：SDR/HDR10/DV 各一条完整路径
  - 沉浸影院模式：进入/屏幕调节/环境切换/平面曲面切换 各一条
  - 全景模式：360°/180°/SBS/OU/鱼眼 各一条
  - 播放控件：倍速/音轨/字幕/进度条/快进快退 各一条
  - 错误处理：网络断开/恢复播放提示/播放结束行为 各一条
  - 手势：单捏合/双击/长按/拖拽（结构验证 + 代码路径确认）
  - 设置：所有 Settings 项的修改和持久化验证
  - 文件源：本地/SMB/WebDAV/Photo Library 各一条
- [ ] 每条路径包含**具体预期结果**（不接受"检查是否正常"）
- [ ] 写入 docs/qa-plans/qa-plan-v3-comprehensive.md

### T0.5 — 对抗性审查 QA 计划（三阶段裁决）
- [ ] **阶段 1 — Codex 挑战**：将 QA 计划 + 功能全清单发给 codex，要求找出：
  - 功能清单中有但 QA 路径未覆盖的功能
  - 验证步骤过于模糊的（"检查是否正常" 不可接受，必须有具体预期结果）
  - Requirements.md 中的边缘情况未覆盖的
  - 用户常见操作序列未覆盖的（播放中切换数据源、连续播放不同格式视频等）
- [ ] **阶段 2 — Counter-Agent 反驳**：
  - Simulator CLI 无法执行的操作 → 降级为代码路径 + 结构验证，但标注 "human-only"
  - 不可降级的：视频能否播放、UI 渲染是否正确、导航路径是否通畅
- [ ] **阶段 3 — Opus 裁决**：对照 Requirements.md 做最终决定
- [ ] 修订后的 QA 计划更新到 docs/qa-plans/

### T0.6 — 验证所有功能是否真正实现
- [ ] 对照 T0.1 功能全清单，逐项检查代码（不依赖测试结果，直接审查代码）：
  - 功能入口是否可达（UI 按钮存在且不是 disabled）
  - 核心逻辑是否完整（不是 stub/TODO/fatalError）
  - 数据流是否通畅（UI → UseCase → Domain → 持久化 全链路）
- [ ] 发现"名义上实现但断联"的功能 → 标记为 Phase 2 修复项

---

## Phase 1: QA 执行

### T1.1 — 执行全覆盖 /qa E2E 测试
- [ ] 按 T0.4 的 QA 计划，使用 /qa skill 逐条执行
- [ ] 每条路径记录：PASS / FAIL / PARTIAL / BLOCKED（附具体原因和证据）
- [ ] FAIL/PARTIAL 项自动生成修复任务清单
- [ ] 生成 QA 报告到 docs/qa-reports/qa-report-v3-comprehensive.md

### T1.2 — HelloWorld 对照验证
- [ ] 按 T0.2 的 UX 改进清单，逐项检查 Enchron 需改进的程度
- [ ] 标注：已符合 / 需改进（附改进方案）/ 不适用（附理由）

---

## Phase 2: 缺陷修复与 UX 改进

### T2.1 — 修复 QA 发现的功能缺陷
- [ ] 按优先级修复 T1.1 中 FAIL 项（P0 先于 P1 先于 P2）
- [ ] 每修复一项，运行对应 QA 路径确认 PASS
- [ ] `swift test` 保持全绿

### T2.2 — HelloWorld 启发的 UX 改进
- [ ] 按改进清单实施，优先级：
  1. ImmersiveSpace 管理模式（Toggle + environment 变量，参考 HelloWorld 的 OrbitToggle/SolarSystemToggle）
  2. Detail View 布局优化（分栏 + 响应式 GeometryReader，参考 ModuleDetail）
  3. Control Panel 样式（Glass + ornament 锚定，参考 GlobeControls）
  4. Settings Slider 布局（Grid: 标签 + 滑条 + 数值，参考 SliderGridRow）
  5. 动画与过渡（spring 动画、opacity 协调，参考 DragRotationModifier）
- [ ] 每项改动后验证不破坏现有功能

### T2.3 — 测试素材播放验证
- [ ] 用所有测试素材执行播放测试（每种格式至少播放一次）
- [ ] 验证投影类型自动检测正确性
- [ ] 验证渲染管线输出正确性

---

## Phase 3: 回归验证

### T3.1 — 全面回归
- [ ] `swift test` 全绿
- [ ] /qa 用完整 QA 计划重新执行（T0.4 的全部路径）
- [ ] Health Score ≥ 95
- [ ] REGRESSION.md 更新

### T3.2 — 对抗性最终审查
- [ ] codex 审查所有修复和改进代码
- [ ] 对照 Requirements.md 逐条核实
- [ ] 对照 HelloWorld 参考模式核实 UX 改进效果

---

## 人类已确认的设计决策

1. **QA 计划是第一优先级** — 在修复任何代码之前，必须先有覆盖全部用户场景的 QA 计划
2. **HelloWorld 必须实际参考** — 不能只在文档里提一句，要真正读代码、对比、学习
3. **测试素材必须齐全** — 每种宣称支持的格式都要有可播放的测试文件
4. **结构验证 ≠ 用户验证** — "代码路径正确"不等于"用户体验正常"
5. **QA 计划也要对抗性审查** — 确保计划本身没有遗漏

---

## 终止条件（必须 12/12 全部满足才可标 DONE）

- [ ] 全覆盖 QA 计划已设计并通过对抗性审查（docs/qa-plans/ 存在且经审查）
- [ ] 测试素材覆盖所有宣称支持的格式（SDR/HDR10/DV/HLG/180°/360°/SBS/OU/鱼眼/MKV/MP4/MOV/AVI）
- [ ] /qa E2E 测试覆盖所有三种播放模式的完整用户操作路径
- [ ] /qa Health Score ≥ 95
- [ ] 每个 QA FAIL 项已修复并重新验证
- [ ] HelloWorld 参考审计完成，改进项已实施或标注理由
- [ ] `swift test` 全绿（≥ 248 tests, 0 FAIL）
- [ ] `swift build` 零 error
- [ ] 零占位按钮、零断联功能、零 stub 代码
- [ ] REGRESSION.md 已更新
- [ ] 对抗性最终审查通过
- [ ] 所有"降级为结构验证"的项明确标注 "human-only verification required"
