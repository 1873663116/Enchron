# Overnight Log — v2 三种播放路径完整实现

---
## Round 1 — 2026-04-02T13:20:00+08:00

**Pipeline State**: (init) → PLANNING
**本轮目标**: T0.1 全文档审计与功能清单提取
**完成情况**:
- [AGENT] doc-audit-requirements (Sonnet) → 读取 product_philosophy + Requirements.md | 提取 89 个功能点，按 7 模块分组
- [AGENT] doc-audit-design (Sonnet) → 读取 design_docs/ 8 个文件 | 提取 14 个 protocol 完整签名 + 领域模型 + 实施路线图
- [AGENT] doc-audit-contracts (Sonnet) → 读取 contracts/ + REGRESSION.md | 4 个 API 端点 + 34 条活跃回归项
- [AGENT] code-audit (Sonnet) → 审计 SpatialScene/PlayerUI/PlaybackCore/Persistence/Settings | 逐功能判定实现状态
- 综合产出 ExecPlan010: 42 个功能点 × 实现状态（16 ✅ / 9 🔶 / 15 ❌ / 2 🔲）

**核心发现**:
- 沉浸影院模式几乎全部缺失（17 项中仅 1 项完全实现）：VirtualScreenEntity 不存在，环境系统不存在，位置 UI 存在但无 3D 消费者
- 全景模式只有 360° 可用（8 项中 2 项完成）：180°/SBS/OU/鱼眼全部未实现
- 播放模式路由断裂：AppCoordinator.decidePlaybackMode 存在但未接入 PlaybackLaunchCoordinator
- 窗口模式已完整（10/10），v1 overnight 产出可信

**Decision Log**:
- [AUTO] 审计并行策略 | 4 Sonnet subagent 并行 | P3+P6 | 文档量大，最高效
- [AUTO] 功能清单范围 | 聚焦三种播放路径 + 占位清除 | P3 | TODOS.md 范围已界定

**测试状态**: swift test: 未执行（本轮为文档审计轮）| 基线: 205 passed
**下轮应做**: T0.2 — API 调研（context7 MCP：RealityKit 虚拟屏幕、Metal SBS/OU shader、环境切换、180° 裁剪）
**Status**: IN_PROGRESS

---
## Round 2 — 2026-04-02T14:45:00+08:00

**Pipeline State**: PLANNING → PLANNING
**本轮目标**: T0.2 — context7/deepwiki API 调研（8 课题 + 代码审计）
**完成情况**:
- [AGENT] research-realitykit (Sonnet) → context7 MCP 调研 R1-R4 | Material 选型、Mesh API、环境切换、位置控制完整方案
- [AGENT] research-metal (Sonnet) → context7 MCP 调研 M1-M4 | SBS/OU 统一 shader、180° UV 裁剪、鱼眼重映射完整 shader 代码
- [AGENT] research-deepwiki (Sonnet) → deepwiki 调研 Apple visionOS 示例 | Hello World/Destination Video 模式参考
- [AGENT] code-audit-pipeline (Explore) → 现有渲染管线全文审计 | PanoramaLayerBridge/PanoramaSphereEntity/VideoShaders/AppCoordinator 完整状态

**核心架构决策 (9 项)**:
- [D1] Material = UnlitMaterial（复用现有管线，mpv 非 AVPlayer 故 VideoMaterial 不可用）
- [D2] 纹理源 = 复用 PanoramaLayerBridge 的 TextureResource（播放模式互斥）
- [D3] 曲面屏幕 = generateCylinder + faceCulling=.front（RealityKit 无原生 curvedPlane）
- [D4] 环境切换 = Sky dome Entity 材质参数替换（无需重开 ImmersiveSpace）
- [D5] 暗黑影院 = 纯色 UnlitMaterial（无需 Skybox 资产）
- [D6] SBS/OU = 统一 compute kernel + mode 参数
- [D7] 180° 裁剪 = LowLevelMesh 自定义 UV（U=[0.25,0.75]）
- [D8] 鱼眼重映射 = GPU compute + 双线性采样（4K 约 2-5ms）
- [D9] Stereo 3D = 左右眼各一个 PanoramaSphereEntity

