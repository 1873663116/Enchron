# ExecPlan030 — v3 R9 T1.1 批次 2: QA 执行 D+E+F

## 目标
执行 QA 计划批次 2：D 沉浸影院(5) + E 全景(6) + F 3D立体(3) = 14 条路径

## 执行策略
1. 确认 App 构建状态（沿用 R8 的 build 或重新 build）
2. 启动 Simulator + 安装 App
3. 并行发 Sonnet subagent 做代码结构审计（D+E+F 路径涉及的代码）
4. 结合 Simulator 截图 + 结构审计，逐条判定 PASS/FAIL/PARTIAL/DEFERRED

## 已知预期 FAIL
- QA-D01: F3.2 P0 bridge 断联 → 虚拟屏幕无视频
- QA-D04: F6.1-F6.3 环境仅纯色
- QA-D05: F6.6 屏幕形状不持久化
- QA-E02: F1.21 180° 可能误判 360°
- QA-F03: F3.2 P0 bridge 断联

## 产出
- docs/qa-reports/qa-report-v3-batch2-DEF.md
