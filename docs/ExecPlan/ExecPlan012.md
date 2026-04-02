# ExecPlan012 — T0.3 综合测试计划设计

> Round: 3
> Phase: PLANNING
> 日期: 2026-04-02
> 目标: 为 EP010 功能清单中每个未实现功能设计测试用例（≥ 40），并为 /qa 设计 E2E 测试路径

## 设计原则

1. **Test-First**: 所有测试在功能代码之前写入，必须在当前代码上 FAIL
2. **编译通过**: 需创建最小 stub 类型（空 enum/struct），使 `swift test` 能编译但测试失败
3. **旧测试不受影响**: 205 个现有测试保持全 PASS
4. **每个测试映射到功能清单**: 无孤立测试，无未覆盖功能

## 测试策略

### 编译策略

现有 test target（`XrPlayerCoreTests`）只能测试 `Package.swift` 中列出的源文件。新测试需要的类型分两类：

**A. 已存在类型上的新行为**（修改现有代码即可）：
- `SavedScreenPosition` — 增加 distance/angle 校验
- `ProjectionDetection` — 增加 fisheye 检测分支
- `ProjectionType` — 增加计算属性

**B. 全新类型**（需创建 stub + 加入 Package.swift）：
- `CinemaEnvironment` — 沉浸环境枚举
- `ScreenGeometry` — 屏幕形状配置
- `VirtualScreenConfiguration` — 虚拟屏幕配置
- `StereoMode` — 立体帧分离模式
- `HemisphereMeshConfiguration` — 半球网格参数
- `FisheyeRemapConfiguration` — 鱼眼重映射参数
- `DecidePlaybackModeUseCase` — 播放模式决策用例
- `PlaybackModeManaging` — 播放模式管理协议

**T0.5 落地步骤**：先创建 B 类 stub 文件（仅类型壳，无实现），加入 Package.swift sources，再写测试代码。

---

## 单元测试设计（43 个测试用例）

### File 1: CinemaEnvironmentTests.swift — 沉浸环境域（6 tests）

映射功能: A12-A14（3 个环境）、A15（SceneSelector 功能化）、A16（环境切换）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 1 | testCinemaEnvironmentHasExactlyThreeCases | `CinemaEnvironment.allCases.count == 3`；包含 `.darkTheatre`, `.starryNight`, `.sunsetNature` | 类型不存在 |
| 2 | testCinemaEnvironmentRawValuesAreUnique | 所有 `rawValue` 唯一且非空（用作持久化键和环境 ID） | 类型不存在 |
| 3 | testDarkTheatreRequiresNoSkyboxAsset | `.darkTheatre.skyboxAssetName == nil`；纯黑环境无需外部资源（per D5） | 类型不存在 |
| 4 | testStarryNightHasSkyboxAsset | `.starryNight.skyboxAssetName != nil` | 类型不存在 |
| 5 | testSunsetNatureHasSkyboxAsset | `.sunsetNature.skyboxAssetName != nil` | 类型不存在 |
| 6 | testCinemaEnvironmentCodableRoundTrip | 编码 → 解码保持相等 | 类型不存在 |

**Stub 规格**:
```swift
// XrPlayer/SpatialScene/Domain/CinemaEnvironment.swift
extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case darkTheatre, starryNight, sunsetNature
        
        public var skyboxAssetName: String? {
            nil // stub — tests 3-5 will FAIL (starryNight/sunsetNature should return non-nil)
        }
    }
}
```

---

### File 2: VirtualScreenConfigTests.swift — 虚拟屏幕配置（7 tests）

映射功能: A1-A4（虚拟屏幕 Entity）、A6（Settings 形状选择）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 7 | testScreenGeometryFlatHasDimensions | `.flat` 创建时需指定 width/height；默认 2.4m × 1.35m（16:9） | 类型不存在 |
| 8 | testScreenGeometryCurvedHasRadiusAndHeight | `.curved` 需 radius + height；per D3 用圆柱近似 | 类型不存在 |
| 9 | testScreenGeometryIsCodable | flat 和 curved 均可 encode → decode 保持相等 | 类型不存在 |
| 10 | testVirtualScreenConfigDefaultAspectRatio | 默认宽高比 ≈ 16:9（`abs(width/height - 16.0/9.0) < 0.01`） | 类型不存在 |
| 11 | testVirtualScreenConfigWidthClampedToMin | width < 1.0m → clamped to 1.0m | 类型不存在 |
| 12 | testVirtualScreenConfigWidthClampedToMax | width > 10.0m → clamped to 10.0m | 类型不存在 |
| 13 | testVirtualScreenConfigShapeSwitchPreservesSize | flat(2.4, 1.35) → switchTo(.curved(r:2.5)) → 高度仍为 1.35m | 类型不存在 |