**Decision Log**:
- [AUTO] Material 选型 | UnlitMaterial over ShaderGraphMaterial | P5+P3 | 现有管线已验证，ShaderGraphMaterial 需 RCP 过重
- [AUTO] 纹理源复用 | PanoramaLayerBridge 共享 | P3+P4 | 播放模式互斥，零额外开发
- [AUTO] 曲面实现 | generateCylinder 近似 | P3 | 无原生 API，圆柱内侧效果足够
- [AUTO] 调研并行策略 | 3 Sonnet + 1 Explore 并行 | P6 | 4 个独立课题组，最大化吞吐

**测试状态**: swift test: 未执行（本轮为调研轮）| 基线: 205 passed
**下轮应做**: T0.3 — 综合测试计划设计（基于功能清单 + 调研结果，为每个功能设计测试用例 ≥ 40）
**Status**: IN_PROGRESS

---
## Round 3 — 2026-04-02T16:10:00+08:00

**Pipeline State**: PLANNING → PLANNING
**本轮目标**: T0.3 — 综合测试计划设计
**完成情况**:
- 审查现有测试结构（6 个测试文件，205 tests，全部 import XrPlayerCore）
- 审查 Package.swift 的 XrPlayerCore target sources（59 个源文件）
- 审查 SavedScreenPosition/ScreenPositionStoring/ProjectionDetection/AppCoordinator 当前实现状态
- 设计 43 个新测试用例（超过 40 最低要求），覆盖 8 个测试文件
- 设计 8 条 E2E 测试路径（供 /qa Simulator 测试），覆盖全部三种播放模式
- 建立功能 → 测试覆盖矩阵（42 功能中 37 个有测试覆盖，5 个为已完成功能已有测试）
- 完整产出写入 ExecPlan012

**测试计划摘要（43 tests × 8 files）**:
- CinemaEnvironmentTests (6): 环境枚举 3 case + skybox 映射 + Codable
- VirtualScreenConfigTests (7): 屏幕形状 + 尺寸校验 + 切换逻辑
- ScreenPositionValidationTests (5): distance/angle/offset clamping + 默认工厂
- StereoFrameSplitTests (7): SBS/OU UV 区域 + 输出尺寸计算
- HemisphereMeshConfigTests (4): 180° UV 范围 + 经度范围 + 顶点数
- FisheyeRemapConfigTests (3): FOV 默认值 + 中心映射 + 越界处理
- PlaybackModeRoutingTests (6): UseCase + 手动覆盖 + 决策矩阵扩展
- ProjectionDetectionExtendedTests (5): fisheye 检测 + ProjectionType 计算属性

**FAIL 分类**: 33 新类型 stub / 4 缺少校验 / 3 缺少计算属性 / 2 缺少分支 / 1 协议不存在

**Decision Log**:
- [AUTO] 测试策略 | stub + FAIL 而非编译错误 | P1+P5 | 编译通过才能运行旧测试
- [AUTO] Stub 位置 | 域层而非测试层 | P4+P5 | Stub 就是最终类型骨架，Phase 1 直接填充
- [AUTO] E2E 路径数 | 8 条路径 | P1+P2 | 覆盖三种播放模式 + 交叉验证 + 手动覆盖
- [AUTO] 测试文件拆分 | 每个域一个文件 | P3 | 清晰映射，独立运行

**测试状态**: swift test: 未执行（本轮为计划设计轮）| 基线: 205 passed
**下轮应做**: T0.4 — 对抗性审查（三阶段裁决：Codex 挑战 → Counter-Agent 反驳 → Opus 裁决）
**Status**: IN_PROGRESS

---
## Round 4 — 2026-04-02T17:30:00+08:00

