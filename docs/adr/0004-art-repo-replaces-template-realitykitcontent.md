# ADR-0004：美术仓库取代模板 RealityKitContent

- 状态：已接受
- 日期：2026-06-14
- 决策者：项目负责人

## 背景

app 的 `Packages/RealityKitContent/` 目前是 visionOS 模板自带内容（`Package.realitycomposerpro`
+ `.rkassets`：`Immersive.usda` / `Scene.usda` / `SkyDome.usdz`）。沉浸场景与材质的创作真相已迁到
独立姊妹仓库 `Xrplay_scene`（Reality Composer Pro 3 原生装配，见其 ADR-0003）。

## 决策

**模板 RealityKitContent 作废，由美术仓库 `Xrplay_scene` 的导出（RealityKitContent / USD）直接取代。**
app 不再维护模板内的场景/材质内容；`SpatialScene` 消费的 RealityKit 内容以美术仓库导出为准。

## 后果

- `Packages/RealityKitContent/` 现有模板内容视为**遗留占位**，待美术仓库产出就绪后替换。
- **具体集成机制（替换 / 复制 / submodule / 构建期导入）待美术仓库接近生产时另定**，必要时补 ADR——
  本 ADR 只确立「所有权归美术仓库」，不规定尚不存在的机制。
- 姊妹仓库关系记于 `CLAUDE.md`；美术侧细节见 `Xrplay_scene` 的 `CLAUDE.md` / ADR-0003。

## 关联

- `Xrplay_scene` ADR-0003（Godot → RCP3 转向）。
- 视频帧路径（mpv `IOSurface` → RealityKit 零拷贝，见 `mpv/CLAUDE.md`）与本决策正交。