**Stub 规格**:
```swift
// XrPlayer/SpatialScene/Domain/ScreenGeometry.swift
extension SpatialSceneDomain {
    public enum ScreenGeometry: Sendable, Equatable, Codable {
        case flat(width: Float, height: Float)
        case curved(radius: Float, height: Float)
    }
}

// XrPlayer/SpatialScene/Domain/VirtualScreenConfiguration.swift
extension SpatialSceneDomain {
    public struct VirtualScreenConfiguration: Sendable, Equatable {
        public var geometry: ScreenGeometry
        // stub: no clamping, no defaults → tests 10-13 FAIL
    }
}
```

---

### File 3: ScreenPositionValidationTests.swift — 屏幕位置校验（5 tests）

映射功能: A7-A9（位置调节）、A11（环境独立记忆）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 14 | testPositionDistanceClampedToMinimum | `SavedScreenPosition(distanceMeters: 0.5)` → `.distanceMeters == 2.0` | 当前无 clamping |
| 15 | testPositionDistanceClampedToMaximum | `SavedScreenPosition(distanceMeters: 25.0)` → `.distanceMeters == 20.0` | 当前无 clamping |
| 16 | testPositionAngleClampedToRange | `SavedScreenPosition(viewAngleDegrees: 60.0)` → `.viewAngleDegrees == 45.0` | 当前无 clamping |
| 17 | testPositionVerticalOffsetClampedToRange | offset 超出 ±5.0m → clamped | 当前无 clamping |
| 18 | testPositionDefaultFactory | `SavedScreenPosition.default(for: "darkTheatre")` → distance=5.0, offset=0, angle=0 | factory 方法不存在 |

**实现路径**: 修改 `SavedScreenPosition.init` 增加 `max(2.0, min(20.0, distanceMeters))` 等校验。测试 18 需增加 static factory。

---

### File 4: StereoFrameSplitTests.swift — 立体帧分离域（7 tests）

映射功能: B3（SBS）、B4（OU）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 19 | testStereoModeHasTwoCases | `.sideBySide`, `.overUnder` 两个 case | 类型不存在 |
| 20 | testSBSLeftEyeUVRect | SBS 左眼区域: origin=(0,0), size=(0.5, 1.0) | 类型不存在 |
| 21 | testSBSRightEyeUVRect | SBS 右眼区域: origin=(0.5, 0), size=(0.5, 1.0) | 类型不存在 |
| 22 | testOULeftEyeUVRect | OU 左眼（上半）: origin=(0, 0), size=(1.0, 0.5) | 类型不存在 |
| 23 | testOURightEyeUVRect | OU 右眼（下半）: origin=(0, 0.5), size=(1.0, 0.5) | 类型不存在 |
| 24 | testStereoOutputDimensions_SBS | 输入 3840×1080 → 每眼 1920×1080 | 类型不存在 |
| 25 | testStereoOutputDimensions_OU | 输入 1920×2160 → 每眼 1920×1080 | 类型不存在 |

**Stub 规格**:
```swift
// XrPlayer/PlaybackCore/Domain/ValueObjects/StereoMode.swift
extension PlaybackCoreDomain {
    public enum StereoMode: String, Sendable, CaseIterable, Codable {
        case sideBySide
        case overUnder
        
        public struct UVRect: Sendable, Equatable {
            public let originX: Float, originY: Float
            public let width: Float, height: Float
        }
        
        // stub: returns zero rect → tests 20-25 FAIL
        public var leftEyeUVRect: UVRect { UVRect(originX: 0, originY: 0, width: 0, height: 0) }
        public var rightEyeUVRect: UVRect { UVRect(originX: 0, originY: 0, width: 0, height: 0) }
        
        public func outputDimensions(inputWidth: Int, inputHeight: Int) -> (width: Int, height: Int) {
            (0, 0) // stub → tests 24-25 FAIL
        }
    }
}
```

---

### File 5: HemisphereMeshConfigTests.swift — 180° 半球网格（4 tests）

