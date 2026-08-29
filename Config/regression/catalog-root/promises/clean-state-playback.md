---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "clean-state-playback",
  "title": "Clean State Playback",
  "promises": [
    {
      "id": "promise:clean-state-playback:c01",
      "title": "无信令片源（容器与样本均不含投影元数据）按 window 呈现为平面播放。",
      "statement": "无信令片源（容器与样本均不含投影元数据）按 window 呈现为平面播放。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:clean-state-playback:c02",
      "title": "带信令片源（Apple APMP、MV-HEVC 等）按源分类进入相应的呈现方式。",
      "statement": "带信令片源（Apple APMP、MV-HEVC 等）按源分类进入相应的呈现方式。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:clean-state-playback:c03",
      "title": "观看进度从 0 开始，因为 resetState 已经清除了 enchron.* 键。",
      "statement": "观看进度从 0 开始，因为 resetState 已经清除了 enchron.* 键。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Clean State Playback promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:clean-state-playback:c01`

Proposal `PR-CSP-C01` comes from `.agents/skills/vp-e2e/features/clean-state-playback.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:clean-state-playback:c02`

Proposal `PR-CSP-C02` comes from `.agents/skills/vp-e2e/features/clean-state-playback.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:clean-state-playback:c03`

Proposal `PR-CSP-C03` comes from `.agents/skills/vp-e2e/features/clean-state-playback.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