**Pipeline State**: PLANNING → PLANNING
**本轮目标**: T0.4 — 对抗性审查（三阶段裁决）
**完成情况**:
- [SKILL] /codex:adversarial-review → 5 条挑战（3 HIGH, 0 MEDIUM→1 MEDIUM, 1 process）
- [AGENT] Counter-Agent (Sonnet) → 逐条评估 | REJECT×3, PARTIAL ACCEPT×2
- [OPUS] Supervisor 裁决 → 驳回×3, 部分采纳×1, 采纳降级×1

**Codex 挑战 → 裁决摘要**:
1. EP013 执行记录为空 → **驳回**（自指问题，文档正在执行中）
2. C1 MediaProfile 零覆盖 → **驳回**（Codex 事实错误，V02Tests.swift 有 4 个 MediaProfileTests）
3. A15 SceneSelector 代理测试 → **部分采纳**（补覆盖矩阵注释，E2E 已覆盖接线）
4. GPU 渲染无确定性检查 → **驳回**（visionOS Simulator 无 Metal GPU 是硬约束，域层数学已测）
5. E2E 断言主观 → **采纳降级**（状态转换步骤量化，渲染质量标注 HUMAN VISUAL）

**测试计划影响**: 43 单元测试 + 8 E2E 路径不变。变更仅为文档修订（覆盖矩阵注释 + E2E 描述改进 + 已知局限节）

**Decision Log**:
- [AUTO] C1 驳回 | 自指问题 | P5 | EP013 正在执行中
- [AUTO] C2 驳回 | Codex 事实错误 | P5 | V02Tests.swift:7 有 MediaProfileTests
- [AUTO] C3 部分采纳 | 补注释不加测试 | P1+P5 | E2E P2-S3/S10/S11 覆盖选择器
- [AUTO] C4 驳回 | Simulator 硬约束 | P3 | 域层数学已有确定性测试
- [AUTO] C5 采纳降级 | E2E 描述分类 | P1+P5 | 状态量化 + 渲染标注人工

**测试状态**: swift test: 未执行（本轮为审查轮）| 基线: 205 passed
**下轮应做**: T0.5 — 测试代码落地（创建 stub 类型 + 编写 43 个测试 + swift test 确认红色 + git commit）
**Status**: IN_PROGRESS

---
## Round 5 — 2026-04-02T18:15:00+08:00

**Pipeline State**: PLANNING → EXECUTING
**本轮目标**: T0.5 — 测试代码落地
**完成情况**:
- [AGENT] stub-creator (Sonnet) → 创建 9 个 stub 源文件 + 更新 Package.swift（12 新 source entries）
- [AGENT] test-creator (Sonnet) → 创建 8 个测试文件（43 tests） + 修改 ProjectionType.swift（+3 stub 计算属性）
- `swift test`: 248 tests executed, 1 skipped, 43 FAILED (all new), 205 PASSED (all old)
- git commit: bb83631

**新增文件 (20 files changed, 696 insertions)**:
- 9 stub 源文件: SpatialSceneDomain + CinemaEnvironment + ScreenGeometry + VirtualScreenConfiguration + HemisphereMeshConfiguration + FisheyeRemapConfiguration + StereoMode + PlaybackModeManaging + DecidePlaybackModeUseCase
- 8 测试文件: CinemaEnvironmentTests(6) + VirtualScreenConfigTests(7) + ScreenPositionValidationTests(5) + StereoFrameSplitTests(7) + HemisphereMeshConfigTests(4) + FisheyeRemapConfigTests(3) + PlaybackModeRoutingTests(6) + ProjectionDetectionExtendedTests(5)
- Package.swift: +12 source paths (9 new stubs + 3 existing deps)
- ProjectionType.swift: +3 stub computed properties (isStereo3D, requiresHemisphereMesh, requiresFisheyeRemap)

**Phase 0 退出条件验证**:
- ✅ T0.1 全文档审计 (Round 1)
- ✅ T0.2 API 调研 (Round 2)
- ✅ T0.3 测试计划设计 (Round 3)
- ✅ T0.4 对抗性审查三阶段裁决 (Round 4)
- ✅ T0.5 测试代码落地: 43 新测试全 FAIL, 205 旧测试全 PASS
- → **Phase Transition: PLANNING → EXECUTING**

