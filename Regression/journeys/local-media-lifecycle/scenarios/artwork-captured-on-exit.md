---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:artwork-captured-on-exit",
  "title": "退出播放时用当前画面更新 Artwork",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:cache-and-artwork:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 600000,
  "staticCases": [
    "default"
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
      "arguments": {
        "target": "artwork-cache"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:01",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:02",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 5000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerPanel-button-play"
        ],
        "summonControls": true
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 30,
        "lifecycle": "paused",
        "presentation": "either-main-window"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:07",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "artworkExpectation": "exit-replaces-current-frame",
        "context": "window",
        "count": 4,
        "minimumIntervalMillis": 0
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:08",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "artworkExpectation": "exit-replaces-current-frame",
        "artworkKey": "result://call:local-media-lifecycle:artwork-captured-on-exit:08/artworkKey",
        "context": "window",
        "count": 4,
        "minimumIntervalMillis": 0
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:11",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:12",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 22000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:13",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerPanel-button-play"
        ],
        "summonControls": true
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:14",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 30,
        "lifecycle": "paused",
        "presentation": "either-main-window"
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:15",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "artworkExpectation": "exit-replaces-current-frame",
        "artworkKey": "result://call:local-media-lifecycle:artwork-captured-on-exit:08/artworkKey",
        "context": "window",
        "count": 4,
        "minimumIntervalMillis": 0
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:16",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:17",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "artworkExpectation": "exit-replaces-current-frame",
        "artworkKey": "result://call:local-media-lifecycle:artwork-captured-on-exit:08/artworkKey",
        "context": "window",
        "count": 4,
        "minimumIntervalMillis": 0,
        "relatedFrameManifests": [
          "result://call:local-media-lifecycle:artwork-captured-on-exit:08/frameManifest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:10/frameManifest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:16/frameManifest"
        ],
        "relatedResults": [
          "result://call:local-media-lifecycle:artwork-captured-on-exit:06/artworkCurrentDigest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:06/artworkStoredDigest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:06/artworkByteStreamScope",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:06/artworkByteStreamRequestCount",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:08/artworkStoredDigest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:08/artworkStoredBytes",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:12/artworkCurrentDigest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:12/artworkStoredDigest",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:12/artworkByteStreamScope",
          "result://call:local-media-lifecycle:artwork-captured-on-exit:12/artworkByteStreamRequestCount"
        ]
      },
      "callId": "call:local-media-lifecycle:artwork-captured-on-exit:18",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:artwork-captured-on-exit:o01:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:artwork-captured-on-exit:18",
      "rubric": "rubric:local-media-lifecycle.artwork-captured-on-exit.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:local-media-lifecycle:artwork-captured-on-exit:o01:default"
  }
}
---
# 退出播放时用当前画面更新 Artwork

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
