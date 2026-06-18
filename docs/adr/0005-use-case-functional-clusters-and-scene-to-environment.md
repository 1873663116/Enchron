# ADR-0005：用例表功能簇重构 + Scene→Environment 改名

- 状态：已接受（第 3 点「ID 前缀沿用 `SCEN`」于 2026-06-18 被 ADR-0006 推翻，改用 `ENV`）
- 日期：2026-06-17
- 决策者：项目负责人（经一轮逐 surface 采访）

## 背景

`docs/use_cases.md`（立档见 ADR-0003）初版为「每章一张大平表」，五章（Launch/Files/Settings/Playback/Scene）内各自一长串行，人类与 agent 阅读都「应接不暇」，且粒度无明确判据。同时，领域概念「Scene」（场景卡片选择的沉浸观影环境）与 SwiftUI 的 `Scene` 协议（`WindowGroup`/`Window`/`ImmersiveSpace` 等窗口/空间容器，经 Apple 文档确认）命名冲突；FakeApp 阶段将大量使用 SwiftUI `Scene`，同一代码库里「Scene」会有两个意思。

## 决策

1. **功能簇结构**：每章按功能簇分组（`###` 子标题 + 一句职责），顶部加索引；保留 surface 为顶层轴（承载 `accessibilityIdentifier` 锚点与测试归属）。
2. **粒度判据入宪章**：一条用例 = 一个可观察断言 = 一个 UI 测试；附「偏粗要拆 / 偏细要并 / 负路径与模式各占一条」决策程序。
3. **Scene→Environment 改名**：领域术语「Scene」改为「Environment（环境）」，入册 `CONTEXT.md`；用例表章名改 Environment。**ID 前缀沿用 `SCEN`**——`UC-SCEN-NN` 不改，因宪章「ID 永不复用、不承载语义」，churn 全部 ID 仅为前缀对齐不值当，前缀作不透明遗留标识。
4. **Advanced 画面参数 = libplacebo 全集**：播放设置面板 Advanced 分区的参数源 = mpv（gpu-next/libplacebo）暴露的可调项（出处 `~/Applications/mpv/xr-fork/verify-visionos`），以官方名替换测试 app 的临时命名；落用例表为 1 条（`UC-PLAY-28`）+ 参数附录；只读焊死项（`target-prim`/`target-trc`）作信息行不可交互。
5. **诊断不进表**：Settings → Advanced 的 28 项工程/诊断工具按宪章「内部机制不进表」不逐条立用例，只记一条「面存在」（`UC-SET-20`）。

## 后果

- 排序规则修订：章内按簇分组、簇内按动线；ID 序号在簇内不连续属正常，仍永不复用。
- 本轮退役：过滤（FILE-21/22）、最近播放（FILE-29/30/31）、卡片元数据并入 hover（FILE-25）、全局默认倍速（SET-03）、沉浸开关/风格/形状移至别处（SET-04/05/06）、缓存空禁用并入 SET-09（SET-10）、顶栏元数据条（PLAY-20）。详见用例表退役名单。
- 本轮新增：本地文件管理（FILE-40~43）、播放设置面板簇（PLAY-25~28）、⋯ 菜单/时间轴/窗口反向缺口（PLAY-29/30/31）、Settings 反向缺口（SET-17/18/19/20）、场景选择反向缺口与真接（SCEN-15~18）。
- **代码改名 sweep**：`SceneCard`/`SceneCardCarousel`/`FeaturedScene`/`CampScenePage`/`SceneCarousel`(token) 等领域标识符改为 `Environment*`；**不动** SwiftUI `Scene`（`some Scene`）、`windowScene`、`SenseZone*`、`SceneFeature*` 资源名。
- Environment 的沉浸/全景呈现行为（SCEN-02~12）留给「定稿前端接管真实 Demo」阶段；进入场景（SCEN-18 expand→`xrplay_scene` 真场景）本轮在场，mpv 帧进 RCP3 场景已验证。

## 关联

- ADR-0003（用例表立档）、ADR-0004（美术仓取代模板）。
- `CONTEXT.md` 新增 Environment 术语。
- SwiftUI `Scene` 协议事实：Apple 官方文档（DocumentationSearch 确认 WindowGroup/Window/ImmersiveSpace 均 conform `Scene`）。
