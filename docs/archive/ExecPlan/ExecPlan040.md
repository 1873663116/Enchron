# ExecPlan040 — UX-06 Drag+Magnify 同时手势

**目标**: 在 DragRotationModifier 中添加 MagnifyGesture，与 DragGesture 同时激活（模仿 HelloWorld PlacementGesturesModifier 模式）  
**范围**: DragRotationModifier.swift 一个文件，增量修改  
**类别**: Phase 2 T2.2 HelloWorld UX 改进 #3

---

## 背景

HelloWorld PlacementGesturesModifier 中 Drag 与 Magnify 通过 `.simultaneousGesture` 同时工作。  
Enchron 当前 DragRotationModifier 只有 DragGesture，缺少缩放手势。

**Magnify 在 Enchron 空间视图中的映射**：
- 全景模式 (panorama): 缩放球体 → 模拟 FOV 调整
- 沉浸影院模式 (immersive): 缩放虚拟屏幕 → 屏幕大小调整
- 实现方式: `.scaleEffect(scale)` 应用于 RealityView 内容，配合 `.interactiveSpring`

## 实施步骤

1. **DragRotationModifier.swift** 修改：
   - 新增 `@State private var scale: Double = 1.0` 和 `startScale: Double?`
   - `body(content:)` 中添加 `.scaleEffect(scale)`（在 rotation3DEffect 之前）
   - 添加 `.simultaneousGesture(MagnifyGesture()...)`:
     - `onChanged`: 记录 startScale，clamp 到 0.5...2.0，`.interactiveSpring` 动画
     - `onEnded`: 清理 startScale（保留 scale 状态）

2. **swift build** 验证零 error

3. **swift test** 确认 248 passed, 0 failures

## 验收标准

- swift build: 0 errors
- swift test: ≥ 248 passed, 0 failures
- UX-06 状态: 完成 ✅
