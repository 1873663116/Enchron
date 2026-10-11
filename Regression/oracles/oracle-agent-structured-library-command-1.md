---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-library-command@1",
  "title": "Agent Structured Library Command",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "library.command",
      "evidenceSchema": "library-command@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:f1bf08d2e6e3e280f0de9115951c5b8cb3cca93d612340b8663bc7b35504645d"
  }
}
---
# Agent Structured Library Command

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
