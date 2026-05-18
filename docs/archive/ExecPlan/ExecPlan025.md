# ExecPlan025 — T0.2 HelloWorld 参考审计

> Round: 2 (v3)
> Phase: PLANNING
> 目标: 读取 HelloWorld 实际代码，与 Enchron 逐项对比 UX 模式，输出改进清单

## 计划

### 1. 读取 HelloWorld 关键文件（7 个领域）
- Scene 定义 + ImmersiveSpace (WorldApp.swift)
- Observable 状态管理 (ViewModel.swift)
- 导航 + 布局 (ModuleDetail.swift, ModuleCard.swift)
- Glass 控制面板 (GlobeControls.swift)
- Settings UI (SliderGridRow.swift, SettingsButton.swift)
- 手势 + 动画 (DragRotationModifier.swift, PlacementGesturesModifier.swift)
- 沉浸空间管理 (GlobeToggle.swift, OrbitToggle.swift, SolarSystemToggle.swift, SolarSystemControls.swift)

### 2. 读取 Enchron 对应实现

### 3. 逐项对比，输出改进清单
- 每项标注优先级和具体改动位置
- 写入 docs/qa-plans/helloworld-ux-audit-v3.md

## 委派方案

3 个并行 Explore Agent：
- Agent A: 导航/布局/Scene 定义
- Agent B: 控件/设置/Glass 面板
- Agent C: 手势/动画/沉浸空间管理
