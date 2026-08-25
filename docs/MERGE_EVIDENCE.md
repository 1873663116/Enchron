# PR 证据分级与免读合并门

本文是 PR 免读合并的分级标准、每级所需证据、证据清单（manifest）格式与 gauntlet 门语义的真相源。分级器与 manifest 校验器是 `Scripts/verification/merge_evidence_tier.py`，自测是 `Scripts/verification/test_merge_evidence_tier.py`。Device Hub 词汇（`device-hub` 驱动、spatialTap 探针契约）复用 `Scripts/verification/journey_units.py`，本文不定义平行概念。

当前阶段（Phase 1）只启用 W0/W1 的免读判定；W2/W3 的免读判定在 Phase 3 启用，在此之前门对 W2/W3 输出「非免读，需证据清单」，改动走人审。

## 裁决表

| 类别 | 范围 | 免读合并所需证据 |
|---|---|---|
| W0 | 仅 docs、skills、scripts | gauntlet 绿 |
| W1 | 仅测试代码 | gauntlet 绿 |
| W2 | 单 feature 内、不触播放管线 | gauntlet 绿 + 模拟器 e2e 证据 |
| W3 | 播放管线、呈现切换、沉浸相关 | gauntlet 绿 + Device Hub 真实输入（注视+捏合）模拟器 e2e 证据；真机仅解码能力类特例 |

## 路径映射

分级按 commit 范围内的改动路径归类。一个范围取其中最高级；映射之外的路径一律向上归 W3，绝不向下归级。前缀按最长匹配优先，因此 `Packages/PlaybackCore/Tests/` 命中 W1 而不落入包本体的 W3。

| 前缀 | 级 | 依据 |
|---|---|---|
| `docs/` | W0 | 文档 |
| `.agents/skills/` | W0 | 技能指令 |
| `Scripts/` | W0 | 脚本（含验证脚本；见「已知张力」） |
| `Tests/` | W1 | 仓库根测试代码 |
| `Packages/PlaybackCore/Tests/` | W1 | 播放核心包的测试代码 |
| `Modules/DesignSystem/` | W2 | 单 feature，不触播放管线 |
| `Modules/Emby/` | W2 | 单 feature，不触播放管线 |
| `Modules/MediaLibrary/` | W2 | 单 feature，不触播放管线 |
| `Apps/DesignPreview/` | W2 | 设计预览壳，被结构检查禁止引用 App 层 |
| `Apps/Enchron/` | W3 | App 壳持有呈现切换与沉浸场景生命周期 |
| `Modules/MediaSource/` | W3 | 字节流供给播放管线 |
| `Modules/PlaybackFeature/` | W3 | 播放管线 |
| `Modules/PlaybackPresentation/` | W3 | 呈现切换 |
| `Packages/PlaybackCore/` | W3 | 播放核心（Tests 子目录除外） |
| `Packages/RealityKitContent/` | W3 | 沉浸内容 |
| `Config/` | W3 | 执法状态：基线与台账即约束，改基线等于改约束，永不属于 W0 |
| 其余任何路径 | W3 | 未归类，向上归级 |

「其余任何路径」当前覆盖仓库根的工程与构建配置（`Enchron.xcodeproj`、`Package.swift`、各 xctestplan）、根级指令文档（`AGENTS.md`、`ARCHITECTURE.md`、`CLAUDE.md`）、钩子与 CI 配置等。它们要么改变构建产物，要么改变执法与指令本身，保守归 W3 而不是扩大 W0 的批准范围。

## 门的语义

`Scripts/verification/run_verification_gauntlet.py` 的 structure 层运行两个检查：`merge-evidence-tier` 对当前范围输出分级裁决，`merge-evidence-tier-tests` 运行分级器自测。两者在 quick 与 full 模式都运行。

门回答的问题是「这个范围是否免读合并」，不是「这个提交是否合法」。因此：

- W0/W1：裁决行输出「免读合并合格」。
- W2/W3：裁决行输出「非免读，需证据清单」，并逐项列出该级所需证据；gauntlet 不因此 FAIL，改动走人审。
- 只有分级器自身崩溃才使该 structure 检查 FAIL。

范围默认 `@{upstream}..HEAD`，也可显式传 `base..head`。默认范围无法解析（无上游、git 失败）时按 W3 上归输出非免读，不阻断 gauntlet；显式传入的非法范围按用法错误退出。空范围没有可裁决的改动，输出「免读合并合格」。

