# 修复 KI-007 KI-010 KI-011

本 ExecPlan 是活文档。Progress、Surprises & Discoveries、Decision Log、
Outcomes & Retrospective 四个章节必须在工作进行中保持更新。

本文档须遵循 PLANS.md（仓库根目录）的全部要求进行维护。

## Purpose / Big Picture

本计划原本要同时修复三个长期问题：SMB 子目录点不开、首播黑屏与首次打开信息面板卡顿、以及 HDR 识别和真实输出脱节。计划执行后，实际结果是分化的：SMB 子目录问题已解决，信息面板容器对齐问题已解决，HDR 内容识别与状态呈现已明显改善；但“首次构建后首启首播的一次性冷卡顿”仍未解决，“HDR 真实显示与 HDR/SDR 切换”也仍未解决。

因此，这份计划的最终状态不是“全部达成”，而是“部分达成并完成了问题重分层”。它最大的价值不再是施工指令，而是把哪些问题已解决、哪些问题仍开放、以及为什么要拆出 EP-002 重新聚焦，完整记录下来。

## Progress

- [x] (2026-03-15 21:32) 读取 AGENTS.md、ARCHITECTURE.md、REGRESSION.md、known_issues.md、PLANS.md、TESTING.md、quality_gates.md，恢复项目语境。
- [x] (2026-03-15 21:32) 完成 KI-007、KI-010、KI-011 的代码级根因排查，并将诊断结果回写到 `workspace-agents/known_issues.md`。
- [x] (2026-03-15 21:36) 修复 KI-011 的 SMB share 内路径换算；补充了 share 根、嵌套目录和子目录文件完整路径的单元测试。
- [x] (2026-03-15 21:58) 调整 KI-007 首播关键路径，移除首播前本地 `AVURLAsset` 冷探测，补充 `metadata_prefetch_*`、`launch_gate_ready`、`mpv_ready`、`first_frame_visible` 等阶段日志。
- [x] (2026-03-15 22:10) 将 `i` 信息面板从自定义浮层回退为系统 `Menu` 容器，与现有系统菜单容器保持一致。
- [x] (2026-03-15 22:18) 为 HDR 增加正式设置入口、补充 HDR 状态日志，并把内容识别从仅 `FILE_LOADED` 扩展到 `VIDEO_RECONFIG`。
- [x] (2026-03-15 22:28) 修复一次由本计划引入的启动回归：播放控制任务错误复用事件循环串行队列，导致 `warmup_ready` 后 `loadfile` 无法真正执行。改为独立 control queue。
- [x] (2026-03-15 22:39) 完成 agent 自检。`swift build`、`swift test`、`swiftlint lint`、`scripts/check-workaround.sh XrPlayer/`、visionOS Simulator `xcodebuild` 均通过。
- [x] (2026-03-15 23:05) 完成真机结果复盘。KI-011 通过；`i` 面板容器对齐通过；HDR 内容识别准确但真实显示与切换失败；首次构建后首启首播仍有一次性冷卡顿。
- [x] (2026-03-15 23:18) 将 EP-001 标记为 done，转入归档；把剩余问题迁移到 `known_issues.md` 和新的 EP-002。

## Surprises & Discoveries

- Observation: SMB 的问题不在 UI，不在权限，而在 share 根目录场景下的路径换算。
  Evidence: `SMBDataSourceAdapter.smbRelativePath(from:)` 在 `components.count <= 1` 时直接返回 `/`，导致任意子目录被重新塌缩回 share 根。

- Observation: 首播黑屏问题并不等价于“没有 warmup”。真机日志已证明 `warmup_ready` 在点播前出现，但首次构建后首播仍然会明显卡顿。
  Evidence: 真机日志先出现 `[MPV] warmup_ready mode=native`，后续仍可看到首次播放阶段产生 MoltenVK 实例创建、shader LUT 生成和 SPIR-V 翻译的重负载日志。

- Observation: 首次构建后首播只卡一次，符合“首次真正建立渲染管线与 shader cache”的特征，不符合“每次播放逻辑都走错”的特征。
  Evidence: 真机日志包含 `[MPV][warn][vo/gpu-next/libplacebo] Spent 1010.191 ms generating shader LUT (slow!)` 与 `Spent 1238.006 ms translating SPIR-V (slow!)`，而后续切视频可恢复秒切。

- Observation: HDR 内容识别已经基本可信，但输出链路明确没有闭环。
  Evidence: 真机日志同时出现 `content=true` 与 `verified_surface=false output=previewSDR`。这说明“内容识别为 HDR”和“真实 HDR 输出”已经被清楚分离，失败点在输出路径而不是识别路径。

- Observation: 当前 native GPU 路径还存在真实线程约束问题，可能直接阻断 HDR surface 验证。
  Evidence: 真机日志反复出现 `Modifying properties of a view's layer off the main thread is not allowed`，且栈追踪落在 MoltenVK swapchain 重建路径。

## Decision Log

