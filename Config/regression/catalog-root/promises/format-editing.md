---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "format-editing",
  "title": "Format Editing",
  "promises": [
    {
      "id": "promise:format-editing:c01",
      "title": "Window 与 Portal 的编辑界面都由窗口菜单承载：菜单由 `PlayerUI-TopAction-videoFormat` 打开，编辑项使用 `PlayerUI-VideoFormat-*` 系列标识。",
      "statement": "Window 与 Portal 的编辑界面都由窗口菜单承载：菜单由 `PlayerUI-TopAction-videoFormat` 打开，编辑项使用 `PlayerUI-VideoFormat-*` 系列标识。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:format-editing:c02",
      "title": "在 Portal 呈现中，菜单会同时显示 `PlayerUI-TopAction-resumePanorama` 与 `PlayerUI-TopAction-videoFormat`。",
      "statement": "在 Portal 呈现中，菜单会同时显示 `PlayerUI-TopAction-resumePanorama` 与 `PlayerUI-TopAction-videoFormat`。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:format-editing:c03",
      "title": "Automatic 恢复选项：当格式的 provenance 为 source 时，该选项被禁用并显示对勾。",
      "statement": "Automatic 恢复选项：当格式的 provenance 为 source 时，该选项被禁用并显示对勾。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:format-editing:c04",
      "title": "应用格式之后的呈现路由：应用全景投影会路由到 portal，应用 Flat 会路由到 window。要进一步进入 Panorama，需要点击 `PlayerUI-TopAction-resumePanorama`。",
      "statement": "应用格式之后的呈现路由：应用全景投影会路由到 portal，应用 Flat 会路由到 window。要进一步进入 Panorama，需要点击 `PlayerUI-TopAction-resumePanorama`。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Format Editing promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:format-editing:c01`

Proposal `PR-FE-C01` comes from `.agents/skills/vp-e2e/features/format-editing.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:format-editing:c02`

Proposal `PR-FE-C02` comes from `.agents/skills/vp-e2e/features/format-editing.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:format-editing:c03`

Proposal `PR-FE-C03` comes from `.agents/skills/vp-e2e/features/format-editing.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:format-editing:c04`

Proposal `PR-FE-C04` comes from `.agents/skills/vp-e2e/features/format-editing.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
