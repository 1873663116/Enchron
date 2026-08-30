---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:subtitle-switch-and-off",
  "title": "字幕切换、关闭与恢复",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:track-selection:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 128000,
  "staticCases": [
    "embedded-text",
    "embedded-bitmap",
    "off",
    "restore"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-subtitles-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-subtitles-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:04",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles",
          "PlayerUI-menu-subtitles-ffmpeg.subtitle.3"
        ]
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:07",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles",
          "PlayerUI-menu-subtitles-ffmpeg.subtitle.5"
        ]
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:09",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles",
          "PlayerUI-menu-subtitles-off"
        ]
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:11",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles",
          "PlayerUI-menu-subtitles-ffmpeg.subtitle.3"
        ]
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedFrameManifests": [
          "result://call:local-media-lifecycle:subtitle-switch-and-off:07/frameManifest",
          "result://call:local-media-lifecycle:subtitle-switch-and-off:09/frameManifest",
          "result://call:local-media-lifecycle:subtitle-switch-and-off:11/frameManifest"
        ]
      },
      "callId": "call:local-media-lifecycle:subtitle-switch-and-off:13",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "embedded-text",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:embedded-text",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:subtitle-switch-and-off:07",
      "rubric": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "embedded-bitmap",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:embedded-bitmap",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:subtitle-switch-and-off:09",
      "rubric": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "off",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:off",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:subtitle-switch-and-off:11",
      "rubric": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "restore",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:restore",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:subtitle-switch-and-off:13",
      "rubric": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:embedded-text"
      },
      {
        "observation": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:embedded-bitmap"
      },
      {
        "observation": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:off"
      },
      {
        "observation": "obligation:local-media-lifecycle:subtitle-switch-and-off:o01:restore"
      }
    ]
  }
}
---
# 字幕切换、关闭与恢复

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
