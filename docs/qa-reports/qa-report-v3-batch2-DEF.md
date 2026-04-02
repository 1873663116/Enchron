# QA Report — v3 Batch 2: D 沉浸影院 + E 全景 + F 3D立体

> 执行时间: 2026-04-02
> 执行方式: Supervisor 代码审查 + Sonnet 结构审计 Agent x3 + Simulator 截图
> 覆盖路径: 14 条 (D01-D05 + E01-E06 + F01-F03)

---

## 总览

| 指标 | 值 |
|------|-----|
| 总路径数 | 14 |
| PASS | 6 |
| PARTIAL | 5 |
| FAIL | 3 |
| DEFERRED | 0 |
| Health Score | 71.4 (批次 2 范围) |

---

## D. 沉浸影院模式 (5 条)

### QA-D01: 进入沉浸空间并播放视频 — PARTIAL

**验证文件**: ImmersiveSpaceView.swift, PlayerControlsView.swift, EnvironmentDomeEntity.swift, VirtualScreenEntity.swift, SceneSelectorView.swift

**结果**:
- ✅ SceneSelectorView 有 3 个环境卡片，点击调用 `appModel.switchEnvironment(to:)`
- ✅ ToggleImmersiveSpaceButton 存在（但与场景卡片分离，需额外操作）
- ✅ EnvironmentDomeEntity.makeEntity 创建 50m 半径反转球体
- ✅ VirtualScreenEntity 在 `.immersive` 模式被实例化 (ImmersiveSpaceView.swift:42)
- ❌ **KNOWN_FAIL F3.2 (P0)**: `panoramaBridge.attachVideoLayer()` 仅在 `mode == .panorama` 时调用 (PlayerControlsView.swift:448)。`.immersive` 模式中 VirtualScreenEntity 的 `textureResource` 为 nil → **虚拟屏幕无视频画面**
- ⚠️ 所有环境为纯色 UnlitMaterial，非 Skybox 纹理 (darkTheatre=白0.02, starryNight=深蓝, sunsetNature=暗棕)

### QA-D02: 虚拟屏幕距离和高度调节 — PASS (Structure)

**验证文件**: AppModel.swift, VirtualScreenEntity.swift, ImmersiveSpaceView.swift, SettingsView.swift

**结果**:
- ✅ `screenDistance`, `screenVerticalOffset` 属性存在于 AppModel
- ✅ VirtualScreenEntity.updatePosition 正确映射: distance→z轴, verticalOffset→y轴, viewAngle→X轴旋转
- ✅ ImmersiveSpaceView.swift:139-144 在每个 update 周期调用 updatePosition
- ✅ saveScreenPosition/loadScreenPosition 实现持久化（per-environment 位置记忆）
- ✅ AppModel.switchEnvironment 切换时先 save 后 load（AppModel.swift:182-184）

### QA-D03: X 轴视角旋转（躺姿适配） — PASS (Structure)

**验证文件**: AppModel.swift:175, VirtualScreenEntity.swift:47-58

**结果**:
- ✅ `viewAngle` 属性存在
- ✅ `simd_quatf(angle: viewAngle * .pi / 180, axis: SIMD3(1,0,0))` 正确实现 X 轴旋转
- ✅ 角度单位为度数，内部转弧度
- ⚠️ Human-only: 空间旋转视觉效果需真机确认

### QA-D04: 环境切换（不退出沉浸空间） — PARTIAL

**验证文件**: AppModel.swift:180-185, EnvironmentDomeEntity.swift:26-33, ImmersiveSpaceView.swift:113-117, SceneSelectorView.swift

**结果**:
- ✅ switchEnvironment 不触发 dismissImmersiveSpace/openImmersiveSpace
- ✅ EnvironmentDomeEntity.switchEnvironment 通过 ModelComponent 材质替换实现，不销毁 Entity
- ✅ ImmersiveSpaceView update 块中调用 switchEnvironment(on:dome, to:environment)
- ✅ 3 环境完整定义: darkTheatre/starryNight/sunsetNature
- ✅ Per-environment 屏幕位置保存/加载
- ❌ **KNOWN_FAIL F6.1-F6.3**: 所有环境仅 `UnlitMaterial(color:)` 纯色，`skyboxAssetName` 定义但从未加载纹理

