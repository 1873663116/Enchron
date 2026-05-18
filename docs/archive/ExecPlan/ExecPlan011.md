# ExecPlan011 — T0.2 API 调研（context7 MCP）

> Round: 2
> Phase: PLANNING
> 日期: 2026-04-02
> 目标: 使用 context7 MCP 调研 8 个 Apple 框架 API 课题，为 T0.3 测试计划提供技术依据

## 调研课题

### RealityKit 组（4 课题）

| # | 课题 | 目的 |
|---|------|------|
| R1 | 虚拟屏幕渲染方案（VideoMaterial vs ShaderGraphMaterial vs UnlitMaterial） | 确定 A1-A5 的 Material 选型 |
| R2 | ModelEntity 平面/曲面 mesh 创建与动态切换 | 确定 A2-A4 的 mesh 实现方案 |
| R3 | ImmersiveSpace 多环境加载与切换 API | 确定 A12-A17 的环境系统方案 |
| R4 | Entity 位置/旋转/缩放持久化与恢复 | 确定 A7-A9 + A11 的位置控制方案 |

### Metal 组（4 课题）

| # | 课题 | 目的 |
|---|------|------|
| M1 | Stereo 3D SBS 左右帧分离 shader | 确定 B3 的实现方案 |
| M2 | Stereo 3D OU 上下帧分离 shader | 确定 B4 的实现方案 |
| M3 | 180° 半球纹理坐标裁剪 | 确定 B2 的实现方案 |
| M4 | 鱼眼投影重映射（equidistant fisheye → equirectangular） | 确定 B5 的实现方案 |

## 调研方法

- context7 MCP: resolve-library-id → query-docs（RealityKit + Metal）
- deepwiki MCP: Apple 官方 visionOS 示例（Hello World, Destination Video）
- 代码审计: 现有 SpatialScene/Shared 渲染管线全文审查
- 每课题产出: API 签名、代码示例、约束/注意事项、架构决策

---

## 调研结果

### R1: 虚拟屏幕渲染方案 — Material 选型

**结论: 复用现有 PanoramaLayerBridge + UnlitMaterial 路径**

| Material | 适用场景 | 能否用于 Enchron |
|----------|---------|-----------------|
| VideoMaterial | AVPlayer 绑定 | **不可用** — Enchron 用 mpv，非 AVPlayer |
| ShaderGraphMaterial | 自定义 shader + DrawableQueue | 可用但过重 — 需要 Reality Composer Pro 预建 MaterialX |
| UnlitMaterial | 静态/动态纹理，不受光照 | **推荐** — 已在 PanoramaSphereEntity 验证 |

**关键发现:**
- `VideoMaterial(avPlayer:)` 要求 AVPlayer 实例，mpv 解码路径无法使用
- `DrawableQueue + ShaderGraphMaterial` 是 Apple 推荐的 CPU/GPU 动态纹理方案，但需 RCP 创建 MaterialX 图
- 现有 `PanoramaLayerBridge` 已实现完整管线: drawable → MTLBlitCommandEncoder → LowLevelTexture → TextureResource → UnlitMaterial
- **播放模式互斥**（window/immersive/panorama 不并存），同一个 TextureResource 可绑定到不同 Entity

**架构决策:**
- MVP 阶段: 复用 PanoramaLayerBridge 的 TextureResource，用 UnlitMaterial 贴到平面/曲面 Entity
- 未来优化: 如需 HDR tone-mapping 在 RealityKit 侧处理，可升级为 ShaderGraphMaterial

**代码路径:**
```
mpv → MPVNativeMetalLayer.lastVendedDrawable
  → PanoramaLayerBridge.handleDisplayLink()
  → MTLBlitCommandEncoder.copy() → LowLevelTexture
  → TextureResource (共享)
  → UnlitMaterial(texture: textureResource)
  → ModelEntity(mesh: plane/cylinder, materials: [material])
```

---

### R2: ModelEntity Mesh 创建与动态切换

**结论: generatePlane + generateCylinder(faceCulling trick)，运行时 entity.model?.mesh = newMesh**

**平面屏幕:**
```swift
let flatMesh = MeshResource.generatePlane(width: 2.4, height: 1.35, cornerRadius: 0.02)
// 生成在 xy-plane，法线朝 +Z（面向用户）
```

