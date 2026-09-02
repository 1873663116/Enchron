---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:local-directory-subtitle-source",
  "title": "Prepare local directory subtitle source",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:local-directory-subtitle-source:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "emby-aggregate"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-30s-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:09",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:10",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:11",
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
      "callId": "call:preparation:local-directory-subtitle-source:12",
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
      "callId": "call:preparation:local-directory-subtitle-source:13",
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
      "callId": "call:preparation:local-directory-subtitle-source:14",
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
      "callId": "call:preparation:local-directory-subtitle-source:15",
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
      "callId": "call:preparation:local-directory-subtitle-source:16",
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
      "callId": "call:preparation:local-directory-subtitle-source:17",
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
      "callId": "call:preparation:local-directory-subtitle-source:18",
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
      "callId": "call:preparation:local-directory-subtitle-source:19",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "emby"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:20",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Address",
        "mode": "replace",
        "textFile": "repo://Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:21",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Username",
        "mode": "replace",
        "textFile": "repo://Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "username",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:22",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Password",
        "mode": "replace",
        "textFile": "repo://Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:23",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Emby-Connection-Connect"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:24",
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
      "callId": "call:preparation:local-directory-subtitle-source:25",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "emby-aggregate"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-directory-subtitle-source:26",
      "operation": "operation:preparation.local-directory-subtitle-source@1",
      "arguments": {
        "directoryName": "sdr-bframe-aggregate-30s-sidecars",
        "mediaFileName": "sdr-bframe-aggregate-30s.mkv",
        "memberFileNames": [
          "sdr-bframe-aggregate-30s.mkv",
          "sdr-bframe-aggregate-30s.zh-CN.srt",
          "sdr-bframe-aggregate-30s.styled.ass"
        ]
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "local-directory-subtitle-source-ready",
      "schema": "media-source.local-directory-sidecars@1",
      "producedByCall": "call:preparation:local-directory-subtitle-source:26",
      "dependsOnTags": [
        "app.session",
        "certificate.trust",
        "emby.account",
        "fixture.corpus",
        "lane.instance",
        "library.contents",
        "source.connection",
        "source.emby",
        "source.emby.fixture-revision",
        "source.session",
        "source.webdav"
      ]
    }
  ]
}
---
# Prepare local directory subtitle source

The runtime Preparation adapter writes the WebDAV runtime identity before typing credentials, connects the same seeded Enchron Regression Emby library as preparation:emby-test-library, dismisses the system Save-Password sheet raised by each credential form it submits, stages the registered media and sidecars, imports one directory-backed media reference, validates its typed bookmark receipt, and produces the local directory subtitle source identity.
