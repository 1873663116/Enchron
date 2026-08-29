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
    "digest": "sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686"
  }
}
---
# Agent Structured Window Control Plane

The runtime Oracle adapter accepts exactly its registered evidence type and schema pair and returns ordered typed evaluations.
