---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:emby-test-library",
  "title": "Prepare emby test library",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "implementation-gap",
  "blockers": [
    {
      "kind": "implementation-gap",
      "capability": "operation:preparation.emby-account@1",
      "detail": "preparation:emby-test-library requires this runtime capability: operation:preparation.emby-account@1"
    }
  ],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:emby-test-library:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "emby-aggregate"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "emby-test-library-ready",
      "schema": "remote-source.emby-library@2",
      "producedByCall": null,
      "dependsOnTags": [
        "app.session",
        "emby.account",
        "lane.instance",
        "source.emby",
        "source.emby.fixture-revision"
      ]
    }
  ]
}
---
# Prepare emby test library

The runtime Preparation adapter can validate the seeded Emby server, but the Catalog has no registered producer Operation that establishes the in-app Emby account; this Preparation therefore remains blocked and produces no reusable state.
