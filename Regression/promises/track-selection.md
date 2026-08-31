---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "track-selection",
  "title": "Track Selection",
  "promises": [
    {
      "id": "promise:track-selection:c01",
      "title": "音轨切换，包括多条同名音轨之间的切换。",
      "statement": "音轨切换，包括多条同名音轨之间的切换。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:track-selection:c02",
      "title": "音轨在打开、预热、播放、跳转或 renderer 失败时退休后，视频仍继续播放并可继续跳转。",
      "statement": "音轨在打开、预热、播放、跳转或 renderer 失败时退休后，视频仍继续播放并可继续跳转。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:track-selection:c03",
      "title": "AC-3 与 E-AC-3（含 JOC）采用压缩直递；其余 FFmpeg 可解码的音轨则以保留原采样率和声道布局的交错 Float32 PCM 播放。",
      "statement": "AC-3 与 E-AC-3（含 JOC）采用压缩直递；其余 FFmpeg 可解码的音轨则以保留原采样率和声道布局的交错 Float32 PCM 播放。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:track-selection:c04",
      "title": "字幕轨的切换与关闭。",
      "statement": "字幕轨的切换与关闭。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:track-selection:c05",
      "title": "外挂字幕的加载，来源包括本地同目录文件、远程来源与 Emby 的 external stream。",
      "statement": "外挂字幕的加载，来源包括本地同目录文件、远程来源与 Emby 的 external stream。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:track-selection:c06",
      "title": "轨道选择在跳转与呈现切换之后仍然保持。",
      "statement": "轨道选择在跳转与呈现切换之后仍然保持。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Track Selection promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:track-selection:c01`

Proposal `PR-TS-C01` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:track-selection:c02`

Proposal `PR-TS-C02` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:track-selection:c03`

Proposal `PR-TS-C03` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:track-selection:c04`

Proposal `PR-TS-C04` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:track-selection:c05`

Proposal `PR-TS-C05` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:track-selection:c06`

Proposal `PR-TS-C06` comes from `.agents/skills/vp-e2e/features/track-selection.md` at line 12, section Sub-features, source ordinal 6.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
