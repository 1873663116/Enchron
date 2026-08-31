---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:viewing-state-and-storage",
  "title": "观看状态与存储设置",
  "scenarioRefs": [
    "scenario:viewing-state-and-storage:exit-saves-position",
    "scenario:viewing-state-and-storage:reopen-resumes-near-position",
    "scenario:viewing-state-and-storage:completed-media-starts-from-beginning",
    "scenario:viewing-state-and-storage:clear-all-local-progress",
    "scenario:viewing-state-and-storage:remote-index-reused-on-second-open",
    "scenario:viewing-state-and-storage:local-playback-does-not-write-index",
    "scenario:viewing-state-and-storage:storage-rows-report-and-clear"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "viewing-storage-fixtures-ready",
      "schema": "fixture-set.viewing-storage@2"
    }
  ]
}
---
# 观看状态与存储设置

The Journey groups scenarios and declares only the reviewed state-handoff edges.
