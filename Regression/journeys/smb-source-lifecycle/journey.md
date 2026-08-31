---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:smb-source-lifecycle",
  "title": "SMB 共享与目录浏览",
  "scenarioRefs": [
    "scenario:smb-source-lifecycle:smb-browse-shares-and-directories"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "smb-test-source-ready",
      "schema": "remote-source.smb-fixture@2"
    }
  ]
}
---
# SMB 共享与目录浏览

The Journey groups scenarios and declares only the reviewed state-handoff edges.
