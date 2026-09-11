---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "emby-library",
  "title": "Emby Library",
  "promises": [
    {
      "id": "promise:emby-library:c01",
      "title": "首页的海报墙与\"接下来看\"横条。",
      "statement": "首页的海报墙与\"接下来看\"横条。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:emby-library:c02",
      "title": "系列详情页，含季选择与剧集列表。",
      "statement": "系列详情页，含季选择与剧集列表。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:emby-library:c03",
      "title": "单集详情页上只有一个 Play 入口 `Emby-Detail-Play`，它以服务器回报的进度为续播候选；是否先弹 Resume Playback? alert 由设置页 Resume Playback 一行的偏好决定。",
      "statement": "单集详情页上只有一个 Play 入口 `Emby-Detail-Play`，它以服务器回报的进度为续播候选；是否先弹 Resume Playback? alert 由设置页 Resume Playback 一行的偏好决定。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:emby-library:c04",
      "title": "播放进度回报给服务器（对应 `ViewingStateAuthority.mediaServer`）。",
      "statement": "播放进度回报给服务器（对应 `ViewingStateAuthority.mediaServer`）。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:emby-library:c05",
      "title": "封面经由服务器图片接口获取，按 image tag 作键落盘。",
      "statement": "封面经由服务器图片接口获取，按 image tag 作键落盘。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Emby Library promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:emby-library:c01`

Proposal `PR-EMBY-C01` comes from `.agents/skills/vp-e2e/features/emby-library.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:emby-library:c02`

Proposal `PR-EMBY-C02` comes from `.agents/skills/vp-e2e/features/emby-library.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:emby-library:c03`

Proposal `PR-EMBY-C03` comes from `.agents/skills/vp-e2e/features/emby-library.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:emby-library:c04`

Proposal `PR-EMBY-C04` comes from `.agents/skills/vp-e2e/features/emby-library.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:emby-library:c05`

Proposal `PR-EMBY-C05` comes from `.agents/skills/vp-e2e/features/emby-library.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