**Decision Log**:
- [AUTO] Stub 设计 | displayName 属性拦截纯结构测试 | P1+P5 | 确保 43/43 全 FAIL
- [AUTO] Package.swift | 同时加入 3 个已有但未列入的文件 | P4 | SavedScreenPosition/FileIdentifier/PlaybackMode 为测试编译依赖
- [AUTO] Phase Transition | PLANNING 5 项全部完成 | P6 | 退出条件明确满足

**测试状态**: swift test: 248 total | 205 passed | 43 failed | 1 skipped | 新增: 43 | FAIL: all 43 new tests
**下轮应做**: T1.1 — 沉浸影院模式：虚拟屏幕实体（VirtualScreenEntity + 平面/曲面 mesh + 纹理桥接）
**Status**: IN_PROGRESS

---
## Round 6 — 2026-04-02T22:20:00+08:00

**Pipeline State**: EXECUTING → EXECUTING
**本轮目标**: T1.1 — 沉浸影院模式：虚拟屏幕实体
**完成情况**:
- 填充 CinemaEnvironment stub: displayName（暗黑影院/星空夜景/自然日落）+ skyboxAssetName（nil/StarryNight/SunsetNature）→ 6 tests PASS
- 填充 VirtualScreenConfiguration stub: aspectRatio（flat=w/h, curved=arcWidth/h）+ init width clamping [1.0,10.0] + switchToCurved 保持高度 → 7 tests PASS
- [AGENT] Sonnet subagent → 创建 VirtualScreenEntity.swift（enum + 4 static methods）+ 更新 ImmersiveSpaceView（.immersive 分支接入虚拟屏幕）
- VirtualScreenEntity: makeEntity / updateTexture / switchGeometry / updatePosition
- ImmersiveSpaceView: @State virtualScreenEntity 管理生命周期，.panorama/.immersive/.window 三态互斥清理
- git commit: 848f8a2

**核心实现决策**:
- VirtualScreenEntity 遵循 PanoramaSphereEntity 的 enum+static 模式
- Flat: MeshResource.generatePlane(width:height:) xy-plane
- Curved: MeshResource.generateCylinder + scale.x *= -1（内侧渲染）
- switchGeometry: 先 abs(scale.x) 重置再按需翻转，确保 curved→flat→curved 正确
- 纹理复用: PanoramaLayerBridge.textureResource 共享（播放模式互斥）
- 位置: SIMD3(0, verticalOffset, -distance) + simd_quatf X轴旋转

**Decision Log**:
- [AUTO] VirtualScreenEntity 模式 | enum+static 与 PanoramaSphereEntity 一致 | P4+P5 | 复用已验证模式
- [AUTO] 曲面法线翻转 | scale.x *= -1 | P3 | 与 PanoramaSphereEntity 同一技巧
- [AUTO] Settings 屏幕形状 UI | 推迟到 T1.2 一起做 | P3 | 位置控制 + 形状选择天然一组

**测试状态**: swift test: 248 total | 218 passed | 30 failed (test cases) | 1 skipped | T1.1 目标 13 tests 全部 PASS
**下轮应做**: T1.2 — 屏幕位置控制（SavedScreenPosition clamping + ScreenPositionStoring 环境独立记忆 + Settings 屏幕形状选择）
**Status**: IN_PROGRESS

---
## Round 7 — 2026-04-02T14:30:00+08:00

**Pipeline State**: EXECUTING → EXECUTING
**本轮目标**: T1.2 — 沉浸影院模式：屏幕位置控制
**完成情况**:
- SavedScreenPosition.init 添加 clamping: distance [2.0, 20.0], verticalOffset [-5.0, 5.0], viewAngle [-45.0, 45.0] → 5 ScreenPositionValidationTests PASS
- AppModel: 新增 currentCinemaEnvironment + screenShape 属性，save/load 改用环境键
- AppModel: 新增 switchEnvironment(to:) → save old env position → switch → load new env position
- SettingsView: "Immersive Space" section 新增 Screen Shape Picker (Flat/Curved) + Cinema Environment Picker (3 环境)
- ImmersiveSpaceView: .immersive 分支传入 appModel.screenShape，运行时 switchGeometry
- git commit: 68ec753

