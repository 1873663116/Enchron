---
date: 2026-04-06
topic: combination-matrix-investigation
context: three-axis-orthogonal-model
---

# 三轴正交模型全场景组合矩阵调研报告

## 1. 三轴定义（目标状态）

| 轴 | 枚举 | 值 |
|----|------|----|
| **投影类型** | `ProjectionType` | `.flat` / `.equirectangular180` / `.equirectangular360` / `.fisheye` |
| **立体布局** | `StereoLayout` | `.mono` / `.sideBySide` / `.topBottom` |
| **播放模式** | `PlaybackMode` | `.window` / `.immersive` / `.panorama` |

> **注意**：本文档基于目标状态三轴分析。当前代码仍使用旧枚举（`stereoscopicSBS`/`stereoscopicOU`/`panorama360`/`panorama180`），重构后映射见第 5 节。

---

## 2. 全组合枚举矩阵（4 × 3 × 3 = 36 种）

图例：
- **OK** — 合法组合，有明确渲染行为
- **OK↓** — 技术可行但降格（非原生最优体验）
- **ILLEGAL** — 违反约束规则，UI 应禁用或拦截
- **RARE** — 现实中极罕见，但技术上可行

### 2.1 ProjectionType = `.flat`

| StereoLayout | PlaybackMode = `.window` | PlaybackMode = `.immersive` | PlaybackMode = `.panorama` |
|---|---|---|---|
| `.mono` | **OK** — 标准 2D 窗口播放 | **OK** — 虚拟影院大屏 2D | **ILLEGAL** — flat 不可用全景模式 |
| `.sideBySide` | **OK↓** — 仅取左眼半帧，相当于半宽画面；用户可开关 3D | **OK** — 虚拟影院大屏，3D 眼镜分眼可感知景深 | **ILLEGAL** — flat 不可用全景模式 |
| `.topBottom` | **OK↓** — 仅取上半帧，半高画面；用户可开关 3D | **OK** — 同 SBS，3D 可感知景深 | **ILLEGAL** — flat 不可用全景模式 |

**flat 小结**：Panorama 模式对 flat 完全禁止（共 3 个 ILLEGAL）。Window 和 Immersive 对所有 StereoLayout 均可行。

### 2.2 ProjectionType = `.equirectangular180`

| StereoLayout | PlaybackMode = `.window` | PlaybackMode = `.immersive` | PlaybackMode = `.panorama` |
|---|---|---|---|
| `.mono` | **OK↓** — 等矩投影平铺显示，失真明显但可作预览 | **OK↓** — 大屏平铺，投影失真 | **OK** — 前半球 180° 2D VR 沉浸 |
| `.sideBySide` | **OK↓** — 取左眼半帧，等矩平铺 | **OK↓** — 大屏立体 3D，投影未展开 | **OK** — 3D VR 180°（最典型 3D 180 VR 内容） |
| `.topBottom` | **OK↓** — 取上半帧，等矩平铺 | **OK↓** — 大屏立体 3D | **OK** — 3D VR 180°（Over-Under 变体） |

**equirectangular180 小结**：0 个 ILLEGAL，6 个有意义（其中 3 个 Panorama 合法）。

### 2.3 ProjectionType = `.equirectangular360`

| StereoLayout | PlaybackMode = `.window` | PlaybackMode = `.immersive` | PlaybackMode = `.panorama` |
|---|---|---|---|
| `.mono` | **OK↓** — 等矩平铺预览，失真 | **OK↓** — 大屏全景平铺 | **OK** — 360° 2D 全景，最常见 360 VR |
| `.sideBySide` | **OK↓** — 取左眼半帧，平铺 | **OK↓** — 大屏立体 3D | **OK** — 3D VR 360°（SBS 格式） |
| `.topBottom` | **OK↓** — 取上半帧，平铺 | **OK↓** — 大屏立体 3D | **OK** — 3D VR 360°（OU 格式） |

