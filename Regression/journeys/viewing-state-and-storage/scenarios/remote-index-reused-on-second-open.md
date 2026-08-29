---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:remote-index-reused-on-second-open",
  "title": "远程文件第二次打开复用容器索引",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:cache-and-artwork:c01"
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:01",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "container-index"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:02",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:03",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:06",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:07",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:08",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:02/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:09",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:02/viewingStorageDigest",
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:09/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:13",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:14",
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
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:15",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:02/viewingStorageDigest",
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:09/viewingStorageDigest",
          "result://call:viewing-state-and-storage:remote-index-reused-on-second-open:11/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:remote-index-reused-on-second-open:16",
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
      "id": "obligation:viewing-state-and-storage:remote-index-reused-on-second-open:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:remote-index-reused-on-second-open:16",
      "rubric": "rubric:viewing-state-and-storage.remote-index-reused-on-second-open.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:viewing-state-and-storage:remote-index-reused-on-second-open:o01:default"
  }
}
---
# 远程文件第二次打开复用容器索引

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
