---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:audio-track-switch-same-session",
  "title": "同名与跨编码音轨在同一会话切换",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:track-selection:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 130000,
  "staticCases": [
    "unique-label",
    "duplicate-label-index-0",
    "duplicate-label-index-1"
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
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-duplicate-label-audio-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-duplicate-label-audio-30s.mkv"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:04",
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
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-1"
        ]
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "durationMillis": 5000,
        "expectedAudioTrackID": "1",
        "expectedSession": "result://call:local-media-lifecycle:audio-track-switch-same-session:06/session",
        "inputDevice": "Steinberg UR12",
        "wavPath": "audio/audio-track-switch-same-session-unique-label.wav"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:08",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-audio@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "durationMillis": 5000,
        "expectedAudioTrackID": "2",
        "expectedSession": "result://call:local-media-lifecycle:audio-track-switch-same-session:06/session",
        "inputDevice": "Steinberg UR12",
        "wavPath": "audio/audio-track-switch-same-session-duplicate-label-index-0.wav"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-audio@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-3"
        ]
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "durationMillis": 5000,
        "expectedAudioTrackID": "3",
        "expectedSession": "result://call:local-media-lifecycle:audio-track-switch-same-session:06/session",
        "inputDevice": "Steinberg UR12",
        "wavPath": "audio/audio-track-switch-same-session-duplicate-label-index-1.wav"
      },
      "callId": "call:local-media-lifecycle:audio-track-switch-same-session:12",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-audio@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "unique-label",
      "evidenceSchema": "audio-measurement@2",
      "evidenceType": "audio.measurement",
      "id": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:unique-label",
      "oracle": "oracle:agent-audio@2",
      "producedByCall": "call:local-media-lifecycle:audio-track-switch-same-session:08",
      "rubric": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "duplicate-label-index-0",
      "evidenceSchema": "audio-measurement@2",
      "evidenceType": "audio.measurement",
      "id": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:duplicate-label-index-0",
      "oracle": "oracle:agent-audio@2",
      "producedByCall": "call:local-media-lifecycle:audio-track-switch-same-session:10",
      "rubric": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "duplicate-label-index-1",
      "evidenceSchema": "audio-measurement@2",
      "evidenceType": "audio.measurement",
      "id": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:duplicate-label-index-1",
      "oracle": "oracle:agent-audio@2",
      "producedByCall": "call:local-media-lifecycle:audio-track-switch-same-session:12",
      "rubric": "rubric:local-media-lifecycle.audio-track-switch-same-session.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:unique-label"
      },
      {
        "observation": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:duplicate-label-index-0"
      },
      {
        "observation": "obligation:local-media-lifecycle:audio-track-switch-same-session:o01:duplicate-label-index-1"
      }
    ]
  }
}
---
# 同名与跨编码音轨在同一会话切换

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