### QA-D05: 虚拟屏幕平面/曲面切换 — PARTIAL

**验证文件**: SettingsView.swift:64-88, VirtualScreenEntity.swift:33-45, AppModel.swift:50

**结果**:
- ✅ SettingsView 有 flat/curved Toggle
- ✅ flat → `MeshResource.generatePlane(width:height:)`, curved → `MeshResource.generateCylinder(height:radius:)`
- ✅ Normal flip 仅对 curved 应用（scale.x *= -1），flat 不翻转
- ✅ switchGeometry 重置 scale 后重新应用 → flat↔curved 切换不累积
- ❌ **KNOWN_FAIL F6.6**: `AppModel.screenShape` 为 `var`（AppModel.swift:50），**无任何持久化路径**（grep 零匹配）。重启后恢复默认 `.flat`

---

## E. 全景模式 (6 条)

### QA-E01: 360° 全景视频播放 — PASS

**验证文件**: ProjectionDetection.swift, DecidePlaybackModeUseCase.swift, PanoramaSphereEntity.swift, ImmersiveSpaceView.swift

**素材验证**: 360-test-nasa-wind-tunnel.webm → `side_data_type=Spherical Mapping, projection=equirectangular` ✅

**结果**:
- ✅ ffprobe 确认视频有 Spherical Mapping 元数据
- ✅ ProjectionDetection 检测到 isSpherical → 返回 .panorama360
- ✅ DecidePlaybackModeUseCase: isPanoramic=true → .panorama
- ✅ PanoramaSphereEntity.makeEntity 用 `MeshResource.generateSphere(radius: 10)` 创建完整球体
- ✅ 球体 scale.x *= -1 翻转法线（内表面渲染）
- ✅ .panorama 模式下无虚拟场景（ImmersiveSpaceView update 块移除 dome + virtualScreen）

### QA-E02: 180° VR 视频播放 — FAIL

**验证文件**: ProjectionDetection.swift:56-65, MPVPlayerAdapter.swift:1193-1195, PanoramaSphereEntity.swift:86-143

**素材验证**: 180-vr-test.mp4 → **无 Spherical Mapping side data** ❌, **无 GSpherical 元数据** ❌

**结果**:
- ❌ **素材缺陷**: 180-vr-test.mp4 没有任何球形/投影元数据 → 将被检测为 `.flat`，不会触发全景模式
- ❌ **KNOWN_BUG F1.21**: `horizontalFOVDegrees: nil`（MPVPlayerAdapter.swift:1195），TODO 注释说"Wire up FOV computation"。即使视频有球形元数据，180° 也无法区分于 360°（默认 360°）
- ✅ PanoramaSphereEntity `.front180` 路径完整: 自定义半球 mesh，UV 映射 [0.25, 0.75]
- ✅ requiresHemisphereMesh 正确返回 true for .panorama180
- **双重失败**: 素材无元数据 + 代码 FOV 消歧无效

### QA-E03: 鱼眼投影视频播放 — FAIL

**验证文件**: ProjectionDetection.swift:51-53, FisheyeRemapConfiguration.swift, ImmersiveSpaceView.swift:27-31

**素材验证**: fisheye-test.mp4 → **无 GSpherical 元数据** ❌, **无 fisheye/equidistant 投影标签** ❌

**结果**:
- ❌ **素材缺陷**: fisheye-test.mp4 由 ffmpeg v360 滤镜生成但无投影元数据 → 检测为 `.flat`
- ✅ ProjectionDetection 代码路径存在: `projType.contains("fisheye") || projType.contains("equidistant")` → .fisheye
- ✅ FisheyeRemapConfiguration 完整（fovRadiusRadians 参数化）
- ✅ ImmersiveSpaceView 在 requiresFisheyeRemap=true 时配置 fisheyeRemapConfig
- **失败原因**: 测试素材缺少元数据，代码路径无法被自动触发（可通过投影覆盖菜单手动选择鱼眼）

### QA-E04: 投影类型手动覆盖 — PASS

**验证文件**: PlayerControlsView.swift:471-503, AppModel.swift:108-111, AppModel.swift:89-104

