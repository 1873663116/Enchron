---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:webdav-source-lifecycle:certificate-trust-boundary",
  "title": "证书询问只在连接阶段出现",
  "journey": "journey:webdav-source-lifecycle",
  "promiseRefs": [
    "promise:remote-source-connection:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 320000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "webdav-test-source-ready",
      "schema": "remote-source.webdav-fixture@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:02",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {},
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:04",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:05",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {},
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-add",
          "FileBrowsing-SourcesSidebar-addWebDAV"
        ]
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Enchron Regression WebDAV Draft"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/runtimePath",
        "textJSONKey": "address"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect",
          "FileBrowsing-CertificateTrust-cancel"
        ]
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "assertAbsent": [
          "FileBrowsing-CertificateTrust-cancel",
          "FileBrowsing-SourceConnection-webDAV-password"
        ],
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-add",
          "FileBrowsing-SourcesSidebar-addWebDAV"
        ]
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "deadlineSeconds": 20,
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "requireMatchedElement": true
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:14",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:webdav-source-lifecycle:certificate-trust-boundary:06/cursorToken",
        "relatedResults": [
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:08/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:09/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:10/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:13/tappedIdentifiers",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:13/assertAbsentObservations",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:14/response",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:14/matchedElement"
        ],
        "remoteExpectation": "certificate-trust-boundary",
        "remoteGenerationToken": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/generationToken"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:15",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect",
          "FileBrowsing-CertificateTrust-trust"
        ],
        "labels": [
          "以后"
        ]
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:17",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:18",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:19",
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
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:20",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 1000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:21",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:webdav-source-lifecycle:certificate-trust-boundary:06/cursorToken",
        "relatedResults": [
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:08/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:09/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:10/postActionState",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:13/tappedIdentifiers",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:13/assertAbsentObservations",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:14/response",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:14/matchedElement",
          "result://call:webdav-source-lifecycle:certificate-trust-boundary:15/cursorToken"
        ],
        "remoteExpectation": "certificate-trust-boundary",
        "remoteGenerationToken": "result://call:webdav-source-lifecycle:certificate-trust-boundary:01/generationToken"
      },
      "callId": "call:webdav-source-lifecycle:certificate-trust-boundary:22",
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
      "id": "obligation:webdav-source-lifecycle:certificate-trust-boundary:o01:cancelled-form",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:webdav-source-lifecycle:certificate-trust-boundary:15",
      "rubric": "rubric:webdav-source-lifecycle.certificate-trust-boundary.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:webdav-source-lifecycle:certificate-trust-boundary:o01:connected-trace",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:webdav-source-lifecycle:certificate-trust-boundary:22",
      "rubric": "rubric:webdav-source-lifecycle.certificate-trust-boundary.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:webdav-source-lifecycle:certificate-trust-boundary:o01:cancelled-form"
      },
      {
        "observation": "obligation:webdav-source-lifecycle:certificate-trust-boundary:o01:connected-trace"
      }
    ]
  }
}
---
# 证书询问只在连接阶段出现

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