- Decision: 将修复顺序固定为 KI-011 -> KI-007 -> KI-010。
  Rationale: SMB 路径问题范围最小、可快速验证；KI-007 次之；KI-010 涉及播放器输出路径，风险最高且更依赖真机验证。
  Date: 2026-03-15

- Decision: KI-007 的目标不是“靠文案掩盖等待”，而是把非必要冷启动工作移出用户点击后的感知关键路径。
  Rationale: 质量门禁 G4、G5、G15 明确要求首播瓶颈可测量且不接受明显可感知卡顿。
  Date: 2026-03-15

- Decision: 当用户明确否定自定义 `i` 面板容器后，立即回退到系统 `Menu`，不再坚持自定义实现。
  Rationale: 该问题属于 UI 语义对齐，不是功能创新；系统容器是项目规则中的默认优先级。
  Date: 2026-03-15

- Decision: EP-001 到此结束，不继续在同一计划内追打 HDR 真正输出与首启首播一次性冷卡顿，而是拆到 EP-002。
  Rationale: 这两个剩余问题都需要新的目标聚焦和新的验证策略。继续在 EP-001 内叠加会模糊“已解决”和“未解决”的边界。
  Date: 2026-03-15

## Outcomes & Retrospective

- Outcome: KI-011 已解决。SMB 子目录进入、逐层返回以及子目录视频播放在真机上通过。
- Outcome: `i` 信息面板的容器语义已修正。它重新使用系统 `Menu`，不再是自定义浮层。
- Outcome: HDR 内容识别已明显改善，日志与 UI 都能区分 Dolby Vision、HDR10 和 SDR；但真实输出仍停留在 `previewSDR`，HDR/SDR 按钮也未实现真实显示切换。
- Outcome: 首次构建后首启首播的黑屏/卡顿仍开放。虽然播放卡死回归已修掉，但“一次性冷卡顿”没有消失。
- Lesson: 这轮最重要的收获不是“把三个问题都修完”，而是把问题边界重新划清。KI-007 已从“首播黑屏”缩小为“首次构建后首启首播的一次性冷建链成本”；KI-010 已从“识别不准”缩小为“真实 HDR 输出链路和切换语义未闭环”。

## Context and Orientation

Enchron 是一个面向 visionOS 的播放器，主链路是 `FileBrowsing -> PlaybackLaunchCoordinator -> PlaybackCore -> PlayerUI`。本计划覆盖过三块代码。

第一块是 SMB 浏览链路。入口在 `XrPlayer/FileBrowsing/Views/FolderListView.swift`，点击文件夹后会调用 `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift` 的 `navigateToFolder(...)`，真正访问 SMB 服务器的逻辑在 `XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift`。这里的关键术语是“share 内相对路径”，它指的是已经连接到某个 SMB share 后，再传给 AMSMB2 的目录路径；它不应该再次带上 share 名。

第二块是首播与信息面板链路。播放请求统一进入 `XrPlayer/App/PlaybackLaunchCoordinator.swift`，播放器实现位于 `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift`，播放器状态和展示态在 `XrPlayer/WindowVideoViewModel.swift` 与 `XrPlayer/MainView.swift`，信息面板在 `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`。这里的关键术语是“关键路径”，它指用户点开视频后，到首帧真正显示前必须经历的那段不可跳过路径。任何不必放在这段路径里的工作，都应当移出去。

第三块是 HDR 输出链路。媒体内容识别来自 `XrPlayer/App/PlaybackMediaMetadataService.swift` 和 `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift`；HDR 输出状态由 `XrPlayer/PlaybackCore/Domain/ValueObjects/HDRType.swift` 中的 `HDROutputMode` 表达；正式设置入口位于 `XrPlayer/PlayerUI/Views/PlaybackMenuView.swift`。这里的关键术语是“输出闭环”，它指配置、播放器初始化、渲染路径、UI 状态和验证证据必须指向同一条真实能力，而不是各说各话。

## Plan of Work

本计划的实施已经完成，未完成项不再继续在此文档内推进。M1 的工作是收口 SMB 路径语义，让 ViewModel 与 adapter 对“当前浏览路径”的理解一致。M2 的工作是把首播感知关键路径里的非必要工作移走，并让信息面板不再走首次重型宿主初始化。M3 的工作是让 HDR 控制进入正式设置面板，并把 HDR 内容识别与输出状态通过日志显式分离。

执行结果证明：M1 完整成功；M2 成功了一半，主要收获是稳定了阶段日志、修正了 `i` 面板容器，但并未消除“首次构建后首启首播的一次性冷卡顿”；M3 也成功了一半，主要收获是识别与状态诚实化，但真实 HDR 输出和切换能力仍未建立。剩余工作已移交给 EP-002。

## Milestones

### M1: 修复 SMB share 内目录导航

这个里程碑已完成。用户现在可以从 SMB share 根目录进入任意子目录，再逐层进入更深目录并返回上一级。问题根因是 share 根场景下路径被错误塌缩成 `/`，修复后 UI 与 ViewModel 无需理解底层路径细节。

