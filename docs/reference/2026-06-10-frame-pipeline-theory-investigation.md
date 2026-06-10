# 帧管线理论闭环调查 — 双出口 × 三种 PlaybackMode

Purpose: 把「mpv fork 双出口 × 三种 PlaybackMode」管线的理论可行性逐条钉到证据上，并给出阶段 2 的最小验证序列。
Status: Investigation（调查报告）。结论在阶段 2 实验取证后凝结进 `docs/contracts/`，本文不是 contract。
Owner/scope: 跨 XrPlayer 与 mpv fork（`github.com/1873663116/mpv`，`enchron` 分支）两仓库的管线事实。视频帧从解码到显示的完整链路。
Date: 2026-06-10

---

## 1. 统一管线模型

mpv 是唯一的帧生产者，带两条可切换的出口；三种 `PlaybackMode` 是出口的消费方式：

```
                         ┌─ 出口 A：swapchain（gpu-context=moltenvk）
                         │    mpv 直接渲染进 App 提供的 CAMetalLayer
  mpv (vo=gpu-next,      │    └─▶ 窗口模式（SwiftUI 窗口内的 layer）
  vulkan / MoltenVK) ────┤
                         └─ 出口 B：常驻纹理（gpu-context=macvk_resident + xr_resident_*）
                              mpv 渲染进 Swift 分配的双 IOSurface 环，原子发布 front
                              └─▶ 沉浸模式（RealityKit 虚拟屏幕材质采样）
                              └─▶ 全景模式（RealityKit 球体/半球内壁采样）
```

- 出口选择是 mpv 侧的运行时开关（`gpu-context` 属性 + `xr_resident_set_enabled`），目标形态为热切（`UPDATE_VO`，只重建 VO 不重启 mpv 实例）。
- 呈现决策（`PlaybackMode`）属于 `PlayerUI`，出口切换由 App 组装层执行，符合 ARCHITECTURE.md 既有不变量：`PlaybackCore` 报告帧，不决定呈现。
- 出口 A 在 visionOS 上可用的前提是 MPVKit 的 `0001-player-add-moltenvk-context.patch`（提供不依赖 AppKit 的 CAMetalLayer 挂接 context）。上游 mpv 自带的 `macvk` context 绑定 AppKit，仅服务 macOS 验证环境。

## 2. 证据底座（已证事实）

### 2.1 现 App 已在 visionOS 生产中跑通出口 A

代码与运行证据（XrPlayer 仓库）：

- `XrPlayer/PlaybackCore/Adapters/MPV/MPVConfiguration.swift` — `vo=gpu-next`、`gpu-api=vulkan`、`gpu-context=moltenvk`、`hwdec=videotoolbox`（VideoToolbox 输出 NV12 CVPixelBuffer，gpu-next 经 MoltenVK 零拷贝消费）。
- `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift:199` — CAMetalLayer 指针经 `wid` 传给 libmpv；layer 更换时整个 libmpv 实例冷重建。
- `XrPlayer/Shared/MPVNativeMetalLayerView.swift` — `MPVNativeMetalLayer`（CAMetalLayer 子类）挂进 SwiftUI 窗口。
- 依赖锁定：`XrPlayer.xcodeproj/.../Package.resolved` → `mpvkit/MPVKit` **0.41.0**（revision `613c0cc`）。

该路径在窗口模式下日常运行，是「visionOS 无 AppKit 也能跑 mpv 窗口渲染」的存在性证明。

### 2.2 fork 已在 macOS 验证出口 B 全链路（阶段 0a / 1）

证据（mpv fork `enchron` 分支，本地克隆 `/home/user/mpv`）：

- 出口 API：`include/mpv/xr_resident.h` 四函数（`set_enabled` / `configure_external_iosurfaces` / `front_iosurface_id` / `clear`）。
- 双 IOSurface 环：`video/out/vulkan/xr_resident_texture.m` — Swift 分配 2 张 IOSurface，mpv 交替写、原子发布 front ID（`g_front_id` 无锁读）；IOSurface → `MTLTexture` → 经 `VK_EXT_metal_objects` 导入为 `pl_tex`（参考上游 `hwdec_vt_pl.m` 模式）。
- 无窗生产者：`video/out/vulkan/context_mac_resident.m` — surfaceless context `macvk_resident`，建设备不建 swapchain/窗口；`vo_gpu_next` 无 swapchain 时把 IOSurface 当渲染目标渲染一次（ADR 0003）。
- 热切：运行时改 `gpu-context` 属性触发 `UPDATE_VO`，只重建 VO；macOS 验证 app（`xr-fork/verify/`）以 SIGUSR1/2 实测窗口 ↔ 沉浸往返。
- 色彩契约（ADR 0004）：出口 B 字节 = IEC sRGB / BT.709 / full-range / SDR；写端 `target-trc=srgb` + `treat-srgb-as-power22=input` + `target-colorspace-hint=no`，读端 `.rgba8Unorm_srgb` 视图 + `UnlitMaterial(applyPostProcessToneMap: false)`；窗口模式（macOS）`target-colorspace-hint=yes`。
- meson 守卫 `vulkan && darwin`，出口 B 源文件不依赖 cocoa/swift，visionOS 打包（cocoa 落空、swift-build 关闭）保留出口（ADR 0004 决策 3）。