**曲面屏幕:**
```swift
let curvedMesh = MeshResource.generateCylinder(height: 1.35, radius: 2.5)
// 需要 faceCulling = .front 使内侧可见（用户在圆柱内部观看）
// 替代方案: 从 Reality Composer Pro 导出自定义曲面 USDZ
```

**运行时切换（零重建）:**
```swift
func switchScreenShape(_ entity: ModelEntity, to shape: ScreenShape) {
    entity.model?.mesh = shape == .flat
        ? MeshResource.generatePlane(width: w, height: h)
        : MeshResource.generateCylinder(height: h, radius: r)
}
```

**约束:**
- RealityKit 无原生 `generateCurvedPlane`，曲面用圆柱近似
- generatePlane(width:height:) 在 xy-plane；generatePlane(width:depth:) 在 xz-plane — 虚拟屏幕用前者
- mesh 替换触发 GPU 重传，首帧可能微卡顿，仅在用户手势触发时调用

**建议:** 定义 `ScreenGeometry` 枚举（`.flat` / `.curved(radius:)`），封装 mesh 生成逻辑

---

### R3: ImmersiveSpace 多环境加载与切换

**结论: Sky dome Entity + VirtualEnvironmentProbeComponent，无需重开 ImmersiveSpace**

**核心方案:**
1. 创建巨大球体 Entity（radius ≥ 1000m），faceCulling = .front（内侧渲染）
2. 材质承载环境纹理（ShaderGraphMaterial 或 UnlitMaterial + 环境贴图）
3. VirtualEnvironmentProbeComponent 同步间接光照
4. 切换时替换材质参数，不关闭/重开 ImmersiveSpace

**环境定义:**
```swift
enum CinemaEnvironment: String, CaseIterable {
    case darkTheatre   // 纯黑 — 最简，可用纯色 UnlitMaterial
    case starryNight   // 星空 — Skybox 纹理或程序化星点
    case sunsetNature  // 日落 — 暖色调 Skybox + 环境光

    var skyboxAssetName: String? { ... }
}
```

**关键 API:**
```swift
// 加载环境资源（async，建议预加载）
let envResource = try await EnvironmentResource(named: "StarryNight", in: .main)

// 光照探针（让 skybox 影响 PBR 材质）
let probe = VirtualEnvironmentProbeComponent.Probe(environment: envResource)
entity.components.set(VirtualEnvironmentProbeComponent(source: .single(probe)))

// ImmersiveSpace 状态管理（AppModel 已有三态机）
enum ImmersiveSpaceState { case closed, inTransition, open }
```

**约束:**
- EnvironmentResource 加载是 async，所有环境应在 ImmersiveSpace 打开时并发预加载
- VirtualEnvironmentProbeComponent 必须与 skybox 同步更新，否则光照/背景不匹配
- "暗黑影院" 环境可用纯色 UnlitMaterial（无需 Skybox 资产），最简实现

---

### R4: Entity 位置控制与持久化

**结论: entity.position + entity.orientation，序列化为 Float 数组存入现有 ScreenPositionStoring**

**控制 API:**
```swift
// 位置（父坐标系，SIMD3<Float>）
screenEntity.position = SIMD3<Float>(0, -0.1, -distance)

// 旋转（simd_quatf）
screenEntity.orientation = simd_quatf(angle: viewAngle, axis: SIMD3(1, 0, 0))

// 完整变换
screenEntity.transform = Transform(scale: .one, rotation: quat, translation: pos)
```

**持久化（与现有 ScreenPositionStoring 对接）:**
- AppModel 已有 `screenDistance`, `screenVerticalOffset`, `screenViewAngle` 字段
- ScreenPositionStoring 接口已支持 `environmentID` 参数
- 当前硬编码 `"virtual-screen"` → 需改为传入 `CinemaEnvironment.rawValue`

**约束:**
- SIMD3/simd_quatf 不自动 Codable，现有实现已用分离的 Double 字段（distance/offset/angle）规避
- ImmersiveSpace 坐标原点随用户头部位置确定，跨会话恢复需考虑漂移
- position/orientation 是 @MainActor，非主线程修改需 await MainActor.run {}

---