映射功能: B2（180° 裁剪）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 26 | testHemisphereUVRangeForFrontHalf | U 范围 [0.25, 0.75]（等矩形纹理中央 50%，per M3） | 类型不存在 |
| 27 | testHemisphereLongitudeRange | 经度范围 [-π/2, π/2]（前半球） | 类型不存在 |
| 28 | testHemisphereVertexCount | stacks=64, slices=64 → 65×65=4225 顶点 | 类型不存在 |
| 29 | testHemisphereFullLatitudeRange | V 范围 [0.0, 1.0]（纬度完整覆盖） | 类型不存在 |

**Stub 规格**:
```swift
// XrPlayer/SpatialScene/Domain/HemisphereMeshConfiguration.swift
extension SpatialSceneDomain {
    public struct HemisphereMeshConfiguration: Sendable, Equatable {
        public let stacks: Int
        public let slices: Int
        public let radius: Float
        
        // stub: zero values → all tests FAIL
        public var uRange: ClosedRange<Float> { 0...0 }
        public var longitudeRange: ClosedRange<Float> { 0...0 }
        public var vertexCount: Int { 0 }
        public var vRange: ClosedRange<Float> { 0...0 }
    }
}
```

---

### File 6: FisheyeRemapConfigTests.swift — 鱼眼重映射（3 tests）

映射功能: B5（鱼眼重映射）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 30 | testFisheyeDefaultFOVIsHalfPi | 默认 FOV = π/2 弧度（180° 鱼眼，per M4） | 类型不存在 |
| 31 | testFisheyeCenterPixelMapsToCenter | 输入 (0.5, 0.5) → 输出 (0.5, 0.5)（中心不变性） | 类型不存在 |
| 32 | testFisheyeOutOfFOVReturnsNil | 距离中心 > fovRadius 的采样点 → nil（填黑） | 类型不存在 |

**Stub 规格**:
```swift
// XrPlayer/SpatialScene/Domain/FisheyeRemapConfiguration.swift
extension SpatialSceneDomain {
    public struct FisheyeRemapConfiguration: Sendable, Equatable {
        public let fovRadiusRadians: Float
        
        public init(fovRadiusRadians: Float = 0) { // stub: 0 instead of π/2
            self.fovRadiusRadians = fovRadiusRadians
        }
        
        // stub: always returns nil → tests 31-32 FAIL
        public func sampleCoordinate(outputU: Float, outputV: Float) -> (u: Float, v: Float)? {
            nil
        }
    }
}
```

---

### File 7: PlaybackModeRoutingTests.swift — 播放模式决策（6 tests）

映射功能: C3（决策矩阵）、C5（graceful transition）、C6（PlaybackModeManaging）、C7（DecidePlaybackModeUseCase）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 33 | testDecidePlaybackModeUseCaseExistsAndCallable | 可实例化 `DecidePlaybackModeUseCase`，可调用 `.decide()` | 类型不存在 |
| 34 | testDecisionWithManualOverrideToWindow | panorama360 + override=.window → .window（覆盖优先） | UseCase 不存在 |
| 35 | testDecisionWithManualOverrideToImmersive | flat + non-immersive + override=.immersive → .immersive | UseCase 不存在 |
| 36 | testDecisionWithNoOverrideFallsBackToAuto | flat + non-immersive + override=nil → .window（自动决策） | UseCase 不存在 |
| 37 | testDecisionStereo3DInImmersiveIsImmersive | SBS + immersive=true → .immersive（SBS 非 panoramic） | UseCase 不存在 |
| 38 | testPlaybackModeManagingProtocolExists | `PlaybackModeManaging.self` 可引用为协议类型 | 协议不存在 |

**Stub 规格**:
```swift
// XrPlayer/PlayerUI/Domain/Ports/PlaybackModeManaging.swift
public protocol PlaybackModeManaging: Sendable {
    func decideMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool,
        manualOverride: PlaybackMode?
    ) -> PlaybackMode
}

// XrPlayer/PlayerUI/UseCases/DecidePlaybackModeUseCase.swift
public struct DecidePlaybackModeUseCase: PlaybackModeManaging {
    public init() {}
    public func decideMode(...) -> PlaybackMode {
        .window // stub: always returns window → tests 34-37 FAIL
    }
}
```

---

### File 8: ProjectionDetectionExtendedTests.swift — 投影检测扩展（5 tests）

映射功能: B5（鱼眼检测）、B7（180° FOV）、B8（手动覆盖）

