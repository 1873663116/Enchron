---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "mode-transitions",
  "title": "Mode Transitions",
  "promises": [
    {
      "id": "promise:mode-transitions:c01",
      "title": "打开媒体后的落地呈现：干净状态下按媒体来源的分类决定；当存在持久化的格式覆盖时，按覆盖决定。",
      "statement": "打开媒体后的落地呈现：干净状态下按媒体来源的分类决定；当存在持久化的格式覆盖时，按覆盖决定。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:mode-transitions:c02",
      "title": "从 window 切换到 portal：应用全景格式，并等待主窗口达到稳态。",
      "statement": "从 window 切换到 portal：应用全景格式，并等待主窗口达到稳态。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:mode-transitions:c03",
      "title": "从 portal 切换到 panorama：需要显式点击窗口菜单中的 `PlayerUI-TopAction-resumePanorama`，该入口的 accessibility label 是 Enter Panorama。",
      "statement": "从 portal 切换到 panorama：需要显式点击窗口菜单中的 `PlayerUI-TopAction-resumePanorama`，该入口的 accessibility label 是 Enter Panorama。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:mode-transitions:c04",
      "title": "从 panorama 退回 portal：通过控件面板上的 exit 完成。",
      "statement": "从 panorama 退回 portal：通过控件面板上的 exit 完成。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:mode-transitions:c05",
      "title": "window 与 docked 之间的双向切换：进入经过 TopAction-dock 与 DockMenu，退出通过控件面板上的 exit。",
      "statement": "window 与 docked 之间的双向切换：进入经过 TopAction-dock 与 DockMenu，退出通过控件面板上的 exit。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:mode-transitions:c06",
      "title": "失败回滚：当 settle 等待超时后，转场必须干净地回滚，不允许悬挂在中间状态。",
      "statement": "失败回滚：当 settle 等待超时后，转场必须干净地回滚，不允许悬挂在中间状态。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Mode Transitions promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:mode-transitions:c01`

Proposal `PR-MT-C01` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:mode-transitions:c02`

Proposal `PR-MT-C02` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:mode-transitions:c03`

Proposal `PR-MT-C03` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:mode-transitions:c04`

Proposal `PR-MT-C04` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:mode-transitions:c05`

Proposal `PR-MT-C05` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:mode-transitions:c06`

Proposal `PR-MT-C06` comes from `.agents/skills/vp-e2e/features/mode-transitions.md` at line 12, section Sub-features, source ordinal 6.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