### M1 + M2: Stereo 3D 帧分离（SBS + OU 统一 shader）

**结论: 单个 compute kernel，mode 参数控制水平/垂直分离**

**Metal shader (`stereoFrameSplit`):**
- 输入: 全宽/全高原始帧纹理
- 输出: 左眼 + 右眼两张半尺寸纹理
- SBS (mode=0): 左半/右半水平分割
- OU (mode=1): 上半/下半垂直分割
- 纯内存拷贝操作，4K SBS 约 415 万像素/眼，GPU 带宽绰绰有余

**Swift 调度 (`StereoFrameSplitter`):**
```swift
enum StereoMode: UInt32 { case sideBySide = 0; case overUnder = 1 }

func split(commandBuffer:, input:, outLeft:, outRight:, mode:)
// dispatchThreads 以输出纹理尺寸为网格大小
```

**整合位置:** PanoramaLayerBridge blit 之后 → StereoFrameSplitter → 两个 TextureResource → 左右眼各一个 PanoramaSphereEntity

**文件落地:** `XrPlayer/Shared/VideoShaders.metal` (追加 kernel) + `XrPlayer/SpatialScene/Renderers/StereoFrameSplitter.swift`

---

### M3: 180° 半球纹理坐标裁剪

**结论: LowLevelMesh 自定义 UV 方案（UV-U 限制 [0.25, 0.75]）**

**数学映射:**
```
等矩形纹理 UV:
  U = (longitude + π) / (2π)
  V = (latitude + π/2) / π

前半球 longitude ∈ [-π/2, π/2] → U ∈ [0.25, 0.75]
纬度不变 → V ∈ [0.0, 1.0]
```

**实现: `HemisphereMeshBuilder`**
- 使用 `LowLevelMesh` 自定义顶点（position + normal + uv）
- 经度范围限制 [-π/2, π/2]（前半球）
- UV 直接映射到等矩形纹理中央 50%
- stacks=64, slices=64 约 4225 顶点

**替代 PanoramaSphereEntity 的 generateSphere:**
```swift
// 360° 全景
let mesh = MeshResource.generateSphere(radius: 10)  // 现有

// 180° 半球（新增）
let lowLevelMesh = try HemisphereMeshBuilder.build(radius: 10, stacks: 64, slices: 64)
let mesh = try MeshResource(from: lowLevelMesh)
```

**文件落地:** `XrPlayer/SpatialScene/Renderers/HemisphereMeshBuilder.swift`

---

### M4: 鱼眼投影重映射

**结论: GPU compute kernel 逐像素反向映射，r = f * θ 公式**

**数学推导:**
```
输出等矩形 (u,v) → 球面方向 (λ,φ) → 3D 单位向量 (x,y,z)
→ θ = acos(z)  // 与光轴夹角
→ r = θ / fov_radius  // 归一化径向距离
→ ψ = atan2(y,x)  // 方位角
→ 鱼眼采样坐标 (fx,fy) = (r*cos(ψ)+1)/2, (r*sin(ψ)+1)/2
```

**Metal shader (`fisheyeToEquirectangular`):**
- 输入: 鱼眼纹理（access::sample + 双线性插值）
- 输出: 等矩形纹理
- 参数: fovRadiusRad（视场半角弧度），默认 π/2（180° 鱼眼）
- 超出视场范围的像素填黑

**性能:** 每像素含 acos/atan2/cos/sin，4K 输出约 2-5ms。可缓存 UV 映射表优化。

**整合位置:** PanoramaLayerBridge blit 之后 → FisheyeRemapper.remap() → 等矩形纹理 → TextureResource → PanoramaSphereEntity（现有）

**文件落地:** `XrPlayer/Shared/VideoShaders.metal` (追加 kernel) + `XrPlayer/SpatialScene/Renderers/FisheyeRemapper.swift`

---

## 架构决策汇总

