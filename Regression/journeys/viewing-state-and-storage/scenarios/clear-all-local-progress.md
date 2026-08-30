---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:clear-all-local-progress",
  "title": "Playback Progress 清除全部本地观看状态",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:viewing-state:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 630000,
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
        "awaitEmptyStores": [
          "viewing-state"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:01",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:02",
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
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:04",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "fileName": "viewing-storage-16m01s-b.mp4"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:05",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:06",
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
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:07",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "viewing-storage-16m01s.mp4",
        "minimumPositionMillis": 20000,
        "minimumRemainingMillis": 300000
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:08",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:clear-all-local-progress:01/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:10",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s-b.mp4"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:11",
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
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:12",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "positionMillionths": 997000,
        "summonControls": true
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:13",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "ended",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:clear-all-local-progress:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:10/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:15",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:clear-all-local-progress:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:10/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:15/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:17",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "target": "playback-progress"
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:18",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "viewing-state"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:clear-all-local-progress:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:10/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:15/viewingStorageDigest",
          "result://call:viewing-state-and-storage:clear-all-local-progress:17/viewingStorageDigest"
        ],
        "relatedResults": [
          "result://call:viewing-state-and-storage:clear-all-local-progress:01/viewingStorageObservation",
          "result://call:viewing-state-and-storage:clear-all-local-progress:10/viewingStorageObservation",
          "result://call:viewing-state-and-storage:clear-all-local-progress:15/viewingStorageObservation",
          "result://call:viewing-state-and-storage:clear-all-local-progress:17/viewingStorageObservation"
        ]
      },
      "callId": "call:viewing-state-and-storage:clear-all-local-progress:19",
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
      "id": "obligation:viewing-state-and-storage:clear-all-local-progress:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:clear-all-local-progress:19",
      "rubric": "rubric:viewing-state-and-storage.clear-all-local-progress.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:viewing-state-and-storage:clear-all-local-progress:o01:default"
  }
}
---
# Playback Progress 清除全部本地观看状态

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
