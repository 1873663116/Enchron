# ExecPlan017 — T1.3 三个沉浸式环境

## 目标
实现 3 个沉浸式影院环境（暗黑影院、星空夜景、自然日落），功能化 SceneSelectorView，集成到 ImmersiveSpaceView。

## 架构决策
- D4: 一个 sky dome Entity，切换材质颜色（无需重开 ImmersiveSpace）
- D5: 暗黑影院 = 纯色 UnlitMaterial
- 星空夜景 / 自然日落：同样使用纯色 UnlitMaterial（项目无 skybox 纹理资产，后期可替换）
- Sky dome 半径 50m（虚拟屏幕最远 20m，dome 必须在屏幕外侧）

## 实施步骤

### Step 1: 新建 EnvironmentDomeEntity.swift
路径: `XrPlayer/SpatialScene/Renderers/EnvironmentDomeEntity.swift`

```swift
enum EnvironmentDomeEntity {
    static let domeRadius: Float = 50.0
    
    static func makeEntity(environment: CinemaEnvironment) -> Entity
    static func switchEnvironment(on entity: Entity, to environment: CinemaEnvironment)
}
```

颜色方案:
- darkTheatre: UIColor(white: 0.02, alpha: 1)
- starryNight: UIColor(red: 0.01, green: 0.01, blue: 0.06, alpha: 1)
- sunsetNature: UIColor(red: 0.15, green: 0.08, blue: 0.03, alpha: 1)

实现模式与 PanoramaSphereEntity 一致：inverted sphere + UnlitMaterial。

### Step 2: CinemaEnvironment 添加颜色属性
在 CinemaEnvironment.swift 新增 `ambientColor: UIColor` 计算属性。

### Step 3: 修改 ImmersiveSpaceView
- 新增 `@State private var environmentDomeEntity: Entity?`
- `.immersive` case 的 make closure: 创建 EnvironmentDomeEntity + VirtualScreenEntity
- `.immersive` case 的 update closure: 检测 appModel.currentCinemaEnvironment 变化，调用 switchEnvironment
- `.panorama` 和 `.window` case: 清理 environmentDomeEntity

### Step 4: 修改 SceneSelectorView
- 注入 `@Environment(AppModel.self) var appModel`
- ForEach 改为遍历 `CinemaEnvironment.allCases`
- 每个按钮的 action 调用 `appModel.switchEnvironment(to:)`
- 显示 `environment.displayName`
- 按环境换不同 SF Symbol（moon.stars / star.fill / sun.horizon）
- 选中状态绑定 `appModel.currentCinemaEnvironment`
- 去掉第 4 个占位按钮

### Step 5: Package.swift
新增 `"SpatialScene/Renderers/EnvironmentDomeEntity.swift"` 到 sources

## 验证
- `swift test`: 25 failures 不增不减（T1.3 无专属 failing tests，不应引入新 failure）
- 编译通过: `swift build`
- SceneSelectorView 3 个按钮 → 3 个真实环境
- ImmersiveSpaceView .immersive 模式下 dome + 虚拟屏幕共存
- 环境切换不中断播放（只替换 dome 材质）
- 环境切换后屏幕位置自动恢复（T1.2 已实现的 switchEnvironment 逻辑）

## TODOS.md 对应
- [ ] 环境 1: 暗黑影院
- [ ] 环境 2: 星空夜景
- [ ] 环境 3: 自然日落
- [ ] SceneSelectorView 功能化
- [ ] 播放中环境切换不中断播放
- [ ] 环境切换后恢复屏幕位置记忆
