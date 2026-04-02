# ExecPlan001 — 全局审视与诊断

**Pipeline State**: PLANNING（Round 1）
**目标**: 全面了解代码库当前状态，评估产品优缺点，为后续 PLANNING 轮次的迭代计划提供基础
**日期**: 2026-04-02

---

## 任务分解

1. **代码库探索**
   - 各模块文件结构与代码量
   - 当前功能实现程度
   - 测试覆盖情况

2. **文档审计**
   - workspace-agents/ 下文档与当前 skills 的对齐度
   - 过时引用识别

3. **优缺点诊断**
   - 已有优势（保持）
   - 关键短板（改进方向）
   - 按 TODOS.md 各 Phase 评估优先级

---

## 代码库概况

| 模块 | 文件数 | 代码行数 | 核心功能 |
|------|--------|---------|---------|
| PlaybackCore | 21 | 2,139 | mpv 集成完整，HDR/EDR/投影检测已实现 |
| FileBrowsing | 16 | 2,786 | 本地/SMB/WebDAV 全部已实现 |
| PlayerUI | 13 | 1,842 | 播放控件、DetailedTimelineView、播放模式决策已实现 |
| Persistence | 15 | 401 | 5 个 port 全部已实现（进度/凭证/偏好/位置/数据源） |
| App | 6 | 480 | PlaybackLaunchCoordinator 完整（215行） |
| SpatialScene | 4 | 408 | 全景球体+场景选择器已实现 |
| Settings | 1 | 20 | 极简（仅自动恢复开关+版本号） |
| Shared | 4 | 335 | Metal 渲染器+常量+扩展 |
| **合计** | **80** | **8,011** | — |

测试：6 个测试文件，50+ 用例。31 项回归追踪。SwiftLint Domain 层隔离守卫。无 CI/CD。

## 产品优势（保持）

1. **架构纪律强**：Clean Architecture + DDD，SwiftLint 编译期强制 Domain 层隔离
2. **核心功能完整**：播放引擎、文件浏览（本地/SMB/WebDAV）、持久化、空间场景全部可用
3. **HDR 链路成熟**：HDR10/DV 检测、CAEDRMetadata、Dynamic Tone Mapping 已修复
4. **文档体系 A 级**：product_philosophy → Requirements → quality_gates → ARCHITECTURE 闭环
5. **已用 visionOS 原生材质**：glassBackgroundEffect、ornament、HoverEffect 已在用
6. **全景/空间能力就绪**：投影类型自动检测 + PanoramaSphereEntity + 场景选择器

## 关键短板（改进方向）

### P0 — 用户体验缺失
1. **无视频详情二级界面**（T3.2）：点击即播，无法预览信息/选字幕/选音轨/配置模式
2. **沉浸空间入口深埋**（T3.4）：必须进入播放后才能触发，App 主界面无法配置
3. **Settings 空壳**（20行）：无实质设置内容

### P1 — UI/UX 待重构
4. **Liquid Glass 迁移不完整**（T3.1）：已有 glassBackgroundEffect 但未系统化应用
5. **二级进度条逻辑冗余**（T3.3）：DetailedTimelineView 独立存在，需合并到主进度条
6. **文件浏览体验普通**：功能完整但视觉设计未达"非常好"标准

### P2 — 工程与测试
7. **缺全景测试视频**（T1.2）：180°/360° 测试素材未就绪
8. **文档结构旧版**（T0.1）：workspace-agents/ 有术语表重复、contracts 部分未验证
9. **无 E2E 系统测试**（T2.1）：从未做过完整的 Simulator QA

## Phase 优先级评估

| Phase | 价值 | 风险 | 建议顺序 |
|-------|------|------|---------|
| Phase 0 | 低（内务） | 低 | 可穿插在其他阶段中 |
| Phase 1 | 中（前置依赖） | 低 | 先完成 T1.2 获取全景视频 |
| Phase 2 | 高（发现隐藏 bug） | 中 | Phase 3 之前做一轮基线 QA |
| **Phase 3** | **最高（核心体验跃升）** | **高** | **主攻目标，T3.2 是最有价值的新功能** |
| Phase 4 | 高（功能完整性） | 中 | Phase 3 完成后推进 |

## Decision Log

- [AUTO] 优先级排序 | Phase 3 > Phase 2 > Phase 1 > Phase 4 > Phase 0 | P1(Completeness) + P5(Explicit) | Phase 3 的视频详情界面是最大的用户体验升级点，Phase 2 的 QA 基线在重构前做更有价值
- [AUTO] 下轮方向 | 进入 Phase 0 文档清理 + Phase 1 测试资源准备 | P6(Bias toward action) + P3(Pragmatic) | 这两个是低风险快速完成的前置任务，为后续主攻 Phase 2/3 扫清障碍
