---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "picture-interpretation",
  "title": "Picture Interpretation",
  "promises": [
    {
      "id": "promise:picture-interpretation:c01",
      "title": "HDR10 与 HLG 片源的色彩与亮度解释正确。",
      "statement": "HDR10 与 HLG 片源的色彩与亮度解释正确。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:picture-interpretation:c02",
      "title": "对 Dolby Vision profile 5、7 双层、8 单层、10（AV1）各形态的处理。",
      "statement": "对 Dolby Vision profile 5、7 双层、8 单层、10（AV1）各形态的处理。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:picture-interpretation:c03",
      "title": "向后兼容的 Dolby Vision 单层片源可以在播放中切换为其声明所对应的 HDR10 或 HLG 解释；Profile 5 不提供这一偏好。",
      "statement": "向后兼容的 Dolby Vision 单层片源可以在播放中切换为其声明所对应的 HDR10 或 HLG 解释；Profile 5 不提供这一偏好。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:picture-interpretation:c04",
      "title": "立体片源的左右眼画面正确分离并呈现深度。",
      "statement": "立体片源的左右眼画面正确分离并呈现深度。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:picture-interpretation:c05",
      "title": "180° 与 360° 全景片源按所选覆盖角包裹画面。",
      "statement": "180° 与 360° 全景片源按所选覆盖角包裹画面。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:picture-interpretation:c06",
      "title": "对 Apple Immersive 投影的支持。",
      "statement": "对 Apple Immersive 投影的支持。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Picture Interpretation promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:picture-interpretation:c01`

Proposal `PR-PI-C01` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 9, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:picture-interpretation:c02`

Proposal `PR-PI-C02` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 10, section Sub-features, source ordinal 2.

Profile 20 自 2026-09-11 起不在自动覆盖内。`scenario:dynamic-range-interpretation:dolby-vision-profile-matrix` 曾带一个 `dv-profile-20` case，现已移除；本 Promise 的 title 与 statement 同日去掉「、20」，与 `.agents/skills/vp-e2e/features/picture-interpretation.md` 第 10 行仍然逐字相同。排除的理由不是缺片源：Apple 的 Profile 20 HLS 样本保存在 `TestMedia/Samples/DynamicRange/DolbyVision/Profile20/Apple-Historic-Planet-HLS`，`Tests/Fixtures/fixture-registry.json` 另注册了 `Samples/DynamicRange/DolbyVision/Profile20/Apple-Streaming-Examples/3D-example.mp4`。当时记下的理由是「AVFoundation 不支持 Profile 20」，该理由在 2026-09-11 复核时被推翻：Apple 的 HLS authoring specification 在 visionOS 修订条款下第 1.9c 条写 “Dolby Vision stereo video MUST be Profile 20 (MV-HEVC) and less than or equal to Level 9.”，第 1.40 条写 “Stereo video MUST be encoded using Dolby Vision Profile 20 (MV-HEVC).”（`https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices`，文档修订记录 2025-03-25 条目为 “Clarified use of DV20 for Stereo video for VisionOS.”）。visionOS 既然要求立体 Dolby Vision 片源必须是 Profile 20，平台不支持该 profile 的说法不成立。本仓库也没有任何对 Profile 20 播放的实测。因此这个 case 的排除当前没有成立的依据，留待重新裁决；在此之前本 Promise 不宣称覆盖 Profile 20。

语义权威决策 `HC-007`（`Config/regression/semantic-authority-decisions.tsv` 第 9 行，`Config/regression/catalog-root/semantic-authority.json` 同文）读作 「Dolby Vision profiles 10 and 20 remain included. Supply them in an admitted MP4 or MKV form; do not add DASH or HLS solely for fixture reachability and do not drop the profiles.」，未随 case 移除而改动，也不应当改动：它「不得放弃这两个 profile」的裁断与上一段推翻的理由方向一致。`Scripts/regression/review_stage.py` 第 633 至 702 行要求 `decisions` 恰好是 HC-000 至 HC-023、每条 `status` 都是 `decided`，没有 superseded、amended 或修订历史的字段，因此改判一条已批准的决策只能就地改写批准记录的文字。`Regression/agent-operability-review-protocol.md` 第 38 行禁止评审 Agent 裁决 HumanCoverage 问题，`docs/MERGE_EVIDENCE.md` 把 `regression-contract` 归入 `HumanReviewRequired`；本次目录改动不持有该授权，决策原文因此保持不变，冲突记录在此。

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:picture-interpretation:c03`

Proposal `PR-PI-C03` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 11, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:picture-interpretation:c04`

Proposal `PR-PI-C04` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 12, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:picture-interpretation:c05`

Proposal `PR-PI-C05` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 13, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:picture-interpretation:c06`

Proposal `PR-PI-C06` comes from `.agents/skills/vp-e2e/features/picture-interpretation.md` at line 14, section Sub-features, source ordinal 6.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
