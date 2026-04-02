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

### T2.1 — Apple Vision Pro Simulator E2E 测试（必须完成，不可跳过）
- **工具**: Apple Vision Pro Simulator（不是真机，就是 Simulator）
- **强制要求**: 这不是"待真机验证"，这是 overnight 必须自主完成的任务
- **方法**: 使用 /qa skill + xcodebuild + simctl 在 Simulator 上执行系统化测试
- **迭代**: 发现问题 → 修复 → 回归测试，循环直到全部通过
- **测试文件**: 使用 /Users/xiongzhipeng/Movies/ 下的 5 个测试视频文件
- **覆盖**:
  - 文件浏览（本地/SMB/WebDAV）
  - 视频播放启动流程（包括新的视频详情二级界面）
  - 播放控件交互
  - 统一进度条操作
  - 沉浸空间开关（全局入口 + 播放内）
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

### T4.1 — 审计设计文档 vs 实现差距 ✅
- 完整 gap 分析：5 类 19 项差距（详见 docs/ExecPlan/ExecPlan003.md）
- A 类：文档过时 6 项 → 全部修复
- B 类：Settings 断连 3 项 → B1 已修复，B2/B3 待人类决策
- C 类：UI 功能缺口 5 项 → C1 已修复，C2-C5 待人类决策
- D 类：播放速度缺失 1 项 → 已修复
- E 类：未实现功能 4 项 → 待人类决策

### T4.2 — 补齐所有未实现功能（必须全部完成）
- **已完成**: 文档更新 6 项 + Settings 持久化 + 播放速度 10 档 + 文件排序 UI
- **Round 8 完成**:
  - [x] B2: 播放结束行为设置（Stop / Repeat / Play Next）
  - [x] B3: 默认倍速设置（10 档 Picker）
  - [x] C2: 恢复播放提示 UX（VideoDetailView 双按钮 Resume/Start Over，遵循 ResumePolicy）
  - [x] C3: 文件列表进度指示（橙色圆点 + Watched X:XX）
  - [x] E2: 播放结束后自动下一集（handlePlaybackEnded + nextFileProvider）
- **剩余待实现**:
  - C4: 屏幕位置控件（自主设计，实现）
  - C5: X 轴旋转控件
  - E1: Photo Library 源
  - E3: 缓存清理策略（5天过期）
  - E4: 网络中断重连机制
- **原则**: 遇到 UX 决策时自主判断，参考 Apple HIG 和 visionOS 设计规范，不要等人类

---

## 终止条件

- [x] 文档结构符合当前 Skills 工作流
- [x] 5 种测试视频（SDR/HDR10/DV/180°/360°）全部就绪
- [ ] Apple Vision Pro Simulator E2E 测试全部通过（在 Simulator 上完成，不等真机）
- [x] 所有 UI 组件使用 Liquid Glass
- [x] 视频详情二级界面功能完整
- [x] 进度条已简化（无二级展开）
- [x] 沉浸空间可在 App 启动时配置
- [ ] 设计文档所有功能已实现（B2/B3/C2-C5/E1-E4 全部完成）
- [ ] 零已知 bug（Simulator 验证通过）