**equirectangular360 小结**：0 个 ILLEGAL，同 180。

### 2.4 ProjectionType = `.fisheye`

| StereoLayout | PlaybackMode = `.window` | PlaybackMode = `.immersive` | PlaybackMode = `.panorama` |
|---|---|---|---|
| `.mono` | **OK↓** — 圆形 fisheye 平铺，可作预览 | **OK↓** — 大屏未 remap | **OK** — fisheye→equirectangular remap 后球面渲染 |
| `.sideBySide` | **RARE/OK↓** — 双圆 fisheye 平铺，取左半 | **RARE/OK↓** — 大屏立体 3D | **RARE/OK** — 双 fisheye→remap + 立体分眼（现实极罕见） |
| `.topBottom` | **RARE/OK↓** — 上下双圆 fisheye，取上半 | **RARE/OK↓** — 大屏立体 3D | **RARE/OK** — 上下 fisheye→remap + 立体（极罕见） |

**fisheye 小结**：0 个 ILLEGAL，但 fisheye + stereo 现实中极罕见（见第 4.4 节分析）。

---

## 3. 合法/非法汇总

| 状态 | 数量 | 说明 |
|------|------|------|
| **OK** | 9 | 完全合法且最优渲染 |
| **OK↓** (降格) | 24 | 技术可行，体验非最优，UI 可提示 |
| **RARE/OK** | 3 | fisheye + stereo，技术合法但现实极罕见 |
| **ILLEGAL** | 3 | flat + panorama（3 种 StereoLayout × 1） |

**总计**：3 种严格非法（均为 flat + panorama），33 种技术可行。

---

## 4. 约束规则确认

### 4.1 Panorama 模式约束
- **规则**：Panorama 模式仅对 `isPanoramic = true` 的 ProjectionType 开放
- **来源**：`DecidePlaybackModeUseCase.allowedModes(for:)` + 需求文档 §2.3
- **结论**：flat 的所有 StereoLayout 组合均不可用 Panorama，共 3 个 ILLEGAL ✓

### 4.2 mono 内容 3D 开关
- **规则**：`.mono` 内容 3D 开关禁用（锁定 2D）
- **来源**：需求文档 §2.4
- **结论**：现有代码未实现 StereoLayout，mono 判断逻辑在 `ProjectionDetection.detect()` 中未显式处理（stereo3dIn 为空时隐式为 mono）

### 4.3 flat + sideBySide/topBottom 渲染行为

**Window 模式**：
- `PanoramaLayerBridge.stereoCropMode` 设置为对应的 `StereoMode`
- `encodeBlitCopy` 通过 `leftEyeUVRect` 截取左眼区域（SBS 取左半帧，OU 取上半帧）
- 渲染到窗口的 CAMetalLayer，像素数量减半但内容完整
- 用户关闭 3D 时：不设置 stereoCropMode → 全帧显示（左右眼叠加，看起来双影）
- **推荐 UI 提示**：3D 开关默认开启，关闭时显示"非 3D 显示模式"

**Immersive 模式**：
- 通过 `VirtualScreenEntity` 大屏显示
- `PanoramaLayerBridge.stereoCropMode` 同样裁切左眼，在虚拟影院大屏上呈现
- 用户佩戴 visionOS 设备但设备本身不做立体渲染（MVP 阶段仅左眼单帧）
- 真正的立体 3D 需要 visionOS 立体渲染支持（Apple Spatial Video 路径）

### 4.4 fisheye + stereo 现实可行性
- **现实情况**：极少数双目 fisheye 相机（如 Insta360 部分型号的双鱼眼原始格式）会产生此组合
- **技术实现**：`PanoramaLayerBridge` 当前 `encodeFisheyeRemap` 在 `stereoCropMode` 存在时不生效（代码逻辑：fisheye remap 取优先，不与 stereo crop 叠加）
- **缺口**：fisheye + stereo 需要先裁切左眼区域，再对该区域做 fisheye remap，当前管线不支持此组合
- **建议**：初期标记为 UNSUPPORTED，fisheye 检测到时强制 stereoLayout = .mono

