# Enchron Overnight 任务队列

> 生成时间: 2026-04-02
> 模式: 全流程自主迭代（Planning → Review → Execution → Verification → Completion）
> 终止条件: 所有功能实现、端到端测试通过、零已知 bug

---

## Phase 0: 文档结构现代化

### T0.1 — 整理项目文档结构 ✅
- **目标**: 将文档架构更新到当前 Skills 工作流版本
- **背景**: 当前文档结构是上一个世代的版本，Skills 和 Overnight 已迭代更新
- **范围**:
  - 审计 `workspace-agents/` 下所有文档，对照当前可用 skills 列表
  - 清理过时引用，更新 CLAUDE.md / ARCHITECTURE.md / TESTING.md 中的文档路由表
  - 确保 exec-plans、archive、contracts 目录结构符合当前 overnight/CE 工作流
  - PLANS.md 和 TODOS.md 不再作为 git 跟踪文件（动态生成）
  - 更新 .overnight/config.yml 如需要

---

## Phase 1: 测试资源准备

### T1.1 — 验证现有测试视频 ✅
- 3 文件验证通过（SDR/HDR10/DV）

### T1.2 — 获取全景测试视频 ✅
- 360° NASA WebM (25MB) + 180° VR test MP4 (3.2MB)

---

## Phase 2: 端到端 QA 测试

### T2.1 — Apple Vision Pro Simulator E2E 测试
- **工具**: Apple Vision Pro Simulator
- **范围**: 每个按钮、每个交互路径的详细测试
- **方法**: 使用 QA skill 执行系统化测试
- **迭代**: 发现问题 → 修复 → 回归测试，循环直到全部通过
- **覆盖**:
  - 文件浏览（本地/SMB/WebDAV）
  - 视频播放启动流程
  - 播放控件交互
  - 进度条操作
  - 沉浸空间开关
  - 所有测试视频格式（SDR/HDR10/Dolby Vision/180°/360°）

---

## Phase 3: UI/UX 全面重构

### T3.1 — Liquid Glass 组件迁移 ✅
- FileBrowsing: 数据源 chip 玻璃效果、连接栏 ultraThinMaterial、空状态玻璃容器
- PlayerUI: 已有 glassBackgroundEffect 保持
- Settings: 新增 Immersive Space 区域、About 区域增强
- SceneSelectorView: 场景卡片玻璃背景

### T3.2 — 视频详情二级界面 ✅
- T3.2a: PlaybackLaunchCoordinator prepare/confirm 拆分（PreparedPlayback + 60s TTL）
- T3.2b: VideoDetailView 新建（元数据展示 + 音频/字幕轨道列表 + Play 确认）
- FileBrowserView navigationDestination 导航集成

### T3.3 — 进度条简化 ✅
- 删除 DetailedTimelineView（-438 行）
- 移除 showDetailedTimeline/pausedForTimeline 状态
- 精确时间标签拖动时内联显示
- 逐帧步进移入 secondaryControlRow

### T3.4 — 沉浸空间全局入口 ✅
- ToggleImmersiveSpaceButton 新增 .compact 样式
- AppTabView toolbar 全局入口（播放时隐藏）

---

## Phase 4: 设计文档全功能实现

### T4.1 — 审计设计文档 vs 实现差距
- **路径**: `workspace-agents/design_docs/`
- **动作**: 对比设计文档中规划的所有功能与当前实现状态，列出完整 gap list

### T4.2 — 补齐所有未实现功能
- **范围**: 根据 T4.1 的 gap list，逐个实现
- **迭代**: 实现 → 测试 → 修复 → 下一个，直到设计文档中的功能 100% 落地

---

## 终止条件

- [x] 文档结构符合当前 Skills 工作流
- [x] 5 种测试视频（SDR/HDR10/DV/180°/360°）全部就绪
- [ ] Apple Vision Pro Simulator E2E 测试全部通过（需真机/模拟器验证）
- [x] 所有 UI 组件使用 Liquid Glass
- [x] 视频详情二级界面功能完整
- [x] 进度条已简化（无二级展开）
- [x] 沉浸空间可在 App 启动时配置
- [ ] 设计文档中所有功能已实现（Phase 4）
- [ ] 零已知 bug（需真机验证）