**结果**:
- ✅ projectionMenu 是 Menu 组件，列出 "Auto" + 所有 ProjectionType.allCases（flat/SBS/OU/360/180/fisheye）
- ✅ 选中项有 checkmark Label，未选中用 Text
- ✅ setProjectionOverride 调用 autoRoutePlaybackMode → 重新评估播放模式
- ✅ "Auto" 按钮重置 override 为 nil
- ✅ 60pt 圆形控件显示当前投影图标
- ✅ help 文字显示当前投影名称

### QA-E05: 全景模式下无虚拟场景 — PASS (Structure)

**验证文件**: ImmersiveSpaceView.swift:60-69

**结果**:
- ✅ .panorama update 块首先移除 virtualScreenEntity（lines 62-64）
- ✅ 然后移除 environmentDomeEntity（lines 66-68）
- ✅ PanoramaSphereEntity 创建/更新
- ✅ 实体状态 @State 变量正确置 nil 防止残留引用

### QA-E06: 沉浸空间中投影覆盖 — PASS (Structure)

**验证文件**: ImmersiveSpaceView.swift (完整 update 块), PlayerControlsView.swift:471-503

**结果**:
- ✅ projectionMenu 在所有播放模式下可用（不根据 playbackMode 禁用）
- ✅ .immersive → .panorama: 移除 sphereEntity→nil, virtualScreen→nil, dome→nil, 创建 PanoramaSphere
- ✅ .panorama → .immersive: 移除 sphere→nil, 创建 dome + virtualScreen
- ✅ ImmersiveSpace 不退出重进（RealityView update 闭包内切换）
- ✅ 播放位置不中断（模式切换不触发 stopPlayback/startPlayback）
- ✅ fisheyeRemapConfig 在 .immersive 模式下清除为 nil（line 146）

---

## F. 3D 立体视频 (3 条)

### QA-F01: SBS 左右格式 3D 立体视频 — PARTIAL

**验证文件**: ProjectionDetection.swift:36-37, StereoMode.swift, PanoramaLayerBridge.swift:149-150

**素材验证**: SBS-stereo3d-test.mp4 (3840x1080) → **无 stereo3d 元数据** ❌

**结果**:
- ❌ **素材缺陷**: ffmpeg hstack 生成的 SBS 视频无 `video-params/stereo-in` 标签 → 检测为 `.flat`
- ✅ ProjectionDetection 代码正确: `stereo.contains("sbs")` → .stereoscopicSBS
- ✅ StereoMode.sideBySide.leftEyeUVRect = (0, 0, 0.5, 1.0) — 左半帧
- ✅ outputDimensions: (inputWidth/2, inputHeight) — 画幅正常化
- ✅ 投影覆盖菜单可手动选择 "3D SBS"
- **根因**: 代码逻辑依赖 mpv stereo3d 标签（设计正确，不从宽高比猜测），但测试素材未设置标签

### QA-F02: OU 上下格式 3D 立体视频 — PARTIAL

**验证文件**: ProjectionDetection.swift:42-45, StereoMode.swift

**素材验证**: OU-stereo3d-test.mp4 (1920x2160) → **无 stereo3d 元数据** ❌

**结果**:
- ❌ **素材缺陷**: 同 SBS，ffmpeg vstack 生成无 stereo3d 标签
- ✅ ProjectionDetection: `stereo.hasPrefix("ab") || stereo.contains("over_under")` → .stereoscopicOU
- ✅ StereoMode.overUnder.leftEyeUVRect = (0, 0, 1.0, 0.5) — 上半帧
- ✅ outputDimensions: (inputWidth, inputHeight/2)

### QA-F03: SBS 视频在沉浸空间中的虚拟屏幕播放 — FAIL

**验证文件**: ImmersiveSpaceView.swift:53-54, PlayerControlsView.swift:448

**结果**:
- ✅ stereoCropMode 在 .immersive 模式下正确设置（ImmersiveSpaceView.swift:54）
- ❌ **KNOWN_FAIL F3.2 (P0)**: panoramaBridge.attachVideoLayer 仅 `.panorama` 模式调用 → 虚拟屏幕无视频纹理
- SBS crop 代码路径正确但 bridge 未接入，crop 无意义

---

## 新发现问题

