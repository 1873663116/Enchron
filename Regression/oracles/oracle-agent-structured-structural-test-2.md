---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-structural-test@2",
  "title": "Agent Structured Structural Test",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "structural.test",
      "evidenceSchema": "structural-test@2"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:f1bf08d2e6e3e280f0de9115951c5b8cb3cca93d612340b8663bc7b35504645d"
  }
}
---
# Agent Structured Structural Test

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
