---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "viewing-state",
  "title": "Viewing State",
  "promises": [
    {
      "id": "promise:viewing-state:c01",
      "title": "退出播放时保存当前位置。",
      "statement": "退出播放时保存当前位置。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:viewing-state:c02",
      "title": "再次打开同一视频时从该位置续播。",
      "statement": "再次打开同一视频时从该位置续播。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:viewing-state:c03",
      "title": "播放完的媒体被标记为已看完，之后不再续播。",
      "statement": "播放完的媒体被标记为已看完，之后不再续播。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:viewing-state:c04",
      "title": "Emby 提供 Resume 与 Play from Beginning 两个入口，前者尊重服务器进度，后者忽略服务器进度。",
      "statement": "Emby 提供 Resume 与 Play from Beginning 两个入口，前者尊重服务器进度，后者忽略服务器进度。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:viewing-state:c05",
      "title": "设置页的 Playback Progress 一行可以整体清除本地进度。",
      "statement": "设置页的 Playback Progress 一行可以整体清除本地进度。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Viewing State promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:viewing-state:c01`

Proposal `PR-VS-C01` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:viewing-state:c02`

Proposal `PR-VS-C02` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:viewing-state:c03`

Proposal `PR-VS-C03` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:viewing-state:c04`

Proposal `PR-VS-C04` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:viewing-state:c05`

Proposal `PR-VS-C05` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