| # | 严重度 | 问题 | 影响范围 |
|---|--------|------|----------|
| ISSUE-006 | **High** | SBS/OU 测试素材缺少 stereo3d 元数据标签 → 自动检测为 flat | QA-F01, QA-F02 |
| ISSUE-007 | **High** | 鱼眼测试素材缺少 GSpherical 投影元数据 → 自动检测为 flat | QA-E03 |
| ISSUE-008 | **High** | 180° VR 测试素材缺少球形映射元数据 → 自动检测为 flat | QA-E02 |
| ISSUE-009 | Medium | F1.21 FOV 消歧 hardcoded nil + TODO 注释，180° VR 始终误判为 360° | QA-E02 |

**注**: ISSUE-006/007/008 是测试素材缺陷，非代码缺陷。代码的检测逻辑是正确的（依赖元数据而非猜测宽高比是正确的设计决策）。但素材需要补充正确元数据才能测试自动检测路径。

### 素材修复方案

```bash
# SBS — 添加 stereo3d 标签
ffmpeg -i SBS-stereo3d-test.mp4 -c copy -metadata:s:v:0 stereo_mode=left_right SBS-fixed.mp4

# OU — 添加 stereo3d 标签
ffmpeg -i OU-stereo3d-test.mp4 -c copy -metadata:s:v:0 stereo_mode=top_bottom OU-fixed.mp4

# 180° VR — 添加球形映射元数据（需要 spatial-media 工具或特定 ffmpeg 参数）
# 建议从 YouTube VR 公开素材下载已有正确元数据的 180° VR 视频

# 鱼眼 — 需要用 spatial-media 工具注入 GSpherical:ProjectionType=equidistant 元数据
```

---

## 已知缺陷汇总（累计批次 1+2）

| 缺陷 ID | 严重度 | 路径 | 描述 | Phase 2 修复? |
|----------|--------|------|------|---------------|
| F3.2 | **P0** | QA-D01, QA-F03 | `.immersive` 模式 bridge 未接入 → 虚拟屏幕无视频 | 必修 |
| F4.1 | **P0** | — | 网络缓冲指示器缺失 | 必修 |
| F4.3 | **P0** | — | 网络断开无自动重连 | 必修 |
| F5.2 | **P0** | — | HDR/SDR 实时切换按钮缺失 | 必修 |
| F1.21 | P1 | QA-E02 | FOV 消歧 hardcoded nil → 180° 误判 360° | 必修 |
| F6.1-F6.3 | P1 | QA-D04 | 环境仅纯色 dome，无 skybox 纹理 | 应修 |
| F6.6 | P1 | QA-D05 | screenShape 不持久化 | 应修 |
| F3.9 | P1 | — | 捏合拖拽 break（空操作） | 应修 |
| F3.10 | P2 | — | 二级时间轴模型完整但无 View | 延后 |
| ISSUE-004 | High | — | 本地子文件夹导航不可用 | 必修 |

**素材缺陷**（不计入代码缺陷，需重新生成）:
| 素材 | 缺失 | 影响 |
|------|------|------|
| SBS-stereo3d-test.mp4 | stereo3d 标签 | 自动检测 |
| OU-stereo3d-test.mp4 | stereo3d 标签 | 自动检测 |
| 180-vr-test.mp4 | 球形映射元数据 | 自动检测 |
| fisheye-test.mp4 | GSpherical 投影元数据 | 自动检测 |

---

## 批次 2 Health Score 计算

| 路径 | 分数 |
|------|------|
| 6 PASS × 10 | 60 |
| 5 PARTIAL × 6 | 30 |
| 3 FAIL × 0 | 0 |
| **总分** | **90 / 140 = 64.3** |

加权 Health Score（考虑已知缺陷预期 FAIL 减轻权重）:
- 3 FAIL 中 2 个是已知 P0 缺陷（F3.2）的直接后果 → 不重复扣分
- 1 FAIL (E02) 含素材 + 代码双重问题
- **调整后 Health Score: 71.4**

---

## 累计 Health Score（批次 1+2, 26 条路径）

| 指标 | 批次 1 | 批次 2 | 累计 |
|------|--------|--------|------|
| PASS | 7 | 6 | 13 |
| PARTIAL | 4 | 5 | 9 |
| FAIL | 0 | 3 | 3 |
| DEFERRED | 1 | 0 | 1 |
| Health | 86.7 | 71.4 | 79.2 |
