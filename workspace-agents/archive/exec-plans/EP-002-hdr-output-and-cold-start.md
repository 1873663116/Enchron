# [SUPERSEDED] 修复 HDR 真实输出并解释首启首播一次性冷卡顿

> **状态：SUPERSEDED（2026-03-17）**
>
> 本计划基于错误的根因分析，已被废止。核心误判如下：
>
> 1. **KI-010 的根因不是 `verified_surface=false` 或 MoltenVK 线程违规。** libmpv gpu-next 路径已能正确渲染 HDR10/HLG/DoVI（tone-mapping=auto + target-trc=auto），Metal Layer 也已配置为 rgba16Float + wantsExtendedDynamicRangeContent。真正缺失的是 `CAEDRMetadata`——Apple 显示系统因此不知道内容的 mastering 亮度，无法做精确的 system-level EDR tone mapping。
> 2. **HDR/SDR 按钮的问题不是"切换了有限的 runtime hint"。** gpu-next 内部已经处理了 HDR tone mapping，按钮切换 target-trc/target-prim 是有效的。缺失的是 Metal layer 上的 CAEDRMetadata 同步。
> 3. **首启首播问题与 HDR 输出是独立问题，不应合并在同一个 ExecPlan 中。**
>
> 后续工作由新的 HDR + Panorama 综合计划替代，该计划基于对 libmpv 渲染路径的重新调研。

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

本计划的第一目标是修复当前最严重、最影响产品判断的问题：HDR 内容虽然能被正确识别，但仍然只能以 `previewSDR` 输出，HDR/SDR 按钮也不能改变真实显示效果。完成后，用户应当能够在真机上看到一条诚实且可切换的 HDR 输出路径：如果设备和当前渲染路径支持真实 HDR，就真的进入 HDR 输出；如果不支持，UI 必须明确表达受限状态，并且按钮语义不能继续伪装成“已经切换成功”。

本计划的第二目标不是立刻“修掉”首启首播问题，而是把“首次构建后只卡一次、之后都秒切”的原因解释清楚并做成可验证结论。完成后，团队应能准确回答两个状态问题：首次启动但还没点任何视频时，播放核心到底预热到了什么程度；第一次真正播放成功后，播放核心又额外建立了哪些状态，因此后续切视频会明显更快。

## Progress

- [x] (2026-03-15 23:18) 根据 EP-001 真机结果创建 EP-002，并冻结新目标：HDR 真实输出优先，首启首播问题先做状态解释和根因验证，不急于继续编码。
- [ ] 梳理 native GPU 路径中 `verified_surface=false` 的具体判定条件，确认它依赖哪些线程、layer 和像素格式前提。
- [ ] 梳理 `setHDREnabled(...)` 当前到底切换了哪些 runtime hint、哪些真实管线状态没有变。
- [ ] 追踪 `MPVNativeMetalLayerView` 与 MoltenVK swapchain 的主线程约束，解释为什么真机会出现 `Modifying properties of a view's layer off the main thread is not allowed`。
- [ ] 设计并实施一条唯一可信的 HDR 输出路径，收口 UI 语义、状态模型和日志证据。
- [ ] 定义“首启未播放”和“首次播放后”的播放核心状态模型，并补足相应日志或诊断证据。
- [ ] 完成 agent 自检、agent运行simulator模拟人类操控验证、真机验证清单，确认 HDR 与首启冷卡顿的结论都可复现和解释。

## Surprises & Discoveries

- Observation: HDR 问题已经不是“识别失败”，而是“识别成功但真实输出未成立”。
  Evidence: 真机日志出现 `content=true` 与 `verified_surface=false output=previewSDR` 的稳定组合。

- Observation: 首次构建后首启首播的问题具备一次性冷建链特征。
  Evidence: 真机日志出现 `Spent 1010.191 ms generating shader LUT (slow!)` 与 `Spent 1238.006 ms translating SPIR-V (slow!)`，而后续切视频恢复秒切。

