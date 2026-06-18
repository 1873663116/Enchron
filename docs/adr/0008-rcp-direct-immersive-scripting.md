# ADR-0008：RCP 直接沉浸接入（RealityKitScripting）

- 状态：**接法已批准；实验阶段不落地（负责人已确认不提交 43MB 二进制/远程依赖）**
- 日期：2026-06-18（2026-06-18 两次复议）
- 决策者：项目负责人已批准 RKS 接法（解除 SwiftPM 依赖硬边界），并明确「这个大文件就没必要提交了」

## 复议（2026-06-18，FakeApp 收口轮）

负责人已明确批准本场景接法（"场景我一开始就批准过你的"），SwiftPM 依赖硬边界**解除**。
但同一指令要求"别造难以丢弃的东西（实验，一个月内可能删）"。落地 RKS world 需：
① 提交 ~43MB `Immersive_Space.reality` 二进制进仓；② 新增远程 SwiftPM 依赖
`apple/realitykitscripting`（改 `Package.resolved`、手改真 `.xcodeproj` pbxproj，有
损坏工程、连带打挂其余已绿构建的风险）。这两项是全计划中**唯一非可丢弃**的部分,与
可丢弃原则正面冲突。

**决策（已定）：场景体验用可丢弃方式交付**——`SenseZoneVolumeRoot`(volumetric WindowGroup)
+ 共享 `EnvironmentCardCarousel`(7 卡)+ 中心卡展开经唯一沉浸入口进沉浸,沉浸里**沿用
既有程序球顶 `EnvironmentDomeEntity`**(零新依赖、零二进制、随时可删)。

负责人于 2026-06-18 第二次复议时确认「这个大文件就没必要提交了」——**实验阶段不提交
43MB `Immersive_Space.reality`、不接 RealityKitScripting 远程依赖**。RKS 真 world 交换
本文「决策」节即配方,留作实验转正后再启用,不是权限阻塞。

## 背景

美术仓库 `Xrplay_scene` 用 RCP3 装配并导出 `world` 场景（含 RCP3 Script Graph）。
mpv fork `enchron` 分支的 `xr-fork/verify-visionos` 已跑通：`Entity(named:"world")` 加载该场景 +
mpv 帧上屏。关键事实（来自 verify）：`world` 含 Script Graph，**漏接 RealityKitScripting 会报
NetworkAssetManager / Invalid sampler binding、场景加载失败**。要在生产 `ImmersiveSpaceView` 用
真 `world` 取代手搓程序球顶 `EnvironmentDomeEntity`（ENV-18），就必须接这套。

但接入需要：① 新增 SwiftPM 依赖 `github.com/apple/realitykitscripting`；② `XrPlayerApp.init`
`try RKS.initialize()`；③ RealityView 挂 `.scriptingSystem()`；④ 复制 `Immersive_Space.reality`
（~43MB）进仓并加 Copy Bundle Resources；⑤ Info.plist 四个 ARKit 用途串（已在 ADR-0007 范围内补齐）。
其中 ① 升级/新增 SwiftPM 依赖是 `CLAUDE.md` 列明的硬边界，需人类裁决，agent 不自接。

## 决策（提案）

**生产沉浸走 RCP 直接接入：接 RealityKitScripting，`ImmersiveSpaceView` 加载美术 `world`
取代程序球顶；视频屏沿用既有 `VirtualScreenEntity`（帧管线不动）。** 本提案 supersede 既有两处推迟：
- ADR-0004「具体集成机制待定」——此处给出机制：复制 `.reality` + `Entity(named:"world")` + RKS。
- 沉浸场景接入的推迟——此处给出接法（照 verify-visionos）。

待裁决项（人类批准前不动）：新增 RealityKitScripting SwiftPM 依赖。

## 后果（若批准）

- `Package.resolved` 变更；与 MPVKit→自产 XCFramework 同属「依赖范围授权」需复核的类别。
- `world` 在生产 `.mixed/.full` 沉浸样式下完整包裹需实测（verify 只验过 `.progressive`）。
- 空间点按（ENV-10）需确认 `world` 实体带命中组件（InputTarget/Collision），否则点按落空。
- 数量错配：美术 1 个 `world`、卡 7 张；本轮任意卡都进同一 `world`（见 `EnvironmentSceneMapping`）。

## 现状（本提案未落地部分）

- 已完成：四个 ARKit 用途串、`EnvironmentSceneMapping`（卡→world 总映射 + 单测）。
- 未完成（待批准）：RKS 依赖、`.reality` 复制、`RKS.initialize`、`.scriptingSystem`、
  `ImmersiveSpaceView` world 加载、SenseZone volume 进入/返回迁移（ENV-13/14）。

## 关联

- ADR-0004（美术仓库所有权）；ADR-0007（FakeApp 架构，本提案承接其沉浸硬边界）。
- 参考实现：`mpv` 仓 `enchron` 分支 `xr-fork/verify-visionos`（VerifyVisionOSApp / ImmersiveView /
  VerifyModel / project.yml）。
- 记忆 `art-scene-repo` / `rcp3-xcode-integration-flow`。
