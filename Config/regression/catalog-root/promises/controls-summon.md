---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "controls-summon",
  "title": "Controls Summon",
  "promises": [
    {
      "id": "promise:controls-summon:c01",
      "title": "窗口模式：点击播放表面即可切换 chrome 的显隐；chrome 会在秒级时间后自动隐藏，任何交互都会重置这个计时。",
      "statement": "窗口模式：点击播放表面即可切换 chrome 的显隐；chrome 会在秒级时间后自动隐藏，任何交互都会重置这个计时。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:controls-summon:c02",
      "title": "docked 与 panorama：用户注视并捏合各自呈现的产品交互外壳，即可召唤空间内控件；控件在每次显现时读一次头部姿态定位，落位之后 world-locked，不随头部继续移动。",
      "statement": "docked 与 panorama：用户注视并捏合各自呈现的产品交互外壳，即可召唤空间内控件；控件在每次显现时读一次头部姿态定位，落位之后 world-locked，不随头部继续移动。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:controls-summon:c03",
      "title": "控件会自动隐藏，但打开二级菜单会把控件钉住。",
      "statement": "控件会自动隐藏，但打开二级菜单会把控件钉住。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Controls Summon promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:controls-summon:c01`

Proposal `PR-CS-C01` comes from `.agents/skills/vp-e2e/features/controls-summon.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:controls-summon:c02`

Proposal `PR-CS-C02` comes from `.agents/skills/vp-e2e/features/controls-summon.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:controls-summon:c03`

Proposal `PR-CS-C03` comes from `.agents/skills/vp-e2e/features/controls-summon.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
