---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:issue-surface-behavior",
  "title": "错误表达与下一步指引",
  "scenarioRefs": [
    "scenario:issue-surface-behavior:source-failure-guidance-matrix",
    "scenario:issue-surface-behavior:typed-single-slot-contract"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "issue-fixtures-ready",
      "schema": "fixture-set.issue-surfaces@2"
    }
  ]
}
---
# 错误表达与下一步指引

The Journey groups scenarios and declares only the reviewed state-handoff edges.
