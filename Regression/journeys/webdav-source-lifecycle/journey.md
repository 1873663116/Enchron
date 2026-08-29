---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:webdav-source-lifecycle",
  "title": "WebDAV 连接、证书、浏览与播放",
  "scenarioRefs": [
    "scenario:webdav-source-lifecycle:webdav-add-source",
    "scenario:webdav-source-lifecycle:webdav-open-through-loopback",
    "scenario:webdav-source-lifecycle:certificate-trust-boundary"
  ],
  "ordering": [
    {
      "after": "scenario:webdav-source-lifecycle:webdav-open-through-loopback",
      "before": "scenario:webdav-source-lifecycle:webdav-add-source"
    }
  ],
  "sharedState": [
    {
      "key": "webdav-test-source-ready",
      "schema": "remote-source.webdav-fixture@2"
    }
  ]
}
---
# WebDAV 连接、证书、浏览与播放

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