- Observation: native GPU 路径还存在线程约束违规，这可能既影响稳定性，也影响 HDR surface 验证。
  Evidence: 真机日志反复出现 `Modifying properties of a view's layer off the main thread is not allowed`，栈追踪落在 MoltenVK swapchain 初始化路径。

## Decision Log

- Decision: EP-002 把 HDR 真实输出列为第一目标，把首启首播问题降级为“先解释状态与根因，再决定是否编码”。
  Rationale: 用户已明确要求先把 HDR 问题搞定；而首启首播当前最缺的是状态解释，而不是继续盲改。
  Date: 2026-03-15

- Decision: EP-002 先冻结一条唯一可信的 HDR 输出路径，再讨论 HDR/SDR 按钮的交互细节。
  Rationale: 如果输出路径不唯一，按钮语义永远不可信。
  Date: 2026-03-15

## Outcomes & Retrospective

- 2026-03-15：计划已创建，尚未开始新的代码实现。EP-001 的剩余问题已被重排优先级并收口到本计划。

## Context and Orientation

Enchron 当前播放链路的关键文件集中在 `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift`、`XrPlayer/PlaybackCore/Adapters/MPV/MPVConfiguration.swift`、`XrPlayer/PlayerUI/Views/PlaybackMenuView.swift` 与 `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`。HDR 内容识别的证据来自 `media-profile`，真实输出状态的证据来自 `hdr_state` 中的 `verified_surface` 与 `output`。

这里的“真实 HDR 输出”指的是：最终播放链路真的进入 HDR 呈现，而不是仅仅把内容识别成 HDR，或者只改动 tone mapping hint。“一次性冷卡顿”指的是：首次构建后第一次成功播放时才出现的重型初始化成本；后续不论切视频还是重新打开视频都明显更快。

本计划尤其关心两个状态：

第一，用户刚启动 App、但还没点任何视频时，player core 到底完成了什么。根据现有日志，`warmup_ready` 只能证明 warmup 流程完成到了可接受 layer 并建立基础路径，但还不能证明真正的播放渲染管线、shader cache、swapchain 和媒体解码链都已经建好。

第二，第一次真正播放成功后，player core 进入了什么状态。根据现有真机现象和日志，这时至少会额外完成一次真实 `vo=gpu-next` 播放路径建立、MoltenVK 设备与 swapchain 初始化、libplacebo shader LUT 生成、SPIR-V 翻译，以及相关缓存驻留。因此后续播放才会出现“秒切”的体感。

## Plan of Work

先从 HDR 开始，完整梳理 `MPVPlayerAdapter` 中从内容识别到输出模式判定的路径，确认 `verified_surface` 目前到底由什么条件置为真。如果它从未置真，就需要顺着 native layer、像素格式、`vo=gpu-next` 初始化和主线程约束一路向下查，找出是“验证逻辑缺失”还是“真实 HDR surface 根本没有建立”。

在 HDR 输出路径收口之前，不继续扩展 HDR/SDR 按钮能力。先保证 UI 文案、按钮启用态和日志证据完全一致，再决定按钮是“切真实输出管线”还是“只切 preview/tone mapping 模式”。

HDR 路径结论稳定后，再单独整理首启首播的状态模型。这里先不承诺修复，而是把“未点播时的 warmup 状态”和“首次播放后的热态”通过日志与代码路径对应起来，形成团队可复述的结论。如果这个过程表明问题主要来自首次真实 GPU 管线建链，那么后续要处理的就不是泛化的“播放黑屏”，而是更具体的“首次真实渲染管线初始化成本”。

## Milestones

### M1: 冻结 HDR 失败点

这个里程碑完成后，团队应能明确回答：HDR 内容为什么仍停在 `previewSDR`，失败点是在识别、surface 建立、线程约束、像素格式，还是在输出验证逻辑本身。此时不要求已经修复，但必须把失败点缩到一个具体层级。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 打开一个 Dolby Vision 视频和一个 HDR10 视频 → 预期日志都能稳定给出 `content=true` 与当前 `verified_surface/output` 的真实值

