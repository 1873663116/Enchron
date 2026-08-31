---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:projection-and-stereo:apple-immersive-projection",
  "title": "Apple Immersive 投影声明进入渲染器",
  "journey": "journey:projection-and-stereo",
  "promiseRefs": [
    "promise:picture-interpretation:c06"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 180000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "projection-corpus-ready",
      "schema": "fixture-set.projection-stereo@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:projection-and-stereo:apple-immersive-projection:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "fileName": "Immersive-Video-example.f99766.mp4"
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-Immersive-Video-example.f99766.mp4"
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:04",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {
        "context": "panorama",
        "deadlineSeconds": 20,
        "identifier": "PlayerUI-spatial-state",
        "requireMatchedElement": true,
        "summonControls": true
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "panorama",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "relatedResults": [
          "result://call:projection-and-stereo:apple-immersive-projection:07/matchedElement",
          "result://call:projection-and-stereo:apple-immersive-projection:07/response"
        ]
      },
      "callId": "call:projection-and-stereo:apple-immersive-projection:08",
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
      "id": "obligation:projection-and-stereo:apple-immersive-projection:o01:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:projection-and-stereo:apple-immersive-projection:08",
      "rubric": "rubric:projection-and-stereo.apple-immersive-projection.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:projection-and-stereo:apple-immersive-projection:o01:default"
  }
}
---
# Apple Immersive 投影声明进入渲染器

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
