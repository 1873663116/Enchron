# ExecPlan021 — Phase Transition + T2.1/T2.3

**Round**: 12
**Pipeline State**: EXECUTING → VERIFYING
**目标**: Phase 1 完成确认 + Phase Transition + T2.1 swift test 验证 + T2.3 REGRESSION.md 更新

## 执行计划

1. `swift test` 确认 248 tests 全绿 → ✅ 248 passed, 0 failed, 1 skipped (pre-existing WebDAV)
2. Phase Transition: EXECUTING → VERIFYING
3. T2.1 验证: ✅ 248 ≥ 245, 0 FAIL, 1 pre-existing SKIP
4. T2.3 REGRESSION.md 更新:
   - 新增 REG-100 ~ REG-109 (10 条回归项)
   - 更新代码路径映射索引 (13 条新增/修改)
   - 现有回归项无退化

## 新增回归项摘要

| REG | 标题 | 来源 |
|-----|------|------|
| REG-100 | 虚拟屏幕实体创建与渲染 | T1.1 |
| REG-101 | 虚拟屏幕平面/曲面切换 | T1.1 |
| REG-102 | 屏幕位置调节可用 | T1.2 |
| REG-103 | 环境独立位置记忆 | T1.2 |
| REG-104 | 沉浸影院环境切换 | T1.3 |
| REG-105 | 180° 半球裁剪渲染 | T1.4 |
| REG-106 | Stereo 3D SBS/OU 帧分离渲染 | T1.4 |
| REG-107 | 鱼眼投影重映射 | T1.4 |
| REG-108 | 投影类型手动覆盖 | T1.4 |
| REG-109 | 播放模式自动路由 | T1.5 |
