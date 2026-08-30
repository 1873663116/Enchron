---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:format-coverage:audio-delivery-codec-matrix",
  "title": "压缩直递与 Float32 PCM 编解码矩阵",
  "journey": "journey:format-coverage",
  "promiseRefs": [
    "promise:track-selection:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 930000,
  "staticCases": [
    "ac3",
    "eac3-joc",
    "dts",
    "truehd",
    "vorbis",
    "aac",
    "flac"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "format-corpus-ready",
      "schema": "fixture-set.format-corpus@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-audio-codec-matrix-15s.mkv"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:03",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:08",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-audio-codec-matrix-15s.mkv"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:10",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:12",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-3"
        ]
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:15",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:16",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-dts_es.dts"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:17",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:18",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 500,
        "minimumRemainingMillis": 500
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:22",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-atmos.thd"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:23",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "ended",
        "presentation": "window"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:25",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:26",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:27",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-1.0-test_small.ogg"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:28",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:29",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 1000
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:30",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:31",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:32",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:33",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-audio-codec-matrix-15s.mkv"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:34",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:35",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:36",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-1"
        ]
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:37",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:38",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:39",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:40",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-audio-codec-matrix-15s.mkv"
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:41",
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
      "callId": "call:format-coverage:audio-delivery-codec-matrix:42",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:43",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-8"
        ]
      },
      "callId": "call:format-coverage:audio-delivery-codec-matrix:44",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {},
      "callId": "call:format-coverage:audio-delivery-codec-matrix:45",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "ac3",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:ac3",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:07",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "eac3-joc",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:eac3-joc",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:14",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "dts",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:dts",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:20",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "truehd",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:truehd",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:25",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "vorbis",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:vorbis",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:31",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "aac",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:aac",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:38",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "flac",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:format-coverage:audio-delivery-codec-matrix:o01:flac",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:format-coverage:audio-delivery-codec-matrix:45",
      "rubric": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:ac3"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:eac3-joc"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:dts"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:truehd"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:vorbis"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:aac"
      },
      {
        "observation": "obligation:format-coverage:audio-delivery-codec-matrix:o01:flac"
      }
    ]
  }
}
---
# 压缩直递与 Float32 PCM 编解码矩阵

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
