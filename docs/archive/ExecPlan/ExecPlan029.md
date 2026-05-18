# ExecPlan029 — Phase 1 T1.1 QA 执行（批次 1: A+B+C）

> Round 8 | 2026-04-02
> Pipeline: EXECUTING
> 目标: 执行 QA 计划 A/B/C 类（启动导航 + 文件源 + 窗口播放）共 12 条路径

## 执行路径

### A. 启动与导航 (3)
- QA-A01: 应用启动首屏显示 → Simulator
- QA-A02: 场景选择面板交互 → Simulator + Structure
- QA-A03: NavigationStack 文件浏览导航 → Simulator

### B. 文件源管理 (4)
- QA-B01: 本地文件浏览与选择 → Simulator
- QA-B02: SMB 数据源添加与浏览 → Simulator
- QA-B03: WebDAV 数据源添加 → Simulator
- QA-B04: Apple Photos 视频访问 → Structure + Human-only

### C. 窗口模式播放 (5)
- QA-C01: SDR MKV 窗口模式完整播放路径 → Simulator
- QA-C02: HDR10 MP4 窗口模式播放 + HDR 标签 → Simulator + Structure
- QA-C03: Dolby Vision 播放 + HDR10 兼容回退 → Simulator + Structure
- QA-C04: MOV 容器格式播放 → Simulator
- QA-C05: AVI 容器格式播放 → Simulator

## 执行方式
- 使用 /qa skill 批量执行 Simulator 可执行路径
- Structure 路径通过代码审计确认
- Human-only 路径记录为 DEFERRED

## 完成标准
- 12 条路径全部有结果（PASS/FAIL/PARTIAL/BLOCKED/DEFERRED）
- FAIL/PARTIAL 项生成修复任务清单