| # | 测试名 | 验证内容 | FAIL 原因 |
|---|--------|---------|-----------|
| 39 | testFisheyeDetectionFromGSphericalProjection | input: `gSphericalProjectionType = "fisheye"` → `.fisheye` | 当前无 fisheye 分支，返回 .flat |
| 40 | testFisheyeDetectionFromEquidistantTag | input: `gSphericalProjectionType = "equidistant_fisheye"` → `.fisheye` | 同上 |
| 41 | testProjectionTypeIsStereo3D | `.stereoscopicSBS.isStereo3D == true`; `.flat.isStereo3D == false` | 计算属性不存在 |
| 42 | testProjectionTypeRequiresHemisphereMesh | `.panorama180.requiresHemisphereMesh == true`; `.panorama360 == false` | 计算属性不存在 |
| 43 | testProjectionTypeRequiresFisheyeRemap | `.fisheye.requiresFisheyeRemap == true`; `.panorama360 == false` | 计算属性不存在 |

**实现路径**:
- 测试 39-40: 修改 `ProjectionDetection.detect()` 增加 fisheye 分支
- 测试 41-43: 在 `ProjectionType` 上增加计算属性

---

## 功能 → 测试覆盖矩阵

| 功能 ID | 功能名 | 单元测试 | E2E 路径 |
|---------|--------|---------|----------|
| A1 | VirtualScreenEntity | 7, 10 | P2-S4 |
| A2 | 平面 mesh | 7, 10, 11 | P2-S4 |
| A3 | 曲面 mesh | 8, 12 | P2-S5 |
| A4 | 形状切换 | 9, 13 | P2-S5,S6 |
| A5 | 纹理桥接 | — (需 Metal/GPU) | P2-S4 |
| A6 | Settings 形状选择 | 9 | P2-S5 |
| A7 | 距离调节 | 14, 15 | P2-S7 |
| A8 | 高度调节 | 17 | P2-S8 |
| A9 | 旋转调节 | 16 | P2-S9 |
| A10 | 位置持久化 | — (已 ✅) | P2-S10 |
| A11 | 环境独立记忆 | 18 | P2-S12,S15 |
| A12 | 暗黑影院 | 1, 2, 3, 6 | P2-S3 |
| A13 | 星空夜景 | 1, 2, 4, 6 | P2-S10 |
| A14 | 自然日落 | 1, 2, 5, 6 | P2-S13 |
| A15 | SceneSelector 功能化 | 1 | P2-S10 |
| A16 | 播放中环境切换 | — (需 UI runtime) | P2-S10,S11 |
| A17 | 位置恢复 | 18 | P2-S12,S15 |
| B1 | 360° 全景 | — (已 ✅) | P3 全部 |
| B2 | 180° 裁剪 | 26, 27, 28, 29 | P4 全部 |
| B3 | SBS 帧分离 | 19, 20, 21, 24 | P5-S1,S3 |
| B4 | OU 帧分离 | 19, 22, 23, 25 | P5-S4,S6 |
| B5 | 鱼眼重映射 | 30, 31, 32, 39, 40 | P6 全部 |
| B6 | 自动检测 | — (已 ✅) | P8-S1 |
| B7 | 180° FOV 检测 | — (已有测试) | P4-S2 |
| B8 | 手动覆盖 | 34, 35 | P7 全部 |
| C1 | MediaProfile | — (已 ✅) | — |
| C2 | ProjectionType | 41, 42, 43 | — |
| C3 | 决策矩阵 | 33, 34, 35, 36, 37 | P8 全部 |
| C4 | 模式切换 UI | — (已 ✅ UI) | P8-S2 |
| C5 | Graceful transition | 37 | P8-S3,S5 |
| C6 | PlaybackModeManaging | 38 | — |
| C7 | DecidePlaybackModeUseCase | 33 | — |
| E1 | SceneSelector 占位 | 1 | P2-S3 |
| E2 | FOV computation | 39, 40 | P6-S2 |

**覆盖率**: 42 个功能中 37 个有单元测试或 E2E 覆盖。5 个已完成功能（A10, B1, B6, C1, C4）已有测试。

---

## E2E 测试路径（供 /qa 技能执行）

所有 E2E 路径在 Apple Vision Pro Simulator 上执行。每步标注验证点。

### Path 1: 窗口模式基线回归

