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
