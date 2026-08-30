---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-accessibility-tree@1",
  "title": "Agent Structured Accessibility Tree",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "accessibility.tree",
      "evidenceSchema": "accessibility-tree@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212"
  }
}
---
# Agent Structured Accessibility Tree

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
