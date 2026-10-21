---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:portal-format-and-panorama-actions-coexist",
  "title": "Portal 同时提供格式编辑与 Enter Panorama",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:format-editing:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 150000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:03",
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
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono",
        "summonControls": true
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "context": "portal",
        "dismissControls": true,
        "labels": [
          "Playback surface"
        ]
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "portal",
        "identifiers": [
          "PlayerUI-TopAction-videoFormat"
        ]
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "portal",
        "identifiers": [
          "PlayerUI-VideoFormat-cancel"
        ]
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "alsoInspect": [
          "PlayerUI-TopAction-resumePanorama",
          "PlayerUI-TopAction-videoFormat"
        ],
        "context": "portal",
        "dismissControls": true,
        "identifiers": [
          "PlayerUI-TopAction-resumePanorama"
        ],
        "labels": [
          "Playback surface"
        ]
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:presentation-tour:portal-format-and-panorama-actions-coexist:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:portal-format-and-panorama-actions-coexist:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:portal-format-and-panorama-actions-coexist:09",
      "rubric": "rubric:presentation-tour.portal-format-and-panorama-actions-coexist.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:portal-format-and-panorama-actions-coexist:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:portal-format-and-panorama-actions-coexist:10",
      "rubric": "rubric:presentation-tour.portal-format-and-panorama-actions-coexist.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:portal-format-and-panorama-actions-coexist:o01:default"
      },
      {
        "observation": "obligation:presentation-tour:portal-format-and-panorama-actions-coexist:o02:default"
      }
    ]
  }
}
---
# Portal 同时提供格式编辑与 Enter Panorama

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
