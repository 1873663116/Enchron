# ExecPlan036 — F6.1-F6.3 Skybox 纹理加载修复

**Phase**: EXECUTING (Phase 2 T2.1)
**目标**: 修复沉浸环境仅纯色 dome 的问题，实现 skybox 纹理加载

## 根因

`EnvironmentDomeEntity.material(for:)` 始终使用 `UnlitMaterial(color: .init(tint:))` 纯色，
完全忽略了 `CinemaEnvironment.skyboxAssetName` 属性。同时项目中不存在实际的纹理图片资源。

## 修复方案

### 1. 生成 Skybox 纹理图片
- StarryNight: 深蓝/黑底 + 随机星点 + 银河渐变带，等距柱状投影，4096×2048
- SunsetNature: 底部暖橙→中部粉紫→顶部深蓝渐变，等距柱状投影，4096×2048
- 工具: Python PIL 或 ImageMagick

### 2. 添加到 Asset Catalog
- `XrPlayer/Assets.xcassets/StarryNight.imageset/`
- `XrPlayer/Assets.xcassets/SunsetNature.imageset/`

### 3. 更新 EnvironmentDomeEntity
参考 HelloWorld Starfield.swift 和项目内 PanoramaSphereEntity/VirtualScreenEntity 的模式：
- `material(for:)` → async，当 `skyboxAssetName` 非 nil 时用 `TextureResource(named:)` 加载
- 加载成功 → `mat.color = .init(tint: .white, texture: .init(resource))`
- 加载失败 → fallback 到现有纯色
- `makeEntity` → async
- `switchEnvironment` → async 重新加载纹理

### 4. 验证
- `swift build` 零 error
- 现有 CinemaEnvironmentTests 仍绿

## 影响范围
- `XrPlayer/SpatialScene/Renderers/EnvironmentDomeEntity.swift`
- `XrPlayer/SpatialScene/Scenes/ImmersiveSpaceView.swift`（调用端适配 async）
- `XrPlayer/Assets.xcassets/`（新增 2 个 imageset）
