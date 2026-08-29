---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:library-management:files-picker-import-route",
  "title": "Files 选择器与 iCloud Drive 导航导入",
  "journey": "journey:library-management",
  "promiseRefs": [
    "promise:media-import:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 130000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "system-import-fixtures-ready",
      "schema": "fixture-set.system-import@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:library-management:files-picker-import-route:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:library-management:files-picker-import-route:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-Manage-button"
        ]
      },
      "callId": "call:library-management:files-picker-import-route:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-Manage-addFiles"
        ]
      },
      "callId": "call:library-management:files-picker-import-route:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "systemControl": "home",
        "targetDomain": "system-toolbar"
      },
      "callId": "call:library-management:files-picker-import-route:05",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "systemControl": "home",
        "targetDomain": "system-toolbar"
      },
      "callId": "call:library-management:files-picker-import-route:06",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 2160,
        "shotWidth": 3840,
        "shotX": 1470,
        "shotY": 1221,
        "targetDomain": "canvas"
      },
      "callId": "call:library-management:files-picker-import-route:07",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 2160,
        "shotWidth": 3840,
        "shotX": 1855,
        "shotY": 1020,
        "targetDomain": "canvas"
      },
      "callId": "call:library-management:files-picker-import-route:08",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 2160,
        "shotWidth": 3840,
        "shotX": 2494,
        "shotY": 803,
        "targetDomain": "canvas"
      },
      "callId": "call:library-management:files-picker-import-route:09",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "systemImportExpectation": "files"
      },
      "callId": "call:library-management:files-picker-import-route:10",
      "maxInvocations": 1,
      "operation": "operation:library.snapshot@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "library-command@1",
      "evidenceType": "library.command",
      "id": "obligation:library-management:files-picker-import-route:o01:default",
      "oracle": "oracle:agent-structured-library-command@1",
      "producedByCall": "call:library-management:files-picker-import-route:10",
      "rubric": "rubric:library-management.files-picker-import-route.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:library-management:files-picker-import-route:o01:default"
  }
}
---
# Files 选择器与 iCloud Drive 导航导入

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
