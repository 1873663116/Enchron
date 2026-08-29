---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:issue-surface-behavior:source-failure-guidance-matrix",
  "title": "凭据、主机与地址失败给出可区分下一步",
  "journey": "journey:issue-surface-behavior",
  "promiseRefs": [
    "promise:remote-source-connection:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 260000,
  "staticCases": [
    "credentials-rejected",
    "server-unreachable",
    "invalid-address",
    "requires-https"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "issue-fixtures-ready",
      "schema": "fixture-set.issue-surfaces@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:02",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:03",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:04",
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
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Failure Matrix credentials-rejected"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:01/runtimePath",
        "textJSONKey": "address"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:01/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:01/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:12",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:13",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:14",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:15",
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
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Failure Matrix server-unreachable"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:17",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:12/runtimePath",
        "textJSONKey": "unreachableAddress"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:18",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:12/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:19",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:12/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:20",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:21",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:22",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:23",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:24",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:25",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:26",
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
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:27",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Failure Matrix invalid-address"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:28",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:23/runtimePath",
        "textJSONKey": "missingPathAddress"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:29",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:23/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:30",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:23/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:31",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:32",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:33",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:34",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:35",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:36",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:37",
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
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:38",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "secret": false,
        "text": "Failure Matrix requires-https"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:39",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:34/runtimePath",
        "textJSONKey": "httpAddress"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:40",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "secret": false,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:34/runtimePath",
        "textJSONKey": "user"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:41",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "secret": true,
        "textFile": "result://call:issue-surface-behavior:source-failure-guidance-matrix:34/runtimePath",
        "textJSONKey": "password"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:42",
      "maxInvocations": 1,
      "operation": "operation:accessibility.type@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:43",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV"
      },
      "callId": "call:issue-surface-behavior:source-failure-guidance-matrix:44",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "credentials-rejected",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:credentials-rejected",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:source-failure-guidance-matrix:11",
      "rubric": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "server-unreachable",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:server-unreachable",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:source-failure-guidance-matrix:22",
      "rubric": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "invalid-address",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:invalid-address",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:source-failure-guidance-matrix:33",
      "rubric": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "requires-https",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:requires-https",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:issue-surface-behavior:source-failure-guidance-matrix:44",
      "rubric": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:credentials-rejected"
      },
      {
        "observation": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:server-unreachable"
      },
      {
        "observation": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:invalid-address"
      },
      {
        "observation": "obligation:issue-surface-behavior:source-failure-guidance-matrix:o01:requires-https"
      }
    ]
  }
}
---
# 凭据、主机与地址失败给出可区分下一步

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
