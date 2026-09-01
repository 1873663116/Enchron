---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:webdav-test-source",
  "title": "Prepare webdav test source",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:webdav-test-source:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:06",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:07",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-add",
          "FileBrowsing-SourcesSidebar-addWebDAV"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:08",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "text": "Enchron Regression WebDAV",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:09",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "textFile": "repo://.build/regression-remote-source/runtime.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:10",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "textFile": "repo://.build/regression-remote-source/runtime.json",
        "textJSONKey": "user",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:11",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "textFile": "repo://.build/regression-remote-source/runtime.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:12",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:13",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-CertificateTrust-trust"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:14",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "以后"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:15",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:webdav-test-source:16",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "webdav-test-source-ready",
      "schema": "remote-source.webdav-fixture@2",
      "producedByCall": "call:preparation:webdav-test-source:16",
      "dependsOnTags": [
        "app.session",
        "certificate.trust",
        "fixture.corpus",
        "lane.instance",
        "source.connection",
        "source.session",
        "source.webdav",
        "system.permission"
      ]
    }
  ]
}
---
# Prepare webdav test source

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
