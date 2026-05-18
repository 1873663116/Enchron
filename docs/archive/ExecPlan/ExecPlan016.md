# ExecPlan016 — T1.2 屏幕位置控制

**Round**: 7
**Pipeline**: EXECUTING
**目标**: 完成 T1.2，让 ScreenPositionValidationTests (5) 从 FAIL → PASS

## 改动清单

### 1. SavedScreenPosition.swift — init clamping
- `distanceMeters`: clamp to [2.0, 20.0]
- `verticalOffsetMeters`: clamp to [-5.0, 5.0]
- `viewAngleDegrees`: clamp to [-45.0, 45.0]
- 直接修复 5 个 ScreenPositionValidationTests

### 2. AppModel.swift — 环境感知位置持久化
- 新增 `currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre`
- 新增 `screenShape: SpatialSceneDomain.ScreenGeometry = .flat(width: 2.4, height: 1.35)`
- `saveScreenPosition()` / `loadScreenPosition()` 改用 `currentCinemaEnvironment.rawValue` 作为 key
- 新增 `switchEnvironment(to:)` — save old → switch → load new

### 3. SettingsView.swift — 沉浸空间设置扩展
- "Immersive Space" section 内新增：
  - Screen Shape Picker (Flat / Curved)
  - Cinema Environment Picker (3 environments)
- 绑定到 AppModel 的对应属性

### 4. ImmersiveSpaceView.swift — 环境切换时 restore 位置
- 监听 `appModel.currentCinemaEnvironment` 变化
- 变化时自动调用 position restore

## 影响的测试
- ScreenPositionValidationTests: 5 tests (FAIL → PASS)
- 预期结果: 248 total, 223 passed, 25 failed

## 依赖
- T1.1 VirtualScreenEntity (Round 6, ✅)
- CinemaEnvironment 枚举 (Round 6, ✅)
- ScreenPositionStoring / SwiftDataStore (已存在, ✅)
