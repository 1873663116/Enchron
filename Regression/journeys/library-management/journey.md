---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:library-management",
  "title": "系统导入入口与库管理",
  "scenarioRefs": [
    "scenario:library-management:files-picker-import-route",
    "scenario:library-management:photo-picker-import-route",
    "scenario:library-management:folder-naming",
    "scenario:library-management:folder-delete-rehomes-references",
    "scenario:library-management:move-references",
    "scenario:library-management:confirmed-batch-deletion",
    "scenario:library-management:current-folder-search-counts"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "system-import-fixtures-ready",
      "schema": "fixture-set.system-import@2"
    }
  ]
}
---
# 系统导入入口与库管理

The Journey groups scenarios and declares only the reviewed state-handoff edges.
