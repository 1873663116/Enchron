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

### T1.1 — 验证现有测试视频
- **路径**: `/Users/xiongzhipeng/Movies/`
- **已有文件**:
  - `dolby-vision-test.mp4` (Dolby Vision)
  - `HDR10-test.MP4` (HDR10)
  - `SDR-test.mkv` (SDR)
- **动作**: 验证文件完整性，确认可被 mpv 正常解码

### T1.2 — 获取全景测试视频
- **目标**: 下载 180° 和 360° 全景视频测试文件
- **要求**:
  - 文件尽量小（能测试即可，建议 < 100MB 每个）
  - 180° 半球全景视频 x1
  - 360° 全球全景视频 x1
  - 存放路径: `/Users/xiongzhipeng/Movies/`
  - 优先使用免费/CC 许可的测试素材

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

### T3.1 — Liquid Glass 组件迁移
- **目标**: 全部 UI 使用 Liquid Glass 组件
- **参考**: `/Users/xiongzhipeng/Movies/HelloWorld` 项目的动画和排版布局
- **技能**: 使用所有 Design 相关 skills（liquid-glass-design, visionos-design-guidelines, apple-hig, mobile-ios-design, frontend-design, design-consultation, design-review 等）
- **范围**:
  - FileBrowsing 文件浏览界面重新设计，做到"非常好"的浏览体验
  - PlayerUI 播放界面组件全部 Liquid Glass 化
  - Settings 设置界面
  - 所有弹窗、选择器、导航组件

### T3.2 — 视频详情二级界面（核心新功能）
- **目标**: 点击视频后不直接播放，而是进入视频详情界面
- **行为流程**:
  1. 用户点击视频文件
  2. 开始预热播放管线（PlaybackLaunchCoordinator 异步预加载）
  3. 同时展示视频详情二级界面（不是播放界面）
  4. 详情界面展示:
     - 视频完整信息（分辨率、编码、时长、文件大小、HDR 类型等）
     - 字幕轨道选择
     - 音频轨道选择
     - 播放模式配置（3D 模式 / 全景模式 / 沉浸空间模式 / 普通窗口模式）
  5. 用户确认后开始播放（管线已预热，启动近乎即时）
- **架构影响**: 需要先更新相关设计文档和接口契约，再实现
- **注意**: 此功能需要修改 PlaybackLaunchCoordinator 的启动流程

### T3.3 — 进度条简化
- **目标**: 取消二级进度条概念
- **行为**: 一级进度条直接作为详细进度条使用（原来的二级进度条功能合并到一级）
- **范围**: 删除 DetailedTimelineView 的独立展开逻辑，将其功能内联到主进度条

### T3.4 — 沉浸空间全局入口
- **目标**: APP 启动时即可设置和开关沉浸空间
- **行为**: 不需要进入播放才能操作沉浸空间，在主界面即可配置
- **范围**: SceneSelectorView 集成到 App 层级导航

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
- [ ] 5 种测试视频（SDR/HDR10/DV/180°/360°）全部就绪
- [ ] Apple Vision Pro Simulator E2E 测试全部通过
- [ ] 所有 UI 组件使用 Liquid Glass
- [ ] 视频详情二级界面功能完整
- [ ] 进度条已简化（无二级展开）
- [ ] 沉浸空间可在 App 启动时配置
- [ ] 设计文档中所有功能已实现
- [ ] 零已知 bug
