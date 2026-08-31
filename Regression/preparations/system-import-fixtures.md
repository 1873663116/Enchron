---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:system-import-fixtures",
  "title": "Prepare system import fixtures",
  "lane": "simulator",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:system-import-fixtures:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "system-import-fixtures"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "system-import-fixtures-ready",
      "schema": "fixture-set.system-import@2",
      "producedByCall": "call:preparation:system-import-fixtures:01",
      "dependsOnTags": [
        "fixture.corpus",
        "input.device-hub",
        "lane.instance",
        "system.permission"
      ]
    }
  ]
}
---
# Prepare system import fixtures

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
