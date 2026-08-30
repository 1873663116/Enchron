---
{
  "schema": "enchron.regression.oracle",
  "schemaVersion": 1,
  "id": "oracle:agent-structured-window-control-plane@1",
  "title": "Agent Structured Window Control Plane",
  "kind": "agent",
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_oracle_adapter.py",
    "digest": "sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212"
  }
}
---
# Agent Structured Window Control Plane

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
