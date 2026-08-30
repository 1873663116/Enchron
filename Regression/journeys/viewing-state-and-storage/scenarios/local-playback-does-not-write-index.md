---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:local-playback-does-not-write-index",
  "title": "本地播放不写容器索引缓存",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:cache-and-artwork:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 600000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "viewing-storage-fixtures-ready",
      "schema": "fixture-set.viewing-storage@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "target": "container-index-cache"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:01",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "container-index",
          "viewing-state"
        ],
        "containerIndexExpectation": "baseline-empty",
        "deadlineSeconds": 30,
        "includeViewingStorage": true
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:02",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Media Library"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:05",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {},
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:06",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:07",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:08",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "sdr-bframe-aggregate-30s.mkv",
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:09",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "containerIndexExpectation": "local-active-empty",
        "expectedBaselineDigest": "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/containerIndexDigest",
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:10",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "containerIndexExpectation": "local-after-empty",
        "expectedBaselineDigest": "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/containerIndexDigest",
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/viewingStorageDigest",
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:10/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:12",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:14",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:15",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:16",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "sdr-bframe-aggregate-30s.mkv",
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:17",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "containerIndexExpectation": "remote-positive-control",
        "expectedBaselineDigest": "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/containerIndexDigest",
        "expectedLocalActiveDigest": "result://call:viewing-state-and-storage:local-playback-does-not-write-index:10/containerIndexDigest",
        "expectedLocalAfterDigest": "result://call:viewing-state-and-storage:local-playback-does-not-write-index:12/containerIndexDigest",
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:02/viewingStorageDigest",
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:10/viewingStorageDigest",
          "result://call:viewing-state-and-storage:local-playback-does-not-write-index:12/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:local-playback-does-not-write-index:18",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:viewing-state-and-storage:local-playback-does-not-write-index:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:local-playback-does-not-write-index:18",
      "rubric": "rubric:viewing-state-and-storage.local-playback-does-not-write-index.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:viewing-state-and-storage:local-playback-does-not-write-index:o01:default"
  }
}
---
# 本地播放不写容器索引缓存

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
