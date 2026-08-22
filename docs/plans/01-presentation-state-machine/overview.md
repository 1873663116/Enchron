# 呈现状态机重构

状态：搁置
最后推进：2026-08-15
停在：phase-9

2×2 模型与全部转换边已在生产代码里（`Modules/PlaybackPresentation/Model/PlaybackPresentation.swift`），
phase-1 至 phase-8 的代码与模拟器判据成立，两个设备探针的裁决已产出并被下游消费。欠三件：
phase-7 的横向边连续性与 phase-8 的表冠单双按，两处设备证据从未产出；phase-9 承诺的死代码清理
只做了自动全景进入与对角线两项，沉浸宿主格式编辑那批仍在 `PlaybackPanel.swift`；phase-5 第 4 条
自带的重验条件已被 `3d6074bb` 的共存 resident window 触发，重验未做。

## Context

呈现模型收敛为 2×2：内容族（flat 对 panoramic，由生效投影决定）× 场景宿主（主窗口对沉浸空间）。四个呈现各占一格：

| | 主窗口 | 沉浸空间 |
|---|---|---|
| flat | window | docked |
| panoramic | portal | panorama |

合法转换只有三类：同族进出沉浸（window↔docked、portal↔panorama）、同窗改投影（window↔portal）、同格改立体排列（自环，原地重建技术 session）。对角线不存在直接边。格式编辑只发生在主窗口列；应用全景投影停在 portal，进入沉浸永远由用户显式按钮触发。

## Scope

包含：边集合的类型化与集中校验；resolver 改为 portal 默认（删除自动进入 panorama 及其 pending 机制）；移除沉浸宿主的格式编辑；按内容族区分的进沉浸按钮；横向边的实现（转移或重建，由探针裁决）；表冠收起行为。

排除：系统停靠（自定义解码管线不可用）；Dock 的窗口化形态（Dock 必须使用环境锚点上的屏幕实体）；沉浸空间内的格式编辑（永久移除，切错格式的用户在 portal 修正后再进入）。

## Constraints

- 最低 visionOS 27：`progressive(range:initialAmount:)`、`onImmersionChange`、`VideoPlayerComponent(videoRenderer:)` 全部可用。
- renderer 与 VideoPlayerComponent 一对一，组件建成后不可换 renderer；跨场景转移的唯一形状是旧 entity 摘组件、新 entity 用同一 renderer 建新组件，该时序无文档承诺，由 phase-6 探针裁决。
- 格式变化必须重建技术 session（RealityKit 保留旧投影分类，见 `docs/research/realitykit-runtime-video-format-override-2026-08-07.md`）。
- 渐进沉浸下窗口永远渲染在虚拟内容之前；App 无法直接读取表冠事件，旋转与沉浸量归系统所有，App 不基于沉浸量触发行为；表冠按压的 27 真机事实见 phase-5 裁决。见 `docs/research/visionos-progressive-crown-and-playback-continuity-2026-08-11.md`。

## Alternatives

横向边的实现有两个候选：同一技术 session 的 renderer 跨场景重绑定（连续、无重建），或保留现有的预组装替换（有短暂切换）。边集合与全部纵向行为对两者不敏感；phase-6 探针给出裁决，失败则横向边保持重建实现，模型不变。

## Applicable skills

设备阶段读 `.agents/skills/vp-e2e`；每次提交前对 diff 应用 unslop。

## Phases

1. [phase-1-content-family-core.md](phase-1-content-family-core.md)
2. [phase-2-resolver-portal-default.md](phase-2-resolver-portal-default.md)
3. [phase-3-immersive-format-editing-removal.md](phase-3-immersive-format-editing-removal.md)
4. [phase-4-family-entry-buttons.md](phase-4-family-entry-buttons.md)
5. [phase-5-device-crown-facts.md](phase-5-device-crown-facts.md)
6. [phase-6-renderer-rebind-probe.md](phase-6-renderer-rebind-probe.md)
7. [phase-7-horizontal-edges.md](phase-7-horizontal-edges.md)
8. [phase-8-crown-collapse.md](phase-8-crown-collapse.md)
9. [phase-9-regression-matrix.md](phase-9-regression-matrix.md)

阶段 1–4 不依赖设备，全部可在模拟器通道验证；5 与 6 是设备实验，7、8 消费其结论；9 收口。

## Verification

- 静态与单元：`zsh Scripts/test-visionos-domain.sh <visionOS Simulator destination id>`
- 设备回归：`Scripts/verification/playback_mode_matrix.py`，PASS 需像素佐证。
