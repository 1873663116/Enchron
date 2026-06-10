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

## 5. 阶段 2 验证序列（每个实验回答一个问题）

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
E6 窗口回归：自产 xcframework 替换 MPVKit 官方包，窗口模式 A/B 同片源对比
   → 验证：行为等价（含 HDR/EDR 路径）。回答 C4
∥  HDR 并行实验（C9）：纯 RealityKit，与 E1-E6 无依赖，随时可做
```

依赖关系：E1 → E2 → E3/E4 → E5；E6 在 E1 后即可做。E2 失败则回到 fork 调整导入机制（影响出口契约形状），这是「先验证后重构」顺序的依据。

注：将 MPVKit 官方包替换为自产 xcframework 属于依赖变更，为人类裁决项（CLAUDE.md 边界），到 E6 时显式决策。

## 6. 风险与开放问题

- **C6 是单点最大未知**：MoltenVK 在 visionOS 上对 `VK_EXT_metal_objects` 的支持状态未经本项目验证，需 E2 实证；失败的备选是改用 MoltenVK 的 IOSurface 直接导入路径或 CVPixelBuffer 中介（届时出契约修正）。
- HDR：出口 B 契约当前为 SDR；沉浸 HDR 取决于 C9 实验，是 PRD 范围决策的输入而非既成能力。
- `macvk_resident` 命名带 `mac` 但设计为 darwin 通用，阶段 2 落地后宜在 fork 侧统一命名（命名约定工作的一部分）。
- 现 `PanoramaLayerBridge` 的 fisheye / stereo 处理迁移（§3 功能继承清单），新消费端设计时纳入。
- License：MPVKit-GPL + fork（GPL/LGPL）是既有事实，发布姿态在 PRD 中显式记录，人类裁决。

## 7. 文档体系衔接

- 本文结论在 E1-E6 取证后凝结为 `docs/contracts/frame-pipeline.md`（出口 API 语义、双缓冲、色彩契约、切换语义、平台矩阵）；contract 先于 App 核心重构定稿。
- 新术语（常驻纹理出口、双缓冲环、front 发布、出口 A/B 的正式命名）经 `docs/ubiquitous_language.md` 收编后再进入代码与 contract。
- fork 仓库 `CLAUDE.md`「解耦边界」一节中「visionOS 上两种模式都应走 IOSurface 出口」的表述按本文 §1 模型更新（窗口模式走 moltenvk 出口 A；该更新需在 fork 仓库的会话中完成）。