裁决与逐路径归类写入 gauntlet run 目录的 `structure/merge-evidence-tier.log`；`--json` 输出机器可读裁决。

## 证据清单（manifest）标准

W2/W3 的 PR 用一份 JSON manifest 声明分级与逐项证据指针，使「缺证据」由机器判定而不是自由文本。格式版本 1：

| 字段 | 类型 | 何时必填 | 说明 |
|---|---|---|---|
| `version` | 数字 | 总是 | 固定 1 |
| `range` | 字符串 | 总是 | 被裁决的 commit 范围 |
| `declaredTier` | 字符串 | 总是 | W0–W3；只允许声明不低于分级器计算值的级 |
| `gauntlet` | 对象 | 总是 | `runDirectory` 与 `summary` 指向 gauntlet run 产物，`verdict` 必须为 `passed` |
| `simulatorE2E` | 数组 | W2 起 | 每项 `unit`（操作单元名）+ `artifacts`（产物路径列表） |
| `deviceHubInput` | 数组 | W3 | 每项 `unit`、`target`、`entity`、`probe`、`probeLog`（探针行文件）、`diagnostics`（diagnostics JSON） |
| `realDeviceDecode` | 数组 | W3 特例 | 每项 `capability`、`reason`、`evidence`（产物路径列表） |

W3 的判定规则：`deviceHubInput` 非空，或 `realDeviceDecode` 非空（仅解码能力类改动可用真机证据替代，此即裁决表的分号条款；纯解码特例同时豁免 `simulatorE2E`）。`deviceHubInput` 每项必须满足：

- `unit` 是 `Scripts/verification/journey_units.py` 注册的、含 device-hub 步骤的操作单元；
- `probe` 是 App 侧探针行，形态为 spatialTap entity=&lt;entity&gt; ... accepted=true，由 `journey_units.py` 的 `probe_matches_contract` 谓词判定——命令通道写不出 spatialTap 行，因此合成输入无法伪造这条证据。

示例：

```json
{
  "version": 1,
  "range": "origin/main..HEAD",
  "declaredTier": "W3",
  "gauntlet": {
    "runDirectory": ".scratch/VerificationGauntlet/runs/20260825T120000Z-100",
    "summary": ".scratch/VerificationGauntlet/runs/20260825T120000Z-100/summary.json",
    "verdict": "passed",
    "mode": "quick"
  },
  "simulatorE2E": [
    {
      "unit": "playback.controls-window",
      "artifacts": [".scratch/e2e/controls-window/run1"]
    }
  ],
  "deviceHubInput": [
    {
      "unit": "playback.controls-window",
      "target": "PlayerUI-window-playback-surface",
      "entity": "EnchronWindowInput.surface",
      "probe": "spatialTap entity=EnchronWindowInput.surface accepted=true",
      "probeLog": "TestEvidence/device-hub/probe-lines.log",
      "diagnostics": "TestEvidence/device-hub/diagnostics.json"
    }
  ]
}
```

交付约定：manifest 不入库，以 PR 附件交付——PR 描述中的 evidence-manifest 代码块，或附件文件 merge_evidence_manifest.json。入库会让每个 PR 的 manifest 路径反过来参与自身分级。合并前在本地校验：

```
python3 Scripts/verification/merge_evidence_tier.py <base>..<head> --manifest <manifest.json>
```

校验器输出逐项缺失并以退出码表达充分与否；`--json` 给出机器可读报告。

## 已知张力：执法者自改落在 W0

`Scripts/` 整体归 W0 是裁决表批准的原文，这意味着修改验证脚本本身（包括 gauntlet 与本分级器）只需 gauntlet 绿即可免读。对执法者的现有看护：structure 层的 `gauntlet-guard-tests` 覆盖步骤静默终止与锁两个行为；guard 自测层仅在 full 模式运行、覆盖四个 guard 的已知坏样本；`merge-evidence-tier-tests` 覆盖分级器与 manifest 判定本身。这层看护是自测性质的，收窄执法逻辑的改动仍可能在免读下通过，评审执法脚本改动时应知晓此张力。

## Phase 3 启用计划

Phase 3 启用 W2/W3 的免读判定：门在 W2/W3 范围读取 PR 附件 manifest，机器判定证据齐备则输出免读合格，缺失则逐项列出并维持非免读。判定规则即上节所列，届时不再新增词汇。在启用之前，manifest 的格式与判定已由本地校验命令与自测固定。
