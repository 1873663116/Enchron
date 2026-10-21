---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:external-subtitle-source-matrix",
  "title": "本地、远程与 Emby 外挂字幕加载",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:track-selection:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 420000,
  "staticCases": [
    "local-sidecar",
    "webdav-sidecar",
    "emby-external-stream"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    },
    {
      "key": "local-directory-subtitle-source-ready",
      "schema": "media-source.local-directory-sidecars@1"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-folder-sdr-bframe-aggregate-30s-sidecars"
        ],
        "settleDelayMillis": 500
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:04",
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
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "host": "playerUI",
        "sourceKind": "local-sidecar",
        "trackLabel": "sdr-bframe-aggregate-30s.zh-CN.srt"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:playback.select-subtitle@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/host",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/sourceKind",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/deadlineSeconds",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/discoveredTracks",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/selectedTrack",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/settlement",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:06/identityObservation"
        ]
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:08",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:12",
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
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:13",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "host": "playerUI",
        "sourceKind": "source-directory-sidecar",
        "trackLabel": "sdr-bframe-aggregate-30s.zh-CN.srt"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:playback.select-subtitle@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/host",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/sourceKind",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/deadlineSeconds",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/discoveredTracks",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/selectedTrack",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/settlement",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:14/identityObservation"
        ]
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:15",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:16",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:17",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Emby",
          "Enchron Regression Series, poster",
          "Enchron Regression Episode, episode"
        ]
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:18",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "host": "playerUI",
        "sourceKind": "emby-external-stream"
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:playback.select-subtitle@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/host",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/sourceKind",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/deadlineSeconds",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/discoveredTracks",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/selectedTrack",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/settlement",
          "result://call:local-media-lifecycle:external-subtitle-source-matrix:20/identityObservation"
        ]
      },
      "callId": "call:local-media-lifecycle:external-subtitle-source-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "local-sidecar",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:local-sidecar",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:external-subtitle-source-matrix:07",
      "rubric": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "webdav-sidecar",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:webdav-sidecar",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:external-subtitle-source-matrix:15",
      "rubric": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "emby-external-stream",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:emby-external-stream",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:external-subtitle-source-matrix:21",
      "rubric": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:local-sidecar"
      },
      {
        "observation": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:webdav-sidecar"
      },
      {
        "observation": "obligation:local-media-lifecycle:external-subtitle-source-matrix:o01:emby-external-stream"
      }
    ]
  }
}
---
# 本地、远程与 Emby 外挂字幕加载

Each ordered static case begins with its own relaunch and ends with an immediate frame capture produced only for that case. The subtitle Operation discovers the current product menu and selects the unique external track without a fixed track ID or label. The candidate-missing and selection-not-settled outcomes are product-semantic observations with succeeded=true, so capture and the bound Agent Oracle remain mandatory; only invalid Preparation identity or corrupted command transport may interrupt the attempt technically. Evidence from another case, Scenario, lane, or attempt is inadmissible.