#### 验证（双轨）

Agent 自检：
- `swift build` — 通过
- `swift test` — 通过
- `swiftlint lint` — 通过（无 error）
- `scripts/check-workaround.sh XrPlayer/` — 通过

人类真机验证：
- 连接 SMB，进入 share，继续进入子目录并播放子目录视频 → 通过

### M2: 缩短首播感知等待并移除首次信息面板卡顿

这个里程碑部分完成。信息面板卡顿问题已经转化并解决，系统菜单容器恢复正确；播放链的结构化日志也补齐了。但“首次构建后首启首播”的一次性冷卡顿仍存在，因此本里程碑不能算完全达成。

#### 验证（双轨）

Agent 自检：
- `swift build` — 通过
- `swift test` — 通过
- `swiftlint lint` — 通过（无 error）
- `scripts/check-workaround.sh XrPlayer/` — 通过
- 日志可区分 `request_started -> layer_attached -> mpv_ready -> first_frame_visible` — 通过

人类真机验证：
- 首次构建后首启首播仍有一次性冷卡顿 → 未通过
- `i` 面板系统容器语义恢复正确 → 通过

### M3: 打通真实 HDR 输出闭环

这个里程碑部分完成。HDR 内容识别、状态呈现和入口位置都比此前正确，但真正的 HDR 输出闭环仍未形成。当前真机上，HDR 内容被识别为 HDR，可见正确的类型信息，也可点按钮；但 `verified_surface` 始终为 `false`，输出仍是 `previewSDR`。

#### 验证（双轨）

Agent 自检：
- `swift build` — 通过
- `swift test` — 通过
- `swiftlint lint` — 通过（无 error）
- `scripts/check-workaround.sh XrPlayer/` — 通过
- 播放 HDR 内容时，日志能区分 `hdrType` 与 `hdrOutputMode` — 通过

人类真机验证：
- HDR 内容识别和 UI 信息准确 → 通过
- HDR/SDR 按钮点击后能真正切换显示效果 → 未通过
- 真实 HDR 输出建立 → 未通过

## Concrete Steps

EP-001 已不再接收新的施工步骤。后续若继续处理 HDR 真实输出与首次构建后首启首播的一次性冷卡顿，应转到 `workspace-agents/exec-plans/EP-002-hdr-output-and-cold-start.md`。

## Validation and Acceptance

本计划的最终验收结果是“部分通过”。如果以原始目标逐条判断：

- SMB 子目录可进入并可播放：通过。
- 首次打开 `i` 面板不卡顿且容器语义正确：通过。
- 首次构建后首启首播明显改善：未通过。
- HDR 识别、真实显示与切换语义统一：未通过。

因此，EP-001 只能作为一个完成了边界清理和部分修复的归档计划，而不能作为“已完整关闭 KI-007 与 KI-010”的依据。

## Idempotence and Recovery

本计划相关代码修改已经落地；但如果需要继续解决剩余问题，不应在 EP-001 上反复追加，而应在 EP-002 中重新定义目标和验收。这样可以避免未来读者误把“部分修复”当成“全部修复”。

## Artifacts and Notes

当前最关键的真机证据如下：

    [MPV] warmup_ready mode=native
    [MPV] mpv_ready url=...
    [MPV] first_frame_visible url=...
    [MPV][warn][vo/gpu-next/libplacebo] Spent 1010.191 ms generating shader LUT (slow!)
    [MPV][warn][vo/gpu-next/libplacebo] Spent 1238.006 ms translating SPIR-V (slow!)
    [MPV] hdr_state reason=media_profile_detected content=true enabled=true verified_surface=false output=previewSDR ...
    Modifying properties of a view's layer off the main thread is not allowed

这些记录共同说明：首次构建后首启首播的问题集中在一次性冷建链成本；HDR 问题则集中在 native GPU/HDR surface 的真实输出路径和线程约束。

## Interfaces and Dependencies

EP-001 没有改变跨模块协议边界。剩余问题仍围绕以下文件与接口：

- `XrPlayer/App/PlaybackLaunchCoordinator.swift`
- `XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift`
- `XrPlayer/PlaybackCore/Adapters/MPV/MPVConfiguration.swift`
- `XrPlayer/PlayerUI/Views/PlaybackMenuView.swift`
- `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`

如果 EP-002 需要改变 `PlaybackControlling`、HDR 状态模型或 native layer 线程约束相关接口，必须在新计划中先更新对应 contract 与架构说明。

Plan created on 2026-03-15。初版根据 2026-03-15 的根因排查结果建立，用于承接 KI-007、KI-010、KI-011 的后续实现。
Updated on 2026-03-15。记录了 M1 的已完成实现，并把 KI-007 的首轮低风险修复纳入 Progress 与 Outcomes。
Updated on 2026-03-15。记录了 KI-007/KI-010 的收口实现、自检结果，以及等待真机验证的当前状态。
Updated on 2026-03-15。根据真机验证结果将 EP-001 收口为“部分完成”，并把剩余问题转交给 EP-002。