> 目的: 确认 v1 overnight 产出的窗口模式功能在本轮改动后无退化

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 启动 App，进入文件浏览界面 | 本地文件列表正确显示 |
| S2 | 选择一个 SDR .mkv 视频 | 视频在窗口模式播放 |
| S3 | 点击播放/暂停按钮 | 播放状态正确切换 |
| S4 | 拖动时间轴 seek | seek 位置正确 |
| S5 | 切换音轨 | 音频变化 |
| S6 | 开启字幕 | 字幕显示 |
| S7 | 调整倍速到 2x | 播放速度改变 |
| S8 | 选择 HDR10 视频 | HDR 标记显示 |
| S9 | 退出视频 → 重新进入 | 播放记忆弹窗出现 |

### Path 2: 沉浸影院模式（核心新功能）

> 目的: 验证虚拟屏幕 + 环境系统 + 位置控制的完整功能

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 打开一个 flat 视频 | 窗口模式播放正常 |
| S2 | 点击播放模式选择器 → 选择"沉浸影院" | 模式菜单显示三种模式 |
| S3 | 确认进入沉浸空间 | ImmersiveSpace 打开，默认环境: 暗黑影院 |
| S4 | 观察虚拟屏幕 | 平面屏幕渲染，视频内容显示在屏幕上 |
| S5 | 打开 Settings → 屏幕形状选择 → Curved | 屏幕形状变为曲面 |
| S6 | 确认视频继续播放 | 切换过程视频不中断 |
| S7 | 调整距离 Slider（拉远） | 屏幕远离，视觉大小变小 |
| S8 | 调整高度 Slider（上移） | 屏幕向上移动 |
| S9 | 调整旋转 Slider | 屏幕倾斜 |
| S10 | 切换环境: 暗黑影院 → 星空夜景 | 背景变为星空，视频不中断 |
| S11 | 确认星空夜景背景渲染 | 可见星空元素 |
| S12 | 调整星空环境下的屏幕位置 → 记录 | 位置变化生效 |
| S13 | 切换环境: 星空 → 自然日落 | 背景变为暖色日落 |
| S14 | 确认自然日落渲染 | 暖色调背景 + 柔和光照 |
| S15 | 切换回暗黑影院 | 恢复暗黑影院记忆的位置（非星空环境的位置） |
| S16 | 退出沉浸空间 | 返回窗口模式 |

### Path 3: 全景模式 — 360° 回归

> 目的: 确认 360° 全景在改动后无退化

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 选择一个 360° equirectangular 视频 | 自动检测为 panorama360 |
| S2 | 确认自动进入沉浸空间 | ImmersiveSpace 打开 |
| S3 | 确认全球体渲染 | 完整球体内表面显示视频 |
| S4 | 模拟头部转动（Simulator 操作） | 视角变化，可环顾四周 |
| S5 | 验证播放控件可用 | 暂停/播放/seek 正常 |

### Path 4: 全景模式 — 180° 新功能

> 目的: 验证 180° 半球裁剪

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 选择一个带 FOV≤180° 元数据的视频 | 自动检测为 panorama180 |
| S2 | 确认自动进入沉浸空间 | ImmersiveSpace 打开 |
| S3 | 确认前半球渲染 | 视频只显示在前方半球 |
| S4 | 转向后方 | 后方无内容（黑色或空） |

### Path 5: 立体 3D 模式

> 目的: 验证 SBS/OU 帧分离

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 选择一个 SBS 立体视频 | 自动检测为 stereoscopicSBS |
| S2 | 确认窗口模式播放 | 视频渲染（非沉浸时为普通窗口） |
| S3 | 进入沉浸模式 | 虚拟屏幕 + 立体渲染 |
| S4 | 选择一个 OU 立体视频 | 自动检测为 stereoscopicOU |
| S5 | 确认窗口模式播放 | 视频渲染正常 |
| S6 | 进入沉浸模式 | 虚拟屏幕 + 立体渲染 |

### Path 6: 鱼眼投影

> 目的: 验证鱼眼重映射

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 选择一个鱼眼投影视频 | 检测为 fisheye |
| S2 | 确认重映射为等矩形并在球体渲染 | 画面无畸变 |
| S3 | 对比手动切换投影类型 | 切换为 panorama360 → 画面变形（证明重映射在工作） |

### Path 7: 投影类型手动覆盖

> 目的: 验证用户可覆盖自动检测结果

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | 选择一个 flat 视频 | 自动判定为 flat，窗口播放 |
| S2 | 打开投影类型 Picker | Picker 出现在 PlayerControlsView |
| S3 | 覆盖为 panorama360 | 进入全景模式，flat 内容投射到球体（内容变形但功能正常） |
| S4 | 重置为自动检测 | 回到窗口模式 |