### 2.3 MPVKit patch 与 fork 改动的重叠面（本次静态比对）

MPVKit **0.41.0** tag（本地克隆 `/home/user/MPVKit`）对 libmpv 仅有两个 patch：

| Patch | 触及文件 | 与 fork 重叠 |
|---|---|---|
| `0001-player-add-moltenvk-context.patch` | `meson.build`、`meson.options`、`video/out/gpu/context.c`、`video/out/vulkan/common.h`、新增 `video/out/vulkan/context_moltenvk.m` | **`meson.build` + `video/out/gpu/context.c`** 两处，均为「注册新 context / 新源文件」性质的加行 |
| `0002-revert-build-static.patch` | `osdep/mac/meson.build` | 无重叠 |

fork 触及的 mpv 文件（`git diff master enchron --stat`）：`meson.build`、`video/out/gpu/context.c`、`video/out/vulkan/context.{c,h}`、`video/out/vo_gpu_next.c`、新增 `context_mac_resident.m` / `xr_resident_texture.m` / `include/mpv/xr_resident.h`。

结论：重叠面与 fork CLAUDE.md 预判一致且性质良性——把 patch 0001 合入 `enchron` 分支是低风险机械合并；`context_moltenvk.m`、`common.h`、`meson.options` 与 fork 改动零交集。

### 2.4 打包路径存在

MPVKit 构建脚本（`Sources/BuildScripts/XCFrameworkBuild/main.swift`）：mpv 源固定 `github.com/mpv-player/mpv` `v0.41.0`（与 fork 基线一致），平台枚举含 `.xros` / `.xrsimulator`。fork CLAUDE.md 记载的打包路线（fork MPVKit、改源指向 `enchron` 分支、合并 patch、`make build platform=xros`）与脚本结构吻合。依赖链版本对齐（libplacebo 7.360.1、MoltenVK 1.4.1）出自 fork CLAUDE.md 记载，本次未独立复核。

## 3. 现状管线 vs 目标管线

| 维度 | 现状（MPVKit 0.41.0 官方包） | 目标（fork 双出口） |
|---|---|---|
| 窗口模式 | 出口 A：moltenvk swapchain → CAMetalLayer | **不变**（同一条路径，理论等价） |
| 沉浸/全景帧路径 | `PanoramaLayerBridge`：CADisplayLink 轮询 `MPVNativeMetalLayer.lastVendedDrawable`，blit/compute 拷贝进 `LowLevelTexture` | 出口 B：mpv 直写双 IOSurface 环，RealityKit 直接采样 front，零额外拷贝、无 drawable 劫持 |
| 撕裂防护 | 依赖 drawable 生命周期巧合 | 双缓冲 + front 原子发布（门①，ADR 0003） |
| 模式切换 | layer 更换 → libmpv 整体冷重建 | `gpu-context` 热切（`UPDATE_VO` 只重建 VO）；冷重建保留为保底路径 |
| 色彩语义 | drawable 格式跟随 layer（bgra8 / rgba16f + EDR 元数据） | 出口 B 有确定字节语义（IEC sRGB SDR 契约），可数值验收 |
| HDR | 窗口模式经 layer EDR（`HDRProbeController` / `EDRMetadataDescriptor`） | 窗口模式不变；出口 B 当前 SDR（tone-map 到 SDR），16F 扩展待真机裁决 |

**功能继承清单**（现 `PanoramaLayerBridge` 承载、迁移到出口 B 时必须保留的消费端处理）：

1. 立体裁切（SBS / TopBottom 取左眼，`stereoCropMode`）；
2. 鱼眼 → equirectangular 重映射（Metal compute `fisheye_remap`）；
3. 帧去重（同帧不重拷）→ 出口 B 由 front ID 变化天然取代；
4. 表面快照诊断（格式 / EDR / colorspace 记录）。

其中 1、2 在新管线中属于读端（RealityKit 采样侧或中间 compute），与出口契约正交，但迁移时不可丢失。

## 4. 关键论断与证据状态