### 4.5 stereo + window 模式渲染细节

| 组合 | 渲染结果 | 体验评级 |
|------|----------|----------|
| flat/SBS + window + 3D on | 左眼半帧，画面正常但分辨率损失 50% | 可接受，属于 3D 内容的预览窗口 |
| flat/SBS + window + 3D off | 全帧 SBS（双影叠加效果） | 差，应默认关闭或提示 |
| equirect360/SBS + panorama | 球面 + 立体 UV 分割 = 完整 3D VR 360 | 最佳 VR 体验 |
| equirect180/SBS + panorama | 半球 + 立体 UV 分割 = 完整 3D VR 180 | 最佳 3D 180 体验 |

---

## 5. 自动路由逻辑（目标状态）

### 5.1 当前实现分析

`DecidePlaybackModeUseCase.decideMode()` 现有逻辑（仅依赖 ProjectionType）：

```swift
// 当前逻辑（基于旧枚举）
if profile.projectionType.isPanoramic { return .panorama }
if isEnvironmentActive { return .immersive }
return .window
```

**问题**：完全忽略 StereoLayout，无法区分 flat+stereo 应路由到 Immersive 的情况。

### 5.2 目标路由逻辑（需实现）

```swift
// 目标逻辑（三轴感知）
switch (profile.projectionType, profile.stereoLayout) {
case (.flat, .mono):
    return .window                          // 普通 2D 平面视频

case (.flat, .sideBySide), (.flat, .topBottom):
    return .immersive                       // 3D 平面内容 → 沉浸大屏 3D

case (let p, _) where p.isPanoramic:
    return .panorama                        // 全景内容（任何 StereoLayout）→ 全景模式

default:
    return isEnvironmentActive ? .immersive : .window
}
```

### 5.3 默认路由表（完整）

| ProjectionType | StereoLayout | 默认 PlaybackMode | 3D 状态 |
|---|---|---|---|
| `.flat` | `.mono` | `.window` | 禁用 |
| `.flat` | `.sideBySide` | `.immersive` | 开启 |
| `.flat` | `.topBottom` | `.immersive` | 开启 |
| `.equirectangular180` | `.mono` | `.panorama` | 禁用 |
| `.equirectangular180` | `.sideBySide` | `.panorama` | 开启 |
| `.equirectangular180` | `.topBottom` | `.panorama` | 开启 |
| `.equirectangular360` | `.mono` | `.panorama` | 禁用 |
| `.equirectangular360` | `.sideBySide` | `.panorama` | 开启 |
| `.equirectangular360` | `.topBottom` | `.panorama` | 开启 |
| `.fisheye` | `.mono` | `.panorama` | 禁用 |
| `.fisheye` | `.sideBySide` | `.panorama` | 开启（但受限，见 §4.4） |
| `.fisheye` | `.topBottom` | `.panorama` | 开启（但受限，见 §4.4） |

---

## 6. 渲染管线差异分析

### 6.1 各投影类型的管线需求

| ProjectionType | 网格 | UV 映射 | Metal Shader | 说明 |
|---|---|---|---|---|
| `.flat` | 平面矩形（VirtualScreenEntity） | 标准 0-1 UV | 无额外 shader | 直接 blit 到窗口或虚拟屏 |
| `.equirectangular360` | 全球面（半径翻转法线） | 球面投影标准 UV | 无（RealityKit UnlitMaterial） | 纹理直接映射到球面内壁 |
| `.equirectangular180` | 前半球（自定义 HemisphereMesh） | U=[0.25, 0.75]（前 180° 段） | 无 | 自定义半球网格 + UV offset |
| `.fisheye` | 全球面（同 360） | 经 remap 后标准 UV | `fisheye_remap` Metal compute shader | 先 remap 为等矩，再球面显示 |

