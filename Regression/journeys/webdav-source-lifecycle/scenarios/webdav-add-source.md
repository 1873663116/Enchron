---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:webdav-source-lifecycle:webdav-add-source",
  "title": "通过产品表单添加 WebDAV 来源",
  "journey": "journey:webdav-source-lifecycle",
  "promiseRefs": [
    "promise:remote-source-connection:c01"
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
      "key": "webdav-test-source-ready",
      "schema": "remote-source.webdav-fixture@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:02",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:webdav-source-lifecycle:webdav-add-source:03",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:04",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
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
      "callId": "call:webdav-source-lifecycle:webdav-add-source:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Enchron Regression WebDAV"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:webdav-source-lifecycle:webdav-add-source:01/runtimePath",
        "textJSONKey": "address"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:webdav-source-lifecycle:webdav-add-source:01/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:webdav-source-lifecycle:webdav-add-source:01/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:09",
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
      "callId": "call:webdav-source-lifecycle:webdav-add-source:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "remoteExpectation": "webdav-connection",
        "remoteGenerationToken": "result://call:webdav-source-lifecycle:webdav-add-source:01/generationToken"
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "relatedResults": [
          "result://call:webdav-source-lifecycle:webdav-add-source:05/interaction",
          "result://call:webdav-source-lifecycle:webdav-add-source:10/interaction"
        ]
      },
      "callId": "call:webdav-source-lifecycle:webdav-add-source:12",
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
      "id": "obligation:webdav-source-lifecycle:webdav-add-source:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:webdav-source-lifecycle:webdav-add-source:12",
      "rubric": "rubric:webdav-source-lifecycle.webdav-add-source.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:webdav-source-lifecycle:webdav-add-source:o01:default"
  }
}
---
# 通过产品表单添加 WebDAV 来源

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
