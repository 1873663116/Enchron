# ExecPlan019 — T1.4 渲染层适配器 + 投影覆盖 UI

## 目标
实现 T1.4 剩余渲染层功能：180° 半球 mesh、SBS/OU 帧裁剪、投影类型手动覆盖 UI。
鱼眼重映射 compute shader 推迟到下轮。

## 变更清单

### 1. PanoramaSphereEntity — 半球 mesh 生成
**文件**: `XrPlayer/SpatialScene/Renderers/PanoramaSphereEntity.swift`

当前状态: `.front180` projection enum 存在但实际仍生成完整球体。

变更:
- 新增 `generateHemisphereMesh(radius:stacks:slices:)` static method
- 使用 MeshDescriptor 程序化生成前半球顶点:
  - longitude: -π/2 到 π/2 (前半球)
  - latitude: -π/2 到 π/2 (完整垂直范围)
  - UV: U=0...1, V=0...1 (映射整个纹理到半球)
- `.front180` case 调用 `generateHemisphereMesh` 替代 `generateSphere`

### 2. PanoramaLayerBridge — SBS/OU 帧裁剪
**文件**: `XrPlayer/SpatialScene/Renderers/PanoramaLayerBridge.swift`

当前状态: blit 全帧复制。

变更:
- 新增 `public var stereoCropMode: PlaybackCoreDomain.StereoMode? = nil`
- `handleDisplayLink()` 中, 当 stereoCropMode 非 nil:
  - 根据 StereoMode.leftEyeUVRect 计算 sourceOrigin + sourceSize
  - LowLevelTexture 尺寸 = StereoMode.outputDimensions
  - blit 只复制左眼区域 (MVP: 单目渲染)
- 当 stereoCropMode == nil: 行为不变 (全帧)

### 3. AppModel — 投影状态管理
**文件**: `XrPlayer/AppModel.swift`

变更:
- 新增 `var detectedProjectionType: PlaybackCoreDomain.ProjectionType = .flat`
- 新增 `var projectionOverride: PlaybackCoreDomain.ProjectionType? = nil`
- 新增计算属性 `var effectiveProjectionType: PlaybackCoreDomain.ProjectionType`
  - = projectionOverride ?? detectedProjectionType
- 新增方法 `func updateDetectedProjection(_ type: ProjectionType)`
- 新增方法 `func setProjectionOverride(_ type: ProjectionType?)`

### 4. PlayerControlsView — 投影覆盖 Picker
**文件**: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`

变更:
- 在 secondaryControlRow 中新增 `projectionMenu` (位于 playbackModeMenu 之后)
- Menu 显示 ProjectionType.allCases
- 当前有效投影类型显示 checkmark
- 选择时调用 `appModel.setProjectionOverride(type)`
- 选择 "Auto" 时设为 nil (恢复自动检测)

### 5. ImmersiveSpaceView — 投影类型接线
**文件**: `XrPlayer/SpatialScene/Scenes/ImmersiveSpaceView.swift`

变更:
- `.panorama` case: 传递 `appModel.effectiveProjectionType.requiresHemisphereMesh ? .front180 : .full360` 到 PanoramaSphereEntity
- update 闭包: 投影类型变化时重建 sphere entity (mesh 不同需要重建)

### 6. AppCoordinator — 桥接投影检测到 AppModel
**文件**: `XrPlayer/App/AppCoordinator.swift`

变更:
- `decidePlaybackMode(for:)` 中, 调用 `appModel.updateDetectedProjection(profile.projectionType)`
- 同时根据投影类型设置 `panoramaBridge.stereoCropMode`

## 不做 (推迟到 Round 11)
- 鱼眼重映射 Metal compute shader
- Stereo 3D 双眼渲染 (MVP 先用左眼单目)
- T1.5 graceful transition
- T1.6 占位清除

## 依赖
- StereoMode (域层已完成, R9)
- HemisphereMeshConfiguration (域层已完成, R9)
- ProjectionType (域层已完成, R9)