### 6.2 StereoLayout 的 UV 分割

| StereoLayout | 左眼 UV | 右眼 UV | 裁切方式 |
|---|---|---|---|
| `.mono` | 全帧 [0,0,1,1] | — | 无裁切 |
| `.sideBySide` | [0, 0, 0.5, 1.0] | [0.5, 0, 0.5, 1.0] | 水平二等分 |
| `.topBottom` | [0, 0, 1.0, 0.5] | [0, 0.5, 1.0, 0.5] | 垂直二等分 |

**当前实现**（`StereoMode.leftEyeUVRect`）已正确定义 SBS 和 OU 的 UV rect，与目标一致，但枚举名需从 `StereoMode` 改为 `StereoLayout`，并增加 `.mono` 值。

### 6.3 Panorama + Stereo 管线组合

对于全景立体内容（如 equirectangular360 + sideBySide）：
1. `PanoramaLayerBridge` 在帧复制时，通过 `stereoCropMode.leftEyeUVRect` 裁切左眼区域
2. 输出的 `LowLevelTexture` 是左眼的等矩纹理（宽度减半）
3. `PanoramaSphereEntity` 将此纹理映射到球面内壁
4. **MVP 局限**：只渲染左眼，visionOS 两眼看到相同画面（无立体深度感）
5. **完整 3D** 需要双 `LowLevelTexture`（左/右眼各一个）+ RealityKit 立体投影 API

---

## 7. 当前代码实现状态

### 7.1 已实现的组合

| 组合（当前枚举） | 实现状态 | 代码位置 |
|---|---|---|
| `.flat` + `.window` | 完整 | `PanoramaLayerBridge`（直通窗口，不走 bridge） |
| `.flat` + `.immersive` | 完整 | `VirtualScreenEntity` + `PanoramaLayerBridge` |
| `.panorama360` + `.panorama` | 完整 | `PanoramaSphereEntity` (full360) + bridge |
| `.panorama180` + `.panorama` | 完整 | `PanoramaSphereEntity` (front180) + 自定义半球 mesh |
| `.fisheye` + `.panorama` | 完整 | bridge + `fisheye_remap` Metal shader |
| `.stereoscopicSBS` + `.window/immersive` | 完整（左眼裁切） | `PanoramaLayerBridge.stereoCropMode = .sideBySide` |
| `.stereoscopicOU` + `.window/immersive` | 完整（左眼裁切） | `PanoramaLayerBridge.stereoCropMode = .overUnder` |
| `.stereoscopicSBS` + `.panorama` | 完整（左眼裁切球面） | `ImmersiveSpaceView.stereoModeForCurrentProjection()` |
| `.stereoscopicOU` + `.panorama` | 完整（左眼裁切球面） | 同上 |

> 注：`.stereoscopicSBS`/`.stereoscopicOU` 是旧枚举，混合了投影类型和立体布局。重构后分别映射为：
> - `stereoscopicSBS` → `projectionType = .flat, stereoLayout = .sideBySide`（如为 flat 3D 内容）
> - `panorama360 + stereo` → `projectionType = .equirectangular360, stereoLayout = .sideBySide/topBottom`

### 7.2 缺失的实现

| 缺失项 | 原因 | 优先级 |
|---|---|---|
| `StereoLayout.mono` 枚举值 | 当前 `StereoMode` 缺 `.mono` | **P0** — 重构必须 |
| `MediaProfile.stereoLayout` 字段 | `MediaProfile` 无此字段 | **P0** — 重构必须 |
| `ProjectionDetection` StereoLayout 检测 | 当前只返回 `ProjectionType`（混合轴） | **P0** — 重构必须 |
| `DecidePlaybackModeUseCase` 三轴路由 | 当前不感知 StereoLayout | **P1** |
| flat+stereo → Immersive 自动路由 | 依赖上一项 | **P1** |
| fisheye + stereo 裁切+remap 管线 | 需要 2-pass：先裁切再 remap | **P2** — 初期可禁用 |
| 真正双眼立体渲染（左+右眼各一份） | 需 RealityKit 立体 API | **P3** — 超出 MVP 范围 |

