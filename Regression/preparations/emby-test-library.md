---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:emby-test-library",
  "title": "Prepare emby test library",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
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
      "producedByCall": "call:preparation:emby-test-library:01",
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

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