| # | 决策 | 选择 | 依据 |
|---|------|------|------|
| D1 | 虚拟屏幕 Material | UnlitMaterial（复用现有管线） | mpv 非 AVPlayer，VideoMaterial 不可用；ShaderGraphMaterial 需 RCP 过重 |
| D2 | 虚拟屏幕纹理源 | 复用 PanoramaLayerBridge 的 TextureResource | 播放模式互斥，无并存需求，零额外开发 |
| D3 | 曲面屏幕实现 | generateCylinder + faceCulling=.front | RealityKit 无原生 curvedPlane，圆柱内侧近似效果佳 |
| D4 | 环境切换机制 | Sky dome Entity 材质参数替换 | 无需重开 ImmersiveSpace，切换延迟 <16ms |
| D5 | 暗黑影院环境 | 纯色 UnlitMaterial（无 Skybox 资产） | 最简实现，纯黑背景无需外部资源 |
| D6 | SBS/OU 分离 | 统一 compute kernel + mode 参数 | 逻辑几乎相同，一个 shader 覆盖两种格式 |
| D7 | 180° 裁剪方案 | LowLevelMesh 自定义 UV（方案 b） | 比 mesh 裁剪更简单，clamp_to_edge 自动处理边界 |
| D8 | 鱼眼重映射 | GPU compute + 双线性采样 | 硬件纹理单元加速，4K 输出 2-5ms |
| D9 | Stereo 3D 输出 | 左右眼各一个 PanoramaSphereEntity | 立体渲染需双 Entity 分别绑定左/右眼纹理 |

---

## 完整渲染管线蓝图

```
libmpv 渲染
    ↓
MPVNativeMetalLayer.lastVendedDrawable (MTLTexture)
    ↓
PanoramaLayerBridge.handleDisplayLink()
    ↓ MTLBlitCommandEncoder → LowLevelTexture → TextureResource
    ↓
    ├─── [window 模式] MetalVideoRenderer → MTKView（现有，不改）
    │
    ├─── [immersive 模式] TextureResource
    │     → UnlitMaterial
    │     → VirtualScreenEntity (plane / cylinder)
    │     → Sky dome Entity (环境背景)
    │     → VirtualEnvironmentProbeComponent (间接光照)
    │
    ├─── [panorama 360°] TextureResource
    │     → UnlitMaterial
    │     → PanoramaSphereEntity (generateSphere, 现有)
    │
    ├─── [panorama 180°] TextureResource
    │     → UnlitMaterial
    │     → HemisphereMeshEntity (LowLevelMesh, UV=[0.25,0.75])
    │
    ├─── [stereo SBS/OU] MTLTexture
    │     → StereoFrameSplitter (compute kernel)
    │     → leftEye TextureResource + rightEye TextureResource
    │     → 双 PanoramaSphereEntity
    │
    └─── [fisheye] MTLTexture
          → FisheyeRemapper (compute kernel)
          → equirect MTLTexture → TextureResource
          → PanoramaSphereEntity (360° 球体)
```

## 新增文件清单（预计）

| 文件 | 模块 | 用途 |
|------|------|------|
| VirtualScreenEntity.swift | SpatialScene/Renderers | 虚拟屏幕 Entity（plane/cylinder + material） |
| HemisphereMeshBuilder.swift | SpatialScene/Renderers | 180° 半球 LowLevelMesh 生成 |
| StereoFrameSplitter.swift | SpatialScene/Renderers | SBS/OU compute kernel 调度 |
| FisheyeRemapper.swift | SpatialScene/Renderers | 鱼眼重映射 compute kernel 调度 |
| CinemaEnvironment.swift | SpatialScene/Scenes | 环境预设定义 + sky dome 管理 |
| VideoShaders.metal（追加） | Shared | stereoFrameSplit + fisheyeToEquirectangular kernel |

## 修改文件清单（预计）

| 文件 | 修改内容 |
|------|---------|
| ImmersiveSpaceView.swift | 增加 immersive 模式分支：创建虚拟屏幕 + 环境 |
| PanoramaSphereEntity.swift | 增加 180° 投影支持（调用 HemisphereMeshBuilder） |
| SceneSelectorView.swift | 功能化：绑定 CinemaEnvironment 枚举，切换触发环境加载 |
| AppModel.swift | 增加 currentEnvironmentID + 环境相关状态 |
| AppCoordinator.swift | decidePlaybackMode 接入主流程 |
| ScreenPositionControlView.swift | 位置调节驱动 3D Entity transform |
| SettingsView.swift | 增加屏幕形状选择（Flat/Curved） |
| PlayerControlsView.swift | 增加投影类型手动覆盖 Picker |
