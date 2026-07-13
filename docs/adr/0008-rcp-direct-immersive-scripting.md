# ADR-0008：RCP 直接沉浸接入（RealityKitScripting）

- 状态：**已落地（2026-06-19）——真实 RCP `world` 接入完成，模拟器运行时验证通过**
- 日期：2026-06-18 立档（两次复议）；2026-06-19 第三次复议推翻延期 + 当日落地
- 决策者：项目负责人已批准 RKS 接法（解除 SwiftPM 依赖硬边界）；2026-06-19 进一步要求**立即落地**，"所谓的'已延期'都不存在"

## 复议（2026-06-19，接管真实场景——推翻延期）

负责人推翻"实验阶段不落地"决定：**expand 必须接入真实 RCP `world` 场景；假场景（程序化球顶 `EnvironmentDomeEntity`）与"黑屏/空沉浸"状态全部丢弃。** 接法参照隔壁 mpv fork 的 `xr-fork/verify-visionos`（已跑通的 visionOS 场景接入，文件见下「关联」）。新增约束：**expand 进沉浸后 SenseZone volume 不关闭**（区别于窗口播放"进沉浸关主窗"）。

落地清单（配方见本文「背景」节，等同活跃计划批 4 的 233–264 行）——**全部完成**：
1. ✅ SwiftPM 依赖 `github.com/apple/realitykitscripting`（main，rev `e0a8a39`）+ 传递依赖 `swift-syntax` 603.0.2；仅链接（MPVKit 模式），不嵌入。`project.pbxproj` + workspace `Package.resolved` 已改，构建通过。
2. ✅ `XrPlayerApp.init` 调 `try RKS.initialize()`（do/catch + assertionFailure）。
3. ✅ `ImmersiveSpaceView` 的 RealityView 挂 `.realityScripting()`（rev `e0a8a39` 已把 `.scriptingSystem()` 改名）；`Entity(named:"world")` 取代 `EnvironmentDomeEntity`（后者已删，94 行孤儿）。
4. ✅ `Immersive_Space.reality`（42MB）拷入 `XrPlayer/SpatialScene/Resources/`，经 fileSystemSynchronizedGroups 自动进 Copy Bundle Resources（确认落到 `XrPlayer.app/Immersive_Space.reality`）。
5. ✅ Info.plist 键已就绪（4 个 ARKit 串 + `UIApplicationSupportsMultipleScenes`，见 `Config/XrPlayer-Info.plist`）。
6. ✅ expand → 唯一沉浸入口进沉浸、加载 world、**volume 保持打开**（用 mixed 沉浸，见下「机制」）。

**机制（环境浏览-展开 vs 沉浸播放）：** 两种意图分流，避免播放副作用污染环境浏览：
- 环境浏览-展开（ENV-18）：`SenseZoneVolumeRoot.enterImmersive` 置 `AppModel.isEnvironmentImmersiveActive = true` 后请求沉浸；`MainView` 的 `.open` 请求走 `openImmersiveSpaceUnified(fullImmersion: false)` → **mixed 沉浸**（系统不隐藏窗口/volume，故 volume 不关）。`playbackMode` **保持 `.window`**，`ImmersiveSpaceView` 的 `.window` 分支在该标志下加载 `world`（仅世界、无虚拟屏，这是场景预览非播放）。沉浸关闭时 `onDisappear` 清标志。
- 沉浸播放（ENV-03）：`playbackMode == .immersive` → full 沉浸 + 关主窗（既有行为），world + `VirtualScreenEntity` 视频屏并存（option ①，帧管线不动）。

**未决子项定案：**
- ① 43MB 二进制提交策略——**定案：不提交**。本地拷入 `XrPlayer/SpatialScene/Resources/Immersive_Space.reality` + `.gitignore`，app 本地可跑、可上真机。负责人 2026-06-19 确认"这种大文件不让它进 Git"。
- ② `world` 在 `.mixed/.full` 完整包裹——**模拟器已验 mixed 加载+渲染**（见下证据）；HDR 亮度/立体景深/full-wrap 主观品质仍属真机·人工评估，未在模拟器证。

**落地证据（2026-06-19 模拟器 Apple Vision Pro）：**
- 运行时日志 `world loaded name=world children=3`，**零** RKS / sampler / NetworkAssetManager / scene-load 报错（计划警告漏接 RKS 会报这些，全无）。
- `simctl screenshot`：沉浸里渲染出美术世界（多云天空 + 水面地平面，**非**旧近黑程序球顶），主窗口在 mixed 沉浸下与世界共存——证 volume 不关机制成立。
- 触发方式：因 visionOS 模拟器无法合成点击，用临时 env-gated 钩子自动走 expand→沉浸路径，验毕即移除（无脚手架残留）。

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