### M2: 建立唯一可信的 HDR 输出路径

这个里程碑完成后，用户在正式设置面板里看到的 HDR 控件与真实输出行为必须一致。若设备支持，则能真正进入 HDR 输出；若不支持，则 UI 会明确表达受限模式，按钮不会再假装“切换成功”。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- HDR 视频播放时切换 HDR/SDR 控件 → 预期显示结果和状态文案同步变化，且不再长期停留在名义可切但实际无变化的状态

### M3: 解释首启首播的一次性冷卡顿

这个里程碑完成后，团队应能准确回答“首次启动未点播时播放核心处于什么状态”和“首次播放成功后播放核心又进入了什么热态”。如果有必要，再决定是否进入后续实现阶段。

#### 验证（双轨）

Agent 自检：
- `swift build` — 预期无 error
- `swift test` — 预期全部通过
- `swiftlint lint` — 预期无 error 级别违规
- `scripts/check-workaround.sh XrPlayer/` — 预期通过

人类真机验证：
- 首次构建后首次启动播放一个本地视频，再连续切换多个视频 → 预期日志和结论能解释为什么只第一次卡、之后秒切

## Concrete Steps

工作目录统一为 `/Users/xiongzhipeng/Applications/Enchron`。

每次实施后都运行：

    swift build
    swift test
    swiftlint lint
    scripts/check-workaround.sh XrPlayer/

每次 HDR 真机验证时，必须保留以下日志片段：

    [MPV] hdr_state reason=... content=... enabled=... verified_surface=... output=...
    [MPV] media-profile hdr=...

每次首启首播验证时，必须保留以下日志片段：

    [MPV] warmup_requested ...
    [MPV] warmup_ready ...
    [MPV] mpv_ready ...
    [MPV] first_frame_visible ...

## Validation and Acceptance

EP-002 的验收优先级非常明确。第一，HDR 真实输出必须被修好，或者至少被诚实收口成“当前设备/当前路径不支持真实 HDR 输出”的明确产品状态。第二，首启首播的一次性冷卡顿必须被解释清楚，团队不能再只停留在“只会第一次发生”的现象描述。

如果 HDR 仍然只能识别、不能真实显示和切换，就不能把 EP-002 视为完成。若首启首播仍未修复，但状态解释已经完整且有证据支撑，可以把这一部分标记为“结论完成，是否编码另议”。

## Idempotence and Recovery

本计划允许先调查、后实现。若中途发现 HDR 真实输出在当前 native GPU 路径下根本不可行，应立即把计划收口到“诚实表达受限状态”，不要继续叠加无效开关。若首启首播调查证明问题主要是首次真实 GPU 管线建链，则后续应单独立项处理，不把它和一般播放启动逻辑混为一谈。

## Artifacts and Notes

当前已知最关键的证据是：

    [MPV] hdr_state reason=media_profile_detected content=true enabled=true verified_surface=false output=previewSDR ...
    [MPV][warn][vo/gpu-next/libplacebo] Spent 1010.191 ms generating shader LUT (slow!)
    [MPV][warn][vo/gpu-next/libplacebo] Spent 1238.006 ms translating SPIR-V (slow!)
    Modifying properties of a view's layer off the main thread is not allowed

这些证据分别对应 HDR 问题的当前失败面和首启首播问题的一次性冷建链特征。

## Interfaces and Dependencies

本计划优先关注以下文件和接口：

- `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift`
- `XrPlayer/PlaybackCore/Adapters/MPV/MPVConfiguration.swift`
- `XrPlayer/PlayerUI/Views/PlaybackMenuView.swift`
- `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- `XrPlayer/App/PlaybackLaunchCoordinator.swift`
- `XrPlayer/XrPlayerApp.swift`

如需改变 HDR 输出状态模型、native layer 初始化路径或跨模块播放接口，必须先更新对应 contract 与架构说明，再改代码。

Plan created on 2026-03-15。根据 EP-001 的真机验证结果建立，HDR 真实输出为第一优先级，首启首播先做状态解释与根因验证。