### Path 8: 播放模式自动路由交叉验证

> 目的: 验证决策矩阵覆盖所有组合

| Step | 操作 | 验证点 |
|------|------|--------|
| S1 | flat 视频 → 确认窗口模式 | auto → window |
| S2 | 手动切到沉浸模式 → 确认虚拟屏幕 | manual → immersive |
| S3 | 360° 视频 → 确认全景模式 | auto → panorama |
| S4 | SBS 视频 + 非沉浸 → 确认窗口模式 | auto → window |
| S5 | SBS 视频 + 进入沉浸 → 确认沉浸模式 | auto → immersive |
| S6 | 快速切换不同视频类型 | 模式自动切换，无崩溃 |

---

## 新增文件清单（T0.5 落地时创建）

### Stub 源文件（加入 Package.swift XrPlayerCore sources）

| 文件路径 | 类型 | 用途 |
|---------|------|------|
| `XrPlayer/SpatialScene/Domain/CinemaEnvironment.swift` | enum | 沉浸环境定义 |
| `XrPlayer/SpatialScene/Domain/ScreenGeometry.swift` | enum | 屏幕形状配置 |
| `XrPlayer/SpatialScene/Domain/VirtualScreenConfiguration.swift` | struct | 虚拟屏幕完整配置 |
| `XrPlayer/SpatialScene/Domain/HemisphereMeshConfiguration.swift` | struct | 180° 网格参数 |
| `XrPlayer/SpatialScene/Domain/FisheyeRemapConfiguration.swift` | struct | 鱼眼重映射参数 |
| `XrPlayer/SpatialScene/Domain/SpatialSceneDomain.swift` | enum (namespace) | SpatialScene 域命名空间 |
| `XrPlayer/PlaybackCore/Domain/ValueObjects/StereoMode.swift` | enum | 立体帧分离模式 |
| `XrPlayer/PlayerUI/Domain/Ports/PlaybackModeManaging.swift` | protocol | 播放模式管理协议 |
| `XrPlayer/PlayerUI/UseCases/DecidePlaybackModeUseCase.swift` | struct | 播放模式决策用例 |

### 测试文件

| 文件路径 | 测试数 |
|---------|--------|
| `Tests/XrPlayerCoreTests/CinemaEnvironmentTests.swift` | 6 |
| `Tests/XrPlayerCoreTests/VirtualScreenConfigTests.swift` | 7 |
| `Tests/XrPlayerCoreTests/ScreenPositionValidationTests.swift` | 5 |
| `Tests/XrPlayerCoreTests/StereoFrameSplitTests.swift` | 7 |
| `Tests/XrPlayerCoreTests/HemisphereMeshConfigTests.swift` | 4 |
| `Tests/XrPlayerCoreTests/FisheyeRemapConfigTests.swift` | 3 |
| `Tests/XrPlayerCoreTests/PlaybackModeRoutingTests.swift` | 6 |
| `Tests/XrPlayerCoreTests/ProjectionDetectionExtendedTests.swift` | 5 |
| **合计** | **43** |

### Package.swift 修改

在 `XrPlayerCore` target 的 `sources` 数组中追加 9 个 stub 文件路径。

---

## FAIL 原因分类

| FAIL 类型 | 测试数 | 说明 |
|-----------|-------|------|
| 类型不存在（stub 返回零值/nil） | 33 | 新类型的 stub 实现故意返回错误值 |
| 现有类型缺少校验 | 4 | SavedScreenPosition 无 clamping |
| 现有类型缺少计算属性 | 3 | ProjectionType.isStereo3D 等 |
| 现有函数缺少分支 | 2 | ProjectionDetection 无 fisheye |
| 协议/用例不存在 | 1 | PlaybackModeManaging |

---

## Decision Log

- [AUTO] 测试策略 | stub + FAIL 而非编译错误 | P1+P5 | 编译通过才能运行旧测试，FAIL 比 compile error 更可控
- [AUTO] Stub 位置 | 域层而非测试层 | P4+P5 | Stub 就是最终类型的骨架，T1 阶段直接填充实现
- [AUTO] E2E 路径数 | 8 条路径 | P1+P2 | 覆盖三种播放模式 + 交叉验证 + 手动覆盖
- [AUTO] 测试文件拆分 | 每个域一个文件 | P3 | 清晰映射，独立运行