| # | 论断 | 状态 | 证据 / 验证方法 |
|---|---|---|---|
| C1 | visionOS 窗口模式无需 AppKit：moltenvk context + CAMetalLayer + `wid` 可用 | **已证** | 现 App 生产运行（§2.1） |
| C2 | 出口 B 全链路（surfaceless 渲染、双缓冲、热切、色彩契约）在 macOS 成立 | **已证** | fork 阶段 0a/1 + verify app（§2.2） |
| C3 | MPVKit patch 0001 可低风险合入 enchron 分支 | **已证（静态）** | 重叠面比对（§2.3）；以实际合并 + 编译为最终判据 |
| C4 | 合并后 fork 在 visionOS 窗口模式与现 MPVKit 0.41.0 行为等价 | 理论 | 同基线 v0.41.0 + 同 patch + fork 对 swapchain 路径的 `!p->sw` 守卫（macOS 已证不扰动窗口行为）。验证：自产 xcframework 替换依赖后窗口模式 A/B 回归 |
| C5 | `macvk_resident`（surfaceless，不依赖 AppKit）在 visionOS 可初始化 | 理论 | ADR 0003 设计意图「macOS/visionOS 共用」。验证：visionOS 冒烟（E2） |
| C6 | `VK_EXT_metal_objects` 在 visionOS 的 MoltenVK 上可用，IOSurface → MTLTexture → `pl_tex` 导入成立 | 理论 | 代码以该扩展守卫（§2.2）。验证：E2 实验；这是阶段 2 最大的单点未知 |
| C7 | `moltenvk` ↔ `macvk_resident` 热切在 visionOS 干净（macOS 验证的是 `macvk` ↔ `macvk_resident`） | 理论 | 验证：E4。失败保底 = 现 App 已验证的冷重建模式 |
| C8 | sRGB 色彩契约在 visionOS 成立（P3 工作空间 + 系统 tone mapping 下 `_srgb` + Unlit 咬合） | 理论 | ADR 0004 推理依据社区报告。验证：E3 目检 + IOSurface 字节 vs `screenshot-to-file` 数值比对 |
| C9 | HDR 出口（rgba16Float + Unlit + 关 tone map 超过 SDR 白） | 开放 | 纯 RealityKit 真机实验（ADR 0004 决策 4），不依赖 mpv，可随时并行 |
| C10 | 出口 B 同步现为 `pl_gpu_finish` 全停，异步跨设备 fence 未做 | 已知欠账 | 性能项非正确性项；E5 真机帧率观察后决策 |
| C11 | 模拟器证据边界：xrsimulator 上 gpu-next 可运行（现 App 模拟器可播放，ASS 降级），但 MoltenVK / IOSurface / 合成行为与真机的差异未刻画 | 部分证据 | 阶段 2 模拟器先行、真机裁决 |

## 5. 架构分叉：出口拓扑（开放决策，挂在 E2/E3 证据之后）

「三种模式都消费常驻纹理」是一个真实的候选架构（fork CLAUDE.md 解耦边界一节的原始建议即此形态）。它包含两个独立决策：

**D1 — mpv 出口数量**

- 双出口（§1 模型，现验证路线）：窗口走出口 A，沉浸/全景走出口 B，模式切换 = `gpu-context` 热切或冷重建。
- 单出口：出口 B 常开，三种模式都消费常驻纹理；mpv 永远是生产者，`gpu-context` 永不切换。

单出口收益：

- 模式切换变成纯 App 侧呈现路由（SwiftUI 场景状态），无管线重建；窗口 ↔ 沉浸过渡可无缝衔接，两个消费者可同时采样同一环（交叉淡化成为可能）。
- C7（热切）从验证矩阵消失；C4 改写为窗口呈现质量裁决（并入 E6）。
- 现 App 的 `wid` 失效冷重建 hack 整体消失，窗口生命周期与 mpv 生命周期解耦。
- 验证面、色彩契约、消费端实现单一化；与产品哲学「不为窗口模式捷径牺牲沉浸场景演进」同向。

单出口代价（D1 的裁决依据）：

- **窗口 HDR 回退**：现 App 唯一建成的窗口 HDR 路径（`fbo-format=rgba16f` + layer EDR 元数据 + 诊断体系）在出口 A 上；出口 B 契约为 SDR，且 RealityKit 自定义纹理路径无文档化 EDR 出口（ADR 0004 决策 4）。C9 实验由可选升级为 D1 的前置输入。
- **节奏与缩放各多一跳**：出口 B 下 mpv 按音频时钟出帧（headless 无 display-resample），窗口尺寸变化依赖环重配或采样器缩放，比 swapchain 直出多一代重采样；感知影响未刻画，E6 并排观察。
- **风险集中**：C6 失败时，双出口仍可交付窗口模式产品；单出口则全线阻塞。故 E2 仍排最前，D1 决策必须等它。
- 全停/fence 欠账（C10）扩大到全部模式，async fence 优先级随 D1 取单出口而上升。