### 7.3 `DecidePlaybackModeUseCase` 现状

```swift
// 当前实现（仅 isPanoramic 判断，不感知 stereo）
public func decideMode(for profile: MediaProfile, isEnvironmentActive: Bool, manualOverride: PlaybackMode?) -> PlaybackMode {
    if profile.projectionType.isPanoramic { return .panorama }
    if isEnvironmentActive { return .immersive }
    return .window
}
```

**缺口**：flat + sideBySide/topBottom 内容会被路由到 `.window`，而目标是路由到 `.immersive`。

---

## 8. 重构映射表（旧枚举 → 三轴）

| 旧 ProjectionType | 新 ProjectionType | 新 StereoLayout | 说明 |
|---|---|---|---|
| `.flat` | `.flat` | `.mono` | 普通 2D 平面 |
| `.stereoscopicSBS` | `.flat` | `.sideBySide` | 平面 3D SBS |
| `.stereoscopicOU` | `.flat` | `.topBottom` | 平面 3D OU |
| `.panorama360` | `.equirectangular360` | `.mono` | 360° 2D 全景 |
| `.panorama180` | `.equirectangular180` | `.mono` | 180° 2D 全景 |
| `.fisheye` | `.fisheye` | `.mono` | fisheye 2D |

**注意**：旧枚举中没有 panorama + stereo 的直接表示，实际内容（如 3D VR 360 SBS）目前通过文件名约定或用户手动切换处理，重构后由 `ProjectionDetection` 同时检测投影和立体。

---

## 9. 关键约束边界条件

1. **用户手动切换限制**：`allowedModes(for:)` 确保 flat 内容无法手动切换到 Panorama（已实现）
2. **3D 降格**：stereo 内容用户可关闭 3D（不设置 stereoCropMode）→ 全帧显示。mono 内容的 3D 开关应在 UI 层灰色禁用（待实现）
3. **投影覆盖（projectionOverride）**：`AppModel.projectionOverride` 允许用户手动覆盖检测结果，触发 `autoRoutePlaybackMode()` 重路由。重构后此机制需同时覆盖 stereoLayout 覆盖
4. **Window 模式的 fisheye/equirect**：内容可在 Window 模式预览，但体验为失真平铺，UI 应提示"建议切换到全景模式"

---

## 10. 结论与建议

### 核心发现

1. **36 种组合中仅 3 种严格非法**（flat + panorama），其余 33 种均技术可行
2. **当前旧枚举已覆盖主要用例**，但混合了投影和立体两个维度，导致 flat+stereo 和 panorama+stereo 的组合逻辑耦合
3. **渲染管线已支持 SBS/OU 的左眼裁切**（`PanoramaLayerBridge.stereoCropMode`），重构后需确保 `StereoLayout` 到 `stereoCropMode` 的映射保持正确
4. **`DecidePlaybackModeUseCase` 需扩展**，加入 stereoLayout 轴的路由逻辑（flat+stereo → immersive）
5. **fisheye + stereo** 现实极罕见且管线不支持，初期强制 mono 降格处理

### 重构优先级

| 优先级 | 任务 |
|--------|------|
| P0 | 拆分 `ProjectionType` 旧枚举，新增 `StereoLayout`（含 `.mono`），更新 `MediaProfile` |
| P0 | 重构 `ProjectionDetection` 返回 `(ProjectionType, StereoLayout)` 元组 |
| P1 | 更新 `DecidePlaybackModeUseCase` 感知 stereoLayout（flat+stereo → immersive） |
| P1 | UI 层 3D 开关的 mono 禁用逻辑 |
| P2 | fisheye + stereo 的 2-pass 管线（裁切 + remap）|
| P3 | 真正双眼立体渲染（RealityKit 立体 API）|
