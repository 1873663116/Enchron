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
      "title": "存在历史进度且由用户主动打开时，本地与 Emby 走同一个决定：设置页 Resume Playback 为 Ask Every Time 时弹出 Resume Playback? alert，Resume 尊重进度，Play from Start 从零开始；为 Always Resume 或 Always Start Over 时不弹 alert，直接按该偏好开播。自动续播（Play Next）不在此列。",
      "statement": "存在历史进度且由用户主动打开时，本地与 Emby 走同一个决定：设置页 Resume Playback 为 Ask Every Time 时弹出 Resume Playback? alert，Resume 尊重进度，Play from Start 从零开始；为 Always Resume 或 Always Start Over 时不弹 alert，直接按该偏好开播。自动续播（Play Next）不在此列：它在 Ask Every Time 下也不弹 alert，直接按保存的进度续播。",
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

打开的来源决定这条承诺是否适用。`Modules/Playback/PlaybackLaunchCoordinator.swift:198` 的 `(.askEveryTime, .userInitiated)` 分支在保存位置大于零时才登记 `pendingResumeDecision`，也就是弹出 alert；`:217` 的 `(.askEveryTime, .automaticContinuation)` 分支在同一偏好下直接按保存位置续播，并记一次 `automaticResumeBypasses`。`.automaticContinuation` 的唯一来源是 Play Next（`:667`）。Emby 走 `decideResume(fromSeconds:onChoice:)`（`:266`），该入口没有 origin 参数，因而总是用户主动打开这一侧。两条计数由 `scenario:local-media-lifecycle:automatic-play-next-resume-policy` 的 rubric 以 `resumePromptPresentations=1` 与 `automaticResumeBypasses=1` 同时读出。

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:viewing-state:c05`

Proposal `PR-VS-C05` comes from `.agents/skills/vp-e2e/features/viewing-state.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