**D2 — 窗口呈现载体（若 D1 = 单出口）**

- RealityView 平面：与球面共用同一套采样/材质实现，最简。
- App 自有 CAMetalLayer blit（采样 front → 全屏四边形）：保留 layer 级 EDR/colorspace 控制，是窗口 HDR 路线的对冲（环升级 16F 后可接 EDR layer）；代价是多一个微型呈现器实现。

「单出口」与「全 RealityKit」是两个决策：D1 取单出口时，D2 仍可选 blit 载体保住 HDR 能力。

可逆性：出口 A（上游 swapchain + moltenvk patch）天然保留在 fork 中，D1 只决定 App 消费哪个出口，可回退；出口 A 并继续充当色彩/质量对照组（ADR 0004 的发现方式正依赖双出口对照）。

## 6. 阶段 2 验证序列（每个实验回答一个问题）

```text
E1 打包脊柱：fork MPVKit → patch 0001/0002 合入 enchron → make build platform=xros
   → 验证：xcframework 产出且含 xr_resident 符号（nm 检查）。回答 C3 终判
E2 出口 B 冒烟：最小 visionOS host 初始化 macvk_resident + 配置双 IOSurface
   → 验证：front ID 开始翻转、采样非空。回答 C5、C6（阶段 2 最大风险，最先打）
E3 贴面与色彩：front 纹理上球面与平面，标准片源目检 + 数值比对
   → 验证：几何正确、无结构性色偏。回答 C8
E4 切换语义：moltenvk ↔ macvk_resident 热切往返
   → 验证：往返 10 次无泄漏/黑帧/死锁；失败则采用冷重建保底并记录。回答 C7
E5 真机一致性：撕裂观察 + 帧率/功耗采样（Instruments）
   → 验证：无可见撕裂；决定 fence 是否进生产前置。回答 C10
E6 窗口呈现裁决：自产 xcframework 下，同片源并排对比——出口 A 窗口 vs
   出口 B 窗口（RealityView 平面 / blit 载体）
   → 验证：画质、缩放、节奏、HDR/EDR、功耗。回答 C4（等价性）并裁决 §5 的 D1/D2
∥  HDR 并行实验（C9）：纯 RealityKit，与 E1-E6 无依赖；若 §5 走向单出口，它是 D1 前置输入
```

依赖关系：E1 → E2 → E3/E4 → E5；E6 在 E1 后即可做。E2 失败则回到 fork 调整导入机制（影响出口契约形状），这是「先验证后重构」顺序的依据。D1/D2（§5）在 E2/E3 + E6 证据后裁决，属人类决策。

注：将 MPVKit 官方包替换为自产 xcframework 属于依赖变更，为人类裁决项（CLAUDE.md 边界），到 E6 时显式决策。

## 7. 风险与开放问题

- **C6 是单点最大未知**：MoltenVK 在 visionOS 上对 `VK_EXT_metal_objects` 的支持状态未经本项目验证，需 E2 实证；失败的备选是改用 MoltenVK 的 IOSurface 直接导入路径或 CVPixelBuffer 中介（届时出契约修正）。
- HDR：出口 B 契约当前为 SDR；沉浸 HDR 取决于 C9 实验，是 PRD 范围决策的输入而非既成能力。
- `macvk_resident` 命名带 `mac` 但设计为 darwin 通用，阶段 2 落地后宜在 fork 侧统一命名（命名约定工作的一部分）。
- 现 `PanoramaLayerBridge` 的 fisheye / stereo 处理迁移（§3 功能继承清单），新消费端设计时纳入。
- License：MPVKit-GPL + fork（GPL/LGPL）是既有事实，发布姿态在 PRD 中显式记录，人类裁决。

## 8. 文档体系衔接

- 本文结论在 E1-E6 取证后凝结为 `docs/contracts/frame-pipeline.md`（出口 API 语义、双缓冲、色彩契约、切换语义、平台矩阵）；contract 先于 App 核心重构定稿。
- 新术语（常驻纹理出口、双缓冲环、front 发布、出口 A/B 的正式命名）经 `docs/ubiquitous_language.md` 收编后再进入代码与 contract。
- fork 仓库 `CLAUDE.md`「解耦边界」一节中「visionOS 上两种模式都应走 IOSurface 出口」的表述按本文 §1 模型更新（窗口模式走 moltenvk 出口 A；该更新需在 fork 仓库的会话中完成）。
