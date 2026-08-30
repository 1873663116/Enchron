---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:playback-failure-category-matrix",
  "title": "播放中四类故障给出对应指引并保住位置",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 760000,
  "staticCases": [
    "connection-interrupted",
    "file-missing",
    "access-refused",
    "data-corrupt"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "faultable-remote-source-ready",
      "schema": "remote-source.faultable@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:03",
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
      "callId": "call:network-resilience:playback-failure-category-matrix:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "recoverable-read-interruption"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "deadlineSeconds": 45,
        "identifier": "PlayerUI-loadFailure-primary",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:08",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:playback-failure-category-matrix:06/receiptID"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-loadFailure-primary"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 5,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 5,
        "minimumPositionMillis": 2000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:12",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:network-resilience:playback-failure-category-matrix:06/activationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:07/matchedElement",
          "result://call:network-resilience:playback-failure-category-matrix:08/fields",
          "result://call:network-resilience:playback-failure-category-matrix:09/restorationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:10/interaction",
          "result://call:network-resilience:playback-failure-category-matrix:11/playbackObservation",
          "result://call:network-resilience:playback-failure-category-matrix:12/fields"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:13",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:15",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:16",
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
      "callId": "call:network-resilience:playback-failure-category-matrix:17",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:18",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "missing-object"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "deadlineSeconds": 45,
        "identifier": "PlayerUI-loadFailure-primary",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:playback-failure-category-matrix:19/receiptID"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:22",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-loadFailure-primary"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:23",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 5,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 5,
        "minimumPositionMillis": 2000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:25",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:network-resilience:playback-failure-category-matrix:19/activationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:20/matchedElement",
          "result://call:network-resilience:playback-failure-category-matrix:21/fields",
          "result://call:network-resilience:playback-failure-category-matrix:22/restorationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:23/interaction",
          "result://call:network-resilience:playback-failure-category-matrix:24/playbackObservation",
          "result://call:network-resilience:playback-failure-category-matrix:25/fields"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:26",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:27",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:28",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:29",
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
      "callId": "call:network-resilience:playback-failure-category-matrix:30",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:31",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "access-denied"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:32",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "deadlineSeconds": 45,
        "identifier": "PlayerUI-loadFailure-primary",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:33",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:34",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:playback-failure-category-matrix:32/receiptID"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:35",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-loadFailure-primary"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:36",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 5,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:37",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 5,
        "minimumPositionMillis": 2000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:38",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:network-resilience:playback-failure-category-matrix:32/activationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:33/matchedElement",
          "result://call:network-resilience:playback-failure-category-matrix:34/fields",
          "result://call:network-resilience:playback-failure-category-matrix:35/restorationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:36/interaction",
          "result://call:network-resilience:playback-failure-category-matrix:37/playbackObservation",
          "result://call:network-resilience:playback-failure-category-matrix:38/fields"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:39",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:40",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:41",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:42",
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
      "callId": "call:network-resilience:playback-failure-category-matrix:43",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:44",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "corrupt-media"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:45",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "deadlineSeconds": 45,
        "identifier": "PlayerUI-loadFailure-primary",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:46",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:playback-failure-category-matrix:47",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:playback-failure-category-matrix:45/receiptID"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:48",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-loadFailure-primary"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:49",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 5,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:50",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 5,
        "minimumPositionMillis": 2000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:51",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:network-resilience:playback-failure-category-matrix:45/activationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:46/matchedElement",
          "result://call:network-resilience:playback-failure-category-matrix:47/fields",
          "result://call:network-resilience:playback-failure-category-matrix:48/restorationReceipt",
          "result://call:network-resilience:playback-failure-category-matrix:49/interaction",
          "result://call:network-resilience:playback-failure-category-matrix:50/playbackObservation",
          "result://call:network-resilience:playback-failure-category-matrix:51/fields"
        ]
      },
      "callId": "call:network-resilience:playback-failure-category-matrix:52",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "connection-interrupted",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:network-resilience:playback-failure-category-matrix:o01:connection-interrupted",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:network-resilience:playback-failure-category-matrix:13",
      "rubric": "rubric:network-resilience.playback-failure-category-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "file-missing",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:network-resilience:playback-failure-category-matrix:o01:file-missing",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:network-resilience:playback-failure-category-matrix:26",
      "rubric": "rubric:network-resilience.playback-failure-category-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "access-refused",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:network-resilience:playback-failure-category-matrix:o01:access-refused",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:network-resilience:playback-failure-category-matrix:39",
      "rubric": "rubric:network-resilience.playback-failure-category-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "data-corrupt",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:network-resilience:playback-failure-category-matrix:o01:data-corrupt",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:network-resilience:playback-failure-category-matrix:52",
      "rubric": "rubric:network-resilience.playback-failure-category-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:network-resilience:playback-failure-category-matrix:o01:connection-interrupted"
      },
      {
        "observation": "obligation:network-resilience:playback-failure-category-matrix:o01:file-missing"
      },
      {
        "observation": "obligation:network-resilience:playback-failure-category-matrix:o01:access-refused"
      },
      {
        "observation": "obligation:network-resilience:playback-failure-category-matrix:o01:data-corrupt"
      }
    ]
  }
}
---
# 播放中四类故障给出对应指引并保住位置

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