**核心实现决策**:
- 环境 Picker 使用 @State selectedEnvironment 中转，避免 Binding 直接绕过 switchEnvironment 的 save/load 逻辑
- ScreenPositionStoring 已由 SwiftDataStore 实现（UserDefaults JSON 编码），无需新增适配器
- ScreenPositionControlView 的 onChange 调用 appModel.saveScreenPosition() 自动使用当前环境键

**Decision Log**:
- [AUTO] Clamping 策略 | init 内 min/max | P5+P3 | 最简洁，与 VirtualScreenConfiguration 风格一致
- [AUTO] 环境 Picker 绑定 | local @State + onChange switchEnvironment | P5 | 避免 Binding 直接变更跳过 save/load
- [AUTO] 屏幕形状默认值 | flat(2.4, 1.35) + curved(radius: 3.0, height: 1.35) | P3 | 16:9 比例 + 合理曲率

**测试状态**: swift test: 248 total | 223 passed | 25 failed (test cases) | 1 skipped | T1.2 目标 5 tests 全部 PASS
**下轮应做**: T1.3 — 3 个沉浸式环境（Sky dome Entity + 材质参数替换 + SceneSelectorView 功能化）
**Status**: IN_PROGRESS

---
## Round 8 — 2026-04-02T14:45:00+08:00

**Pipeline State**: EXECUTING → EXECUTING
**本轮目标**: T1.3 — 3 个沉浸式环境
**完成情况**:
- [NEW FILE] EnvironmentDomeEntity.swift — 50m 半径反转球体，UnlitMaterial 纯色渲染，3 种环境颜色映射
  - darkTheatre: 近黑 (0.02 white)
  - starryNight: 深海军蓝 (0.01, 0.01, 0.06)
  - sunsetNature: 暗琥珀 (0.15, 0.08, 0.03)
- [MODIFIED] ImmersiveSpaceView.swift — 新增 @State environmentDomeEntity, .immersive case 创建 dome + screen, 环境切换走 switchEnvironment 材质替换, .panorama/.window 清理 dome
- [MODIFIED] SceneSelectorView.swift — ForEach CinemaEnvironment.allCases 替代 4 个占位按钮, 绑定 appModel.switchEnvironment(to:), 环境专属 SF Symbol (moon.fill/star.fill/sun.horizon.fill)
- git commit: 8828ff2

**核心实现决策**:
- Sky dome 半径 50m（虚拟屏幕最远 20m，dome 在屏幕外侧）
- 一个 dome entity 复用，切换环境只替换材质（D4 决策执行）
- 暗黑影院纯色无纹理（D5 决策执行）
- 星空/日落暂用纯色（无 skybox 纹理资产），后期可替换为真实纹理
- 环境切换不中断播放：dome 材质替换 + 位置自动恢复（T1.2 的 switchEnvironment 逻辑）

**Decision Log**:
- [AUTO] Sky dome 半径 | 50m | P3 | 虚拟屏幕最远 20m，dome 必须在外侧
- [AUTO] 环境颜色 | 纯色 UnlitMaterial | P3+P6 | 无纹理资产，纯色足以验证切换功能
- [AUTO] SceneSelectorView 按钮数 | 3（from 4 占位）| P5 | 与 CinemaEnvironment.allCases 精确匹配

**测试状态**: swift test: 248 total | 223 passed | 25 failed (test cases) | 1 skipped | T1.3 无专属 failing test（CinemaEnvironment 6 tests 已在 R6 通过）
**下轮应做**: T1.4 — 全景视频完善（180° 半球裁剪 + Stereo 3D SBS/OU + 鱼眼重映射 + 投影覆盖 UI）
**Status**: IN_PROGRESS
