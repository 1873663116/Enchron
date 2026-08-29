---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "media-import",
  "title": "Media Import",
  "promises": [
    {
      "id": "promise:media-import:c01",
      "title": "通过 Files 选择器导入。这是真实用户的主路径，包含 iCloud Drive 的目录导航。",
      "statement": "通过 Files 选择器导入。这是真实用户的主路径，包含 iCloud Drive 的目录导航。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:media-import:c02",
      "title": "通过相册选择器导入。",
      "statement": "通过相册选择器导入。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:media-import:c03",
      "title": "验证用的注入路径：位于 TestMediaInbox 内的文件经由通道命令 `importMedia` 导入，走的是同一个 addFiles 入口。",
      "statement": "验证用的注入路径：位于 TestMediaInbox 内的文件经由通道命令 `importMedia` 导入，走的是同一个 addFiles 入口。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Media Import promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:media-import:c01`

Proposal `PR-MI-C01` comes from `.agents/skills/vp-e2e/features/media-import.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:media-import:c02`

Proposal `PR-MI-C02` comes from `.agents/skills/vp-e2e/features/media-import.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:media-import:c03`

Proposal `PR-MI-C03` comes from `.agents/skills/vp-e2e/features/media-import.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
