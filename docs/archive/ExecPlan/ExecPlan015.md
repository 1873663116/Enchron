# ExecPlan015 — T1.1 沉浸影院模式：虚拟屏幕实体

> Round: 6
> Phase: EXECUTING
> 日期: 2026-04-02
> 目标: 实现 VirtualScreenEntity + 域模型填充，让 VirtualScreenConfigTests(7) + CinemaEnvironmentTests(6) = 13 个测试变绿

## 实施计划

### Step 1: 填充域模型 Stub（使 13 个测试变绿）

**CinemaEnvironment.swift** — 填充 displayName + skyboxAssetName:
- `.darkTheatre.displayName` → "暗黑影院"
- `.starryNight.displayName` → "星空夜景"
- `.sunsetNature.displayName` → "自然日落"
- `.darkTheatre.skyboxAssetName` → nil（纯黑，无需 Skybox）
- `.starryNight.skyboxAssetName` → "StarryNight"
- `.sunsetNature.skyboxAssetName` → "SunsetNature"

**VirtualScreenConfiguration.swift** — 填充 init clamping + aspectRatio + switchToCurved:
- `init`: flat 时 width clamp [1.0, 10.0]
- `aspectRatio`: flat → width/height; curved → (π × radius × 2/3) / height
- `switchToCurved`: 使用 `geometry.height` 保留高度
- 默认值从 `.flat(width: 0, height: 0)` 改为 `.flat(width: 2.4, height: 1.35)`

### Step 2: 创建 VirtualScreenEntity（RealityKit，不在测试 target 中）

文件: `XrPlayer/SpatialScene/Renderers/VirtualScreenEntity.swift`

- 参考 PanoramaSphereEntity 的 enum 模式
- `makeEntity(textureResource:, geometry:)` → 根据 ScreenGeometry 生成 plane 或 cylinder mesh
- `updateTexture(on:, textureResource:)` → 复用纹理更新逻辑
- `switchGeometry(on:, to:)` → 运行时替换 mesh，不重建 Entity
- Curved: `generateCylinder` + `faceCulling = .front`（内侧可见）
- Flat: `generatePlane(width:height:)` + 法线朝 +Z

### Step 3: 更新 ImmersiveSpaceView

- `.immersive` case: 创建 VirtualScreenEntity 并绑定 textureResource
- 纹理来源复用 `panoramaBridge.textureResource`（播放模式互斥，同一资源可共享）
- 添加 `@State private var screenEntity: Entity?` 管理虚拟屏幕生命周期

### Step 4: 验证

- `swift test` 全 248 通过（205 旧 + 13 新变绿 + 30 仍 FAIL = 248）
- git commit

## 依赖关系

- D1: UnlitMaterial（复用现有管线）
- D2: PanoramaLayerBridge TextureResource 共享
- D3: generateCylinder + faceCulling 曲面近似
- R2: generatePlane(width:height:) xy-plane
- R4: entity.position/orientation 位置控制（T1.2 再做）

## 不在本轮范围

- T1.2 屏幕位置控制（距离/高度/旋转 Slider 接入 3D Entity）
- T1.3 3 个沉浸式环境实现
- Settings 屏幕形状选择 UI（需要确认 Settings 结构后再做，可以随 T1.2 一起）
